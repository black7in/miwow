"""MiWow spellgen: hechizos propios desde fichas TOML (ver docs/hechizos.md).

  py -I tools/spellgen/spellgen.py build            fichas de modules/mod-miwow/data/spells/*.toml -> SQL
  py -I tools/spellgen/spellgen.py dump <id>...     muestra un hechizo del Spell.dbc del cliente (campos != 0)
  py -I tools/spellgen/spellgen.py find <texto>     busca hechizos por nombre (esES)
  py -I tools/spellgen/spellgen.py icon <texto>     busca iconos (SpellIcon.dbc)

Cada ficha genera data/sql/db-world/miwow_spells_<ficha>.sql (spell_dbc + spell_ranks + spell_bonus_data +
spell_script_names),
idempotente. El updater de AzerothCore la vuelve a aplicar si cambia. Build-Patch lleva las filas al cliente.

Fuentes (sin BD): client/DBCs/DBCesES (Spell.dbc y auxiliares), esquema de spell_dbc del core
(data/sql/base/db_world/spell_dbc.sql) y enums del core (SharedDefines.h, SpellAuraDefines.h).
"""

import re
import struct
import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DBC_DIR = ROOT / "client" / "DBCs" / "DBCesES"
CORE = ROOT / "azerothcore-wotlk"
SCHEMA = CORE / "data" / "sql" / "base" / "db_world" / "spell_dbc.sql"
SPELLS_DIR = ROOT / "modules" / "mod-miwow" / "data" / "spells"
SQL_DIR = ROOT / "modules" / "mod-miwow" / "data" / "sql" / "db-world"

MIN_ID = 9500000
# Huecos de texto (16 por campo + mascara). El cliente esES lee el 6; el servidor (DBC en ingles), el 0.
# Los nombres de columna de spell_dbc no siguen el orden de 3.3.5: se escribe por posicion.
LOCALE_SLOTS = (0, 6)
TEXT_FIELDS = ("Name", "NameSubtext", "Description", "AuraDescription")
SCHOOLS = {"physical": 0, "holy": 1, "fire": 2, "nature": 3, "frost": 4, "shadow": 5, "arcane": 6}
POWERS = {"mana": 0, "rage": 1, "focus": 2, "energy": 3, "runic": 6}
DMG_CLASSES = {"none": 0, "magic": 1, "melee": 2, "ranged": 3}
ATTR1_CHANNELED_1 = 0x00000004
ATTR1_CHANNELED_2 = 0x00000040
ATTR5_SPELL_HASTE_AFFECTS_PERIODIC = 0x00002000


class SpellError(Exception):
    pass


# --- Datos de entrada -----------------------------------------------------------------------------------------

def load_schema():
    """[(columna, tipo)] de spell_dbc en orden; tipo: 'int', 'uint', 'float', 'str'."""
    text = SCHEMA.read_text(encoding="utf-8")
    body = text[text.index("CREATE TABLE `spell_dbc`"):]
    body = body[:body.index("PRIMARY KEY")]
    columns = []
    for m in re.finditer(r"^\s*`(\w+)`\s+([a-z]+)(\(\d+\))?( unsigned)?", body, re.M):
        name, sqltype, _, unsigned = m.groups()
        if sqltype in ("varchar", "text"):
            kind = "str"
        elif sqltype == "float":
            kind = "float"
        else:
            kind = "uint" if unsigned else "int"
        columns.append((name, kind))
    if len(columns) != 234:
        raise SpellError(f"spell_dbc.sql: {len(columns)} columnas (se esperaban 234)")
    return columns


class Dbc:
    def __init__(self, name):
        data = (DBC_DIR / name).read_bytes()
        magic, self.count, self.fields, self.size, strsize = struct.unpack_from("<4s4I", data)
        if magic != b"WDBC":
            raise SpellError(f"{name}: no es un DBC")
        self.data = data
        self.strings = data[20 + self.count * self.size:]

    def raw(self, i):
        return struct.unpack_from(f"<{self.fields}I", self.data, 20 + i * self.size)

    def floats(self, i):
        return struct.unpack_from(f"<{self.fields}f", self.data, 20 + i * self.size)

    def string(self, offset):
        end = self.strings.index(b"\0", offset)
        return self.strings[offset:end].decode("utf-8", "replace")

    def rows(self):
        for i in range(self.count):
            yield self.raw(i)


def load_enums():
    """{prefijo: {NOMBRE_SIN_PREFIJO: valor}} de los enums del core."""
    sources = [CORE / "src/server/shared/SharedDefines.h",
               CORE / "src/server/game/Spells/Auras/SpellAuraDefines.h"]
    text = "\n".join(p.read_text(encoding="utf-8", errors="replace") for p in sources)
    enums = {}
    for prefix in ("SPELL_EFFECT_", "SPELL_AURA_", "TARGET_", "MECHANIC_"):
        values = {}
        for m in re.finditer(rf"\b{prefix}(\w+)\s*=\s*(\d+)", text):
            values.setdefault(m.group(1), int(m.group(2)))
        enums[prefix] = values
    return enums


class Spells:
    """Spell.dbc del cliente, por ID, con los valores ya tipados segun el esquema."""

    def __init__(self, columns):
        self.columns = columns
        self.dbc = Dbc("Spell.dbc")
        if self.dbc.fields != len(columns):
            raise SpellError(f"Spell.dbc tiene {self.dbc.fields} campos y spell_dbc {len(columns)}")
        self.index = {}
        for i in range(self.dbc.count):
            self.index[struct.unpack_from("<I", self.dbc.data, 20 + i * self.dbc.size)[0]] = i

    def get(self, spell_id):
        i = self.index.get(spell_id)
        if i is None:
            raise SpellError(f"el hechizo {spell_id} no esta en el Spell.dbc del cliente")
        raw = self.dbc.raw(i)
        flt = self.dbc.floats(i)
        row = {}
        for n, (name, kind) in enumerate(self.columns):
            if kind == "float":
                row[name] = flt[n]
            elif kind == "str":
                row[name] = self.dbc.string(raw[n]) if raw[n] else ""
            elif kind == "int":
                row[name] = struct.unpack("<i", struct.pack("<I", raw[n]))[0]
            else:
                row[name] = raw[n]
        return row

    def text(self, row, field):
        return row[self.columns[self._text_start(field) + LOCALE_SLOTS[1]][0]]

    def _text_start(self, field):
        return [c[0] for c in self.columns].index(f"{field}_Lang_enUS")

    def set_text(self, row, field, value):
        start = self._text_start(field)
        for slot in range(16):
            row[self.columns[start + slot][0]] = value if slot in LOCALE_SLOTS else ""


class Indexes:
    """Indices de los DBC auxiliares (duracion, lanzamiento, alcance, radio, icono)."""

    def __init__(self):
        self.duration = {}
        dbc = Dbc("SpellDuration.dbc")
        for i in range(dbc.count):
            r = dbc.raw(i)
            base = struct.unpack("<i", struct.pack("<I", r[1]))[0]
            if r[2] == 0 and struct.unpack("<i", struct.pack("<I", r[3]))[0] == base:
                self.duration.setdefault(base, r[0])
        self.cast = {}
        dbc = Dbc("SpellCastTimes.dbc")
        for i in range(dbc.count):
            r = dbc.raw(i)
            if r[2] == 0:
                self.cast.setdefault(struct.unpack("<i", struct.pack("<I", r[1]))[0], r[0])
        self.range = {}
        dbc = Dbc("SpellRange.dbc")
        for i in range(dbc.count):
            r, f = dbc.raw(i), dbc.floats(i)
            if f[1] == 0:  # alcance minimo 0
                self.range.setdefault(round(f[3], 2), r[0])
        self.radius = {}
        dbc = Dbc("SpellRadius.dbc")
        for i in range(dbc.count):
            r, f = dbc.raw(i), dbc.floats(i)
            if f[2] == 0:
                self.radius.setdefault(round(f[1], 2), r[0])
        self.icons = {}
        dbc = Dbc("SpellIcon.dbc")
        for i in range(dbc.count):
            r = dbc.raw(i)
            path = dbc.string(r[1]) if r[1] else ""
            self.icons.setdefault(path.rsplit("\\", 1)[-1].lower(), (r[0], path))

    @staticmethod
    def _pick(table, key, what, unit):
        if key in table:
            return table[key]
        near = sorted(table, key=lambda k: abs(k - key))[:6]
        raise SpellError(f"no hay {what} de {key}{unit} en el DBC del cliente; cercanos: "
                         + ", ".join(f"{k}{unit}" for k in sorted(near)))

    def duration_index(self, seconds):
        if seconds < 0:
            return self.duration[-1]
        return self._pick(self.duration, int(round(seconds * 1000)), "duracion", " ms")

    def cast_index(self, seconds):
        return self._pick(self.cast, int(round(seconds * 1000)), "tiempo de lanzamiento", " ms")

    def range_index(self, yards):
        return self._pick(self.range, round(float(yards), 2), "alcance", " m")

    def radius_index(self, yards):
        return self._pick(self.radius, round(float(yards), 2), "radio", " m")

    def icon_id(self, name):
        key = name.rsplit("\\", 1)[-1].lower()
        if key not in self.icons:
            raise SpellError(f"icono '{name}' no esta en SpellIcon.dbc (usa: spellgen.py icon <texto>)")
        return self.icons[key][0]


# --- Fichas -----------------------------------------------------------------------------------------------------

def per_rank(value, ranks, what):
    """Escalar -> el mismo en todos los rangos; lista -> uno por rango."""
    if isinstance(value, list):
        if len(value) != ranks:
            raise SpellError(f"{what}: {len(value)} valores para {ranks} rangos")
        return value
    return [value] * ranks


def enum_value(enums, prefix, value, what):
    if isinstance(value, int):
        return value
    key = str(value).upper()
    if key.startswith(prefix):
        key = key[len(prefix):]
    if key == "NONE":
        return 0
    if key not in enums[prefix]:
        options = [k for k in enums[prefix] if key in k][:8]
        raise SpellError(f"{what}: '{value}' no existe ({prefix}*)" + (f"; parecidos: {', '.join(options)}" if options else ""))
    return enums[prefix][key]


EFFECT_FIELDS = ("Effect", "EffectDieSides", "EffectRealPointsPerLevel", "EffectBasePoints", "EffectMechanic",
                 "ImplicitTargetA", "ImplicitTargetB", "EffectRadiusIndex", "EffectAura", "EffectAuraPeriod",
                 "EffectMultipleValue", "EffectChainTargets", "EffectItemType", "EffectMiscValue",
                 "EffectMiscValueB", "EffectTriggerSpell", "EffectPointsPerCombo", "EffectSpellClassMaskA",
                 "EffectSpellClassMaskB", "EffectSpellClassMaskC", "EffectChainAmplitude", "EffectBonusMultiplier")


def apply_effect(row, n, spec, rank, ranks, ctx):
    enums, indexes, where = ctx
    sfx = f"_{n}"
    what = f"{where} effect{n}"
    if "type" in spec:
        effect = enum_value(enums, "SPELL_EFFECT_", spec["type"], what + ".type")
        if effect == 0:
            for field in EFFECT_FIELDS:
                row[field + sfx] = 0.0 if isinstance(row[field + sfx], float) else 0
            return
        if effect != row["Effect" + sfx]:
            # Efecto distinto del de la base: se empieza de cero (no heredar objetivos/auras de otro efecto)
            for field in EFFECT_FIELDS:
                row[field + sfx] = 0.0 if isinstance(row[field + sfx], float) else 0
            row["EffectMultipleValue" + sfx] = 1.0
            row["EffectChainAmplitude" + sfx] = 1.0
            row["EffectBonusMultiplier" + sfx] = 1.0
        row["Effect" + sfx] = effect
    if "aura" in spec:
        row["EffectAura" + sfx] = enum_value(enums, "SPELL_AURA_", spec["aura"], what + ".aura")
    if "value" in spec:
        v = int(per_rank(spec["value"], ranks, what + ".value")[rank])
        row["EffectBasePoints" + sfx] = v - 1
        row["EffectDieSides" + sfx] = 1
    if "min" in spec or "max" in spec:
        lo = int(per_rank(spec["min"], ranks, what + ".min")[rank])
        hi = int(per_rank(spec["max"], ranks, what + ".max")[rank])
        if hi < lo:
            raise SpellError(f"{what}: max < min")
        row["EffectBasePoints" + sfx] = lo - 1
        row["EffectDieSides" + sfx] = hi - lo + 1
    if "target" in spec:
        row["ImplicitTargetA" + sfx] = enum_value(enums, "TARGET_", spec["target"], what + ".target")
    if "target_b" in spec:
        row["ImplicitTargetB" + sfx] = enum_value(enums, "TARGET_", spec["target_b"], what + ".target_b")
    if "radius" in spec:
        row["EffectRadiusIndex" + sfx] = indexes.radius_index(per_rank(spec["radius"], ranks, what + ".radius")[rank])
    if "period" in spec:
        row["EffectAuraPeriod" + sfx] = int(round(per_rank(spec["period"], ranks, what + ".period")[rank] * 1000))
    if "chain" in spec:
        row["EffectChainTargets" + sfx] = int(per_rank(spec["chain"], ranks, what + ".chain")[rank])
    if "misc" in spec:
        row["EffectMiscValue" + sfx] = int(per_rank(spec["misc"], ranks, what + ".misc")[rank])
    if "misc_b" in spec:
        row["EffectMiscValueB" + sfx] = int(per_rank(spec["misc_b"], ranks, what + ".misc_b")[rank])
    if "trigger" in spec:
        row["EffectTriggerSpell" + sfx] = int(per_rank(spec["trigger"], ranks, what + ".trigger")[rank])
    if "mechanic" in spec:
        row["EffectMechanic" + sfx] = enum_value(enums, "MECHANIC_", spec["mechanic"], what + ".mechanic")
    # Por defecto los valores no escalan con el nivel del heroe (para eso estan los rangos). per_level: se suma
    # nivel x per_level (SpellLevel/BaseLevel/MaxLevel = 0; lo usan los ataques basicos, que no tienen rangos)
    row["EffectRealPointsPerLevel" + sfx] = float(per_rank(spec.get("per_level", 0), ranks, what + ".per_level")[rank])
    row["EffectPointsPerCombo" + sfx] = 0.0


def build_rank(spells, spec, rank, ranks, ctx):
    enums, indexes, where = ctx
    base = spells.get(int(spec["base"]))
    row = dict(base)
    first = int(spec["id"])
    row["ID"] = first + rank

    # Limpieza: lo de la base que no queremos heredar
    row["Category"] = 0                     # reutilizacion compartida con la base
    row["CategoryRecoveryTime"] = 0
    row["SpellLevel"] = row["BaseLevel"] = row["MaxLevel"] = 0   # sin penalizacion ni escalado por nivel
    row["SpellDifficultyID"] = 0
    row["SpellDescriptionVariableID"] = 0  # variables de texto que apuntan a otros hechizos
    row["ModalNextSpell"] = 0
    for i in range(1, 9):
        row[f"Reagent_{i}"] = 0
        row[f"ReagentCount_{i}"] = 0
    row["Totem_1"] = row["Totem_2"] = 0
    row["RequiredTotemCategoryID_1"] = row["RequiredTotemCategoryID_2"] = 0
    row["RequiresSpellFocus"] = 0
    # Requisitos/exclusiones por aura de otro hechizo (p. ej. "Alma debilitada" del escudo del sacerdote)
    for key in ("CasterAuraSpell", "TargetAuraSpell", "ExcludeCasterAuraSpell", "ExcludeTargetAuraSpell"):
        row[key] = 0
    row["RuneCostID"] = 0
    row["ShapeshiftMask"] = row["ShapeshiftExclude"] = 0
    row["EquippedItemClass"] = -1           # sin arma (no equipamos objetos)
    row["EquippedItemSubclass"] = 0
    row["EquippedItemInvTypes"] = 0
    row["SpellClassSet"] = int(spec.get("family", 0))  # 0 = generico: sin talentos/glifos de clase ni casos del core
    for i in range(1, 4):
        row[f"SpellClassMask_{i}"] = 0

    # Textos
    rank_text = spec.get("rank_text", "Nivel {n}" if ranks > 1 else "")
    spells.set_text(row, "Name", spec["name"])
    spells.set_text(row, "NameSubtext", rank_text.format(n=rank + 1))
    spells.set_text(row, "Description", spec.get("description", spells.text(base, "Description")))
    spells.set_text(row, "AuraDescription", spec.get("aura_description", spells.text(base, "AuraDescription")))

    # Generales (escalar o lista por rango)
    def opt(key):
        return per_rank(spec[key], ranks, f"{where}.{key}")[rank] if key in spec else None

    if (v := opt("icon")) is not None:
        row["SpellIconID"] = indexes.icon_id(v)
    if (v := opt("visual")) is not None:
        row["SpellVisualID_1"] = int(v)
        row["SpellVisualID_2"] = 0
    if (v := opt("cast_time")) is not None:
        row["CastingTimeIndex"] = indexes.cast_index(v)
    if (v := opt("cooldown")) is not None:
        row["RecoveryTime"] = int(round(v * 1000))
    if (v := opt("gcd")) is not None:
        row["StartRecoveryTime"] = int(round(v * 1000))
    if (v := opt("duration")) is not None:
        row["DurationIndex"] = indexes.duration_index(v)
    if (v := opt("range")) is not None:
        row["RangeIndex"] = indexes.range_index(v)
    if (v := opt("speed")) is not None:
        row["Speed"] = float(v)
    if (v := opt("power")) is not None:
        row["PowerType"] = POWERS[v]
    if (v := opt("cost")) is not None:
        row["ManaCost"] = int(v)
        row["ManaCostPct"] = 0
        row["ManaCostPerLevel"] = 0
    if (v := opt("cost_pct")) is not None:
        row["ManaCostPct"] = int(v)
        row["ManaCost"] = 0
    if (v := opt("school")) is not None:
        row["SchoolMask"] = 1 << SCHOOLS[v]
    if (v := opt("mechanic")) is not None:
        row["Mechanic"] = enum_value(enums, "MECHANIC_", v, where + ".mechanic")
    if (v := opt("max_targets")) is not None:
        row["MaxTargets"] = int(v)
    if (v := opt("dmg_class")) is not None:
        # DmgClass (DefenseType): la celeridad con hechizos solo acorta el lanzamiento de los "magic"; los "ranged"
        # usan la celeridad de distancia (agilidad)
        row["DefenseType"] = DMG_CLASSES[v]
    for key in ("Attributes", "AttributesEx", "AttributesEx2", "AttributesEx3", "AttributesEx4",
                "AttributesEx5", "AttributesEx6", "AttributesEx7"):
        lower = key.lower()
        if (v := opt(lower)) is not None:
            row[key] = int(v)
        if (v := opt(lower + "_add")) is not None:
            row[key] |= int(v)
        if (v := opt(lower + "_remove")) is not None:
            row[key] &= ~int(v) & 0xFFFFFFFF

    for n in (1, 2, 3):
        if f"effect{n}" in spec:
            apply_effect(row, n, spec[f"effect{n}"], rank, ranks, ctx)

    # Columnas sueltas de spell_dbc por nombre (p. ej. ProcChance), escalar o lista por rango
    for column, value in spec.get("fields", {}).items():
        if column not in row:
            raise SpellError(f"{where}.fields: la columna '{column}' no existe en spell_dbc")
        row[column] = per_rank(value, ranks, f"{where}.fields.{column}")[rank]

    # Celeridad con hechizos (intelecto, docs/heroes.md sec. 4 regla 5). Con SPELL_ATTR5_SPELL_HASTE_AFFECTS_PERIODIC
    # el core la aplica tambien a: periodo Y duracion de las auras del hechizo (mismos ticks en menos tiempo; OJO,
    # tambien acorta un aturdimiento/raiz que vaya en el mismo hechizo), duracion de canalizados y lanzamiento de
    # los DmgClass NONE (los MAGIC ya lo tienen sin atributo). Por defecto en todo hechizo no fisico canalizado,
    # periodico o con lanzamiento; los fisicos (melee/ranged) van con la agilidad. haste_periodic = true/false fuerza.
    periodic = any(row[f"EffectAuraPeriod_{n}"] > 0 for n in (1, 2, 3))
    channeled = row["AttributesEx"] & (ATTR1_CHANNELED_1 | ATTR1_CHANNELED_2)
    none_cast = row["CastingTimeIndex"] > 1 and row["DefenseType"] == DMG_CLASSES["none"]  # indice 1 = instantaneo
    physical = row["DefenseType"] in (DMG_CLASSES["melee"], DMG_CLASSES["ranged"])
    haste = spec.get("haste_periodic", not physical and (periodic or channeled or none_cast))
    if haste:
        row["AttributesEx5"] |= ATTR5_SPELL_HASTE_AFFECTS_PERIODIC
    else:
        row["AttributesEx5"] &= ~ATTR5_SPELL_HASTE_AFFECTS_PERIODIC & 0xFFFFFFFF
    return row


def sql_value(value, kind):
    if kind == "str":
        return "'" + value.replace("\\", "\\\\").replace("'", "\\'") + "'"
    if kind == "float":
        return repr(float(value))
    return str(int(value))


def build_file(path, spells, enums, indexes):
    data = tomllib.loads(path.read_text(encoding="utf-8"))
    entries = data.get("spell", [])
    if not entries:
        raise SpellError(f"{path.name}: no hay [[spell]]")

    rows, ranks_sql, bonus_sql, script_sql, used = [], [], [], [], {}
    for spec in entries:
        for key in ("id", "base", "name"):
            if key not in spec:
                raise SpellError(f"{path.name}: falta '{key}' en un [[spell]]")
        where = f"{path.name} [{spec['name']}]"
        ranks = int(spec.get("ranks", 1))
        first = int(spec["id"])
        if first < MIN_ID:
            raise SpellError(f"{where}: id {first} < {MIN_ID} (rango propio de MiWow)")
        for rank in range(ranks):
            sid = first + rank
            if sid in used:
                raise SpellError(f"{where}: id {sid} repetido (ya lo usa {used[sid]})")
            used[sid] = spec["name"]
            rows.append(build_rank(spells, spec, rank, ranks, (enums, indexes, where)))
            if "script" in spec:
                # SpellScript del modulo (C++), por ID: lo que los efectos solos no pueden hacer
                script_sql.append(f"({sid}, '{spec['script']}')")
            if ranks > 1 and spec.get("chain", True):
                ranks_sql.append(f"({first}, {sid}, {rank + 1})")
            if any(k in spec for k in ("coefficient", "dot_coefficient", "ap_coefficient", "ap_dot_coefficient")):
                # <= 0 en spell_bonus_data = calculo por defecto del core (Unit.cpp): no sirve para "sin bonificacion"
                bonus_sql.append("({}, {}, {}, {}, {}, '{}')".format(
                    sid, float(spec.get("coefficient", 0)), float(spec.get("dot_coefficient", 0)),
                    float(spec.get("ap_coefficient", 0)), float(spec.get("ap_dot_coefficient", 0)),
                    f"MiWow: {spec['name']} {rank + 1}".replace("'", "")))

    ids = sorted(used)
    id_list = ", ".join(str(i) for i in ids)
    columns = spells.columns
    out = [f"-- MiWow: GENERADO por tools/spellgen desde modules/mod-miwow/data/spells/{path.name}.",
           "-- No editar a mano: cambiar la ficha y ejecutar  py -I tools/spellgen/spellgen.py build",
           f"DELETE FROM `spell_dbc` WHERE `ID` IN ({id_list});",
           "INSERT INTO `spell_dbc` (" + ", ".join(f"`{c}`" for c, _ in columns) + ") VALUES"]
    out.append(",\n".join("(" + ", ".join(sql_value(row[c], k) for c, k in columns) + ")" for row in rows) + ";")
    out.append(f"DELETE FROM `spell_ranks` WHERE `spell_id` IN ({id_list});")
    if ranks_sql:
        out.append("INSERT INTO `spell_ranks` (`first_spell_id`, `spell_id`, `rank`) VALUES\n" + ",\n".join(ranks_sql) + ";")
    out.append(f"DELETE FROM `spell_bonus_data` WHERE `entry` IN ({id_list});")
    if bonus_sql:
        out.append("INSERT INTO `spell_bonus_data` (`entry`, `direct_bonus`, `dot_bonus`, `ap_bonus`, `ap_dot_bonus`, "
                   "`comments`) VALUES\n" + ",\n".join(bonus_sql) + ";")

    out.append(f"DELETE FROM `spell_script_names` WHERE `spell_id` IN ({id_list});")
    if script_sql:
        out.append("INSERT INTO `spell_script_names` (`spell_id`, `ScriptName`) VALUES" + chr(10)
                   + ("," + chr(10)).join(script_sql) + ";")

    target = SQL_DIR / f"miwow_spells_{path.stem}.sql"
    target.write_text("\n".join(out) + "\n", encoding="utf-8", newline="\n")
    return target, ids


# --- Comandos ---------------------------------------------------------------------------------------------------

def reverse(enums, prefix, value):
    names = [k for k, v in enums[prefix].items() if v == value]
    return f"{value} ({names[0]})" if names else str(value)


def cmd_dump(ids, spells, enums):
    for spell_id in ids:
        row = spells.get(int(spell_id))
        print(f"== {spell_id} {spells.text(row, 'Name')} | {spells.text(row, 'NameSubtext')}")
        print("   " + spells.text(row, "Description").replace("\n", " "))
        for name, kind in spells.columns:
            if kind == "str" or name.endswith("_Lang_Mask"):
                continue
            value = row[name]
            if not value:
                continue
            if name.startswith("Effect_"):
                value = reverse(enums, "SPELL_EFFECT_", value)
            elif name.startswith("EffectAura_"):
                value = reverse(enums, "SPELL_AURA_", value)
            elif name.startswith("ImplicitTarget"):
                value = reverse(enums, "TARGET_", value)
            elif name in ("Mechanic",) or name.startswith("EffectMechanic"):
                value = reverse(enums, "MECHANIC_", value)
            elif name.startswith("Attributes"):
                value = hex(value)
            print(f"   {name} = {value}")


def cmd_find(text, spells):
    text = text.lower()
    for spell_id, i in sorted(spells.index.items()):
        row = spells.dbc.raw(i)
        off = row[136 + LOCALE_SLOTS[1]]
        name = spells.dbc.string(off) if off else ""
        if text in name.lower():
            rank_off = row[153 + LOCALE_SLOTS[1]]
            print(spell_id, name, "|", spells.dbc.string(rank_off) if rank_off else "")


def main(argv):
    if len(argv) < 2 or argv[1] not in ("build", "dump", "find", "icon"):
        print(__doc__)
        return 1
    try:
        columns = load_schema()
        spells = Spells(columns)
        enums = load_enums()
        if argv[1] == "dump":
            cmd_dump(argv[2:], spells, enums)
        elif argv[1] == "find":
            cmd_find(" ".join(argv[2:]), spells)
        elif argv[1] == "icon":
            indexes = Indexes()
            text = " ".join(argv[2:]).lower()
            for key, (icon_id, path) in sorted(indexes.icons.items()):
                if text in key:
                    print(icon_id, path)
        else:
            indexes = Indexes()
            files = sorted(SPELLS_DIR.glob("*.toml"))
            if not files:
                print(f"No hay fichas en {SPELLS_DIR}")
            for path in files:
                target, ids = build_file(path, spells, enums, indexes)
                print(f"{path.name}: {len(ids)} hechizo(s) ({ids[0]}-{ids[-1]}) -> {target.relative_to(ROOT)}")
    except SpellError as error:
        print(f"ERROR: {error}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
