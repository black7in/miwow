-- EventWow: heroes del Asedio (lista inicial elegida por el usuario, docs/heroes-modelos.md) y eleccion en el mundo
-- estilo Warcraft 3 (EventWowMatch::GetPickPositions): esperan en circulo en la region Inicio y se eligen hablando
-- con ellos (npc_eventwow_pick). SIN HABILIDADES todavia (docs/heroes.md); vida/mana provisionales.
-- Ids de ficha 30-44. PNJ de eleccion: rango reservado 9500300-9500399 (npc_text con el mismo ID = descripcion).
DELETE FROM `eventwow_character` WHERE `Id` BETWEEN 30 AND 44;
INSERT INTO `eventwow_character` (`Id`, `Name`, `Description`, `Icon`, `DisplayId`, `Scale`, `Health`, `PowerType`,
    `MaxPower`, `VehicleEntry`, `WeaponMainHand`, `WeaponOffHand`, `PickCreature`) VALUES
(30, 'Arthas', 'El príncipe de Lordaeron, paladín de la Mano de Plata.', 'Interface\\Icons\\Spell_Holy_SealOfMight', 24949, 1.0, 6000, 0, 5000, 0, 37579, 0, 9500300),
(31, 'Arthas, caballero de la Muerte', 'Empuña Agonía de Escarcha. Su camino lleva al Trono Helado.', 'Interface\\Icons\\achievement_boss_lichking', 22235, 1.0, 6000, 0, 5000, 0, 36942, 0, 9500301),
(32, 'Thrall', 'Jefe de Guerra de la Horda, chamán de los elementos.', 'Interface\\Icons\\Achievement_Leader_ Thrall', 4527, 1.0, 6000, 0, 5000, 0, 12183, 0, 9500302),
(33, 'Sylvanas Brisaveloz', 'La Reina Alma en Pena: arquera letal de los Renegados.', 'Interface\\Icons\\Achievement_Leader_Sylvanas', 28213, 1.0, 6000, 0, 5000, 0, 9500200, 0, 9500303),
(34, 'Jaina Valiente', 'Archimaga del Kirin Tor, maestra de la escarcha y lo arcano.', 'Interface\\Icons\\Spell_Frost_FrostBolt02', 30863, 1.0, 6000, 0, 5000, 0, 2177, 0, 9500304),
(35, 'Varian Wrynn', 'Rey de Ventormenta, guerrero sin igual.', 'Interface\\Icons\\Achievement_Leader_King_Varian_Wrynn', 28127, 1.0, 6000, 0, 5000, 0, 45899, 0, 9500305),
(36, 'Tirion Vadin', 'Alto Señor de la Cruzada Argenta, portador de la Crematoria.', 'Interface\\Icons\\INV_Sword_2H_AshbringerCorrupt', 22209, 1.0, 6000, 0, 5000, 0, 13262, 0, 9500306),
(37, 'Kel''Thuzad', 'Liche y archinigromante de la Plaga.', 'Interface\\Icons\\achievement_boss_kelthuzad_01', 15945, 0.24, 6000, 0, 5000, 0, 0, 0, 9500307),
(38, 'Gul''dan', 'El primer brujo orco, maestro de la magia vil.', 'Interface\\Icons\\Ability_Warlock_DemonicPower', 16642, 1.0, 6000, 0, 5000, 0, 23450, 0, 9500308),
(39, 'Archimonde', 'El Profanador, señor de la Legión Ardiente.', 'Interface\\Icons\\Achievement_Boss_Archimonde ', 20939, 0.08, 6000, 0, 5000, 0, 0, 0, 9500309),
(40, 'Vol''jin', 'Líder de los trols Lanza Negra, maestro del vudú.', 'Interface\\Icons\\Spell_Shadow_ShadowWordPain', 10357, 1.0, 6000, 0, 5000, 0, 53835, 0, 9500310),
(41, 'Cairne Pezuña de Sangre', 'Gran jefe de los tauren, sabio y fuerte como la tierra.', 'Interface\\Icons\\Achievement_Leader_Cairne Bloodhoof', 4307, 1.0, 6000, 0, 5000, 0, 14084, 0, 9500311),
(42, 'Lor''themar Theron', 'Regente de Quel''Thalas, explorador de los elfos de sangre.', 'Interface\\Icons\\Achievement_Leader_Lorthemar_Theron ', 17122, 1.0, 6000, 0, 5000, 0, 14882, 24038, 9500312),
(43, 'Garrosh Grito Infernal', 'Hijo de Grom, señor de la guerra de la Horda en Rasganorte.', 'Interface\\Icons\\Ability_Warrior_Rampage', 23006, 1.0, 6000, 0, 5000, 0, 23428, 23428, 9500313),
(44, 'Rey Jokkum', 'Rey de los gigantes de escarcha de las Cumbres Tormentosas.', 'Interface\\Icons\\Spell_Frost_FrostShock', 26778, 0.4, 6000, 0, 5000, 0, 40770, 0, 9500314);

-- Probadores de hechizos (SQL _14_01/_14_02) tambien elegibles en el mundo. Arregla sus iconos: en MySQL '\I' pierde
-- la barra (escribir '\\').
UPDATE `eventwow_character` SET `PickCreature` = 9500315, `Icon` = 'Interface\\Icons\\Spell_Holy_SealOfMight' WHERE `Id` = 19;
UPDATE `eventwow_character` SET `PickCreature` = 9500316, `Icon` = 'Interface\\Icons\\Spell_Fire_FlameBolt' WHERE `Id` = 20;
UPDATE `eventwow_character` SET `PickCreature` = 9500317, `Icon` = 'Interface\\Icons\\Spell_Holy_Renew' WHERE `Id` = 21;

-- Asedio: los 15 heroes + los 3 probadores (los 4 provisionales 10-13 salen del juego; sus fichas se quedan)
DELETE FROM `eventwow_game_character` WHERE `GameId` = 'asedio';
INSERT INTO `eventwow_game_character` (`GameId`, `CharacterId`, `Sort`) VALUES
('asedio', 30, 0), ('asedio', 31, 1), ('asedio', 32, 2), ('asedio', 33, 3), ('asedio', 34, 4), ('asedio', 35, 5),
('asedio', 36, 6), ('asedio', 37, 7), ('asedio', 38, 8), ('asedio', 39, 9), ('asedio', 40, 10), ('asedio', 41, 11),
('asedio', 42, 12), ('asedio', 43, 13), ('asedio', 44, 14), ('asedio', 19, 20), ('asedio', 20, 21), ('asedio', 21, 22);

-- PNJ de eleccion, generados desde las fichas (nombre = el del personaje): copia del Mercader (9500100, faccion 35)
-- solo con dialogo. Modelo, escala y armas los pone el servidor al invocarlo (de la ficha); el modelo de aqui es
-- solo el que exige creature_template_model.
DELETE FROM `creature_template` WHERE `entry` BETWEEN 9500300 AND 9500399;
DELETE FROM `creature_template_model` WHERE `CreatureID` BETWEEN 9500300 AND 9500399;
DELETE FROM `npc_text` WHERE `ID` BETWEEN 9500300 AND 9500399;

CREATE TEMPORARY TABLE `eventwow_tmp_template`
SELECT c.`Id` AS `eventwow_character_id`, t.* FROM `creature_template` t
JOIN `eventwow_character` c ON c.`PickCreature` BETWEEN 9500300 AND 9500399
WHERE t.`entry` = 9500100;
UPDATE `eventwow_tmp_template` t JOIN `eventwow_character` c ON c.`Id` = t.`eventwow_character_id`
SET t.`entry` = c.`PickCreature`, t.`name` = c.`Name`, t.`subname` = '', t.`npcflag` = 1, t.`gossip_menu_id` = 0,
    t.`ScriptName` = 'npc_eventwow_pick', t.`AIName` = '';
ALTER TABLE `eventwow_tmp_template` DROP COLUMN `eventwow_character_id`;
INSERT INTO `creature_template` SELECT * FROM `eventwow_tmp_template`;
DROP TEMPORARY TABLE `eventwow_tmp_template`;

INSERT INTO `creature_template_model` (`CreatureID`, `Idx`, `CreatureDisplayID`, `DisplayScale`, `Probability`, `VerifiedBuild`)
SELECT `PickCreature`, 0, `DisplayId`, 1, 1, 0 FROM `eventwow_character` WHERE `PickCreature` BETWEEN 9500300 AND 9500399;

INSERT INTO `npc_text` (`ID`, `text0_0`, `text0_1`, `Probability0`)
SELECT `PickCreature`, `Description`, `Description`, 1 FROM `eventwow_character` WHERE `PickCreature` BETWEEN 9500300 AND 9500399;
