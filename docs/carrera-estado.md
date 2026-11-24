# Carrera de motos: estado

Juego de carreras por vueltas (tipo Mario Kart). Codigo: `modules/mod-miwow/src/games/MiWowGameRace.cpp`, cliente
`client/src/Interface/FrameXML/MiWowRace.lua`. Mapas de circuito generados sin Warcraft 3 desde un plano JSON
(`tools/mapgen/trackgen.py` y `platformgen.py`, ver "Circuitos" en `docs/mapas.md`).

Decisiones del usuario (2026-11-17): circuito cerrado con vueltas, varios ambientes, en moto (vehiculo), 1-8 jugadores,
moto a 28 yd/s, al acabar resultados en pantalla + boton "Salir", nadie se mueve tras terminar.

## Mapas
- **752 "Circuito de las Cuatro Tierras"** (`Maps/Planos/circuito_cuatro_tierras.json`, SQL `2026_11_17_00`). PROBADO
  ("esta super"; algunas rocas flotan un poco). Juego `carrera`.
- **753 "Circuito Estelar"** (`Maps/Planos/circuito_estelar.json`, `"type": "platforms"`, SQL `2026_11_17_01`). PROBADO.
  Pista en el espacio sin barandillas: sin terreno (ADT todo agujeros, tambien en el `.map` del servidor) + piezas M2
  encadenadas como decoracion del ADT (colision en cliente y vmaps; inclinadas en subidas con MDDF rot[0]/rot[2]).
  Pieza = `SC_Platform2` de la Plaga (elegida por el usuario; cambiar = `model`/`scale` del plano). Cielo = luz global
  propia (`light_dbc` 2600-2699, copia de la del Ojo de la Eternidad). 3516 yd, ocho con CRUCE (el segundo paso va 21 yd
  por debajo: el seguimiento usa tambien la z). Caer: el core mata por debajo de z -500 (pista a -380..-326).
  Juego `carrera_estelar`.
- Meta decorada: 752 arco del Torneo Argenta x7 (colision solo en los pilares, abertura ~27 yd) + estandartes + banderines
  en los controles (props `at`/`side: center` en trackgen); 753 arco tecnologico draenei (sin colision) + pilones.

## Fase 1: carrera (PROBADA 2026-11-17, "ahora si funciona")
- Lee `<DataDir>/maps/<id>_pista.json` al arrancar (sin el, el juego sale "no disponible").
- Seguimiento por ventana alrededor de la muestra anterior (3D: cruces) -> avance, vueltas, posiciones, direccion
  contraria. 2 vueltas, cuenta atras 10 s. Seguimiento con la posicion de la MOTO.
- Parrilla de 8 por `MiWowMatch::GetArrivalPosition` (cada piloto llega a su puesto). Sin `TeleportVehicle` (baja al
  jugador y lo resube por clic y descoloca el control).
- Raiz (UNIT_STATE_ROOT) solo en la moto (al jugador montado el core no deja quitarsela), en carga/cuenta atras/tras
  llegar/resultado; con moto nueva la raiz se reenvia a los 500 ms.
- Caer (z < suelo - `FallDepth`; 753: 10 yd) o salirse (borde + `OffTrackMargin`) -> quitar moto
  (`DismissVehicle`) + mover jugador al ultimo punto bueno + moto nueva, quieto 2 s.
- Primero en llegar -> 30 s para el resto. Resultado 90 s (`GetEndDelay`). Framework: `MiWowMatch::OnTick` (todos los
  estados) y `GetEndDelay`.
- SQL `2026_11_17_02`: moto 9500001 (Chopper a speed_run 4, sin hechizos). Protocolo v9
  (`RACE_INFO/RACE/RACE_EVENT/RACE_RESULTS`).
- Vehiculo y bloqueo de hechizos: `GetVehicleEntry()` -> `MiWowVehicle`; `BlocksPlayerSpells()` -> `MiWowSpellLock`.

## Salida por etapas (PROBADO 2026-11-18, "mucho mejor")
Montar en `Map::AddPlayerToMap` con el cliente cargando daba "HandleSetActiveMoverOpcode: incorrect mover guid";
montar 1,5 s despues desde `Update` NO funciono (causa sin averiguar: el retraso por defecto puede dejar SIN vehiculo a
otros juegos con vehiculo, p. ej. `test_vehicle`). Ahora: llegan a pie a su puesto (`HoldVehicle` en
`OnPlayerArrived`); a los 3 s de la cuenta atras `MountAll`: aviso "¡Todos a sus motos!" (protocolo v11,
`RACE_EVENT MOUNT`, sonido) + `MountVehicle` (moto en su puesto, log "a su moto (puesto N): montado/NO montado" y, si
falla, el `SpellCastResult` de `BoardVehicle`). Si la cuenta atras no llega a ese momento, `OnStart` monta a todos.
La moto se invoca a ras de suelo (`GetMapHeight` hasta 5 yd por debajo): PROBADO.

## Fase 2: poderes (PROBADA 2026-11-18)
- `Powers` hasta 5 en los huecos 1-5 de la barra del vehiculo. Cajas/manchas por el TRAMO recorrido entre dos posiciones
  (el cliente avisa ~cada 0,5 s yendo recto = ~14 yd de salto).
- Filas de 4 cajas cada 180 yd (desde 150 yd hasta 80 yd antes de la meta; 752: 56 cajas, 753: 76), reaparecen a los
  4 s. Caja = criatura 9500010 (CrateCreatureBasic).
- Poder al azar ponderado por posicion (`PowerWeights`) en `m_spells[0..4]` de la moto + `VehicleSpellInitialize`
  (teclas 1-5; con 5 la caja se queda); se conservan si la moto cambia (caida).
- Hechizos `data/spells/carrera.toml` (9502000-9502013): Cohete (al de delante, o al de detras si va primero; proyectil
  9502010 UNIT_TARGET_ANY + script), Turbo (+60 % 3 s), Mancha de aceite (criatura 9500011 detras, 40 s), Escudo (10 s,
  para el siguiente golpe; sin mecanica: la base 17 tenia SHIELD y los vehiculos mecanicos son inmunes), Rayo (frena
  -50 % 4 s a todos los de delante). Golpes = la moto golpeada se lanza el efecto a si misma (Derrape 9502011 aturdir
  1,5 s / Electrocutado 9502012): sin hostilidad, alcanza tambien al mismo grupo.
- Scripts `spell_miwow_race_power` / `_missile`. SQL `2026_11_17_03` + `miwow_spells_carrera.sql`. Protocolo v10
  (`RACE_EVENT ITEM/HIT/BLOCK`).
- Para combates de verdad entre jugadores (otros eventos): zona con `AREA_FLAG_ARENA` (0x80) en `areatable_dbc` = todos
  contra todos nativo (salvo mismo grupo: el core lo comprueba antes).

## Placas de aceleracion (2026-11-18; el efecto funciona)
- `FindBoostPads`: a la salida de cada curva que gire >= 50 grados, por el lado de dentro, lejos de las cajas y >= 100 yd
  entre si; tramos de > 500 yd sin placa se rellenan (una cada ~400 yd, lado alterno). 752 = 10 placas, 753 = 9.
- Hechizo 9502013 Aceleron (+40 % 1,5 s, base Turbo; la velocidad usa la mayor aura, no se suman). Sin protocolo.
- Criatura 9500012: la runa G_RuneGroundBlue01 (27879) NO se veia (animaciones de goober) -> plataforma de
  teletransporte de Ulduar (31853, escala 1,8; radio de recogida 5 yd), SIN PROBAR. SQL `2026_11_18_00` (tambien:
  Piloto = gnomo, display 5436).

## Pendiente
- **Caidas** (el usuario da el evento casi por terminado): al caerse de la plataforma (visto en el 753) deberia volver
  a la pista a los pocos segundos y no lo hace. Logica: `Track` -> `Fell` si z < suelo de la muestra - `FallDepth` o
  lateral > media anchura + `OffTrackMargin`; revisar con la moto cayendo (posicion del vehiculo, ventana de busqueda,
  `Frozen`).
- Sin fecha: placas con otro modelo (el usuario buscara uno, quiza flechas propias); fase 3 trampas; fase 4 "carrera de
  la muerte"; montaje con retraso desde `Update` sin resolver.
