# Parkour "Ascenso" (juego `parkour`, mapa 754) - estado

PAUSADO el 2026-11-18 al final de la sesion. Leer esto al reanudar.

## Decisiones del usuario

- Sin limite de jugadores, **sesion siempre abierta**: se entra y se sale cuando se quiere ("Entrar" en el panel,
  sin cola). Es para divertirse; premios mas adelante.
- Rutas LARGAS con puntos de control SEPARADOS: caer debe costar.
- Ambiente: **Nagrand** (islas flotantes, verde). El cielo de Gelidar/El Oculus de la primera version no gusto.
- Ruta hecha de muebles y objetos de todo tipo, por secciones tematicas, con subidas de sillas (silla por silla),
  bajadas, caminos sin salida...; despues objetos interactivos (trampas, teletransportes...) y efectos visuales.

## Historial de pruebas

1. **1a prueba** (fase 1: cielo de El Oculus, 2x2 ADT, 201 piezas): no gusto el cielo, ruta muy corta, faltaba
   decoracion, el primer salto (salida -> primer objeto) era imposible (la plataforma de salida
   `Nexus_Crashed_Platform_01` esta inclinada y su borde se media mal).
2. **2a prueba** (cielo de Nagrand, 3x3 ADT, islas en salida/controles/meta, 70 islas WMO alrededor):
   "mucho mejor el escenario"; la ruta no gusta (camino aleatorio sin forma).
3. **Ultima version, SIN PROBAR del todo** (el usuario la vio y dijo "regular"; sin detalles): tramos por seccion
   (subidas de sillas, bajadas, zigzag, callejones sin salida). Preguntar que no le convence al reanudar.

Sin comprobar todavia en el juego: que caer devuelve al punto de control sin dano, cronometro / puntos de control /
meta / clasificacion, "Reiniciar", dos jugadores en la misma sesion, que los respaldos no estorben en las subidas.

## Que hay

- **Mapa**: `Maps/Planos/parkour_ascenso.json` -> `tools/mapgen/parkourgen.py` (formato del plano en su docstring y
  en "Recorridos de parkour" de `docs/mapas.md`). Se genera con `tools/Build-Patch.ps1` (cliente + `.map` + vmaps +
  `<DataDir>/maps/754_parkour.txt` con los puntos de control). Sin mmaps (no hacen falta sin PNJ).
  - Plantilla `isla` (`Nagrand_RockFloating_Huge01.m2` a escala 0,1; salida 0,14, meta 0,16) con arboles, matas,
    mariposas y haz de luz encima; el borde de cada salto se mide en la colision (`surface`).
  - 5 secciones x ~55 saltos en tramos (`segments`: run, climb, descent, zigzag, deadend) + 10 callejones.
    Resultado actual: 279 piezas + 56 en callejones, z 56..152.
  - Decoracion: WMO de islas de Nagrand (solo cliente: sin colision en el servidor; lejos de la ruta), rocas, luciernagas.
  - `tools/mapgen/catalog.py`: mide la cara pisable de todos los M2 del cliente (`_work/catalog.csv`) para elegir piezas.
- **SQL** `modules/mod-eventwow/data/sql/db-world/2026_11_18_01_eventwow_map_parkour.sql`: mapa 754, zona 5004, luz
  2601 (LightParams 396/491 = Nagrand), personaje 50 "Saltador" (gnomo, sin hechizos). Hechizo 9503000 "Caida
  segura" (`data/spells/parkour.toml` -> `eventwow_spells_parkour.sql`).
- **Servidor**: `games/EventWowGameParkour.cpp` (lee `754_parkour.txt`; caida = por debajo de la altura de caida de
  la seccion -> ultimo punto de control; cronometro, mejor tiempo y clasificacion de la sesion). Framework de sesion
  abierta: `EventWowGameInfo::OpenSession`, `EventWowMatchMgr::JoinOpenSession`, `EventWowMatch::AddPlayer`.
- **Cliente**: `EventWowParkour.lua` (marcador, avisos, clasificacion, "Reiniciar"); panel con "Entrar".
  Protocolo v12 (`docs/protocolo.md`).

## Ideas pendientes (por orden propuesto)

- Pulir la ruta segun lo que no convenza al usuario ("regular"). Opciones: piezas o tramos colocados a mano en el
  plano, tramos tematicos mas marcados (escaleras de libros, puentes de vigas, saltos largos sueltos), mas
  variedad visual por seccion, callejones mas tentadores (con algo al final).
- Interactivos (fase 3): trampolines, teletransportes entre islas, plataformas que desaparecen al pisarlas, trampas
  (llamas, empujones), sillas en las que sentarse de verdad (gameobject tipo silla; p. ej. te lanza a la siguiente).
- Efectos al tocar un punto de control y en la meta.
- Fase 4: ranking guardado entre sesiones, coleccionables (p. ej. al final de los callejones).
- Fase 5 (opcional): plataformas moviles, editor en el juego.
