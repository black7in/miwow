# Heroes: niveles, habilidades y escala de stats

Diseno de los personajes jugables de los minijuegos con progresion (primero el Asedio, `docs/asedio.md`).
Decidido con el usuario el 2026-11-14. Los personajes siguen siendo fichas en BD (`eventwow_character*`,
"disfraz") sobre el contenedor (elfo de la noche druida); aqui se anade la progresion dentro de la partida.

## 1. Referencia: el mapa de WC3 (`temp/Mi X Hero`)

Leido de `war3mapMisc.txt`, `war3map.w3u` (heroes) y `war3map.w3a` (habilidades):

- **Nivel maximo de heroe: 30** (`MaxHeroLevel=30`).
- **5 habilidades por heroe**: 4 normales (una suele ser un aura) + 1 definitiva.
  - Normales: **4 niveles**, a nivel de heroe **1, 3, 5, 7** (valores por defecto de WC3: requisito 1, salto 2).
  - Definitiva: **2 niveles**, a nivel **6 y 11** (salto 5, puesto en el mapa).
  - Total 4 x 4 + 2 = **18 mejoras**: de 19 a 30 los puntos sobran (solo suben las stats).
- Crecimiento por nivel: atributo principal +2,5 a +7 (los de fuerza +4 a +7).
- Jefes con nivel fijo (15, 20, 25) y stats enormes (100 base, +20 por nivel).

## 2. Nivel real de WoW: 1 a 30 con la experiencia de AzerothCore

- Al empezar la partida el heroe pasa a **nivel 1**; al salir (fin, abandono, logout) vuelve al nivel base
  (`RestoreBaseState`; tambien en cada login, por si el servidor cae a mitad de partida).
- **XP nativa**: barra, aviso y animacion de subida, color de nivel de los enemigos y reparto en grupo (grupos
  nativos), todo del motor. En partida se quita `PLAYER_FLAGS_NO_XP_GAIN`.
- **Tope en 30**: el hook `OnPlayerGiveXP` corta la XP al llegar. El mismo hook aplica un multiplicador por
  juego para ajustar la velocidad de subida (sin tocar `player_xp_for_level`).
- **Las oleadas suben de nivel con el tiempo** (nivel por oleada en los datos del juego). Al ir parejos
  heroes y enemigos, la XP nativa funciona: un enemigo demasiado bajo da poca o ninguna XP.
- **Bloqueados en partida**: puntos de talento (el motor los da desde nivel 10) y logros.
- Vida/mana base del nivel: da igual (a nivel 1 un druida tiene ~50 de vida); la ficha fija la base y el
  crecimiento por nivel va encima.

## 3. Habilidades por niveles

- **Un hechizo propio por cada nivel** de cada habilidad ("Curar" Nivel 1, Nivel 2...), con su descripcion
  y numeros reales: el tooltip lo pinta el cliente desde su `Spell.dbc`, asi que un multiplicador en el
  servidor dejaria el tooltip mal. Descartado el multiplicador por tabla.
- Circuito como los objetos: `spell_dbc` (BD world, servidor) -> `Build-Dbc` -> `Spell.dbc` en `patch-4.MPQ`
  (cliente). IDs >= 9500000. Herramienta prevista para generarlos a partir de un hechizo existente (por decidir:
  "luego vemos como trabajar con hechizos").
- El heroe **empieza sin habilidades**: a nivel 1 tiene 1 punto y elige la primera. **Un punto por nivel**.
- Al tener puntos, la barra de habilidades muestra un **"+"** en las que se pueden mejorar; al pulsarlo el
  servidor valida (puntos libres, nivel de heroe requerido, maximo de la habilidad), cambia el hechizo de la
  casilla por el del siguiente nivel y el tooltip lo refleja.
- **La definitiva se desbloquea a nivel 6.** **La suprema se gana sola a nivel 30** (sin punto).

### Esquema (decidido con el usuario 2026-11-14; ampliado el mismo dia a 4 basicas + suprema)

| Casilla | Rangos | Nivel de heroe para cada rango | Puntos |
|---|---|---|---|
| Basicas 1-4 | 4 cada una | 1, 3, 5, 7 | 16 |
| Definitiva | 3 | 6, 12, 18 | 3 |
| Suprema | 1 | 30 (automatica, premio del nivel maximo) | 0 |
| Atributos | 11 | desde nivel 2 (sin mas limite que los puntos) | 11 |
| **Total** | | | **30** = un punto por nivel |

- **Regla de las basicas**: el rango maximo sube cada 2 niveles: rango maximo = (nivel + 1) / 2 (entero),
  hasta 4. Nivel 1-2 -> rango 1, 3-4 -> 2, 5-6 -> 3, 7+ -> 4 (como el "salto 2" de WC3).
- **Definitiva**: rango maximo 1 a nivel 6, 2 a nivel 12, 3 a nivel 18.
- **Atributos** (como en Dota): cada rango da stats que no dependen del nivel (vida, poder de ataque o con
  hechizos, armadura...; cantidades por heroe en BD). No son hechizos: no hacen falta entradas en `spell_dbc`.
  Sin ellos, del nivel 20 al 30 no habria nada en que gastar.
- **20 hechizos propios por heroe** (4 x 4 + 3 + 1).
- Con 4 basicas, a nivel 7 hay 7 puntos para 16 rangos: hay que elegir que subir; todo al maximo hacia nivel 19.
- **La XP debe permitir llegar a 30 en la fase final** (antes del jefe): si no, la suprema casi no se ve.
- Los puntos se acumulan si no se gastan; no se pueden redistribuir en la partida.
- Barra: teclas 1-4 basicas, 5 definitiva, 6 suprema; "Atributos" como boton aparte (no se lanza). Las de rango 0
  en gris con el "+".
- **Probar un heroe sin partida** (GM): `.eventwow hero <id> [nivel]` | `level <n>` | `off` | `list`
  (EventWowDisguise.cpp; con nivel = con progresion hasta 30, tambien vale `.levelup`; sin nivel = todo aprendido). Con `.dev on`
  + "Ocultar panel" se ve el mundo; enemigos: `.npc add temp 31144` (muneco) / 28104 (esqueleto 80).

### Arthas, caballero de la Muerte (ficha 31) - primer heroe completo (diseno aprobado 2026-11-14)

| Casilla | Habilidad | Que hace | Base (Spell.dbc) |
|---|---|---|---|
| 1 | Golpe de Escarcha | golpe cuerpo a cuerpo con dano de escarcha que ralentiza | 55268 (+ ralentizar propio 9500123, de 6136) |
| 2 | Espiral de la Muerte | proyectil: dana a un enemigo o cura a un aliado | 49895 + script `spell_eventwow_death_coil` (lanza 47632/47633) |
| 3 | Muerte y Descomposicion | zona en el suelo que dana con el tiempo | 49938 (su dano iba por script: aqui PERIODIC_DAMAGE) |
| 4 | Aura de Escarcha | pasiva: armadura a los aliados cercanos, ralentiza a quien le pega | 12556 (armadura de Escarcha de PNJ, efecto 1 -> aura de grupo) |
| Definitiva | Levantar a un muerto | necrofago CONTROLABLE y PERMANENTE (hasta que muere; volver a invocarlo sustituye al anterior); mas fuerte en cada rango | 51533 (SUMMON, SummonProperties 1561) + visual de 52150 / necrofago 26125 |
| Suprema | Furia de la Agonia de Escarcha | mucho dano en area alrededor de Arthas | 70063 (Rey Exanime, ICC; visual 14798) |

Hechizos: `data/spells/arthas.toml` (9500100-9500123). En la ficha 31 (SQL `2026_11_14_06`), de momento el rango 1 de
cada una, hasta el sistema de niveles. `EventWowHeroSpells.cpp`: script de la Espiral y regla de nuestras invocaciones
(sustituir la anterior, escalas de necrofago, aura `trigger` del efecto de invocacion = mejora por rango).

Necrofago: el motor ya lo escala con su dueno. Nivel = el del heroe (`pet_levelstats` de 26125, niveles 1-80) y las
auras nativas de escala de mascota de caballero de la Muerte (`spell_dk_pet_scaling`, 54566/51996/61697) le pasan
el 70 % de la fuerza y el 30 % del aguante del dueno: los libros/objetos/nivel del heroe le suben solos. Por comprobar
con el contenedor druida (los scripts miran al dueno, no su clase). Rangos: necrofago mas fuerte (aura propia o
entrada distinta por rango). Ojo: en modo partida falta mostrar la barra y el retrato de mascota (ver `docs/hechizos.md`).

## 4. Escala de stats: las puntuaciones dependen del nivel

Calculado con las tablas del cliente (`gtCombatRatings`, `gtChanceToSpellCrit`, `gtChanceToMeleeCrit`; druida).
Puntuacion necesaria para un 1 %:

| Nivel | 1-10 | 20 | 30 | 60 | 80 |
|---|---|---|---|---|---|
| Critico | 0,54 | 3,2 | 5,9 | 14 | 45,9 |
| Celeridad / golpe | 0,38 | 2,3 | 4,2 | 10 | 32,8 |
| Pericia | 0,18 | 1,1 | 2,0 | 4,7 | 15,4 |

Ejemplo: +20 de critico = 37 % a nivel 1, 3,4 % a nivel 30, 0,4 % a nivel 80.

- **Agilidad e intelecto** tambien dan critico segun el nivel: 1 de intelecto = 0,14 % de critico con
  hechizos a nivel 1, 0,006 % a nivel 80 (~24 veces menos).
- **Armadura**: reduce mas contra atacantes de nivel bajo (bien para nosotros: heroes y oleadas suben juntos).
- **No dependen del nivel**: aguante (vida), fuerza (poder de ataque), poder de ataque, poder con hechizos,
  vida, mana, regeneracion plana (mp5/hp5).

Decisiones:
1. **Crecimiento por nivel, libros y objetos con stats que no dependen del nivel**: aguante, fuerza, poder de
   ataque, poder con hechizos, armadura, vida, mana.
2. **Stats en porcentaje** para critico/celeridad/golpe/etc. (p. ej. clave `critpct`): `EventWowStats` las
   convierte a puntuacion con la tabla del nivel actual y las recalcula al subir de nivel. "+5 % de critico"
   es siempre un 5 % (y se lee mejor en la tienda).
3. Agilidad e intelecto: cantidades pequenas o asumir su critico extra a nivel bajo; se mide al probar.
4. **Excepcion a las formulas nativas (decidido 2026-11-14): la agilidad sube la velocidad de ataque** (estilo WC3;
   en WoW ninguna stat principal la sube). IMPLEMENTADO y probado 2026-11-16: solo la agilidad EXTRA (total - base del
   contenedor), celeridad % = Max x agi / (agi + Half) (1770 / 1000) en los tres ataques automaticos, suelo de 150 ms
   (config `EventWow.Hero.*`). El motor no tiene tope propio: un golpe por actualizacion del mapa (10 ms). Reglas de conversion propias: solo esta y la siguiente.
   Nativo, sin tocar: fuerza -> +2 poder de ataque (druida sin forma; la agilidad no da poder de ataque),
   poder de ataque -> +1 DPS por cada 14 en cada golpe (tambien sin arma), poder con hechizos -> dano/curacion.
5. **El intelecto sube la celeridad con hechizos** (decidido 2026-11-14). IMPLEMENTADO 2026-11-16 y probado por el usuario
   2026-11-17: "funciona"): como la agilidad, solo el intelecto EXTRA, celeridad % = Max x int / (int + Half) (300 / 1000, config
   `EventWow.Hero.IntellectHaste.*`), `UNIT_MOD_CAST_SPEED` (`ApplyCastTimePercentMod`, como las auras nativas).
   Acelera: lanzamiento de los hechizos `magic`, tiempo global (1,5 s -> minimo 1 s del motor, tope a +50 %) y, con
   `SPELL_ATTR5_SPELL_HASTE_AFFECTS_PERIODIC` (spellgen lo pone por defecto, clave `haste_periodic`): canalizados,
   DoT/HoT (mismos ticks en menos tiempo: mas DPS, no mas dano total) y lanzamiento de los `none`. Los hechizos
   fisicos (melee/ranged: Salva, Filotormenta, Lanzar roca) van con la agilidad. Suelo de lanzamiento
   `EventWow.Hero.SpellCastMinTime` = 500 ms (hook nuevo del core `ModifySpellCastTime`): la celeridad no baja de
   ahi, pero no alarga hechizos que ya eran mas cortos (0,3 s sigue igual) ni toca instantaneos.
   La reutilizacion no la reduce nada de esto.
6. **Reduccion de reutilizacion**: ninguna stat nativa la da (en WoW solo talentos, glifos, bonus de conjunto y auras
   concretas). No habra stat propia; quiza algun objeto ("-20 % de reutilizacion", aura de modificador de
   reutilizacion sobre la familia de nuestros hechizos). Se vera con la tienda.

## 5. Balance

- **Mismo presupuesto por heroe** a cada nivel, repartido distinto (tanque: vida; mago: dano en area;
  sanador: curacion). Objetivos medibles (p. ej. "un heroe de dano a nivel 10 limpia una oleada de carril en
  ~8 s", "el tanque aguanta ~20 s una oleada solo").
- **Calculadora** (Python en `tools/`, por hacer): con las formulas nativas y los coeficientes de los hechizos,
  DPS / vida efectiva / curacion por segundo de cada heroe a cada nivel, para ajustar antes de probar.
- **Registro por partida** (lo mas importante): dano hecho/recibido, curacion y muertes por heroe (log o
  tabla). Se corrige en la BD sin compilar.
- Los enemigos escalan con el tiempo y con el numero de jugadores, no con el nivel de los heroes.

## 6. Pendiente

- **Ataque basico: IMPLEMENTADO (2026-11-14, sin compilar ni probar)**:
  - Ficha `eventwow_character` (SQL `2026_11_14_09`): `AttackSpeed` (ms; 0 = sin ataque basico, no se toca nada),
    `AutoAttackSpell` (0 = "Atacar" cuerpo a cuerpo), `AttackMin/AttackMax` (nivel 1) + `AttackPerLevel` (arma
    invisible, solo cuerpo a cuerpo). Con `AttackSpeed` el ataque es el primer hechizo de la barra (casilla 1, tecla 1;
    fijo, siempre aprendido), antes de las habilidades.
  - Cuerpo a cuerpo: `SetBaseWeaponDamage` + `SetAttackTime(BASE_ATTACK)` al disfrazarse y al cambiar de nivel
    (`EventWowDisguise`); al quitar el disfraz, como sin arma (1-2, 2 s).
  - Distancia/lanzadores: disparo automatico propio (`data/spells/ataques.toml`, 9509020-9509024): dano del hechizo
    = min-max a nivel 1 + `per_level` por nivel (clave nueva de spellgen: `EffectRealPointsPerLevel`) + poder de
    ataque a distancia (Sylvanas, familia de cazador sin mascara) o poder con hechizos (lanzadores). Intervalo =
    `AttackSpeed` (`SetAttackTime(RANGED_ATTACK)`).
  - Clic derecho: hook nuevo del core `OnPlayerCanAttackSwing` (`docs/core-changes.md`): con disparo automatico, en
    vez de golpear se lanza el disparo. El core corta los disparos automaticos (salvo el 75 del cazador) al moverse
    o al lanzar otro hechizo: el modulo lo vuelve a lanzar al pararse si el objetivo sigue seleccionado (ventana de
    0,6 s; si falta estando quieto, lo cancelo el jugador y se olvida).
  - Cliente: la casilla del ataque se marca mientras esta activo (`IsCurrentSpell` / `IsAutoRepeatSpell`).
  - **Armas EQUIPADAS de verdad (decidido con el usuario 2026-11-16; SIN COMPILAR NI PROBAR)**. Problema (probado
    2026-11-14 con Sylvanas): disparaba sin animacion y con el arco envainado. Causa: el Disparo automatico nativo (75)
    lleva `SPELL_ATTR0_USES_RANGED_SLOT`; con el, el CLIENTE mira el arma equipada en la ranura de distancia, elige la
    animacion (arco/escopeta/arrojadiza), la saca a la mano y usa la municion como proyectil; sin arma equipada el
    atributo se habia quitado y el hechizo no se animaba. Un emote de disparo por cada tiro (probado 2026-11-16)
    salia "interrumpido": descartado.
    - Las armas de la ficha (`WeaponMainHand/OffHand/Ranged`, SQL `2026_11_16_00`) las EQUIPA el servidor durante el
      disfraz (`EventWowWeapons::Equip`, `EquipNewItem`: sin comprobaciones de clase/habilidad/nivel) y se destruyen
      al quitarlo (`Unequip`; `ClearInventory` en login como red). No se pueden quitar ni destruir (hook
      `OnPlayerCanUnequipItem`); si faltan, `EventWowDisguise::Update` (1 s, en partida) las repone.
    - Habilidad de arma: el core no la mira para atacar con lo equipado, pero su valor entra en la tabla de golpe (con
      0 falla casi todo). Se da la que le falte al druida al maximo del nivel (`SetSkill`, y al subir de nivel) + la
      competencia al cliente (`SMSG_SET_PROFICIENCY`). Sin SkillRaceClassInfo: si quedara guardada (caida del
      servidor), el core la borra al hacer login por no ser de druida.
      ACTUALIZADO 2026-11-16 (sin probar): el contenedor tiene TODAS las armas de forma permanente (SQL `_16_01`):
      filas de druida en `skillraceclassinfo_dbc` (9500000-9500008, tambien en el DBC del cliente),
      `playercreateinfo_skills` + `playercreateinfo_spell_custom` (competencias 201/196/264/266/202/197/2567/5011/5009)
      aprendidas en cada login (override `PlayerStart.CustomSpells = 1`). Equip ya no anade habilidades (las tiene).
      Probado: con eso el druida equipa el arco, pero en rojo, sin envainar/desenvainar y sin ranura de municion:
      el druida tiene ranura de RELIQUIA (`ChrClasses.dbc` Flags bit 0x08, solo paladin/DK/chaman/druida). SQL `_16_02`:
      druida 0x0A -> 0x02 (solo cliente; Build-Dbc `ExtraRanges` chrclasses_dbc ID 11). Probado: Sylvanas dispara y anima.
    - Mano izquierda con arma: doble empunadura (golpea con la penalizacion nativa); escudo: solo aspecto (el druida no
      bloquea). Arco/escopeta/ballesta: aura 46699 "No necesita municion" (proyectil de flecha en el `SPELL_GO`).
    - Armas propias 9500200 (arco de Sylvanas) y 9500210-9500222: aspecto de las de PNJ, sin stats ni durabilidad,
      dano y velocidad normales de su tipo (1 mano 2,6 s, daga 1,8, 2 manos 3,6, baston 3,3, arco 2,8).
    - Dano: cuerpo a cuerpo = el de la ficha (`AttackMin/Max/PerLevel`, a la velocidad de referencia `AttackSpeed`)
      escalado por (velocidad del arma / `AttackSpeed`): mismo dano por segundo, golpes mas lentos y fuertes con un
      arma de dos manos (hook `OnPlayerApplyWeaponDamage` + `ApplyAttack`). Intervalo = el del arma; sin arma,
      `AttackSpeed`. Disparos: dano del hechizo (9509020 escalado a 2,8 s: 56-84 + 11,2/nivel), intervalo = el del
      arma de distancia (lanzadores sin ella: `AttackSpeed`).
    - 9509020 conserva `USES_RANGED_SLOT` y pide arco/escopeta/ballesta/arrojadiza (`[spell.fields]`). El cliente ya
      no desenvaina a mano. Igual las habilidades de disparo de Sylvanas (Multidisparo, Flecha negra, Salva): se les
      habia quitado el atributo y por eso no usaban el arco (2026-11-16). Regla: habilidad de disparo de un heroe CON
      arma de distancia = conservar el atributo; sin arma (Lor'themar, Disparo Arcano) = quitarlo.
    - Arthas (9500210): el arma de PNJ es de una mano; la copia es maza a dos manos (el usuario lo pidio).
    - Logout: el disfraz se quita en `OnPlayerBeforeLogout` (antes de `SaveToDB`; `OnPlayerLogout` llega despues).
      Sin eso el arma quedaba guardada y al hacer login el core la mandaba por correo.
    - PROBAR: Sylvanas (33) anima el disparo y saca el arco (y se ve el arco envainado en la espalda: antes se
      penso que la ranura de distancia no se dibujaba, pero se probo con un arco de PNJ de envainado 0); la flecha
      sale; Garrosh (43) golpea con las dos hachas; Lor'themar (42) con escudo; heroes de dos manos (31, 35, 36, 41)
      golpes cada 3,6 s; que no fallen casi siempre (habilidad de arma); que no se puedan quitar ni destruir; que al
      quitar el disfraz (`.eventwow hero off`, fin de partida, logout) no quede ni arma ni habilidad (Sylvanas sin
      "Arcos"); un GM en modo dev con armas propias no las pierde (esa ranura no se toca).
  - Probado: disparo de Kel'Thuzad bien. Solo la celeridad (`haste`) acelera los disparos (temporizador de distancia);
    la regla de la agilidad (seccion 4, regla 4) sigue sin implementar.
  - PROBAR: animaciones, que moverse y pararse reanuda el
    disparo, que Esc / cambiar de objetivo lo para, dano por nivel (`.eventwow hero <id> <nivel>`).
- Diseno del ataque basico (decidido 2026-11-14: todos los heroes), segun el tipo de heroe en su ficha:
  - **Cuerpo a cuerpo**: ataque automatico nativo (todos los personajes de WoW pueden pegar cuerpo a cuerpo,
    tambien sin arma). Dano base por ficha y por nivel (`SetBaseWeaponDamage`, el "arma invisible") + velocidad
    de ataque base; encima el motor suma el poder de ataque (fuerza) y el critico.
  - **A distancia** (arqueros, pistoleros): hechizo propio de disparo automatico (se repite solo mientras haya
    objetivo) con el arma de distancia de la ficha equipada de verdad (ver "Armas EQUIPADAS" arriba).
  - **Lanzadores** (magos...): en WoW atacan a distancia con varita ("Disparar", automatico). Igual que los de
    distancia: disparo automatico propio con proyectil magico, mas flojo.
  - Los de distancia/lanzadores calculan su dano en el servidor (base + nivel + stats): el druida contenedor no
    tiene poder de ataque a distancia nativo.
  - Velocidad: la agilidad sube la de todos los tipos (regla 4 de la seccion 4); tope 1 golpe / 0,3 s (aceptado).
- Forma de crear los hechizos (herramienta).

## 7. Orden de implementacion

Pasos 1 y 2 implementados juntos (2026-11-14, probados por el usuario; interfaz a mejorar): `EventWowProgress.*` (nivel 1 -> `MaxLevel` del juego,
`XpRate`, puntos, rangos, atributos, talentos/logros/correo de nivel bloqueados, nivel base al salir y en el login),
`eventwow_character_spell.Kind` (0 fija, 1 basica, 2 definitiva, 3 suprema) y `eventwow_character_attribute` (SQL
`_07`), protocolo v8 (`MATCH_ABILITIES` / `UPGRADE`), barra con rangos, "+", Atributos y barra de XP
(`EventWowAbilities.lua`; lanza por nombre = rango mas alto aprendido). Asedio: `MaxLevel = 30`.

1. Nivel 1 en partida, XP nativa con tope 30 y multiplicador, vuelta al nivel base; talentos y logros bloqueados.
2. Puntos de habilidad: tabla de habilidades por heroe (hechizo por nivel, nivel requerido), protocolo y "+" en
   la barra.
3. Crecimiento de stats por nivel (tabla por heroe) y stats en porcentaje en `EventWowStats`.
4. Hechizos propios por nivel (herramienta + `spell_dbc`) y un heroe completo de prueba.
5. Registro de partida y calculadora para el balance.
