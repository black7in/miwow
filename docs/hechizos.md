# Hechizos propios: como se crean y como vamos a trabajar

Plan del 2026-11-14 (hecho: `tools/spellgen`). Nacio con los heroes de la rama `main` (en `tradicional` no hay heroes; aqui lo
usan la carrera y el parkour). Lo que habla de rangos y puntos de habilidad describe `main`.

## 1. Como funciona un hechizo en WoW 3.3.5

Un hechizo es **una fila de `Spell.dbc`** (234 campos). No hay codigo: el motor lee la fila y ejecuta sus
**3 efectos**. El mismo archivo lo leen los dos lados:

- **Servidor** (AzerothCore): que hace el hechizo (dano, aura, objetivos...). Carga `Spell.dbc` (ingles) y le
  suma las filas de la tabla **`spell_dbc`** de la BD world (`DBCStores.cpp`: `LOAD_DBC(sSpellStore, "Spell.dbc",
  "spell_dbc")`). La tabla tiene las mismas 234 columnas en el mismo orden.
- **Cliente**: nombre, tooltip, icono, efectos visuales, tiempo de lanzamiento en la barra. Si una fila no esta en
  el `Spell.dbc` del cliente, el cliente no sabe que existe.

Nuestro circuito ya existe (igual que los objetos): **filas en `spell_dbc` (SQL del modulo, ID >= 9500000) ->
servidor al arrancar + `Build-Dbc` -> `Spell.dbc` del parche**. `Build-Dbc` es generico y ya vale para Spell
(comprobado: 234 columnas en la tabla). La tabla trae ~4500 filas del propio AC (ID < 9500000): no se tocan.

### Campos que importan

| Grupo | Campos | Para que |
|---|---|---|
| Efectos (x3) | `Effect`, `EffectAura`, `EffectBasePoints`, `EffectDieSides`, `EffectRealPointsPerLevel` | que hace cada efecto y cuanto |
| Objetivos (x3) | `ImplicitTargetA/B`, `EffectRadiusIndex`, `EffectChainTargets`, `MaxTargets` | a quien: objetivo, area alrededor, cono, cadena... |
| Aura (x3) | `EffectAmplitude` (cada cuanto tick), `EffectMiscValue`, `EffectTriggerSpell` | auras periodicas, que stat modifica, hechizo que dispara |
| Tiempos | `CastingTimeIndex`, `DurationIndex`, `RecoveryTime` (reutilizacion), `StartRecoveryTime` (tiempo global) | lanzamiento, duracion, reutilizacion |
| Coste | `PowerType`, `ManaCost`, `ManaCostPct` | |
| Alcance | `RangeIndex`, `Speed` (velocidad del proyectil) | |
| Reglas | `Attributes*` (pasivo, canalizado, no se puede esquivar...), `InterruptFlags`, `Mechanic` (aturdir, raiz... para inmunidades y rendimientos decrecientes) | |
| Cliente | `SpellVisualID_1/2`, `SpellIconID`, `Name/Rank/Description/AuraDescription` (por idioma) | aspecto y tooltip |
| Familia | `SpellClassSet`/`SpellClassMask` | para que un aura/objeto afecte "a todos nuestros hechizos" (p. ej. -20 % reutilizacion) |

Los `*Index` apuntan a otros DBC del cliente (SpellCastTimes, SpellDuration, SpellRadius, SpellRange): usamos sus
valores existentes, no hace falta crear filas nuevas ahi.

Tooltip: el texto lleva variables que el cliente rellena con los datos de la fila: `$s1` (valor del efecto 1),
`$d` (duracion), `$o1` (total de un efecto periodico), `$a1` (radio), `$t1` (intervalo del tick)... Por eso cada
rango tiene su propia fila: "Inflige $s1 de dano" muestra el numero real de ese rango.

### Recetas (efecto + aura + objetivo)

| Quiero... | Como se hace |
|---|---|
| Dano directo | efecto `SCHOOL_DAMAGE` (2), objetivo = enemigo seleccionado |
| Dano en area | `SCHOOL_DAMAGE` con objetivo "enemigos en area" (alrededor del lanzador o del punto elegido) + radio |
| Aturdir | `APPLY_AURA` (6) + aura `MOD_STUN` (12) + duracion; `Mechanic` = aturdir |
| Ralentizar / enraizar | aura `MOD_DECREASE_SPEED` (33, -X %) / `MOD_ROOT` (26) |
| Dano en el tiempo | aura `PERIODIC_DAMAGE` (3) + intervalo |
| Curar / curar en el tiempo | efecto `HEAL` (10) / aura `PERIODIC_HEAL` (8) |
| Escudo | aura `SCHOOL_ABSORB` (69) |
| Mejora de stats | aura `MOD_STAT` (29), `MOD_DAMAGE_PERCENT_DONE`, `MOD_ATTACKSPEED`... |
| Aura de grupo (WC3) | efecto `APPLY_AREA_AURA_PARTY` (35) o `_RAID`: la llevan todos los cercanos mientras dure |
| Zona en el suelo (Ventisca, Consagracion) | `PERSISTENT_AREA_AURA` (27): objeto en el suelo con un aura periodica |
| Rayo encadenado | `EffectChainTargets` = numero de saltos |
| Cargar / empujar | `CHARGE` (96) / `KNOCK_BACK` (98) |
| Invocar | `SUMMON` (28) + criatura |
| Pasiva | `Attributes` con PASSIVE: se aplica sola al aprenderla |
| Ataque basico a distancia | `Attributes` con autorrepeticion (como "Disparar" de la varita) sin `EquippedItemClass` (sin arma) |

Lo que no se pueda expresar con efectos (p. ej. "rebota a 3 enemigos y cura por cada uno") va en un
**SpellScript en C++** de nuestro modulo, enlazado por ID en `spell_script_names`.

## 2. Que se pierde/gana copiando hechizos existentes

Lo mas facil: **partir de un hechizo parecido** (Martillo de justicia para un aturdimiento) y cambiar numeros,
texto e icono. Lo bueno: el aspecto (visual, sonido, animacion) viene hecho. Cuidado:

- Muchos hechizos de clase son **cadenas**: el efecto real lo hace otro hechizo disparado (`EffectTriggerSpell`) o
  un script en C++ del core por ID. Al copiarlo con un ID nuevo **se pierde el script** (y a veces el
  disparado): elegir bases simples o copiar tambien los disparados.
- Ventaja de los ID propios: las correcciones del core por ID (`SpellInfoCorrections`, `spell_custom_attr`,
  scripts) no nos afectan; nuestra fila hace exactamente lo que dice.
- **Coeficientes** (cuanto suma el poder con hechizos/ataque): sin fila en `spell_bonus_data`, AC calcula uno por
  defecto segun el tiempo de lanzamiento (`CalculateDefaultCoefficient`). Pondremos los nuestros en esa tabla.
- Nivel del hechizo (`SpellLevel/BaseLevel/MaxLevel`, `RealPointsPerLevel`): a 0 o fijos, para que el valor no
  cambie con el nivel del heroe (los rangos ya lo suben).
- **Hechizos ocultos**: muchas bases (talentos, hechizos disparados) llevan `SPELL_ATTR0_DO_NOT_DISPLAY` (0x80): no salen
  en el libro ni en la barra de auras. Para una pasiva visible: `attributes_remove = 0x80` (probado con la Pasiva de
  prueba). Los hechizos disparados (el golpe de un aura) conviene dejarlos ocultos.
- **Rangos**: `spell_ranks` encadena los niveles (Nivel 1 -> 2 -> 3...) para que el motor sepa que son el mismo.

### Trampa encontrada: los idiomas en `spell_dbc`

El `Spell.dbc` del cliente esES guarda el texto en el **hueco 6** de los 16 de cada texto (comprobado con
Bola de Fuego). En `spell_dbc` ese hueco se llama `Name_Lang_zhCN` (los nombres de columna de AC no siguen el
orden real de 3.3.5: el hueco de `Name_Lang_esES` es el 9). La herramienta escribira por posicion, no por nombre.

## 3. Herramientas: el Spell Editor de Stoneharry

[WoW Spell Editor](https://github.com/stoneharry/WoW-Spell-Editor) (Stoneharry): programa con ventanas para 3.3.5a
(tambien 2.4.3 y 1.12.1). Importa `Spell.dbc` a una base de datos (SQLite o MySQL), se editan los campos con
nombres y listas desplegables (efectos, auras, objetivos), tiene vista previa de visuales e iconos, y exporta un
`Spell.dbc` nuevo (que habria que poner en cliente y servidor).

Encaja a medias con nosotros:
- **Si**: para **explorar** (buscar un hechizo parecido, ver como esta hecho un aturdimiento, elegir icono y
  visual), y para probar ideas. Muy util para aprender.
- **No como fuente de verdad**: guarda en sus propias tablas (no en `spell_dbc`), exporta un DBC binario entero
  (no se ve que cambio en git) y el servidor no debe recibir un `Spell.dbc` nuevo (sus DBC no se tocan: regla del
  proyecto).

## 4. Propuesta: fichas de texto + generador

**Fuente de verdad = archivos de texto en el repo**, uno por heroe (TOML: legible, admite comentarios; Python 3.13
lo lee sin instalar nada), p. ej. `modules/mod-eventwow/data/spells/cruzado.toml`:

```toml
[[spell]]
id = 9500200
base = 10308                     # Martillo de justicia: copia visual, icono, animacion
name = "Martillo del juicio"
description = "Aturde al objetivo $d y le inflige $s1 de dano Sagrado."
cooldown = [20, 18, 16, 14]      # un valor por rango (o uno solo para todos)
duration = [2, 2.5, 3, 3.5]
effect1 = { type = "SCHOOL_DAMAGE", school = "holy", value = [150, 250, 350, 450] }
effect2 = { type = "APPLY_AURA", aura = "MOD_STUN" }
coefficient = 0.4
```

`tools/spellgen` (Python):
1. Lee la fila base del `Spell.dbc` del cliente (esES, ya en `client/DBCs`).
2. Aplica lo que diga la ficha: nombres de efectos/auras/objetivos legibles (sacados de `SharedDefines.h` y
   `SpellAuraDefines.h` del core) en vez de numeros; segundos en vez de indices (busca el indice de
   SpellDuration/SpellCastTimes/SpellRange/SpellRadius que corresponde, y avisa si no existe).
3. Genera **un hechizo por rango** (ID consecutivos, "Nivel N" en el rango) y escribe SQL idempotente en
   `data/sql/db-world/`: `spell_dbc` + `spell_ranks` + `spell_bonus_data`.
4. `Build-Patch` (ya existe) lleva las filas al `Spell.dbc` del cliente.

Ventajas: se ve en git que cambio, los 4 rangos salen de una sola ficha, se puede ajustar un numero y regenerar
en segundos, y Claude puede escribir/revisar las fichas (el usuario no tiene que conocer los 234 campos).
El Spell Editor queda como **explorador** (opcional): importar el `Spell.dbc` del cliente en una BD aparte
(SQLite, nunca la world) para buscar bases y visuales.

Fuentes de informacion: el propio `Spell.dbc` del cliente (todos los hechizos de 3.3.5 con su texto en espanol),
el codigo de AC (lista de efectos/auras/objetivos y que hace cada uno), la wiki de AC
([spell_dbc](https://www.azerothcore.org/wiki/spell)) y Wowhead (version WotLK) para buscar hechizos por nombre.

## 5. Plan por pasos

1. `tools/spellgen` minimo: copiar una base, cambiar nombre/texto/numeros/tiempos, varios rangos, SQL.
2. Prueba: 1 hechizo (aturdimiento con dano, 4 rangos) en un heroe de prueba -> comprobar tooltip por rango,
   efecto en el servidor y aspecto.
3. Recetas de la seccion 1 una a una (area, aura de grupo, zona en el suelo, DoT, escudo, pasiva, disparo
   automatico) con un hechizo de prueba cada una: la ficha de cada receta queda como ejemplo para copiar.
4. Primer heroe completo (15 hechizos + ataque basico) junto con el sistema de puntos de habilidad.
5. (Opcional) Spell Editor como explorador.

## 6. Uso de `tools/spellgen` (paso 1 hecho y probado 2026-11-14)

```
py -I tools/spellgen/spellgen.py dump 10308         ver como esta hecho un hechizo (campos != 0, con nombres)
py -I tools/spellgen/spellgen.py find martillo      buscar hechizos por nombre (esES)
py -I tools/spellgen/spellgen.py icon holy          buscar iconos
py -I tools/spellgen/spellgen.py build              fichas -> data/sql/db-world/eventwow_spells_<ficha>.sql
```

Despues de `build`: arrancar el worldserver (el updater aplica el SQL; lo reaplica si cambia) o aplicarlo a mano en
la BD de desarrollo, y `Build-Patch` (lee `spell_dbc` de la BD) para el cliente. Reiniciar el worldserver para que
el servidor cargue los cambios.

Fichas en `modules/mod-eventwow/data/spells/*.toml`. Claves de `[[spell]]` (escalar = igual en todos los rangos,
lista = una por rango):

| Clave | Que es |
|---|---|
| `id`, `base`, `name` | obligatorias: primer ID (los rangos son consecutivos), hechizo que se copia, nombre |
| `ranks`, `rank_text`, `chain` | numero de rangos (1), texto de rango ("Nivel {n}"), cadena en `spell_ranks` (true) |
| `description`, `aura_description` | tooltip (por defecto, el de la base) |
| `icon` | textura (`Spell_Holy_SealOfMight`), busca el ID en SpellIcon.dbc |
| `visual` | `SpellVisualID` (aspecto) de otro hechizo; ver con `dump` |
| `cast_time`, `cooldown`, `gcd`, `duration` | segundos (duracion -1 = permanente) |
| `range`, `speed` | alcance en metros, velocidad del proyectil |
| `power`, `cost`, `cost_pct` | mana/rage/energy, coste fijo o % del mana base |
| `school`, `mechanic`, `max_targets`, `family` | escuela, mecanica (STUN...), objetivos maximos, familia (0) |
| `dmg_class` | `none`/`magic`/`melee`/`ranged` (DmgClass): el lanzamiento de los `magic` lo acelera el intelecto, el de los `ranged` la agilidad |
| `haste_periodic` | `SPELL_ATTR5_SPELL_HASTE_AFFECTS_PERIODIC` (celeridad con hechizos en canalizados, DoT/HoT y lanzamiento de los `none`). Por defecto en todo hechizo no fisico canalizado, periodico o `none` con lanzamiento. OJO: acorta TODAS las auras del hechizo (tambien un aturdimiento/raiz que vaya en el mismo) |
| `attributes[_ex..]`, `*_add`, `*_remove` | atributos: poner, anadir o quitar bits |
| `coefficient`, `dot_coefficient`, `ap_coefficient`, `ap_dot_coefficient` | `spell_bonus_data` (<= 0 = calculo por defecto del core) |
| `script` | SpellScript del modulo (`spell_script_names`), p. ej. `spell_eventwow_death_coil` (`EventWowHeroSpells.cpp`) |
| `[spell.fields]` | columnas sueltas de `spell_dbc` por nombre (p. ej. `ProcChance = 25`, `ProcCharges = 0`), escalar o lista por rango |
| `[spell.effectN]` | `type` (SPELL_EFFECT_*, sin prefijo; NONE lo borra), `aura`, `value` o `min`/`max`, `target`, `target_b`, `radius`, `period`, `chain`, `misc`, `misc_b`, `trigger`, `mechanic`, `per_level` (se suma nivel x per_level; por defecto 0: los valores no escalan con el nivel) |

Lo que el generador limpia siempre de la base: categoria de reutilizacion, requisitos/exclusiones por aura de otro hechizo, nivel del hechizo (0: sin penalizacion de
coeficiente ni escalado por nivel, `Unit::CalculateLevelPenalty`), reactivos, totems, arma requerida, formas,
familia/mascara de clase, variables de descripcion y escalado por punto de nivel/combo.
Valor de un efecto = `EffectBasePoints` + 1..`EffectDieSides` (`SpellEffectInfo::CalcValue`): `value = 150` escribe
149 + 1.

Prueba: `data/spells/prueba.toml` (Martillo de prueba, 9500000-9500003, aturdir 2-5 s + 150-450 Sagrado) y el
personaje 19 "Probador de hechizos" en el Asedio (SQL `2026_11_14_01`) con los 4 rangos a la vez.
