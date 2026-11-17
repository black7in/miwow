-- EventWow: mapa propio 752 "EventWowCarrera" (mismo esquema que 2026_11_13_11_eventwow_map_asedio.sql; ver
-- docs/mapas.md). Circuito de carreras generado por tools/mapgen/trackgen.py desde Maps/Planos/circuito_cuatro_tierras.json.
-- Mazmorra de hasta 8 jugadores (el modulo controla la entrada: OnPlayerOverrideInstanceEnter).
-- Nombre en las 16 columnas de idioma: el cliente esES lee la 7a (las columnas de AC no siguen el orden del cliente).

DELETE FROM `map_dbc` WHERE `ID` = 752;
INSERT INTO `map_dbc` (`ID`, `Directory`, `InstanceType`, `Flags`, `PVP`,
    `MapName_Lang_enUS`, `MapName_Lang_enGB`, `MapName_Lang_koKR`, `MapName_Lang_frFR`, `MapName_Lang_deDE`,
    `MapName_Lang_enCN`, `MapName_Lang_zhCN`, `MapName_Lang_enTW`, `MapName_Lang_zhTW`, `MapName_Lang_esES`,
    `MapName_Lang_esMX`, `MapName_Lang_ruRU`, `MapName_Lang_ptPT`, `MapName_Lang_ptBR`, `MapName_Lang_itIT`,
    `MapName_Lang_Unk`, `MapName_Lang_Mask`, `AreaTableID`,
    `MapDescription0_Lang_Mask`, `MapDescription1_Lang_Mask`,
    `LoadingScreenID`, `MinimapIconScale`, `CorpseMapID`, `CorpseX`, `CorpseY`, `TimeOfDayOverride`, `ExpansionID`,
    `RaidOffset`, `MaxPlayers`)
VALUES (752, 'EventWowCarrera', 1, 0, 0,
    'Circuito de las Cuatro Tierras', 'Circuito de las Cuatro Tierras', 'Circuito de las Cuatro Tierras',
    'Circuito de las Cuatro Tierras', 'Circuito de las Cuatro Tierras', 'Circuito de las Cuatro Tierras',
    'Circuito de las Cuatro Tierras', 'Circuito de las Cuatro Tierras', 'Circuito de las Cuatro Tierras',
    'Circuito de las Cuatro Tierras', 'Circuito de las Cuatro Tierras', 'Circuito de las Cuatro Tierras',
    'Circuito de las Cuatro Tierras', 'Circuito de las Cuatro Tierras', 'Circuito de las Cuatro Tierras',
    'Circuito de las Cuatro Tierras',
    16712190, 5002,
    16712190, 16712190,
    250, 1, -1, 0, 0, -1, 0,
    0, 8);

DELETE FROM `mapdifficulty_dbc` WHERE `ID` = 9500002;
INSERT INTO `mapdifficulty_dbc` (`ID`, `MapID`, `Difficulty`, `Message_Lang_Mask`, `RaidDuration`, `MaxPlayers`,
    `Difficultystring`)
VALUES (9500002, 752, 0, 16712188, 0, 8, '');

DELETE FROM `instance_template` WHERE `map` = 752;
INSERT INTO `instance_template` (`map`, `parent`, `script`, `allowMount`) VALUES (752, 0, '', 0);

-- Zona (ID 5000-5099, AreaBit 3700-3799; ver 2026_11_13_12_eventwow_map_areas.sql)
DELETE FROM `areatable_dbc` WHERE `ID` = 5002;
INSERT INTO `areatable_dbc` (`ID`, `ContinentID`, `ParentAreaID`, `AreaBit`, `Flags`,
    `AreaName_Lang_enUS`, `AreaName_Lang_enGB`, `AreaName_Lang_koKR`, `AreaName_Lang_frFR`, `AreaName_Lang_deDE`,
    `AreaName_Lang_enCN`, `AreaName_Lang_zhCN`, `AreaName_Lang_enTW`, `AreaName_Lang_zhTW`, `AreaName_Lang_esES`,
    `AreaName_Lang_esMX`, `AreaName_Lang_ruRU`, `AreaName_Lang_ptPT`, `AreaName_Lang_ptBR`, `AreaName_Lang_itIT`,
    `AreaName_Lang_Unk`, `AreaName_Lang_Mask`, `MinElevation`)
VALUES
    (5002, 752, 0, 3702, 0,
     'Circuito de las Cuatro Tierras', 'Circuito de las Cuatro Tierras', 'Circuito de las Cuatro Tierras',
     'Circuito de las Cuatro Tierras', 'Circuito de las Cuatro Tierras', 'Circuito de las Cuatro Tierras',
     'Circuito de las Cuatro Tierras', 'Circuito de las Cuatro Tierras', 'Circuito de las Cuatro Tierras',
     'Circuito de las Cuatro Tierras', 'Circuito de las Cuatro Tierras', 'Circuito de las Cuatro Tierras',
     'Circuito de las Cuatro Tierras', 'Circuito de las Cuatro Tierras', 'Circuito de las Cuatro Tierras',
     'Circuito de las Cuatro Tierras',
     16712190, -500);
