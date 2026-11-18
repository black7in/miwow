-- EventWow: carreras (juegos "carrera" en el mapa 752 y "carrera_estelar" en el 753; EventWowGameRace.cpp).
--
-- 9500001: moto de carreras = Salvaged Chopper (33062) como la 9500000 (ver _05: sin nombre, script, heroico, clic
-- ni traducciones) pero a 28 yardas/s (speed_run 4 x 7) y SIN hechizos de vehiculo (la barra queda libre para los
-- poderes de la carrera).
DELETE FROM `creature_template` WHERE `entry` = 9500001;
DELETE FROM `creature_template_model` WHERE `CreatureID` = 9500001;
DELETE FROM `creature_template_spell` WHERE `CreatureID` = 9500001;
DELETE FROM `creature_template_addon` WHERE `entry` = 9500001;

CREATE TEMPORARY TABLE `eventwow_tmp_template` SELECT * FROM `creature_template` WHERE `entry` = 33062;
UPDATE `eventwow_tmp_template` SET `entry` = 9500001, `difficulty_entry_1` = 0, `name` = '', `subname` = '', `ScriptName` = '',
    `AIName` = '', `npcflag` = 0, `speed_walk` = 4, `speed_run` = 4;
INSERT INTO `creature_template` SELECT * FROM `eventwow_tmp_template`;
DROP TEMPORARY TABLE `eventwow_tmp_template`;

CREATE TEMPORARY TABLE `eventwow_tmp_model` SELECT * FROM `creature_template_model` WHERE `CreatureID` = 33062;
UPDATE `eventwow_tmp_model` SET `CreatureID` = 9500001;
INSERT INTO `creature_template_model` SELECT * FROM `eventwow_tmp_model`;
DROP TEMPORARY TABLE `eventwow_tmp_model`;

CREATE TEMPORARY TABLE `eventwow_tmp_addon` SELECT * FROM `creature_template_addon` WHERE `entry` = 33062;
UPDATE `eventwow_tmp_addon` SET `entry` = 9500001;
INSERT INTO `creature_template_addon` SELECT * FROM `eventwow_tmp_addon`;
DROP TEMPORARY TABLE `eventwow_tmp_addon`;

-- Personaje 3 "Piloto": goblin (como el Motorista de pruebas) en la moto de carreras. Todos los corredores iguales
-- (EventWowMatch::GetAssignedCharacter = el primero del juego).
DELETE FROM `eventwow_character` WHERE `Id` = 3;
INSERT INTO `eventwow_character` (`Id`, `Name`, `Description`, `Icon`, `DisplayId`, `Scale`, `Health`, `PowerType`,
    `MaxPower`, `VehicleEntry`) VALUES
(3, 'Piloto', 'Piloto goblin en su moto de carreras.', 'Interface\Icons\Ability_Mount_MechaStrider', 7052, 1.0, 0, 0, 0,
    9500001);

DELETE FROM `eventwow_game_character` WHERE `GameId` IN ('carrera', 'carrera_estelar');
INSERT INTO `eventwow_game_character` (`GameId`, `CharacterId`, `Sort`) VALUES
('carrera', 3, 0),
('carrera_estelar', 3, 0);
