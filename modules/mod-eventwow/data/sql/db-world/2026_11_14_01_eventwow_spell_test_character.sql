-- EventWow: personaje de PRUEBA de los hechizos propios (tools/spellgen, ficha data/spells/prueba.toml).
-- Lleva los 4 rangos de "Martillo de prueba" (9500000-9500003) a la vez para comparar tooltips y efectos.
-- Elegible en el Asedio (fase de eleccion). Quitar cuando haya heroes reales.
DELETE FROM `eventwow_character` WHERE `Id` = 19;
INSERT INTO `eventwow_character` (`Id`, `Name`, `Description`, `Icon`, `DisplayId`, `Scale`, `Health`, `PowerType`, `MaxPower`, `VehicleEntry`) VALUES
(19, 'Probador de hechizos', 'Prueba de los hechizos propios: los 4 niveles de Martillo de prueba.', 'Interface\Icons\Spell_Holy_SealOfMight', 26228, 1.0, 9000, 0, 4000, 0);

DELETE FROM `eventwow_character_spell` WHERE `CharacterId` = 19;
INSERT INTO `eventwow_character_spell` (`CharacterId`, `Slot`, `SpellId`) VALUES
(19, 0, 9500000),  -- Martillo de prueba, Nivel 1
(19, 1, 9500001),  -- Nivel 2
(19, 2, 9500002),  -- Nivel 3
(19, 3, 9500003);  -- Nivel 4

DELETE FROM `eventwow_character_stat` WHERE `CharacterId` = 19;

DELETE FROM `eventwow_game_character` WHERE `GameId` = 'asedio' AND `CharacterId` = 19;
INSERT INTO `eventwow_game_character` (`GameId`, `CharacterId`, `Sort`) VALUES
('asedio', 19, 9);
