-- EventWow: mapas propios (rango de IDs de mapa reservado 750-799; ver docs/mapas.md).
-- Por debajo de 800 a proposito (TC9Sidecar.h MAX_MAP_ID); los de WotLK llegan a 724.
-- El terreno lo genera tools/mapgen desde un mapa de Warcraft 3 (Maps/maps.json); aqui solo los datos del mapa:
--   map_dbc            -> Map.dbc (servidor; Build-Dbc lo exporta al cliente: rango 750-799)
--   mapdifficulty_dbc  -> dificultad normal sin reinicio (rango de filas propio 9500000+)
--   instance_template  -> sin el, el mapa no se puede instanciar (EventWowGames::Validate)
--
-- 750 "EventWowTest": mapa de prueba (Maps/Warcraft/test.w3m), mazmorra de 5.
-- Nombre en las 16 columnas de idioma: el cliente esES lee la 7a (las columnas de AC no siguen el orden del cliente).

DELETE FROM `map_dbc` WHERE `ID` = 750;
INSERT INTO `map_dbc` (`ID`, `Directory`, `InstanceType`, `Flags`, `PVP`,
    `MapName_Lang_enUS`, `MapName_Lang_enGB`, `MapName_Lang_koKR`, `MapName_Lang_frFR`, `MapName_Lang_deDE`,
    `MapName_Lang_enCN`, `MapName_Lang_zhCN`, `MapName_Lang_enTW`, `MapName_Lang_zhTW`, `MapName_Lang_esES`,
    `MapName_Lang_esMX`, `MapName_Lang_ruRU`, `MapName_Lang_ptPT`, `MapName_Lang_ptBR`, `MapName_Lang_itIT`,
    `MapName_Lang_Unk`, `MapName_Lang_Mask`, `AreaTableID`,
    `MapDescription0_Lang_Mask`, `MapDescription1_Lang_Mask`,
    `LoadingScreenID`, `MinimapIconScale`, `CorpseMapID`, `CorpseX`, `CorpseY`, `TimeOfDayOverride`, `ExpansionID`,
    `RaidOffset`, `MaxPlayers`)
VALUES (750, 'EventWowTest', 1, 0, 0,
    'Prueba WC3', 'Prueba WC3', 'Prueba WC3', 'Prueba WC3', 'Prueba WC3', 'Prueba WC3', 'Prueba WC3', 'Prueba WC3',
    'Prueba WC3', 'Prueba WC3', 'Prueba WC3', 'Prueba WC3', 'Prueba WC3', 'Prueba WC3', 'Prueba WC3', 'Prueba WC3',
    16712190, 0,
    16712190, 16712190,
    216, 1, -1, 0, 0, -1, 0,
    0, 5);

DELETE FROM `mapdifficulty_dbc` WHERE `ID` = 9500000;
INSERT INTO `mapdifficulty_dbc` (`ID`, `MapID`, `Difficulty`, `Message_Lang_Mask`, `RaidDuration`, `MaxPlayers`,
    `Difficultystring`)
VALUES (9500000, 750, 0, 16712188, 0, 5, '');

DELETE FROM `instance_template` WHERE `map` = 750;
INSERT INTO `instance_template` (`map`, `parent`, `script`, `allowMount`) VALUES (750, 0, '', 0);
