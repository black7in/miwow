-- EventWow: personaje de prueba del disfraz, asignado a los juegos test / test_group.
-- Goblin (modelo de Gazlowe) con vida/mana fijos y tres hechizos de mago existentes.
DELETE FROM `eventwow_character` WHERE `Id` = 1;
INSERT INTO `eventwow_character` (`Id`, `Name`, `Description`, `Icon`, `DisplayId`, `Scale`, `Health`, `PowerType`, `MaxPower`) VALUES
(1, 'Piromano goblin', 'Personaje de prueba del disfraz.', 'Interface\Icons\Spell_Fire_FlameBolt', 7052, 1.2, 5000, 0, 2000);

DELETE FROM `eventwow_character_spell` WHERE `CharacterId` = 1;
INSERT INTO `eventwow_character_spell` (`CharacterId`, `Slot`, `SpellId`) VALUES
(1, 0, 133),   -- Bola de Fuego (rango 1)
(1, 1, 122),   -- Nova de Escarcha (rango 1)
(1, 2, 1953);  -- Traslacion

DELETE FROM `eventwow_game_character` WHERE `GameId` IN ('test', 'test_group');
INSERT INTO `eventwow_game_character` (`GameId`, `CharacterId`, `Sort`) VALUES
('test', 1, 0),
('test_group', 1, 0);
