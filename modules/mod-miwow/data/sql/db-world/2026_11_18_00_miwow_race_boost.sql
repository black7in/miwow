-- MiWow: carrera, placas de aceleracion (MiWowGameRace.cpp; hechizo 9502013 en carrera.toml).
--
-- 9500012: placa de aceleracion = plataforma de teletransporte de Ulduar (UL_TeleportationPad, display 31853; ~11 x 4,5
-- yd a escala 1 segun el modelo, pero a 0,6 se veia diminuta: 1,8; la usa "[DND] Summoning Pad" 39817). La runa
-- G_RuneGroundBlue01 (27879) no se veia. Criatura decorativa
-- como las cajas (_03): copia de "Box" (21629), sin nombre, no seleccionable, sin IA. La invoca el juego.
DELETE FROM `creature_template` WHERE `entry` = 9500012;
DELETE FROM `creature_template_model` WHERE `CreatureID` = 9500012;
DELETE FROM `creature_template_addon` WHERE `entry` = 9500012;

CREATE TEMPORARY TABLE `miwow_tmp_template` SELECT * FROM `creature_template` WHERE `entry` = 21629;
UPDATE `miwow_tmp_template` SET `entry` = 9500012, `name` = '', `subname` = '', `ScriptName` = '', `AIName` = '',
    `npcflag` = 0, `faction` = 35, `flags_extra` = 0,
    -- NON_ATTACKABLE | IMMUNE_TO_PC | IMMUNE_TO_NPC | NOT_SELECTABLE
    `unit_flags` = 0x2000302;
INSERT INTO `creature_template` SELECT * FROM `miwow_tmp_template`;
DROP TEMPORARY TABLE `miwow_tmp_template`;

INSERT INTO `creature_template_model` (`CreatureID`, `Idx`, `CreatureDisplayID`, `DisplayScale`, `Probability`, `VerifiedBuild`) VALUES
(9500012, 0, 31853, 1.8, 1, 0);

