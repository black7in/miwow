# Defensa del castillo (juego `castillo`, mapa 755) - estado

Evento individual de oleadas. Codigo: `modules/mod-miwow/src/games/MiWowGameCastle.cpp`. SQL `2026_11_24_00` (mapa)
y `2026_11_24_01` (criaturas y modelo de la torre). Plano `Maps/Planos/defensa_castillo.json` ->
`tools/mapgen/castlegen.py`.

## Decisiones del usuario (2026-11-24)

- Individual, **solo nivel 80** (`MiWowGameInfo::MinLevel`, error `QUEUE_LEVEL`); los enemigos suben de dificultad.
- **5 etapas x (3 oleadas + jefe)**, con enemigos y jefe distintos en cada etapa; al matar al 5.o jefe se gana.
- **Defender un castillo**: las oleadas llegan por **un solo camino**. Se pierde si la vida del castillo llega a 0;
  morir = reaparecer delante de la torre (8 s).
- **3 guardias** que ayudan a defender.
- Mapa generado desde un plano JSON (no WC3).
- 1a prueba: interfaz nativa sin cambios en los eventos (cliente, `MIWOW_MATCH_RESTRICT_UI`).
- 2a ronda: **el castillo es un PNJ** (para ver su vida), una torre, no una fortaleza gigante; **camino corto**
  (las oleadas tardaban mucho); **portal** donde salen las oleadas con el **jefe final al lado** (las invoca), que
  no se puede atacar hasta su oleada (la ultima): entonces despierta y va como los demas.
- 3a ronda: **oleadas de 20+** enemigos; HUD sin cuadro; **oro del castillo** (moneda propia) por cada enemigo
  muerto y un **vendedor de stats** (todas las que existen) temporales.
- 4a ronda: el oro solo cuenta si remata el jugador (o su mascota); **dificultades** Facil / Medio / Dificil /
  Extremo elegidas al empezar (escalan vida, dano y numero de enemigos).
- 5a ronda: la dificultad en una ventana propia (no el intendente, que vuelve a su sitio); los enemigos y guardias
  se quedaban quietos al morir su objetivo (enganchados al combate sin victima: `UpdateVictim` no evade y
  `MoveInLineOfSight` ignora a los enganchados): ahora salen del combate y siguen la ruta / vuelven a su puesto.
- 6a ronda: la tienda en una ventana propia (al hablar con el intendente), no en el gossip.
- 7a ronda: tienda simplificada (sin temple, bloqueo, parada... ni subida de precio) con packs.
- 8a ronda: compras al doble (mismo precio), oro al doble y bonus por oleada; etapa final con oleadas infinitas
  hasta que el jugador despierta al jefe final.
- Mas adelante: modo de grupo (hay una maqueta "Invasion" en el panel), clasificacion, premios.

## Mapa 755 "EventWowCastillo"

- 1 ADT. Meseta nevada (texturas de Dun Morogh) con un canon de 264 yd (~30 s para los enemigos; ancho 26-30,
  bordes `cut`) desde el portal (sur) hasta una explanada circular (`flat`) con la torre (norte).
- `castlegen.py`: `Lane` = `Track` de trackgen pero ABIERTA (Catmull-Rom con extremos reflejados, sin vuelta);
  `CastleConverter` reutiliza relieve/texturas/decoracion de `TrackConverter` (gancho `make_track`). Escribe
  `<DataDir>/maps/755_castillo.txt` (spawn, portal, boss, gate = torre, start, guard, path; object/door opcionales).
- mmaps generadas (`mmaps_generator 755`).
- Version anterior (descartada en la 2a ronda): fachada de la fortaleza de Conquista del Invierno como objetos del
  servidor (`BattlefieldWG.h`; los huecos entre piezas los tapa alli el WMO fijo de la fortaleza) y canon de 661 yd.
  castlegen aun admite `objects` (con `reference`) por si se quieren edificios.

## Partida

- **Torre del castillo** (9500500) al final del camino: su vida es la del castillo; seleccionable (se ve su barra).
  Modelo propio: torre de Lordaeron (`UndercityTower01.m2`, M2 de decorado) como criatura, display 40000 / modelo
  3500 a escala 0,6 (~29 yd); `creature_model_info` con alcance 6. Sin colision (es una criatura). Sin regeneracion;
  la IA no se mueve, no evade y no se deja curar. Entre etapas: +10 % de vida.
- **Etapa final (5)**: oleadas infinitas (sus 3 en bucle, +15 % de enemigos por vuelta; HUD "Oleada N"). Kazrath
  pasa a atacable pero sigue dormido (`SetDormant(true, true)`: pasivo, sin `NON_ATTACKABLE/IMMUNE_TO_PC`, con
  `IMMUNE_TO_NPC` para que no lo despierten los guardias). Al recibir dano de un jugador o algo suyo (`DamageTaken`)
  despierta; el juego lo ve en el tick (`CheckFinalBossAwake`): grita, sale su escolta y empieza la oleada del jefe
  (ruta hasta la torre). Se gana al limpiar esa oleada.
- **Oro**: normales `8 + 4 x etapa`, jefes `150 + 50 x etapa`, y `30 + 15 x etapa` por oleada superada (aviso).
- **Portal de la Legion** (9500502, display 27735, no seleccionable) detras del inicio del camino; las oleadas salen
  ahi. **Kazrath** (jefe final) espera dormido a su lado: pasivo, `NON_ATTACKABLE | IMMUNE_TO_PC | IMMUNE_TO_NPC`;
  hace el gesto de lanzar al empezar cada oleada. En la oleada del jefe de la etapa 5 despierta (grita) y sigue la
  ruta.
- **Dificultad**: al empezar (tras la cuenta atras) se abre la ventana de eleccion del framework
  (`MiWowMatch::ShowChoice` -> `MATCH_CHOICE`, cliente `MiWowMatch.lua`; responde `CHOOSE`). Fase `Choose`: no salen oleadas; si nadie
  elige en 60 s, Medio. Facil x0,7 vida/dano y x0,75 enemigos; Medio x1; Dificil x1,4 vida, x1,35 dano, x1,25
  enemigos; Extremo x2 vida, x1,8 dano, x1,5 enemigos (cada grupo de la oleada, redondeado, minimo 1). Vida = pct de
  `UNIT_MOD_HEALTH`; dano = `DamageDealt` de la IA (golpes y hechizos; los refuerzos de los jefes lo heredan).
  El intendente sigue junto a la torre (solo tienda).
- **Oro del castillo**: moneda de la partida (no se guarda, no es oro real). Cada invasor que remata el jugador o
  algo suyo (mascota, totem, guardian: `GetCharmerOrOwnerPlayerOrPlayerItself` del asesino en `JustDied`) suma oro (ver "Oro" mas arriba). Hoy es un fondo comun de la partida
  (individual); en modo grupo habria que decidir si por jugador.
- **Intendente del castillo** (9500503, enano, display 13384, `npc_miwow_castle_vendor`) junto a la torre (`vendor`
  del layout). Al hablarle abre la **tienda del cliente** (generica del framework: `MiWowMatch::OpenShop` /
  `BuildShop` / `OnShopBuy`, `MATCH_SHOP`, cliente `MiWowMatch.lua`): una sola pestana (Mejoras, con los packs al final),
  cuadricula con icono, nombre, lo que llevas y precio (rojo si no llega); clic = comprar. Se cierra con
  X/Esc o al alejarse mas de 10 yd; con ella abierta se actualiza el oro (como mucho 1/s).
  Ofertas (`ShopOffers`, precio fijo, sin limite; decision del usuario: pocas stats y que se noten):
  Vida +3000 (40), Mana +3000 (40), Atributos +150 a los 5 (60), Poder de ataque +300 (40), Poder con hechizos +180
  (40), Critico +184 (~4 %, 50), Celeridad +132 (~4 %, 50); packs Combatiente (vida, atributos, AP, critico,
  celeridad: 180) y Hechicero (vida, mana, atributos, SP, critico, celeridad: 210).
- **Guardias** (9500501, x3) delante de la torre; entre etapas reviven los caidos y se curan los vivos.
- **Facciones** (comprobadas en FactionTemplate.dbc): enemigos 14 (hostil a jugadores); torre y guardias 250
  "escoltado" (amistosa con todos los jugadores, hostil a monstruos, grupo jugador -> los monstruos la atacan).
- **IA de los enemigos** (`npc_miwow_castle_invader`): ruta de `path` con `MovePoint`; pelean con quien se encuentren;
  al acabar el combate siguen desde el punto de ruta mas cercano (no vuelven a casa: sin correa en mazmorras); al
  final atacan la torre. Habilidades por temporizador (tabla `InvaderInfos`); jefes con enfurecer y/o refuerzos
  por % de vida (los refuerzos se van si muere el jefe).
- Ritmo: etapa 1 empieza a los 15 s, etapas siguientes 20 s, 8 s entre oleadas, un enemigo cada 0,5 s. Oleadas de
  20-26 enemigos (escolta del jefe 14); los normales son flojos uno a uno (vida 0,3-1,3, dano 0,4-1,1); torre 40.
- HUD (3 lineas): etapa; oleada/jefe y enemigos (o cuenta atras); torre % y oro.
- HUD generico rediseñado (cliente `MiWowMatch.lua`): sin marco, franja oscura difuminada a los lados, titulo
  dorado; `MATCH_HUD` admite varias lineas. Avisos en el centro (`SendAreaTriggerMessage`).
- Sin botin, oro, XP ni reputacion. Hechizos propios del jugador permitidos (es su personaje).

| Etapa | Enemigos | Jefe | Habilidades del jefe |
|---|---|---|---|
| 1 Los vrykul | Guerrero Desollador (Rajar), Rompehuesos (Golpe mortal) | Jarl Skarn | Golpe mortal, Cargar, Torbellino |
| 2 La jauria | Huargo sanguinario (Desgarrar), Huargo colmilloacerado | Colmillo Gris | Desgarrar, Rugido aterrador, Enfurecer 30 % |
| 3 La Plaga | Necrofago, Nigromante (Descarga de las Sombras) | Carneputrida | Rajar, Nube de veneno, Machacar |
| 4 Los elementales | Elemental de tierra, Elemental de tormenta (Cadena de relampagos) | Gromm | Choque de tierra, Pisoton destrozador |
| 5 La Legion | Diablillo vil, Guardia vil, Infernal | Kazrath (junto al portal desde el principio) | Rajar, Salva de Sombras, Aliento de llamas, 4 diablillos 50 %, Enfurecer 20 % |

Hechizos de PNJ de mazmorras de 5 de WotLK, comprobados en el Spell.dbc: 15284, 15496, 16856, 52027, 60067, 59343,
48849, 8599, 53333, 49548, 50234, 48140, 52237, 54511, 57942, 54282. Dificultad = `HealthModifier`/`DamageModifier`
del SQL (enemigos 0,5-2,2; jefes 8-18; torre 25; guardias 4).

## Pendiente (2026-11-24: probado por el usuario hasta la 8a ronda; jugable)

- Minimapa: el usuario dice que no sale. La textura (`eventwow_755_32_32.blp`) y la linea del `md5translate.trs`
  estan bien generadas (igual que los otros mapas): averiguar si en los otros mapas (carrera) si sale.
- Ventana de dificultad (que salga, se pueda elegir y se cierre; tambien tras /reload), que los enemigos sigan al
  morir su objetivo, escalado por dificultad,
  oro solo por muertes propias.
- Ventana de la tienda (pestanas, compra, que se cierre al alejarse y se actualice el oro).
- Oro, intendente (menus, precios, que se apliquen y se quiten al salir), HUD nuevo, oleadas de 20+.

- Que la torre se ve bien como criatura (modelo, escala, que se pueda seleccionar) y que los enemigos la golpean.
- Portal y Kazrath dormido (que no se le pueda atacar) y que despierta en la ultima oleada.
- Que los enemigos siguen la ruta, pelean y vuelven a ella; que los guardias los atacan.
- Dificultad de cada etapa y del jefe final (ajustar modificadores del SQL).
