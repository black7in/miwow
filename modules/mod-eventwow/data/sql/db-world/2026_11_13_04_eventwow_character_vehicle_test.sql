-- EventWow: personaje de prueba del vehiculo, asignado al juego test_vehicle.
-- Goblin (modelo de Gazlowe) en una Salvaged Chopper (33062, moto de Ulduar con hechizos propios en la barra de vehiculo).
DELETE FROM `eventwow_character` WHERE `Id` = 2;
INSERT INTO `eventwow_character` (`Id`, `Name`, `Description`, `Icon`, `DisplayId`, `Scale`, `Health`, `PowerType`, `MaxPower`, `VehicleEntry`) VALUES
(2, 'Motorista goblin', 'Personaje de prueba del vehiculo.', 'Interface\Icons\Spell_Nature_Swiftness', 7052, 1, 0, 0, 0, 33062);

DELETE FROM `eventwow_character_spell` WHERE `CharacterId` = 2;

DELETE FROM `eventwow_game_character` WHERE `GameId` = 'test_vehicle';
INSERT INTO `eventwow_game_character` (`GameId`, `CharacterId`, `Sort`) VALUES
('test_vehicle', 2, 0);
