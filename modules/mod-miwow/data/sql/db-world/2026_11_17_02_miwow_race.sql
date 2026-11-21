-- MiWow: carreras (juegos "carrera" en el mapa 752 y "carrera_estelar" en el 753; MiWowGameRace.cpp).
--
-- 9500001: moto de carreras = Salvaged Chopper (33062) como la 9500000 (ver _05: sin nombre, script, heroico, clic
-- ni traducciones) pero a 28 yardas/s (speed_run 4 x 7) y SIN hechizos de vehiculo (la barra queda libre para los
-- poderes de la carrera).
DELETE FROM `creature_template` WHERE `entry` = 9500001;
DELETE FROM `creature_template_model` WHERE `CreatureID` = 9500001;
DELETE FROM `creature_template_spell` WHERE `CreatureID` = 9500001;
DELETE FROM `creature_template_addon` WHERE `entry` = 9500001;

CREATE TEMPORARY TABLE `miwow_tmp_template` SELECT * FROM `creature_template` WHERE `entry` = 33062;
UPDATE `miwow_tmp_template` SET `entry` = 9500001, `difficulty_entry_1` = 0, `name` = '', `subname` = '', `ScriptName` = '',
    `AIName` = '', `npcflag` = 0, `speed_walk` = 4, `speed_run` = 4;
INSERT INTO `creature_template` SELECT * FROM `miwow_tmp_template`;
DROP TEMPORARY TABLE `miwow_tmp_template`;

CREATE TEMPORARY TABLE `miwow_tmp_model` SELECT * FROM `creature_template_model` WHERE `CreatureID` = 33062;
UPDATE `miwow_tmp_model` SET `CreatureID` = 9500001;
INSERT INTO `creature_template_model` SELECT * FROM `miwow_tmp_model`;
DROP TEMPORARY TABLE `miwow_tmp_model`;

CREATE TEMPORARY TABLE `miwow_tmp_addon` SELECT * FROM `creature_template_addon` WHERE `entry` = 33062;
UPDATE `miwow_tmp_addon` SET `entry` = 9500001;
INSERT INTO `creature_template_addon` SELECT * FROM `miwow_tmp_addon`;
DROP TEMPORARY TABLE `miwow_tmp_addon`;

