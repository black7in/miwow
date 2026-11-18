-- EventWow: mapa propio 754 "EventWowParkour" (mismo esquema que 2026_11_17_01_eventwow_map_espacio.sql; ver
-- docs/mapas.md). Parkour "Ascenso", generado por tools/mapgen/parkourgen.py desde Maps/Planos/parkour_ascenso.json:
-- sin terreno (todo agujeros), ruta de saltos hecha de modelos M2 entre islas flotantes de Nagrand.
-- Nombre en las 16 columnas de idioma: el cliente esES lee la 7a (las columnas de AC no siguen el orden del cliente).

DELETE FROM `map_dbc` WHERE `ID` = 754;
INSERT INTO `map_dbc` (`ID`, `Directory`, `InstanceType`, `Flags`, `PVP`,
    `MapName_Lang_enUS`, `MapName_Lang_enGB`, `MapName_Lang_koKR`, `MapName_Lang_frFR`, `MapName_Lang_deDE`,
    `MapName_Lang_enCN`, `MapName_Lang_zhCN`, `MapName_Lang_enTW`, `MapName_Lang_zhTW`, `MapName_Lang_esES`,
    `MapName_Lang_esMX`, `MapName_Lang_ruRU`, `MapName_Lang_ptPT`, `MapName_Lang_ptBR`, `MapName_Lang_itIT`,
    `MapName_Lang_Unk`, `MapName_Lang_Mask`, `AreaTableID`,
    `MapDescription0_Lang_Mask`, `MapDescription1_Lang_Mask`,
    `LoadingScreenID`, `MinimapIconScale`, `CorpseMapID`, `CorpseX`, `CorpseY`, `TimeOfDayOverride`, `ExpansionID`,
    `RaidOffset`, `MaxPlayers`)
VALUES (754, 'EventWowParkour', 1, 0, 0,
    'Ascenso', 'Ascenso', 'Ascenso', 'Ascenso', 'Ascenso', 'Ascenso', 'Ascenso', 'Ascenso', 'Ascenso', 'Ascenso', 'Ascenso', 'Ascenso', 'Ascenso', 'Ascenso', 'Ascenso', 'Ascenso',
    16712190, 5004,
    16712190, 16712190,
    250, 1, -1, 0, 0, -1, 0,
    0, 40);

DELETE FROM `mapdifficulty_dbc` WHERE `ID` = 9500004;
INSERT INTO `mapdifficulty_dbc` (`ID`, `MapID`, `Difficulty`, `Message_Lang_Mask`, `RaidDuration`, `MaxPlayers`,
    `Difficultystring`)
VALUES (9500004, 754, 0, 16712188, 0, 40, '');

DELETE FROM `instance_template` WHERE `map` = 754;
INSERT INTO `instance_template` (`map`, `parent`, `script`, `allowMount`) VALUES (754, 0, '', 0);

-- Zona (ID 5000-5099, AreaBit 3700-3799; ver 2026_11_13_12_eventwow_map_areas.sql)
DELETE FROM `areatable_dbc` WHERE `ID` = 5004;
INSERT INTO `areatable_dbc` (`ID`, `ContinentID`, `ParentAreaID`, `AreaBit`, `Flags`,
    `AreaName_Lang_enUS`, `AreaName_Lang_enGB`, `AreaName_Lang_koKR`, `AreaName_Lang_frFR`, `AreaName_Lang_deDE`,
    `AreaName_Lang_enCN`, `AreaName_Lang_zhCN`, `AreaName_Lang_enTW`, `AreaName_Lang_zhTW`, `AreaName_Lang_esES`,
    `AreaName_Lang_esMX`, `AreaName_Lang_ruRU`, `AreaName_Lang_ptPT`, `AreaName_Lang_ptBR`, `AreaName_Lang_itIT`,
    `AreaName_Lang_Unk`, `AreaName_Lang_Mask`, `MinElevation`)
VALUES
    (5004, 754, 0, 3704, 0,
     'Ascenso', 'Ascenso', 'Ascenso', 'Ascenso', 'Ascenso', 'Ascenso', 'Ascenso', 'Ascenso', 'Ascenso', 'Ascenso', 'Ascenso', 'Ascenso', 'Ascenso', 'Ascenso', 'Ascenso', 'Ascenso',
     16712190, -500);

-- Cielo: luz global del mapa (posicion 0,0,0 = luz por defecto). Copia de la de Nagrand (Light 418, mapa 530):
-- LightParams 396 (bajo el agua 491) -> LightSkybox NagrandSkyBox (cielo de Draenor con planetas, verdoso).
-- IDs de luz propios: 2600-2699.
DELETE FROM `light_dbc` WHERE `ID` = 2601;
INSERT INTO `light_dbc` (`ID`, `ContinentID`, `X`, `Y`, `Z`, `FalloffStart`, `FalloffEnd`,
    `LightParamsID_1`, `LightParamsID_2`, `LightParamsID_3`, `LightParamsID_4`, `LightParamsID_5`,
    `LightParamsID_6`, `LightParamsID_7`, `LightParamsID_8`)
VALUES (2601, 754, 0, 0, 0, 23262.191, 30725.883, 396, 491, 396, 491, 3, 0, 0, 0);

-- Personaje 50 "Saltador": gnomo (display 5436, como el Piloto) sin hechizos. El disfraz impide al contenedor (druida)
-- usar formas, monturas o cualquier otro hechizo (EventWowDisguise: OnSpellCheckCast).
DELETE FROM `eventwow_character` WHERE `Id` = 50;
INSERT INTO `eventwow_character` (`Id`, `Name`, `Description`, `Icon`, `DisplayId`, `Scale`, `Health`, `PowerType`,
    `MaxPower`) VALUES
(50, 'Saltador', 'Gnomo ágil: solo sus piernas.', 'Interface\\Icons\\Ability_Rogue_Sprint', 5436, 1.0, 0, 0, 0);

DELETE FROM `eventwow_game_character` WHERE `GameId` = 'parkour';
INSERT INTO `eventwow_game_character` (`GameId`, `CharacterId`, `Sort`) VALUES ('parkour', 50, 0);
