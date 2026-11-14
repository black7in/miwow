# Asedio (mapa 751): analisis del mapa de WC3 y plan de reconstruccion

Fuente: `temp/Mi X Hero/` (archivos extraidos de `Maps/Warcraft/Mi_Mapa_XHero.w3x`). El `war3map.j` esta
**ofuscado** (triggers y variables `O12345`); se leyo resolviendo los textos (`war3map.wts`), los objetos
(comentarios del `.wts`) y las regiones (`regionNames` de `Maps/maps.json`). Herramienta de lectura (no
versionada): script de anotacion en el scratchpad; repetible si el amigo cambia el mapa.

Conversion de medidas: 1 casilla de WC3 = 128 unidades = 4 yardas -> **yardas = unidades WC3 / 32**
(700 unidades = ~22 yardas). Las posiciones de abajo son coordenadas de WC3; `mapgen` ya hace la conversion.

**Contenido**: la estructura (carriles, castillo, oleadas, arenas) es del genero hero siege y se reconstruye.
Lo que viene del mapa de terceros en el que se basa (nombres de jefes/heroes, objetos con nombre propio,
textos) NO se copia: en EventWow cada jefe, objeto y evento lleva nombre y criatura de WoW propios.

**Decisiones del usuario (2026-11-13)**: se intenta **mantener la duracion** original (60+ min); **una sola
dificultad** por ahora; primero los **personajes del evento + fase `Picking` sencilla**, despues el MVP de defensa.

**Paso 1 hecho (2026-11-14, probado por el usuario)**: fase `Picking` en el framework (`EventWowMatch::GetPickTime/IsPickUnique`,
`PICK`/`MATCH_PICK`/`MATCH_PICKS`, ventana `EventWowPick.lua`) y juego `asedio` (`games/EventWowGameSiege.cpp`,
sustituye a `test_siege_map`) con 4 heroes PROVISIONALES (SQL `2026_11_14_00`: cruzado, mago, druida, exploradora
oscura; hechizos de mana de nivel 80 sin arma ni forma). De momento: elegir (30 s) y recorrer el mapa 10 min.

**Spawns (propuesta, pendiente de confirmar)**: torres/castillo/necropolis/tiendas/PNJ = criaturas propias
(estructuras con `creature_template_movement.Rooted = 1`); puertas = gameobject `DOOR` con modelo oficial;
portales = gameobject decorativo + teleport por region. Todo **invocado por el juego** (no spawns fijos en BD),
guardado por etiqueta (`ObjectGuid`). Posiciones: `mapgen` lee `war3mapUnits.doo`/`war3map.doo` + tabla
rawcode WC3 -> entrada nuestra en `maps.json` y exporta spawns + regiones para el servidor. Riesgo: las mmaps
no conocen las puertas. Orden: personajes + `Picking` -> exportar spawns/regiones -> MVP de defensa.

## 1. Flujo de la partida en WC3

```
Eleccion (dificultad, modo de heroes) -> elegir heroe en el circulo de Inicio -> aparecer en la base
-> FASE 1: defender el castillo (carriles cada 15 s + oleada grande cada 240 s + eventos)
-> destruir las 8 necropolis (una por carril) -> se abren las puertas de la base
-> FASE 2: las 2 torres del norte -> "Oleada final" (60 s) + 4 heroes oscuros atacan el castillo
-> FASE 3: subir al norte: jefe del Estanque -> salas de la Plaza Media (puertas, 4 heroes oscuros)
-> FASE 4: Plaza Norte: caballero oscuro -> jefe final -> victoria (la partida acaba a los 3 min)
Derrota: si muere el castillo.
```

### Configuracion inicial (solo el jugador 1)
- **Modo**: Normal / Extremo. Extremo -> nivel 1..4 (`dificultad` 2..5).
- **Seleccion de heroe**: estandar / permitir repetidos / todos aleatorios / doble heroe (2 heroes).
- La dificultad multiplica: numero de jefes que salen (`N = dificultad`, max 12), stats de los jefes
  (+500 x dificultad a fuerza/agilidad/intelecto), habilidades extra de los jefes, y acelera los relojes
  (carriles 15 -> 12 s, refuerzos 75 -> 60 s). En Normal no hay dragones ni asesinos.
- Heroe: 24 a elegir (doble clic). Empieza con objetos de inicio, 5000 oro (1000 en algunos modos) y
  1-2 libros de +10.

### Base (sur del mapa): castillo y 8 carriles
- **Castillo** en `Cruce_Centro` (0, -8704), rodeado de torres. Todo enemigo va con orden "atacar" a ese punto.
  Si muere -> **derrota de todos**. La primera vez que recibe dano, sale un heroe aliado de ayuda (PNJ)
  que patrulla los 4 cruces.
- **Carriles** (`Oeste/Centro/Este/Sur_Pasillo_*`, 8): **un carril por jugador conectado** (con 3 jugadores
  solo salen 3 carriles; si alguien se va, su carril se cierra). Cada carril tiene **1 necropolis + 3 zigurats**
  enemigos en su boca.
  - Cada 15 s: 3 unidades (4 a partir de la "ronda" 4) de 2-3 tipos de una tabla de 20 criaturas que sube de
    nivel con el tiempo; matar zigurats de un carril cambia los tipos que salen.
  - Zigurat destruido -> salen N refuerzos de elite en su sitio. Necropolis destruida -> ese carril deja de
    soltar unidades y salen N jefes "destructores".
  - **Las 8 necropolis destruidas** -> se abren las puertas de la base (`ATg2/ATg4`, en (-1632/1632, -7072)),
    paran los carriles y empieza la FASE 2.
  - Refuerzos (solo Extremo, cada 60-75 s): 1 heroe enemigo por carril, cada vez de uno distinto.
- **Oleada grande** (`Next Wave`, reloj de 240 s): de los 4 cruces (`Cruce_Oeste/Norte/Este/Sur`, gira la
  direccion con aviso "ataca desde el OESTE..."), `10 + 2 x oleada` criaturas de la oleada actual (12 tipos).
  Da a los heroes un objeto temporal de velocidad.
- **Niveles** (relojes de 600, 500 y 400 s): Nivel 2/3/4 -> cada carril suelta N dragones de un tipo y el jefe
  del Estanque gana un objeto (se hace mas fuerte cuanto mas se tarda).
- Solo Extremo: **ataque de dragones** cada 320 s (desde `Sala_Sur_2/3`, 5 tipos) y **asesinos** cada 350 s.
- Nivel (por tiempo, cada 300 s): runas en `Cruce_Punto_Suroeste` (vida, mana, velocidad, armadura...).

### Muerte del heroe
- Reaparece en `Cruce_Suroeste` (junto al castillo) a los **120 s**, pierde 10000 oro. Hay un objeto que
  revive al instante (se repone en algunos eventos).

### Economia y contadores
- Oro por matar (recompensa de las criaturas). Hitos de muertes: 100 / 500 / 1000 / 2000 muertes -> +1000 /
  +5000 / +25000 / +50000 oro. Tabla de puntuacion (muertes por jugador).
- Comandos: comprar libros en lote (-50000 oro), elegir otra vez (`-repick`), aleatorio, expulsar, niebla.
  En EventWow nada de esto va por chat: o por la interfaz o se descarta.

### Eventos especiales (la base sigue viva mientras tanto)
- **Evento de granja** (reloj de 750 s): todos los heroes vivos van a SU sala (`Sala_Sur_1..8`, una por
  jugador), 3 minutos matando criaturas que reaparecen (cada muerte = +1 "madera" = puntos del evento,
  tabla propia). Mientras tanto los carriles se pausan. Al acabar vuelven a donde estaban.
- **Evento de supervivencia** (siguiente vez del reloj): todos a `Caja_Este` con un jefe invencible, 2 min
  aguantando; los vivos ganan 50000 oro.
- **Arena especial 1**: a las **2000 muertes** un jugador entra solo a `Caja_Este` contra un jefe (3 min);
  premio: un anillo. Salir de la region o agotar el tiempo -> vuelve.
- **Arena especial 2**: con **80 muertes de oleada** contra dos jefes a la vez; premio: una espada.
- **Desafios** (pisar `Cruce_Punto_Sureste` -> menu "Eventos especiales", con confirmacion): en las salas
  medias (`Sala_Media_*`):
  - Imagen del heroe: duelo contra una copia de tu heroe (mismo nivel, x4 stats).
  - Todas las imagenes: tu contra copias de los heroes de todos + heroes aleatorios.
  - Bestia / Infernal: duelo contra un jefe fijo de la sala.
  - Una vez por jugador; los puntos `*_Punto` de las salas devuelven a la base.

### Fases finales (norte del mapa)
- FASE 2 (puertas de la base abiertas): pisar `Pasillo_Oeste/Este_Abajo` activa 2 torres en
  (-2048/2048, -4352); cada 15 s salen no-muertos de `Pasillo_*_Arriba`. Las 2 torres muertas -> **Oleada
  final** a los 60 s: anillos de criaturas alrededor del castillo + bloques en los 4 cruces + 4 heroes oscuros
  (con mensaje "ataque de los heroes oscuros en 30 s").
- FASE 3: pisar `Punto_Oeste/Este_Norte` -> todos al **Estanque** contra su jefe (el que crecia con los
  niveles). Muerto -> se abre la puerta (0, 1664) a la **Plaza Media**:
  - Entrar por `Plaza_Media_Oeste`: puertas cerradas, oleadas desde los 4 lados de la plaza; al acabar se abren
    las salas con los 4 heroes oscuros (cada uno abre su puerta al morir).
  - Despues `Plaza_Media_Norte`: otra ronda de oleadas; abre la puerta (0, 6656) a la Plaza Norte.
- FASE 4 (`Plaza_Norte`): pelea contra el caballero oscuro + 4 heroes oscuros reforzados; al morir, escena
  ("quien lo mato?") y aparece el **jefe final** con un circulo de poder. Jefe final muerto -> "Felicidades"
  -> victoria a los 3 min, heroes colocados segun la tabla de muertes.

## 2. Funcion de cada region (para renombrar `regionNames`)

| Nombre actual | Funcion real |
|---|---|
| `Inicio` | circulo de seleccion de heroes (lo reemplaza nuestra fase de eleccion) |
| `Cruce_Centro` | **castillo** (objetivo de todos los enemigos) |
| `Cruce_Suroeste` | aparicion/reaparicion de heroes |
| `Cruce_Oeste/Norte/Este/Sur` | entrada de las oleadas grandes |
| `Oeste/Centro/Este/Sur_Pasillo_*` (8) | carriles (aparicion de las unidades de cada jugador) |
| `Sala_Sur_1..8` | salas del evento de granja (una por jugador) |
| `Caja_Este` / `Caja_Este_Arriba` | arena especial / sitio de espera de sus jefes |
| `Cruce_Punto_Suroeste` | runas periodicas |
| `Cruce_Punto_Sureste` | menu de desafios |
| `Sala_Media_*` / `*_Punto` | salas de desafio / vuelta a la base |
| `Pasillo_*_Abajo` / `Pasillo_*_Arriba` | activador de la fase 2 / aparicion de no-muertos |
| `Punto_Oeste/Este_Norte` | entrada al Estanque (fase 3) |
| `Estanque` | jefe del Estanque |
| `Plaza_Media` + `_Oeste/_Norte/_Este/_Sur` | plaza de oleadas (activadores y aparicion) |
| `Plaza_Norte` | batalla final |

Estructuras colocadas en el mapa (coordenadas WC3): castillo (0, -8704) con 8 torres de guardia y 4 de canon;
necropolis + 3 zigurats por carril (p. ej. oeste: (-4736, -8064) y (-4736, -9344)); 2 torres de la fase 2;
jefes en sus salas. Puertas: `ATg1/3` (salas del norte), `ATg2/4` (salida de la base); arboles `LTe*` que se
quitan segun cuantos jugadores hay (cierran carriles vacios).

## 3. Adaptacion a EventWow

| WC3 | EventWow |
|---|---|
| 2 heroes por jugador (modo doble) | **1 personaje** por jugador (ficha `eventwow_character`); solo modos estandar/repetidos/aleatorio |
| 24 heroes, doble clic en el circulo | fase `Picking` (sin implementar) o asignado al principio |
| hasta 8 jugadores, 1 carril cada uno | grupo hasta 5 (`MaxPartySize`): **1 carril por jugador**, asi escala solo |
| oro de WC3 | oro de WoW (ya es la moneda de partida) + tienda nativa |
| madera = puntos del evento | contador propio en el HUD |
| unidades/edificios de WC3 | criaturas de WoW propias (rango 9500000+), edificios = criaturas inmoviles |
| puertas (destructibles) | gameobjects de puerta (abrir/cerrar desde el juego) |
| regiones con evento "entra" | comprobacion de posicion en `OnUpdate` (rectangulos de `maps.json`) |
| orden "atacar a un punto" | criaturas con movimiento al castillo (mmaps ya generados) y agresivas por el camino |
| reaparecer a los 120 s, -10000 oro | `OnPlayerDied`: reaparecer en `Cruce_Suroeste` tras N s |
| castillo muerto = derrota | `SetResult(LOSE)` + `End` |
| dialogos del jugador 1 | dificultad elegida en el panel o en la fase de eleccion (a decidir) |
| partida de 60+ min | probablemente acortar (relojes y numero de fases configurables) |

### Lo que falta en el framework
1. **Spawner de oleadas**: criatura + numero + punto + destino; IA "ir al castillo atacando lo que encuentre"
   (script de criatura propio o `GetMotionMaster()->MovePoint` + agresion). Limpiar todo al acabar.
2. **Regiones de `maps.json` en el servidor**: exportar los rectangulos (ya convertidos) para usarlos por nombre
   desde C++ (`InRegion(player, "Castillo")`, `RegionCenter(...)`).
3. **Objetivos con vida**: castillo y estructuras como criaturas; aviso `OnCreatureDied` en `EventWowMatch`.
4. **Varios relojes en el HUD** (hoy `SetTimer` es uno solo) y contadores (muertes, puntos).
5. **Puertas**: gameobjects colocados por el juego, `OpenDoor/CloseDoor`.
6. **Fases** dentro del juego (maquina de estados propia del juego, no del framework).

### Propuesta de reconstruccion por pasos
1. **MVP "Defensa del castillo"**: castillo + carriles (1 por jugador, cada 15 s) + oleada grande cada N s
   desde los cruces + muerte/reaparicion + derrota si cae el castillo + victoria al aguantar X oleadas.
   Valida lo arriesgado: muchas criaturas, IA de camino, rendimiento.
2. Necropolis/zigurats por carril y apertura de la base (fase 1 completa).
3. Fases 2-4 (puertas, jefes, final).
4. Eventos especiales y desafios, hitos de muertes, dificultad.
