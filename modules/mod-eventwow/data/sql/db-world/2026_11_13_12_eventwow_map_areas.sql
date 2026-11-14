-- EventWow: zona (AreaTable) de cada mapa propio: nombre en el minimapa y al entrar, y area conocida por el servidor.
-- Una sola zona por mapa (sin subzonas). tools/mapgen la escribe en todo el terreno (MCNK del ADT y .map del servidor)
-- segun "areaId" de Maps/maps.json; Build-Dbc la exporta a AreaTable.dbc del cliente.
-- Rangos reservados: ID 5000-5099 (el cliente llega a 4987; el cliente y el core dimensionan tablas por el ID mas
-- alto, por eso no se usa el rango 9500000) y AreaBit (bit de exploracion) 3700-3799 (el cliente usa hasta 3617,
-- limite 4095).
-- Valores como una mazmorra del cliente (Las Minas de la Muerte, 1581): MinElevation -500, mascara de idiomas
-- 0xFF01FE. Sin musica ni ambiente de momento (ZoneMusic / AmbienceID = 0).
-- Nombre en las 16 columnas de idioma: el cliente esES lee la 7a (las columnas de AC no siguen el orden del cliente).

DELETE FROM `areatable_dbc` WHERE `ID` IN (5000, 5001);
INSERT INTO `areatable_dbc` (`ID`, `ContinentID`, `ParentAreaID`, `AreaBit`, `Flags`,
    `AreaName_Lang_enUS`, `AreaName_Lang_enGB`, `AreaName_Lang_koKR`, `AreaName_Lang_frFR`, `AreaName_Lang_deDE`,
    `AreaName_Lang_enCN`, `AreaName_Lang_zhCN`, `AreaName_Lang_enTW`, `AreaName_Lang_zhTW`, `AreaName_Lang_esES`,
    `AreaName_Lang_esMX`, `AreaName_Lang_ruRU`, `AreaName_Lang_ptPT`, `AreaName_Lang_ptBR`, `AreaName_Lang_itIT`,
    `AreaName_Lang_Unk`, `AreaName_Lang_Mask`, `MinElevation`)
VALUES
    (5000, 750, 0, 3700, 0,
     'Prueba WC3', 'Prueba WC3', 'Prueba WC3', 'Prueba WC3', 'Prueba WC3', 'Prueba WC3', 'Prueba WC3', 'Prueba WC3',
     'Prueba WC3', 'Prueba WC3', 'Prueba WC3', 'Prueba WC3', 'Prueba WC3', 'Prueba WC3', 'Prueba WC3', 'Prueba WC3',
     16712190, -500),
    (5001, 751, 0, 3701, 0,
     'Asedio', 'Asedio', 'Asedio', 'Asedio', 'Asedio', 'Asedio', 'Asedio', 'Asedio',
     'Asedio', 'Asedio', 'Asedio', 'Asedio', 'Asedio', 'Asedio', 'Asedio', 'Asedio',
     16712190, -500);

-- Zona principal de cada mapa
UPDATE `map_dbc` SET `AreaTableID` = 5000 WHERE `ID` = 750;
UPDATE `map_dbc` SET `AreaTableID` = 5001 WHERE `ID` = 751;
