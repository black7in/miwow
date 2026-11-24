-- MiWow: mapa propio 755 "EventWowCastillo" (mismo esquema que 2026_11_18_01_miwow_map_parkour.sql; ver
-- docs/mapas.md). Defensa del castillo, generado por tools/mapgen/castlegen.py desde Maps/Planos/defensa_castillo.json:
-- canon nevado (un solo camino) hasta la fachada de la fortaleza de Conquista del Invierno (objetos del servidor).
-- Nombre en las 16 columnas de idioma: el cliente esES lee la 7a (las columnas de AC no siguen el orden del cliente).
-- Sin luz propia: cielo por defecto.

DELETE FROM `map_dbc` WHERE `ID` = 755;
INSERT INTO `map_dbc` (`ID`, `Directory`, `InstanceType`, `Flags`, `PVP`,
    `MapName_Lang_enUS`, `MapName_Lang_enGB`, `MapName_Lang_koKR`, `MapName_Lang_frFR`, `MapName_Lang_deDE`,
    `MapName_Lang_enCN`, `MapName_Lang_zhCN`, `MapName_Lang_enTW`, `MapName_Lang_zhTW`, `MapName_Lang_esES`,
    `MapName_Lang_esMX`, `MapName_Lang_ruRU`, `MapName_Lang_ptPT`, `MapName_Lang_ptBR`, `MapName_Lang_itIT`,
    `MapName_Lang_Unk`, `MapName_Lang_Mask`, `AreaTableID`,
    `MapDescription0_Lang_Mask`, `MapDescription1_Lang_Mask`,
    `LoadingScreenID`, `MinimapIconScale`, `CorpseMapID`, `CorpseX`, `CorpseY`, `TimeOfDayOverride`, `ExpansionID`,
    `RaidOffset`, `MaxPlayers`)
VALUES (755, 'EventWowCastillo', 1, 0, 0,
    'Defensa del castillo', 'Defensa del castillo', 'Defensa del castillo', 'Defensa del castillo', 'Defensa del castillo', 'Defensa del castillo', 'Defensa del castillo', 'Defensa del castillo', 'Defensa del castillo', 'Defensa del castillo', 'Defensa del castillo', 'Defensa del castillo', 'Defensa del castillo', 'Defensa del castillo', 'Defensa del castillo', 'Defensa del castillo',
    16712190, 5005,
    16712190, 16712190,
    250, 1, -1, 0, 0, -1, 0,
    0, 5);

DELETE FROM `mapdifficulty_dbc` WHERE `ID` = 9500005;
INSERT INTO `mapdifficulty_dbc` (`ID`, `MapID`, `Difficulty`, `Message_Lang_Mask`, `RaidDuration`, `MaxPlayers`,
    `Difficultystring`)
VALUES (9500005, 755, 0, 16712188, 0, 5, '');

DELETE FROM `instance_template` WHERE `map` = 755;
INSERT INTO `instance_template` (`map`, `parent`, `script`, `allowMount`) VALUES (755, 0, '', 0);

-- Zona (ID 5000-5099, AreaBit 3700-3799; ver 2026_11_13_12_miwow_map_areas.sql)
DELETE FROM `areatable_dbc` WHERE `ID` = 5005;
INSERT INTO `areatable_dbc` (`ID`, `ContinentID`, `ParentAreaID`, `AreaBit`, `Flags`,
    `AreaName_Lang_enUS`, `AreaName_Lang_enGB`, `AreaName_Lang_koKR`, `AreaName_Lang_frFR`, `AreaName_Lang_deDE`,
    `AreaName_Lang_enCN`, `AreaName_Lang_zhCN`, `AreaName_Lang_enTW`, `AreaName_Lang_zhTW`, `AreaName_Lang_esES`,
    `AreaName_Lang_esMX`, `AreaName_Lang_ruRU`, `AreaName_Lang_ptPT`, `AreaName_Lang_ptBR`, `AreaName_Lang_itIT`,
    `AreaName_Lang_Unk`, `AreaName_Lang_Mask`, `MinElevation`)
VALUES
    (5005, 755, 0, 3705, 0,
     'Defensa del castillo', 'Defensa del castillo', 'Defensa del castillo', 'Defensa del castillo', 'Defensa del castillo', 'Defensa del castillo', 'Defensa del castillo', 'Defensa del castillo', 'Defensa del castillo', 'Defensa del castillo', 'Defensa del castillo', 'Defensa del castillo', 'Defensa del castillo', 'Defensa del castillo', 'Defensa del castillo', 'Defensa del castillo',
     16712190, -500);
