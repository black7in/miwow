-- EventWow: personajes de PRUEBA de la bateria de hechizos (ficha data/spells/prueba.toml, docs/hechizos.md paso 2).
-- Elegibles en el Asedio. Mucha vida y mana para probar sin quedarse seco. Quitar cuando haya heroes reales.
DELETE FROM `eventwow_character` WHERE `Id` IN (20, 21);
INSERT INTO `eventwow_character` (`Id`, `Name`, `Description`, `Icon`, `DisplayId`, `Scale`, `Health`, `PowerType`, `MaxPower`, `VehicleEntry`) VALUES
(20, 'Probador ofensivo', 'Prueba de hechizos: lanzamiento, área, suelo, daño en el tiempo, enraizar, cargar, empujar, cadena, canalizado y disparo automático.', 'Interface\Icons\Spell_Fire_FlameBolt', 19612, 1.0, 20000, 0, 20000, 0),
(21, 'Probador de apoyo', 'Prueba de hechizos: curaciones, escudo, mejora de grupo, aura de grupo, aura de inmolación, pasiva y el martillo.', 'Interface\Icons\Spell_Holy_Renew', 4249, 1.0, 20000, 0, 20000, 0);

DELETE FROM `eventwow_character_spell` WHERE `CharacterId` IN (20, 21);
INSERT INTO `eventwow_character_spell` (`CharacterId`, `Slot`, `SpellId`) VALUES
(20, 0, 9500010),  -- Descarga de prueba (2 s)
(20, 1, 9500011),  -- Explosion de prueba (area alrededor)
(20, 2, 9500012),  -- Fuego del suelo (punto + suelo ardiendo)
(20, 3, 9500013),  -- Dolor de prueba (dano en el tiempo)
(20, 4, 9500021),  -- Nova de prueba (area + enraizar)
(20, 5, 9500022),  -- Carga de prueba
(20, 6, 9500023),  -- Trueno de prueba (empujar)
(20, 7, 9500024),  -- Cadena de prueba
(20, 8, 9500025),  -- Tortura de prueba (canalizado)
(20, 9, 9500026),  -- Disparo de prueba (automatico)
(21, 0, 9500014),  -- Renovacion de prueba (curacion en el tiempo)
(21, 1, 9500015),  -- Sanacion de prueba (1,5 s)
(21, 2, 9500016),  -- Escudo de prueba
(21, 3, 9500017),  -- Furia de prueba (mejora de grupo)
(21, 4, 9500018),  -- Aura de prueba (aura de grupo permanente)
(21, 5, 9500020),  -- Aura de inmolacion de prueba
(21, 6, 9500027),  -- Pasiva de prueba
(21, 7, 9500003);  -- Martillo de prueba, Nivel 4

DELETE FROM `eventwow_character_stat` WHERE `CharacterId` IN (20, 21);

DELETE FROM `eventwow_game_character` WHERE `GameId` = 'asedio' AND `CharacterId` IN (20, 21);
INSERT INTO `eventwow_game_character` (`GameId`, `CharacterId`, `Sort`) VALUES
('asedio', 20, 10),
('asedio', 21, 11);
