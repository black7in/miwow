-- EventWow: mapa propio 751 (mismo esquema que 2026_11_13_10_eventwow_map_test.sql; ver docs/mapas.md).
-- 751 "EventWowAsedio": mapa del asedio (Maps/Warcraft/Mi_Mapa_XHero.w3x, diseno propio), mazmorra de 5.
-- Nombre en las 16 columnas de idioma: el cliente esES lee la 7a (las columnas de AC no siguen el orden del cliente).

DELETE FROM `map_dbc` WHERE `ID` = 751;
INSERT INTO `map_dbc` (`ID`, `Directory`, `InstanceType`, `Flags`, `PVP`,
    `MapName_Lang_enUS`, `MapName_Lang_enGB`, `MapName_Lang_koKR`, `MapName_Lang_frFR`, `MapName_Lang_deDE`,
    `MapName_Lang_enCN`, `MapName_Lang_zhCN`, `MapName_Lang_enTW`, `MapName_Lang_zhTW`, `MapName_Lang_esES`,
    `MapName_Lang_esMX`, `MapName_Lang_ruRU`, `MapName_Lang_ptPT`, `MapName_Lang_ptBR`, `MapName_Lang_itIT`,
    `MapName_Lang_Unk`, `MapName_Lang_Mask`, `AreaTableID`,
    `MapDescription0_Lang_Mask`, `MapDescription1_Lang_Mask`,
    `LoadingScreenID`, `MinimapIconScale`, `CorpseMapID`, `CorpseX`, `CorpseY`, `TimeOfDayOverride`, `ExpansionID`,
    `RaidOffset`, `MaxPlayers`)
VALUES (751, 'EventWowAsedio', 1, 0, 0,
    'Asedio', 'Asedio', 'Asedio', 'Asedio', 'Asedio', 'Asedio', 'Asedio', 'Asedio',
    'Asedio', 'Asedio', 'Asedio', 'Asedio', 'Asedio', 'Asedio', 'Asedio', 'Asedio',
    16712190, 0,
    16712190, 16712190,
    250, 1, -1, 0, 0, -1, 0,
    0, 5);

DELETE FROM `mapdifficulty_dbc` WHERE `ID` = 9500001;
INSERT INTO `mapdifficulty_dbc` (`ID`, `MapID`, `Difficulty`, `Message_Lang_Mask`, `RaidDuration`, `MaxPlayers`,
    `Difficultystring`)
VALUES (9500001, 751, 0, 16712188, 0, 5, '');

DELETE FROM `instance_template` WHERE `map` = 751;
INSERT INTO `instance_template` (`map`, `parent`, `script`, `allowMount`) VALUES (751, 0, '', 0);
