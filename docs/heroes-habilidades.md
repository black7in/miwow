# Habilidades de los heroes del Asedio

**IMPLEMENTADO (2026-11-14, sin compilar ni probar; el usuario lo mandara a probar a otros y recogera opiniones).**
Fichas `modules/mod-eventwow/data/spells/<heroe>.toml` (+ `comun.toml`), SQL generado `eventwow_spells_*.sql`,
fichas/atributos/criaturas en `2026_11_14_08_eventwow_heroes_abilities.sql`, scripts en `EventWowHeroSpells.cpp`
(Flecha negra, Reencarnacion). Rangos de ID por heroe: 9500200 (Arthas principe), 9500300 Thrall, 9500400 Sylvanas,
9500500 Jaina, 9500600 Varian, 9500700 Tirion, 9500800 Kel'Thuzad, 9500900 Gul'dan, 9501000 Archimonde,
9501100 Vol'jin, 9501200 Cairne, 9501300 Lor'themar, 9501400 Garrosh, 9501500 Jokkum, 9509000 comunes.
Criaturas propias: 9500400 serpiente vudu, 9500401 fenix (copias sin IA de 19833 / 21362).

Cambios respecto a la propuesta (al implementar):
- Escudo divino (Arthas principe): solo Arthas en todos los rangos (sin version de grupo).
- Thrall, Furia de los Elementos: aura 8 s que lanza un rayo en area cada segundo + aturdimiento de 2 s al empezar.
- Sylvanas, Reina Alma en Pena: +50 % dano, +30 % velocidad de ataque, inmune a ralentizar (sin salto de disparos).
- Varian, Furia de Lo'Gosh: +velocidad de ataque y +dano (sin robo de vida: no hay aura nativa de robo de vida).
- Kel'Thuzad, basica 2: Volea de Escarcha (28479, dano + ralentizar alrededor) en vez de Fisura de las Sombras
  (la fisura es un PNJ con script del encuentro).
- Vol'jin, basica 2: Serpientes vudu (2-5 guardianes que muerden) en vez de una guarda inmovil que dispara.
- Lor'themar, Trampa de Escarcha: zona alrededor de el (sin objeto trampa).
- Jokkum, Piel de gigante: vida fija (no %): la vida del heroe es base de ficha + lo que sume el motor.
- Invocaciones: solo las CONTROLABLES sustituyen a la anterior; los guardianes se acumulan (varios por lanzamiento).
- Atributos por papel (SQL `_08`): tanque aguante+armadura, cuerpo a cuerpo fuerza+aguante, lanzador intelecto+poder
  con hechizos, distancia poder de ataque.

Texto original de la propuesta:

Esquema de cada heroe (`docs/heroes.md`): 4 basicas x 4 rangos (niveles 1/3/5/7), definitiva x 3 (6/12/18), suprema
automatica a nivel 30 y 11 puntos de Atributos. Hecho y probado: **Arthas, caballero de la Muerte** (ficha 31,
`data/spells/arthas.toml`), que sirve de modelo.

Criterios:
- Cada heroe tiene un **papel** y su kit lo refleja; entre todos cubren tanque, dano cuerpo a cuerpo, dano a distancia,
  lanzador y apoyo/sanacion, para que cualquier grupo de 1-5 funcione.
- Al menos una basica es de **area** (el Asedio son oleadas) y casi todos tienen algo de **control** (aturdir,
  ralentizar, miedo, raiz).
- Cuarta basica = **pasiva o aura** (estilo WC3) en la mayoria: no ocupa tecla util y da identidad.
- Inspiracion: lo que cada personaje hace en WoW/Warcraft (sus hechizos de jefe o de clase). Diseno propio, no el de un
  mapa de terceros.
- **Base** = hechizo del Spell.dbc que copia `tools/spellgen` (comprobados: existen en el cliente esES). Como con
  Arthas, se cambian numeros, coste, reutilizacion, objetivos y textos; la base da el aspecto y la mecanica.
- Marcado **[script]**: necesita codigo en `EventWowHeroSpells.cpp` (los efectos del DBC solos no bastan).
  **[invoc.]**: invocacion (regla comun ya hecha: la nueva sustituye a la anterior; aura de `trigger` por rango).
- Un jugador solo puede tener **una mascota controlable** a la vez; los guardianes (no controlables) no tienen limite.

Ataque basico (`docs/heroes.md` seccion 6, implementado 2026-11-14 sin probar): C = cuerpo a cuerpo nativo
("Atacar" + arma invisible de la ficha), D = disparo automatico fisico propio (Sylvanas, 9509020), L = disparo magico
automatico propio (lanzadores: Jaina/Kel'Thuzad 9509021 Escarcha, Gul'dan 9509022 Sombras, Archimonde 9509023 Fuego,
Vol'jin 9509024 Naturaleza; `data/spells/ataques.toml`). Vol'jin pasa a L (era D). Casilla 1 de la barra = ataque:
las teclas de las habilidades pasan a 2-5, definitiva 6, suprema 7.

## Resumen

| Heroe | Papel | Ataque | Idea |
|---|---|---|---|
| Arthas (principe) | tanque/apoyo | C | paladin: aturde, cura, consagra; escudo divino |
| Arthas caballero de la Muerte | cuerpo a cuerpo | C | HECHO |
| Thrall | lanzador hibrido | C | rayos en cadena y lobos espectrales |
| Sylvanas | distancia | D | arquera: flechas en area, miedo, forma de alma en pena |
| Jaina | lanzador | L | escarcha: ralentiza, congela, elemental de agua |
| Varian | cuerpo a cuerpo | C | guerrero: carga, rajar, golpe mortal, filotormenta |
| Tirion | tanque | C | provoca, escudos y la Crematoria |
| Kel'Thuzad | lanzador | L | escarcha y sombras, esqueletos, explosion de escarcha |
| Gul'dan | lanzador | L | brujo: drenar vida, lluvia de fuego, guardia vil, infernal |
| Archimonde | lanzador/jefe | L | dedo de la muerte, rafaga de aire, fuego apocaliptico |
| Vol'jin | apoyo | L | maleficio, guardas serpiente, gran vudu |
| Cairne | tanque | C | pisoton, ola de choque, reencarnacion |
| Lor'themar | cuerpo a cuerpo/distancia | C | arcano: disparo arcano, silencio, trampas, fenix |
| Garrosh | cuerpo a cuerpo | C | furia: torbellino, sed de sangre, ansia de sangre |
| Rey Jokkum | tanque | C | gigante: roca, tajo de escarcha, avalancha |

## Arthas (principe, paladin) - ficha 30 - tanque/apoyo

| Casilla | Habilidad | Que hace | Base |
|---|---|---|---|
| 1 | Martillo de justicia | aturde a un enemigo 2/2,5/3/3,5 s y lo dana | 10308 |
| 2 | Luz Sagrada | cura mucho a un aliado (o a si mismo), lanzamiento 1,5 s | 48782 |
| 3 | Consagracion | zona sagrada a sus pies que dana a los enemigos | 48819 |
| 4 | Aura de devocion (pasiva) | aura: armadura y +dano sagrado a quien le pega (reprension) para el grupo | 54043 |
| Definitiva | Escudo divino | inmune a todo el dano 4/6/8 s; rango 3: tambien los aliados cercanos | 642 |
| Suprema | Colera de la Luz | explosion sagrada enorme alrededor que aturde a los no-muertos/demonios | 48817 |

Nota: el DK ya tiene un aura de armadura; si se repite demasiado, el aura del principe pasa a "Aura de concentracion"
(+celeridad con hechizos o regeneracion de mana del grupo).

## Thrall - ficha 32 - lanzador hibrido

| Casilla | Habilidad | Que hace | Base |
|---|---|---|---|
| 1 | Cadena de relampagos | rayo que salta a 3/4/5/6 enemigos | 49271 |
| 2 | Tormenta de truenos | onda alrededor: dano, empuja y ralentiza | 59159 |
| 3 | Choque de llamas | dano de fuego + dano en el tiempo | 49233 |
| 4 | Escudo de relampagos (pasiva) | quien le golpea recibe dano de naturaleza (siempre activo) | 49281 |
| Definitiva | Lobos espectrales | 2 lobos guardianes 30 s (rango 3: 3 lobos); como el necrofago, mas fuertes por rango [invoc.] | 51533 |
| Suprema | Furia de los Elementos | tormenta en un area grande: rayos durante 8 s y aturde al empezar | 59159 + 49271 (visual) [script si hace falta encadenar] |

## Sylvanas Brisaveloz - ficha 33 - distancia

| Casilla | Habilidad | Que hace | Base |
|---|---|---|---|
| 1 | Multidisparo | flechas a 3/4/5/6 enemigos en cono | 49048 |
| 2 | Flecha negra | dano de sombras en el tiempo; si el objetivo muere con ella, levanta un esqueleto guardian 20 s [script] | 63672 |
| 3 | Lamento de alma en pena | miedo a los enemigos cercanos 2/2,5/3/3,5 s | 10890 |
| 4 | Aura de disparo certero (pasiva) | aura: +% poder de ataque y +dano a distancia al grupo | 19506 |
| Definitiva | Salva | lluvia de flechas en una zona (canalizada) | 58434 |
| Suprema | Reina Alma en Pena | 15 s: +50 % de dano, inmune a ralentizar, cada disparo salta a un segundo objetivo | aura propia (MOD_DAMAGE_PERCENT_DONE + inmunidad) |

## Jaina Valiente - ficha 34 - lanzador

| Casilla | Habilidad | Que hace | Base |
|---|---|---|---|
| 1 | Descarga de Escarcha | dano alto + ralentizar, lanzamiento 2 s | 42842 |
| 2 | Ventisca | zona canalizada que dana y ralentiza | 42940 |
| 3 | Nova de Escarcha | congela (raiz) a los enemigos cercanos | 42917 |
| 4 | Aura de brillantez (pasiva) | aura: regeneracion de mana del grupo (mp5) | aura propia (MOD_POWER_REGEN, area de grupo) |
| Definitiva | Elemental de agua | elemental CONTROLABLE (barra de mascota) 45 s; mas fuerte por rango [invoc.] | 31687 |
| Suprema | Tormenta de hielo | lluvia de fragmentos en un area enorme 6 s; al final congela 3 s a los que sigan dentro | 42940 (mayor, sin canalizar) + 42917 |

## Varian Wrynn - ficha 35 - cuerpo a cuerpo

| Casilla | Habilidad | Que hace | Base |
|---|---|---|---|
| 1 | Cargar | carga hacia un enemigo y lo aturde 1 s | 11578 |
| 2 | Rajar | golpe que alcanza a 2/3/4/5 enemigos delante | 47520 |
| 3 | Golpe mortal | dano alto y -50 % de curacion recibida 10 s | 47486 |
| 4 | Grito de batalla (pasiva) | aura: +poder de ataque del grupo | 47436 (efecto -> aura de grupo permanente) |
| Definitiva | Furia de Lo'Gosh | 10/12/15 s: +velocidad de ataque y robo de vida | 1719 (aura propia de velocidad + robo) |
| Suprema | Filotormenta | gira 6 s danando a todos alrededor; inmune a control | 46924 |

## Tirion Vadin - ficha 36 - tanque

| Casilla | Habilidad | Que hace | Base |
|---|---|---|---|
| 1 | Grito de la Cruzada | provoca a los enemigos cercanos (le atacan a el) 4/5/6/6 s | 1161 |
| 2 | Tormenta divina | golpe en area; cura a los aliados cercanos un % del dano | 53385 |
| 3 | Escudo sacro | escudo de absorcion en un aliado | 53601 |
| 4 | Aura de la Cruzada Argenta (pasiva) | aura: -% dano recibido por el grupo | aura propia (MOD_DAMAGE_PERCENT_TAKEN, area de grupo) |
| Definitiva | Imposicion de manos | cura por completo a un aliado (reutilizacion 120/100/80 s) | 48788 |
| Suprema | Crematoria purificada | explosion de luz enorme: dano alto a los enemigos y cura a los aliados en el area | 53385 (mayor) + visual de la Crematoria [script: dano/cura segun objetivo, como la Espiral] |

## Kel'Thuzad - ficha 37 - lanzador

| Casilla | Habilidad | Que hace | Base |
|---|---|---|---|
| 1 | Descarga de Escarcha y Sombras | dano de escarcha + ralentizar (la de Naxxramas) | 28478 |
| 2 | Fisura de las Sombras | marca el suelo; a los 2 s explota con mucho dano en area pequena | 27810 |
| 3 | Levantar esqueletos | 2/2/3/3 esqueletos guardianes 25 s [invoc.] | 51533 (otra criatura) |
| 4 | Aura profana (pasiva) | aura: +velocidad de movimiento y regeneracion de vida del grupo | aura propia (MOD_INCREASE_SPEED + hp5, area de grupo) |
| Definitiva | Explosion de Escarcha | congela a un enemigo y a los cercanos (aturde) y los dana en el tiempo | 27808 |
| Suprema | Ira del Archiliche | nova de escarcha gigante alrededor: dano alto y congela 4 s | 42917 (mayor) |

## Gul'dan - ficha 38 - lanzador

| Casilla | Habilidad | Que hace | Base |
|---|---|---|---|
| 1 | Descarga de las Sombras | dano alto, lanzamiento 2 s | 47809 |
| 2 | Drenar vida | canalizado: dana y le cura lo mismo | 47857 |
| 3 | Lluvia de Fuego | zona canalizada de fuego | 47820 |
| 4 | Pacto demoniaco (pasiva) | aura: +poder con hechizos del grupo | 47240 |
| Definitiva | Invocar guardia vil | guardia vil CONTROLABLE (barra de mascota), permanente hasta que muere; mas fuerte por rango [invoc.] | 30146 |
| Suprema | Inferno | cae un infernal en el punto: aturde y dana en area; el infernal (guardian) lucha 30 s | 1122 |

## Archimonde - ficha 39 - lanzador / jefe

| Casilla | Habilidad | Que hace | Base |
|---|---|---|---|
| 1 | Dedo de la muerte | rayo de dano muy alto a un objetivo (reutilizacion larga) | 31984 |
| 2 | Rafaga de aire | lanza por los aires a los enemigos de una zona (sin dano de caida) | 32014 |
| 3 | Fuego apocaliptico | rastro de fuego que dana a quien lo pisa | 31945 / 31944 |
| 4 | Apreton de la Legion (pasiva) | quien le golpea recibe una maldicion de sombras en el tiempo | 31972 (proc al ser golpeado, como el Aura de Escarcha) |
| Definitiva | Terror de la Legion | miedo a los enemigos en un area grande + dano | 31970 |
| Suprema | Profanacion | zona enorme que dana mucho y reduce la curacion de los enemigos | 31945 (mayor) |

## Vol'jin - ficha 40 - apoyo

| Casilla | Habilidad | Que hace | Base |
|---|---|---|---|
| 1 | Maleficio | convierte a un enemigo en rana 2/3/4/5 s (no puede atacar) | 51514 |
| 2 | Guarda serpiente | guardian inmovil que dispara a los enemigos 20 s (2 en rango 4) [invoc.] | 51533 (criatura de guarda) |
| 3 | Ola de sanacion | curacion que salta a 3/4/5/6 aliados | 55459 (Sanacion en cadena; Thrall no cura) |
| 4 | Espiritus loa (pasiva) | aura: regeneracion de vida del grupo (hp5) | aura propia (area de grupo) |
| Definitiva | Gran vudu | los aliados cercanos son inmunes al dano 3/4/5 s (canalizado: Vol'jin no) | 642 (aura de inmunidad como aura de grupo) |
| Suprema | Abrazo de Bwonsamdi | zona de sombras: dana a los enemigos y cura a los aliados lo mismo 8 s | 47857 (aspecto) [script como la Espiral] |

## Cairne Pezuna de Sangre - ficha 41 - tanque

| Casilla | Habilidad | Que hace | Base |
|---|---|---|---|
| 1 | Pisoton de guerra | aturde a los enemigos cercanos 1,5/2/2,5/3 s | 20549 |
| 2 | Ola de choque | dano en cono delante + ralentizar | 46968 |
| 3 | Espiritu de la tierra | se cura en el tiempo y gana armadura 10 s | aura propia (PERIODIC_HEAL + MOD_RESISTANCE) |
| 4 | Aura de resistencia (pasiva) | aura: +velocidad de ataque y de movimiento del grupo | aura propia (MOD_MELEE_HASTE + MOD_INCREASE_SPEED, grupo) |
| Definitiva | Reencarnacion (pasiva) | al recibir un golpe mortal, renace en el sitio con 50/75/100 % de vida (reutilizacion 180/150/120 s) [script] | aura propia + script (absorber el dano mortal) |
| Suprema | Furia de la Madre Tierra | pisoton gigante: dano alto y aturde 3 s en area grande | 20549 (mayor) |

## Lor'themar Theron - ficha 42 - cuerpo a cuerpo / distancia

| Casilla | Habilidad | Que hace | Base |
|---|---|---|---|
| 1 | Disparo Arcano | disparo instantaneo de dano arcano (sin arma de distancia) | 49045 |
| 2 | Torrente Arcano | silencia a los enemigos cercanos 2 s y recupera mana | 28730 |
| 3 | Trampa de Escarcha | zona de hielo que ralentiza mucho a los enemigos | 13809 |
| 4 | Hoja de Quel'Thalas (pasiva) | sus golpes tienen probabilidad de dano arcano extra | aura propia (proc al golpear) |
| Definitiva | Fenix | invoca un fenix guardian 30 s que quema a los enemigos cercanos; mas fuerte por rango [invoc.] | 36723 |
| Suprema | Fuente del Sol | zona de luz 10 s: cura a los aliados y dana a los enemigos [script como la Espiral] | 53385 (aspecto) |

## Garrosh Grito Infernal - ficha 43 - cuerpo a cuerpo

| Casilla | Habilidad | Que hace | Base |
|---|---|---|---|
| 1 | Sed de sangre | golpe que le cura un % del dano | 23881 |
| 2 | Torbellino | gira y dana a todos los cercanos | 1680 |
| 3 | Grito intimidador | miedo a los enemigos cercanos | 5246 |
| 4 | Aluvion (pasiva) | tras un critico, +velocidad de ataque en los siguientes golpes | 12974 |
| Definitiva | Ansia de sangre | +celeridad y velocidad de ataque al grupo 15/20/25 s | 2825 |
| Suprema | Aullido de Aullavisceras | grito en cono enorme: dano alto y aturde 3 s | 46968 (mayor) |

## Rey Jokkum - ficha 44 - tanque

| Casilla | Habilidad | Que hace | Base |
|---|---|---|---|
| 1 | Lanzar roca | lanza una roca a distancia: dano alto y aturde 1 s | 50843 |
| 2 | Tajo de escarcha | golpe en cono de escarcha que ralentiza | 47520 (escuela escarcha) |
| 3 | Rugido glacial | provoca a los enemigos cercanos y gana armadura | 1161 + aura de armadura |
| 4 | Piel de gigante (pasiva) | +% vida maxima y -% dano recibido | aura propia (MOD_INCREASE_HEALTH_PERCENT + MOD_DAMAGE_PERCENT_TAKEN) |
| Definitiva | Avalancha | zona canalizada de rocas y hielo que dana y ralentiza | 42940 (otro aspecto) |
| Suprema | Ira de las Cumbres | terremoto: dano alto y aturde 3 s a todos alrededor; crece de tamano 15 s | 20549 (mayor) + aura de escala |

## Lo que hace falta ademas de las fichas

- **Scripts nuevos** (`EventWowHeroSpells.cpp`): Flecha negra (esqueleto al matar), Reencarnacion (absorber el dano
  mortal y renacer), y un script generico "dana a enemigos / cura a aliados en area" (Crematoria, Bwonsamdi, Fuente
  del Sol) parecido a la Espiral de la Muerte.
- **Criaturas de invocacion** (sin nombre ni script, rango 9500000+ como los vehiculos): lobos, esqueletos, guarda
  serpiente, elemental de agua, guardia vil, infernal, fenix. Comprobar que la criatura original no tiene IA que
  moleste (las de jefe suelen tener scripts).
- **Mascota controlable**: Jaina y Gul'dan (y Arthas DK). La barra de mascota ya funciona en partida.
- **Bases de jefe** (Kel'Thuzad, Archimonde): suelen tener objetivos o efectos raros (dano a todo el mapa, script
  del encuentro). Se revisan con `spellgen dump` antes de copiarlas; si dan guerra, se usa una base de clase con el
  aspecto del jefe (`visual`).
- Ataque basico D/L (disparo automatico propio): pendiente (`docs/heroes.md` seccion 6). Mientras no exista, todos
  pegan cuerpo a cuerpo.

## Orden propuesto

Por lo que reutilizan de Arthas y lo que prueban de nuevo:
1. Varian, Garrosh, Cairne (sin Reencarnacion al principio): cuerpo a cuerpo, bases de clase sencillas.
2. Jaina, Thrall, Gul'dan: lanzadores con invocaciones (mascota controlable y guardianes).
3. Arthas principe, Tirion, Vol'jin: apoyo/curacion + script generico de dano/cura.
4. Sylvanas, Lor'themar: distancia (necesitan el disparo automatico propio).
5. Kel'Thuzad, Archimonde, Jokkum: bases de jefe/criatura, las mas imprevisibles.
