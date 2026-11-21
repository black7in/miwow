-- MiWow: vehiculos propios (rango de entradas reservado 9500000-9599999).
-- Copias de vehiculos existentes SIN NOMBRE: al conducir, el cliente muestra sobre el vehiculo el nombre de la
-- criatura en vez del del jugador (no se puede cambiar por jugador), asi que no se muestra ninguno.
-- Sin script de su contenido original, sin version heroica, sin clic para montar (MiWowVehicle sube al
-- jugador) y sin traducciones (creature_template_locale): el cliente esES usa el nombre base, vacio.
--
-- 9500000: Salvaged Chopper (33062, moto de Ulduar), con sus modelos, hechizos de vehiculo y addon.

DELETE FROM `creature_template` WHERE `entry` = 9500000;
DELETE FROM `creature_template_model` WHERE `CreatureID` = 9500000;
DELETE FROM `creature_template_spell` WHERE `CreatureID` = 9500000;
DELETE FROM `creature_template_addon` WHERE `entry` = 9500000;

CREATE TEMPORARY TABLE `miwow_tmp_template` SELECT * FROM `creature_template` WHERE `entry` = 33062;
UPDATE `miwow_tmp_template` SET `entry` = 9500000, `difficulty_entry_1` = 0, `name` = '', `subname` = '', `ScriptName` = '', `AIName` = '', `npcflag` = 0;
INSERT INTO `creature_template` SELECT * FROM `miwow_tmp_template`;
DROP TEMPORARY TABLE `miwow_tmp_template`;

CREATE TEMPORARY TABLE `miwow_tmp_model` SELECT * FROM `creature_template_model` WHERE `CreatureID` = 33062;
UPDATE `miwow_tmp_model` SET `CreatureID` = 9500000;
INSERT INTO `creature_template_model` SELECT * FROM `miwow_tmp_model`;
DROP TEMPORARY TABLE `miwow_tmp_model`;

CREATE TEMPORARY TABLE `miwow_tmp_spell` SELECT * FROM `creature_template_spell` WHERE `CreatureID` = 33062;
UPDATE `miwow_tmp_spell` SET `CreatureID` = 9500000;
INSERT INTO `creature_template_spell` SELECT * FROM `miwow_tmp_spell`;
DROP TEMPORARY TABLE `miwow_tmp_spell`;

CREATE TEMPORARY TABLE `miwow_tmp_addon` SELECT * FROM `creature_template_addon` WHERE `entry` = 33062;
UPDATE `miwow_tmp_addon` SET `entry` = 9500000;
INSERT INTO `creature_template_addon` SELECT * FROM `miwow_tmp_addon`;
DROP TEMPORARY TABLE `miwow_tmp_addon`;
