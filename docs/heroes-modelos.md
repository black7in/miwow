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
