# Asedio - estado del desarrollo (PAUSADO 2026-11-17)

Diario del evento Asedio movido desde `CLAUDE.md` al pausarlo (2026-11-17), sin cambios de contenido.
Documentos relacionados: `docs/asedio.md` (logica del mapa y plan por pasos), `docs/heroes.md` (diseno de heroes,
niveles, stats, ataque basico), `docs/heroes-habilidades.md`, `docs/heroes-modelos.md`, `docs/hechizos.md`,
`docs/mapas.md` (mapa 751).

## Donde quedamos al pausar (2026-11-17)

- Hecho y probado: mapa 751 completo, eleccion de heroe estilo WC3, 15 heroes con modelo/armas equipadas, niveles
  1-30 y puntos de habilidad, ataque basico, agilidad -> velocidad de ataque, intelecto -> celeridad con hechizos.
- REVISAR: autoataque de los magos no para con Esc; si es cuerpo a cuerpo o distancia y que stat lo sube
  (`docs/heroes.md` sec. 6).
- Pendiente de probar (sin prisa, el usuario): resto de "PROBAR" en `docs/heroes.md` sec. 6 y las habilidades de los
  14 heroes (`docs/heroes-habilidades.md`).
- SIGUIENTE al reanudar: logica del evento (oleadas, regiones, flujo de partida; `docs/asedio.md`).

## Diario

- **Mapa del asedio (751): modelos de muralla HECHOS y probados por el usuario (2026-11-13: "perfecto").** `wallModels` en `maps.json` (ver "Modelos de muro" en
  `docs/mapas.md`), `SC_Wall_01.M2` (muralla de la Plaga) por las caras de los muros (contorno simplificado: diagonales
  reales). v1 (escala 1, 993 modelos en las dos caras) probada por el usuario: los muros salen, pero pequenos/
  "chatos" y se notaba el relieve del terreno; pidio el doble de alto y ~50% mas de ancho. v2 (probada: tamano bien): escala 2
  (uniforme: 24 x 18.6 x 12.8), 378 modelos centrados en los muros finos (salta caras ya tapadas), muro de terreno = huella
  de los modelos a suelo + 8, borde exterior a 11.7 (sin roca detras); pero el muro de terreno asomaba en "dientes" de
  roca por las caras (triangulos de la malla). v3 (huella encogida 3 yardas, `terrainInset`): mucho mejor, aun asomaba
  algo. v4 (probada, "perfecto"): `terrainInset` 5 y `terrainHeight` 5 en maps.json. Despues el usuario encontro pasos
  entre salas: centro de los cruces en "+"/"T" sin modelo (Sala Sur 1 <-> otras) y cuellos diagonales (Sala Sur 2/3 <->
  Cruce_Punto_Suroeste/Sureste). v5 (el usuario: "satisfecho con el mapa, por el momento lo dejamos aqui"): pasada de relleno (39 modelos a 0/90 grados en cruces y cuellos, sin pisar
  puntos de region), 468 modelos; comunicacion entre regiones = WC3 (comprobado por script). Parche y `.map` regenerados.
  Vista previa (no versionada): `tools/mapgen/_work/muros_751*.png`. Familia por si hace falta: SC_Wall_01_Cap 5.0x9.4x6.4 (remate), SC_Wall_01_Ramp,
  SC_Wall_02..06, SC_Wall_Decoration_01/02 (carpeta `World\Expansion02\Doodads\Generic\Scourge`; ninguna esta suelta en
  los ADT de Rasganorte, solo dentro de WMO). Posibles mejoras: remates (Cap) en extremos libres.
  Zona + minimapa (el usuario: "perfecto", 2026-11-13; decision del usuario: un solo nombre de zona para todo el mapa, es una mazmorra de
  evento): SQL `_12` (`areatable_dbc` 5000 "Prueba WC3" / 5001 "Asedio", `map_dbc.AreaTableID`; aplicado a mano en la
  BD de desarrollo), `areaId` en maps.json (MCNK + `.map`), minimapas generados por mapgen + `md5translate.trs`
  (original en `client/Minimap/`, no versionado), `MinimapCluster` visible en partida sin botones. Ver `docs/mapas.md`.
  vmaps + mmaps (dados por buenos por el usuario 2026-11-13; LoS en el juego aun sin PNJ que lo pongan a prueba): `tools/mapgen/vmaps.py` escribe `751.vmtree`, `751_<tx>_<ty>.vmtile` y
  `Sc_Wall_01.m2.vmo` en `data\vmaps` (el extractor de AC no lee nuestro parche-carpeta). Validado: `.vmo` identico al
  oficial (probado con SC_Wall_01_Cap), nombres de tile como los oficiales, linea de vision simulada bloqueada por muros.
  Despues: funcion de cada region con el amigo (renombrar en `regionNames`), minijuego de oleadas.
  Logica del mapa de WC3 analizada (2026-11-13, `temp/Mi X Hero`, script ofuscado): ver `docs/asedio.md` (flujo, funcion
  de cada region, adaptacion a 1 personaje y plan por pasos; nombres/jefes/objetos propios, no los del mapa de terceros).
  Pendiente tambien: completar el paso 6 (inventario + HUD; commit incompleto), ver arriba.
  Asedio paso 1 (2026-11-14, compilado y probado por el usuario: "funciona el pick"): fase de eleccion `Picking` en el framework (Loading -> Picking ->
  Countdown; `GetPickTime()` > 0 y >= 2 personajes; eleccion definitiva, unica por defecto, al azar al acabar el tiempo o
  todos elegidos antes; protocolo v7 `PICK`/`MATCH_PICK`/`MATCH_PICKS`/estado `PICKING`; cliente `EventWowPick.lua`).
  Juego `asedio` (`games/EventWowGameSiege.cpp`, sustituye a `test_siege_map`; 1-5 jugadores, 6 casillas) con 4 heroes
  provisionales (SQL `_14_00`, Id 10-13). Durante la eleccion el jugador puede moverse (sin disfraz).
  Heroes (diseno decidido con el usuario 2026-11-14, SIN IMPLEMENTAR): ver `docs/heroes.md`. Nivel real de WoW 1 -> 30 en
  partida con la XP nativa de AC (tope y multiplicador con `OnPlayerGiveXP`), oleadas que suben de nivel, talentos y
  logros bloqueados, un hechizo propio por nivel de habilidad (tooltip correcto; `spell_dbc` + Spell.dbc), un punto por
  nivel con "+" en la barra, definitiva a nivel 6. Las puntuaciones (critico, celeridad...) valen mucho mas a nivel bajo:
  crecimiento con stats que no dependen del nivel + stats en porcentaje (`critpct`) convertidas segun el nivel.
  Esquema: 3 basicas x 4 rangos (rango max = (nivel+1)/2: niveles 1/3/5/7), definitiva x 3 (6/12/18), Atributos x 15
  (desde nivel 2, stats por rango) = 30 puntos. Agilidad -> velocidad de ataque e intelecto -> celeridad con hechizos
  (unicas reglas propias, 0,5 %/punto provisional, tope 1 golpe/0,3 s). Ataque basico para todos: cuerpo a cuerpo nativo
  con dano base por ficha; distancia y lanzadores con disparo automatico propio (sin arma).
  Hechizos propios (plan 2026-11-14, sin implementar): ver `docs/hechizos.md`. Fichas TOML por heroe -> `tools/spellgen`
  (copia una base del Spell.dbc del cliente, un hechizo por rango) -> SQL `spell_dbc` + `spell_ranks` +
  `spell_bonus_data` -> Build-Dbc. Spell Editor de Stoneharry solo como explorador. OJO: texto esES = hueco 6 de cada
  texto (columna `*_Lang_zhCN` en spell_dbc, los nombres de AC no siguen el orden de 3.3.5).
  Paso 1 hecho (2026-11-14, probado por el usuario: "hechizos funcionando"): `tools/spellgen/spellgen.py` (build/dump/find/icon), ficha
  `data/spells/prueba.toml` -> `eventwow_spells_prueba.sql` (Martillo de prueba 9500000-9500003), personaje 19
  "Probador de hechizos" en el Asedio (SQL `_14_01`). Ambos SQL aplicados a mano en la BD de desarrollo; parche regenerado.
  Paso 2 (2026-11-14, probado por el usuario: "funciona"): bateria de recetas en `prueba.toml` (9500010-9500027: lanzamiento 2 s, area, suelo,
  DoT, HoT, curacion 1,5 s, escudo, mejora de grupo, aura de grupo, aura de inmolacion (aura + hechizo disparado),
  nova/raiz, carga, empujar, cadena, canalizado, disparo automatico sin arma, pasiva). Personajes 20 "Probador ofensivo"
  y 21 "Probador de apoyo" (SQL `_14_02`). spellgen: claves `visual`, `type = "NONE"`, limpia `*AuraSpell`.
  Invocaciones 9500028 (lobo controlable: SummonProperties 1561, categoria PET -> barra de mascota) y 9500029 (2 arboles
  guardianes no controlables: SummonProperties 61). En modo partida la barra/retrato de mascota no se muestran (anadirlos
  si un heroe invoca). Pasiva: la base llevaba DO_NOT_DISPLAY (0x80), quitado.
  Enemigos para probar: `.dev on` + `/eventwow` (chat nativo) + `.npc add temp 28104` (Enraged Skeleton 80) / 31144 (muneco).
  **DONDE QUEDAMOS (2026-11-14)**: heroes del Asedio = jefes/personajes de WoW (Arthas, Rey Exanime, Thrall,
  Sylvanas...). Lista de modelos en `docs/heroes-modelos.md` (displays de la BD + arma de cada PNJ). El usuario los esta
  probando con `.morph` y pasara SU LISTA de heroes con el modelo elegido; despues: definir habilidades de cada uno
  (`docs/heroes.md`: 3 basicas x 4 + definitiva x 3 + atributos; fichas con spellgen) e investigar armas visibles sin
  equipar (las armas no son parte del modelo). Lista inicial de 15 heroes con modelo y armas HECHA (2026-11-14, tabla
  "Lista inicial" en `docs/heroes-modelos.md`). Armas sin equipar: prototipo `EventWowWeapons.cpp` (comando
  `.eventwow weapon set/sheath/clear`, escribe `PLAYER_VISIBLE_ITEM_*`), probado por el usuario: se ven sobre el modelo
  transformado, la Z envaina/desenvaina; `sheath` no hace nada (el cliente controla el envainado propio; quitarlo) y
  la ranura de distancia no se dibuja (arcos en la mano derecha; OJO: probado con un arco de PNJ de envainado 0, a
  revisar con las armas equipadas de 2026-11-16). Armas propias 9500200-9500299 (SQL
  `2026_11_14_03`, 9500200 = arco de Sylvanas visible envainado). Siguiente: armas en la ficha (`eventwow_character`)
  aplicadas por el disfraz.
  **Eleccion estilo Warcraft 3 (decidida con el usuario 2026-11-14, probada: "todo bien"; tamanos a ajustar por el usuario)**: en el Asedio los heroes son PNJ en
  circulo (radio 16) alrededor de la region Inicio (el jugador entra en el centro); se elige hablando con uno (dialogo + confirmacion, definitiva) y su
  PNJ desaparece. Tiempo 60 s; al acabar, al azar a quien no eligio. La ventana `EventWowPick.lua` se mantiene para otros
  juegos (`GetPickPositions()` vacio = ventana). Framework: `EventWowMatch::GetPickPositions/MakePickCircle/CanPick`,
  `UpdatePickCreatures` (aspecto de la ficha: modelo, escala, armas con `SetVirtualItem`); `EventWowPickCreature.cpp`
  (`npc_eventwow_pick`). Ficha: `WeaponMainHand/WeaponOffHand` (el disfraz las pone con `EventWowWeapons`, hook
  `OnPlayerAfterSetVisibleItemSlot` las repone) y `PickCreature` (SQL `_04`). SQL `_05`: 15 heroes (fichas 30-44, sin
  habilidades), PNJ 9500300-9500317 generados desde las fichas (+ `npc_text` mismo ID = descripcion), Asedio = heroes +
  probadores 19-21 (los 10-13 fuera). `_04`/`_05` aplicados a mano en la BD de desarrollo.
  Esquema de habilidades ampliado (2026-11-14): 4 basicas x 4 + definitiva x 3 + suprema (sola a nivel 30) + 11 de
  atributos (`docs/heroes.md`). `.eventwow hero <id>|off|list` (EventWowDisguise.cpp): probar un heroe sin partida.
  **Arthas caballero de la Muerte (ficha 31), probado por el usuario 2026-11-14 ("todos los hechizos probados")**: `data/spells/arthas.toml` (spellgen: clave nueva
  `script`), `EventWowHeroSpells.cpp` (Espiral de la Muerte, invocaciones), SQL `_06` (rango 1 de cada habilidad),
  barra de mascota nativa en partida (`EventWow_ApplyPetBar`, EventWow.lua). SQL aplicados a mano en la BD de desarrollo.
  Despues: base de niveles (paso 1 de `docs/heroes.md`, requiere compilar).
  **Niveles y puntos de habilidad (pasos 1-2 de `docs/heroes.md`, 2026-11-14, probado por el usuario: "funciona"; interfaz a mejorar mucho, afinar hechizos despues)**:
  `EventWowProgress.*` (nivel real 1 -> `EventWowGameInfo::MaxLevel`, XP nativa x `XpRate` con tope, un punto por
  nivel, rangos = cadena de spell_ranks, atributos de `eventwow_character_attribute`, suprema sola al maximo;
  talentos/logros/correo de nivel bloqueados; `Stop` desde `EventWowDisguise::Remove` = nivel base; login = nivel
  base). `EventWowMatch::SetCharacter`: con `MaxLevel` -> nivel 1 antes del disfraz (mide la vida nativa) +
  `Apply(..., true)` (solo fijas) + `Start`. Asedio `MaxLevel = 30`. SQL `_07` (columna `Kind` + atributos de
  Arthas; aplicado a mano en la BD de desarrollo). Protocolo v8 (`MATCH_ABILITIES`/`UPGRADE`). Cliente
  `EventWowAbilities.lua`: rango "n/m", gris sin aprender, "+" (no seguros), boton Atributos, barra de XP, nombre
  con nivel/puntos; lanza por NOMBRE (rango mas alto aprendido). `EventWow.lua`: barra nativa oculta con disfraz
  (tambien en modo dev), pet bar mas arriba (GAP 40). Comando `.eventwow hero <id> [nivel]` / `hero level <n>`.
  **Habilidades de los 14 heroes restantes (2026-11-14, SIN COMPILAR NI PROBAR; el usuario lo mandara a probar a
  otros)**: `docs/heroes-habilidades.md` (diseno, IDs, cambios al implementar). 14 fichas TOML + `comun.toml`
  (Poder de invocacion 9509000-001, Reencarnacion agotada 9509010), SQL `_08` (habilidades/Kind de las fichas 30 y
  32-44, atributos por papel, criaturas 9500400 serpiente / 9500401 fenix). `EventWowHeroSpells.cpp`:
  `spell_eventwow_black_arrow`, `spell_eventwow_reincarnation`; solo las invocaciones controlables sustituyen a la
  anterior. spellgen: clave `[spell.fields]` (columnas sueltas, p. ej. `ProcChance`). Todo aplicado a mano en la BD
  de desarrollo y parche regenerado.
  **Ataque basico de los heroes (2026-11-14, SIN COMPILAR NI PROBAR)**: `docs/heroes.md` seccion 6. Casilla 1 = ataque
  ("Atacar" con arma invisible de la ficha, o disparo automatico propio `data/spells/ataques.toml` 9509020-024) y
  clic derecho (hook nuevo del core `OnPlayerCanAttackSwing`, commit `ab105ded2`). Columnas
  `eventwow_character.AutoAttackSpell/AttackMin/AttackMax/AttackPerLevel/AttackSpeed` (SQL `_09`, aplicado a mano),
  spellgen `per_level`. Parche regenerado.
  Probado por el usuario (2026-11-14): disparo de Kel'Thuzad bien; Sylvanas disparaba sin animacion con el arco
  envainado (el cliente anima segun el arma EQUIPADA en la ranura de distancia). Un emote por disparo salia
  "interrumpido" (probado 2026-11-16, descartado). Tambien corregido `UNIT_MASK_CONTROLABLE_GUARDIAN` ->
  `IsControllableGuardian()` en `EventWowHeroSpells.cpp` (error de compilacion de `ca464c0`).
  **Decision del usuario (2026-11-16): las armas de los heroes se EQUIPAN de verdad durante el disfraz** (todas:
  derecha, izquierda y distancia; excepcion a "los objetos no se equipan", que sigue valiendo para los de la tienda).
  SIN COMPILAR NI PROBAR: `EventWowWeapons::Equip/Unequip` (EquipNewItem, habilidad de arma que falte + competencia,
  doble empunadura, aura 46699 sin municion; no se pueden quitar; Update las repone), `EventWowDisguise` (dano de la
  ficha escalado a la velocidad del arma, hook `OnPlayerApplyWeaponDamage`), columna `WeaponRanged`, armas propias
  9500200 + 9500210-9500222 sin stats, dano/velocidad normales de su tipo (SQL `2026_11_16_00`, aplicado a mano en la
  BD de desarrollo junto con `eventwow_spells_ataques.sql`; parche regenerado). 9509020 recupera `USES_RANGED_SLOT`.
  Detalle y "PROBAR" en `docs/heroes.md` sec. 6.
  Probado por el usuario (2026-11-16): armas equipadas BIEN en todos los heroes (Arthas ya a dos manos, Garrosh doble
  empunadura, Kel'Thuzad). Sylvanas NO: ni dispara con el arco ni lo desenvaina, tampoco tras devolver
  `USES_RANGED_SLOT` a Multidisparo/Flecha negra/Salva. Ademas sus disparos daban "fuera de rango" a cualquier
  distancia: causa = `RangedModRange` 0 del arco (copiado de PNJ; el CLIENTE lo usa como % del alcance) -> 100 (SQL
  `_16_00` aplicado; sin probar; hace falta borrar la carpeta Cache del cliente: datos de objeto cacheados).
  Pendiente de diagnostico (el usuario tuvo que salir): `.demorph` con el disfraz puesto y disparar: si el elfo saca
  el arco y anima, el problema es el modelo de criatura (28213) y hay que buscar otra via; mirar tambien con C (modo
  dev + /eventwow) que el arco esta en la ranura de distancia. Posible relacion con el alcance 0.
  RESUELTO (probado por el usuario 2026-11-16: "lo hicimos"): el druida tenia ranura de RELIQUIA (`ChrClasses.dbc`
  Flags bit 0x08) -> arco en rojo, sin envainar ni municion. SQL `_16_01` (TODAS las habilidades de armas al druida:
  `skillraceclassinfo_dbc` + `playercreateinfo_skills` + `playercreateinfo_spell_custom`, override
  `PlayerStart.CustomSpells = 1`) y `_16_02` (druida Flags 0x0A -> 0x02, Build-Dbc `ExtraRanges` chrclasses_dbc).
  Sylvanas dispara y anima. Probado tambien (2026-11-16, "todo esta bien"): icono del disparo (icono propio en
  `ataques.toml` + `EventWowAbilities.lua` refresca iconos con PLAYER_EQUIPMENT_CHANGED, el cliente da el del arma a
  los hechizos de ranura de distancia) y la casilla del ataque basico ya no se corta al pulsarla varias veces (boton
  "macro": `/startattack` para 6603, `/cast !<nombre>` para 9509020-9509039).
  Todo lo anterior COMMITEADO (2026-11-16).
  Velocidad de ataque (2026-11-16): SOLO la agilidad EXTRA (total - base del contenedor) sube la celeridad de
  todos los ataques automaticos: % = Max x agi / (agi + Half), suelo AttackMinInterval (config
  `EventWow.Hero.AgilityHaste.Max/Half` = 1770/1000, `EventWow.Hero.AttackMinInterval` = 150 ms;
  `EventWowDisguise::UpdateAgilityHaste` cada 250 ms, se deshace en `Remove`). PROBADO por el usuario 2026-11-16 ("funciona").
  Celeridad con hechizos (2026-11-16, PROBADO por el usuario 2026-11-17: "funciona"): igual con el intelecto EXTRA (`UpdateIntellectHaste`,
  `EventWow.Hero.IntellectHaste.Max/Half` = 300/1000, `UNIT_MOD_CAST_SPEED`); spellgen pone
  `SPELL_ATTR5_SPELL_HASTE_AFFECTS_PERIODIC` por defecto (clave `haste_periodic`, nueva `dmg_class`); SQL de hechizos
  regenerados. Suelo de lanzamiento 500 ms (`EventWow.Hero.SpellCastMinTime`, hook nuevo del core
  `UnitScript::ModifySpellCastTime`, commit del core `b88f7bc5d`). Detalle en `docs/heroes.md` sec. 4 regla 5. Comando de prueba
  `.eventwow attackspeed set <pct> | lineal <agi> | wc3 <agi> | off` (EventWowStats.cpp). Problema encontrado: a esa
  velocidad nuestro disparo automatico cortaba las habilidades (Salva...); con el 75 no (probado). Causa: el core da
  reglas propias solo al ID 75. Cambio al core `04ab628c7` (probado: Salva ya no se corta): `SpellInfo::IsAutoShot` + `SpellMgr::SetSpellAutoShot`
  (docs/core-changes.md); `EventWowCharacters::Load` marca los `AutoAttackSpell` de las fichas. REVISAR (anotado 2026-11-17, ver `docs/heroes.md` sec. 6): autoataque de los magos no para con Esc; si es cuerpo a cuerpo o distancia y que stat lo sube. Pendiente (lo hara el usuario sin prisa): el resto de "PROBAR" en
  `docs/heroes.md` sec. 6 y probar las habilidades de los 14 heroes.
  **SIGUIENTE (decidido por el usuario 2026-11-16)**: la logica del evento del Asedio (oleadas, regiones, flujo de
  partida; ver `docs/asedio.md`).
