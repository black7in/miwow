-- EventWow: mapa propio 753 "EventWowEspacio" (mismo esquema que 2026_11_17_00_eventwow_map_carrera.sql; ver
-- docs/mapas.md). Circuito de carreras en el espacio, generado por tools/mapgen/platformgen.py desde
-- Maps/Planos/circuito_estelar.json: sin terreno (todo agujeros), pista de modelos M2 encadenados.
-- Nombre en las 16 columnas de idioma: el cliente esES lee la 7a (las columnas de AC no siguen el orden del cliente).

DELETE FROM `map_dbc` WHERE `ID` = 753;
INSERT INTO `map_dbc` (`ID`, `Directory`, `InstanceType`, `Flags`, `PVP`,
    `MapName_Lang_enUS`, `MapName_Lang_enGB`, `MapName_Lang_koKR`, `MapName_Lang_frFR`, `MapName_Lang_deDE`,
    `MapName_Lang_enCN`, `MapName_Lang_zhCN`, `MapName_Lang_enTW`, `MapName_Lang_zhTW`, `MapName_Lang_esES`,
    `MapName_Lang_esMX`, `MapName_Lang_ruRU`, `MapName_Lang_ptPT`, `MapName_Lang_ptBR`, `MapName_Lang_itIT`,
    `MapName_Lang_Unk`, `MapName_Lang_Mask`, `AreaTableID`,
    `MapDescription0_Lang_Mask`, `MapDescription1_Lang_Mask`,
    `LoadingScreenID`, `MinimapIconScale`, `CorpseMapID`, `CorpseX`, `CorpseY`, `TimeOfDayOverride`, `ExpansionID`,
    `RaidOffset`, `MaxPlayers`)
VALUES (753, 'EventWowEspacio', 1, 0, 0,
    'Circuito Estelar', 'Circuito Estelar', 'Circuito Estelar', 'Circuito Estelar', 'Circuito Estelar', 'Circuito Estelar', 'Circuito Estelar', 'Circuito Estelar', 'Circuito Estelar', 'Circuito Estelar', 'Circuito Estelar', 'Circuito Estelar', 'Circuito Estelar', 'Circuito Estelar', 'Circuito Estelar', 'Circuito Estelar',
    16712190, 5003,
    16712190, 16712190,
    250, 1, -1, 0, 0, -1, 0,
    0, 8);

DELETE FROM `mapdifficulty_dbc` WHERE `ID` = 9500003;
INSERT INTO `mapdifficulty_dbc` (`ID`, `MapID`, `Difficulty`, `Message_Lang_Mask`, `RaidDuration`, `MaxPlayers`,
    `Difficultystring`)
VALUES (9500003, 753, 0, 16712188, 0, 8, '');

DELETE FROM `instance_template` WHERE `map` = 753;
INSERT INTO `instance_template` (`map`, `parent`, `script`, `allowMount`) VALUES (753, 0, '', 0);

-- Zona (ID 5000-5099, AreaBit 3700-3799; ver 2026_11_13_12_eventwow_map_areas.sql)
DELETE FROM `areatable_dbc` WHERE `ID` = 5003;
INSERT INTO `areatable_dbc` (`ID`, `ContinentID`, `ParentAreaID`, `AreaBit`, `Flags`,
    `AreaName_Lang_enUS`, `AreaName_Lang_enGB`, `AreaName_Lang_koKR`, `AreaName_Lang_frFR`, `AreaName_Lang_deDE`,
    `AreaName_Lang_enCN`, `AreaName_Lang_zhCN`, `AreaName_Lang_enTW`, `AreaName_Lang_zhTW`, `AreaName_Lang_esES`,
    `AreaName_Lang_esMX`, `AreaName_Lang_ruRU`, `AreaName_Lang_ptPT`, `AreaName_Lang_ptBR`, `AreaName_Lang_itIT`,
    `AreaName_Lang_Unk`, `AreaName_Lang_Mask`, `MinElevation`)
VALUES
    (5003, 753, 0, 3703, 0,
     'Circuito Estelar', 'Circuito Estelar', 'Circuito Estelar', 'Circuito Estelar', 'Circuito Estelar', 'Circuito Estelar', 'Circuito Estelar', 'Circuito Estelar', 'Circuito Estelar', 'Circuito Estelar', 'Circuito Estelar', 'Circuito Estelar', 'Circuito Estelar', 'Circuito Estelar', 'Circuito Estelar', 'Circuito Estelar',
     16712190, -500);

-- Cielo: luz global del mapa (posicion 0,0,0 = luz por defecto, como GetDefaultMapLight del core). Copia de la del
-- Ojo de la Eternidad (Light 1773, mapa 616): LightParams 8 -> LightSkybox 105 NexusRaid_StarrySky (estrellas).
-- IDs de luz propios: 2600-2699 (Light.dbc del cliente llega a 2538; Build-Dbc exporta ese rango).
DELETE FROM `light_dbc` WHERE `ID` = 2600;
INSERT INTO `light_dbc` (`ID`, `ContinentID`, `X`, `Y`, `Z`, `FalloffStart`, `FalloffEnd`,
    `LightParamsID_1`, `LightParamsID_2`, `LightParamsID_3`, `LightParamsID_4`, `LightParamsID_5`,
    `LightParamsID_6`, `LightParamsID_7`, `LightParamsID_8`)
VALUES (2600, 753, 0, 0, 0, 23262.191, 30725.883, 8, 9, 8, 11, 3, 8, 0, 0);
