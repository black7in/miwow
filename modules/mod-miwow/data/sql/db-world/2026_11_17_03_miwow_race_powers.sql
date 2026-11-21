-- MiWow: carrera con poderes (MiWowGameRace.cpp; hechizos en data/spells/carrera.toml).
--
-- Criaturas decorativas que invoca el juego (sin nombre, no seleccionables, sin IA). Copia de "Box" (21629).
--   9500010: caja de poder (CrateCreatureBasic, display 20366)
--   9500011: mancha de aceite (Oil_Puddle_01, display 31126)
DELETE FROM `creature_template` WHERE `entry` IN (9500010, 9500011);
DELETE FROM `creature_template_model` WHERE `CreatureID` IN (9500010, 9500011);
DELETE FROM `creature_template_addon` WHERE `entry` IN (9500010, 9500011);

CREATE TEMPORARY TABLE `miwow_tmp_template` SELECT * FROM `creature_template` WHERE `entry` = 21629;
UPDATE `miwow_tmp_template` SET `entry` = 9500010, `name` = '', `subname` = '', `ScriptName` = '', `AIName` = '',
    `npcflag` = 0, `faction` = 35, `flags_extra` = 0,
    -- NON_ATTACKABLE | IMMUNE_TO_PC | IMMUNE_TO_NPC | NOT_SELECTABLE
    `unit_flags` = 0x2000302;
INSERT INTO `creature_template` SELECT * FROM `miwow_tmp_template`;
UPDATE `miwow_tmp_template` SET `entry` = 9500011;
INSERT INTO `creature_template` SELECT * FROM `miwow_tmp_template`;
DROP TEMPORARY TABLE `miwow_tmp_template`;

INSERT INTO `creature_template_model` (`CreatureID`, `Idx`, `CreatureDisplayID`, `DisplayScale`, `Probability`, `VerifiedBuild`) VALUES
(9500010, 0, 20366, 1.5, 1, 0),
(9500011, 0, 31126, 1.5, 1, 0);
