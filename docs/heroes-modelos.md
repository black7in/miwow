# Modelos para los heroes (jefes y personajes de WoW)

Sacados de la BD world (`creature_template_model`) el 2026-11-14. Probar con el GM:

```
.morph <display>      ponerse el modelo        .demorph           volver al normal
.modify scale <n>     tamano (1 = normal; algunos jefes son enormes: probar 0.5)
```

**Armas**: no forman parte del modelo. Los PNJ las llevan aparte (`creature_equip_template`), asi que con `.morph`
salen con las manos vacias. Para los heroes las pondremos nosotros (pendiente de investigar: armas "visibles" en el
personaje sin equiparlas). Las armas de los PNJ estan en la ultima columna (ID de objeto).

Varios ID por personaje = distintas versiones (epoca, armadura, mazmorra). La ultima columna de "Notas" dice de
donde sale cada una cuando se sabe; si no, probarlas.

## Lista inicial (elegida por el usuario, 2026-11-14)

Armas = `creature_equip_template` del PNJ que usa ese display (ItemID1 / ItemID2 / ItemID3 = mano derecha / izquierda /
distancia). Son objetos "Monster - ..." que ya estan en el Item.dbc del cliente (los PNJ los muestran).

Fichas: `eventwow_character` 30-44 (SQL `2026_11_14_05`, columnas `WeaponMainHand/WeaponOffHand` = armas visibles,
`PickCreature` 9500300-9500314 = su PNJ de eleccion). Escalas: Kel'Thuzad 0.24 y Archimonde 0.08 (ajustadas por el usuario), Jokkum 0.4.

| Heroe | Display | PNJ de origen | Mano derecha | Mano izquierda | Distancia | Notas |
|---|---|---|---|---|---|---|
| Arthas (principe) | 24949 | 26499 | 37579 maza de Arthas | | | |
| Arthas caballero de la Muerte | 22235 | 24267 (sin armas) | 36942 Agonia de Escarcha | | | decidido (el PNJ no lleva); 49706 = version de ICC (mas brillo), 50840 = rota |
| Thrall | 4527 | 4949 | 12183 Martillo Maldito | | | |
| Sylvanas | 28213 | 10181 | 9500200 arco de Sylvanas (copia de 42775 visible envainado) | | | decidido: arco en la mano derecha (la ranura de distancia no se dibuja). Cimitarras (2179, o 30403 x2 con brillo rojo) descartadas por ahora |
| Jaina | 30863 | 4968 | 2177 baston | | | decidido: solo el baston (el PNJ lleva tambien 12869, libro) |
| Varian | 28127 | 29611 | 45899 espada de Varian | | | |
| Tirion | 22209 | 24232 | 13262 Crematoria | | | |
| Kel'Thuzad | 15945 | 15990 (sin armas) | | | | decidido: sin arma; escala a probar |
| Gul'dan | 16642 | 17008 | 23450 daga de Gul'dan | | | |
| Archimonde | 20939 | 17968 (sin armas) | | | | como en WC3, sin arma; escala a probar |
| Vol'jin | 10357 | 10540 | 53835 guja de Vol'jin | | 14118 arco negro | |
| Cairne | 4307 | 3057 | 14084 totem de Cairne (2 manos) | | | |
| Lor'themar | 17122 | 16802 | 14882 guja de 2 hojas | 24038 escudo elfo de sangre | | |
| Garrosh | 23006 | 25237 | 23428 hacha de Grom | 23428 hacha de Grom | | Gorehowl a dos manos |
| Rey Jokkum | 26778 | 30105 | 40770 maza de gigante de escarcha | | | modelo enorme: escala a probar |

Probado por el usuario (2026-11-14): las armas salen sobre el modelo transformado, en su sitio, y la tecla Z las
envaina/desenvaina. `.eventwow weapon sheath` no hace nada (no hace falta). La ranura de distancia NO se ve: el arco
va en la MANO DERECHA (`set 42775`). Los arcos de PNJ tienen `sheath = 0` (envainados no se dibujan): copias propias
con otro envainado en el rango 9500200-9500299 (SQL `2026_11_14_03`): **9500200 = arco de Sylvanas, tipo 1 (espalda)**,
elegido por el usuario frente al tipo 2 (diagonal). Para otros arcos/armas que no se vean envainados: copia igual.

Comandos (`EventWowWeapons.cpp`, GM, sobre el seleccionado o uno mismo):

```
.morph 22235
.eventwow weapon set 36942            mano derecha [izquierda] [distancia]; 0 = vacia
.eventwow weapon sheath 1             0 envainada, 1 cuerpo a cuerpo, 2 distancia
.eventwow weapon clear
```

## Arthas / Rey Exanime

| Personaje | Display | Notas | Arma del PNJ |
|---|---|---|---|
| Arthas (principe) | 24949 | "Prince of Lordaeron" (La Matanza de Stratholme) | 37579 |
| Arthas humano | 21976 | vision de la Meseta del Sol | |
| Arthas oscuro | 22235 | Arthas caballero de la Muerte (vision) | |
| Arthas, Rey Exanime | 22234 | vision de la Meseta del Sol | 33475 |
| Principe Arthas Menethil | 27545 | | 33475 |
| El Rey Exanime | 24191 | Corona de Hielo (Rasganorte) | |
| El Rey Exanime | 30721 | Ciudadela de la Corona de Hielo (combate final) | 49706 (Agonia de Escarcha) |
| El Rey Exanime | 25325, 27481, 28122 | otras apariciones en Rasganorte | |
| Terenas Menethil | 31021 | espiritu (ICC) | |
| Uther el Iluminado | 23889, 30821 | | |

## Lideres de la Horda

| Personaje | Display | Notas | Arma del PNJ |
|---|---|---|---|
| Thrall | 4527 | Orgrimmar (clasico) | 12183 |
| Thrall | 17292 | joven (Antiguas Laderas de Trabalomas) | |
| Thrall | 27656, 27744, 29591, 29858 | versiones de WotLK (Puerta de Colera, Prueba del Cruzado...) | |
| Lady Sylvanas Brisaveloz | 28213 | Reina alma en pena | 2179, 42775 |
| Lady Sylvanas Brisaveloz | 30776 | Camaras de Reflexion | 49814 x2 |
| Garrosh Grito Infernal | 23006, 29592, 31428 | | 23428 x2 |
| Vol'jin | 10357, 31736 | | |
| Cairne Pezuna de Sangre | 4307 | | |
| Baine Pezuna de Sangre | 30272 | jefe supremo | |
| Alto Senor Supremo Colmillosauro | 30583, 30416 | ICC | |
| Lor'themar Theron | 17122 | | |
| Grom Grito Infernal | 21575, 17470 | | |
| Rexxar | 20918 | | |

## Lideres de la Alianza

| Personaje | Display | Notas | Arma del PNJ |
|---|---|---|---|
| Lady Jaina Valiente | 30863, 30864, 30865, 30866, 30867 | | 2177, 12869 |
| Rey Varian Wrynn | 28127, 29589, 30417 | | 45899 |
| Alto Senor Tirion Vadin | 22209, 29588, 29860, 31011, 31286 | 31011 = ICC (con la Crematoria en el PNJ) | 13262 |
| Alto Senor Bolvar Fordragon | 5566, 24879 | 5566 clasico, 24879 Puerta de Colera | |
| Muradin Barbabronce | 30508 | ICC | 49775, 49774 |
| Rey Magni Barbabronce | 3597 | | |
| Malfurion Tempestira | 15399 | | |
| Tyrande Susurravientos | 7274, 17873 | | |
| Profeta Velen | 17822, 23749 | | |
| Alto Senor Darion Mograine | 25444, 27153, 30869 | caballero de la Muerte | |
| Brann Barbabronce | 26353 | | |

## Villanos de otras epocas

| Personaje | Display | Notas | Arma del PNJ |
|---|---|---|---|
| Illidan Tempestira | 21135, 27571 | | 32632, 32633 (gujas) |
| Kael'thas Caminante del Sol | 20023, 22906 | | |
| Lady Vashj | 20748 | | |
| Akama | 20681 | | |
| Maiev Cantosombrio | 20628 | | |
| Archimonde | 20939 | enorme | |
| Kil'jaeden | 23200 | enorme | |
| Gul'dan | 16642 | | |
| Teron Sanguino | 21254 | | |
| Medivh | 18718 | | |
| Mal'Ganis | 26582 | | |
| Lord Jaraxxus | 29615 | | |

## Jefes de Rasganorte (WotLK)

| Personaje | Display | Notas |
|---|---|---|
| Kel'Thuzad | 15945 (liche, Naxxramas), 19548 (humano) | |
| Anub'arak | 27856 (Azjol-Nerub), 29268 (Prueba del Cruzado) | |
| Lady Susurramuerte | 30893 | ICC |
| Reina de Sangre Lana'thel | 31165 | ICC |
| Libramorte Colmillosauro | 30790 | ICC |
| Lord Tuetano | 31119 | ICC, grande |
| Principes de sangre Keleseth / Taldaram / Valanar | 30857 / 30856 / 30858 | ICC |
| Falric / Marwyn | 30972 / 30973 | Camaras de Reflexion |
| Bronjahm | 30226 | Forja de Almas |
| Ingvar el Desvalijador | 21953 | Fortaleza de Utgarde |
| Rey Ymiron | 28019 | Pinaculo de Utgarde |
| Instructor Razuvious / Gothik / Heigan / Noth / Faerlina | 16582 / 16279 / 16309 / 16590 / 15940 | Naxxramas |
| Baron Osahendido | 10729 | |
| Thorim / Hodir / Freya / Mimiron | 28977 / 28743 / 28777 / 28578 | Ulduar |
| General Vezax | 28548 | Ulduar |
| Algalon el Observador | 28641 | Ulduar |
