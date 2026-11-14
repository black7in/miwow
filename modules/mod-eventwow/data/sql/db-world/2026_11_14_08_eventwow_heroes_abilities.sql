-- EventWow: habilidades de los 14 heroes restantes del Asedio (docs/heroes-habilidades.md; hechizos generados por
-- tools/spellgen desde data/spells/<heroe>.toml) + criaturas propias de sus invocaciones + atributos por papel.
-- Orden de casillas: 4 basicas (Kind 1), definitiva (2), suprema (3). Numeros PROVISIONALES.

-- Criaturas de invocacion propias (rango 9500400-9500499): copias sin la IA/script del original.
--   9500400 Serpiente vudu (Vol'jin): Venomous Snake 19833 sin npc_pet_hunter_snake_trap (calcula su vida con
--           el nivel 40 como base: a nivel bajo saldria mal).
--   9500401 Fenix (Lor'themar): Phoenix 21362 de Kael'thas sin su SmartAI de jefe (renacer, quemarse a si mismo),
--           no elite, con el aura de inmolacion del infernal (19483) para quemar a los enemigos cercanos.
DELETE FROM `creature_template` WHERE `entry` IN (9500400, 9500401);
DELETE FROM `creature_template_model` WHERE `CreatureID` IN (9500400, 9500401);
DELETE FROM `creature_template_addon` WHERE `entry` IN (9500400, 9500401);

CREATE TEMPORARY TABLE `eventwow_tmp_template` SELECT * FROM `creature_template` WHERE `entry` IN (19833, 21362);
UPDATE `eventwow_tmp_template` SET `entry` = 9500400, `name` = 'Serpiente vudú' WHERE `entry` = 19833;
UPDATE `eventwow_tmp_template` SET `entry` = 9500401, `name` = 'Fénix', `rank` = 0 WHERE `entry` = 21362;
UPDATE `eventwow_tmp_template` SET `subname` = '', `ScriptName` = '', `AIName` = '', `gossip_menu_id` = 0, `npcflag` = 0;
INSERT INTO `creature_template` SELECT * FROM `eventwow_tmp_template`;
DROP TEMPORARY TABLE `eventwow_tmp_template`;

INSERT INTO `creature_template_model` (`CreatureID`, `Idx`, `CreatureDisplayID`, `DisplayScale`, `Probability`, `VerifiedBuild`) VALUES
(9500400, 0, 1206, 1, 1, 0),
(9500401, 0, 17765, 1, 1, 0);

INSERT INTO `creature_template_addon` (`entry`, `path_id`, `mount`, `bytes1`, `bytes2`, `emote`, `visibilityDistanceType`, `auras`) VALUES
(9500401, 0, 0, 0, 1, 0, 0, '19483');

-- Habilidades de cada ficha
DELETE FROM `eventwow_character_spell` WHERE `CharacterId` IN (30, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44);
INSERT INTO `eventwow_character_spell` (`CharacterId`, `Slot`, `SpellId`, `Kind`) VALUES
-- Arthas, principe (arthas_principe.toml)
(30, 0, 9500200, 1), (30, 1, 9500204, 1), (30, 2, 9500208, 1), (30, 3, 9500212, 1), (30, 4, 9500216, 2), (30, 5, 9500219, 3),
-- Thrall (thrall.toml)
(32, 0, 9500300, 1), (32, 1, 9500304, 1), (32, 2, 9500308, 1), (32, 3, 9500312, 1), (32, 4, 9500316, 2), (32, 5, 9500319, 3),
-- Sylvanas (sylvanas.toml)
(33, 0, 9500400, 1), (33, 1, 9500404, 1), (33, 2, 9500408, 1), (33, 3, 9500412, 1), (33, 4, 9500416, 2), (33, 5, 9500422, 3),
-- Jaina (jaina.toml)
(34, 0, 9500500, 1), (34, 1, 9500504, 1), (34, 2, 9500512, 1), (34, 3, 9500516, 1), (34, 4, 9500520, 2), (34, 5, 9500523, 3),
-- Varian (varian.toml)
(35, 0, 9500600, 1), (35, 1, 9500604, 1), (35, 2, 9500608, 1), (35, 3, 9500612, 1), (35, 4, 9500616, 2), (35, 5, 9500619, 3),
-- Tirion (tirion.toml)
(36, 0, 9500700, 1), (36, 1, 9500704, 1), (36, 2, 9500708, 1), (36, 3, 9500712, 1), (36, 4, 9500716, 2), (36, 5, 9500719, 3),
-- Kel'Thuzad (kelthuzad.toml)
(37, 0, 9500800, 1), (37, 1, 9500804, 1), (37, 2, 9500808, 1), (37, 3, 9500812, 1), (37, 4, 9500816, 2), (37, 5, 9500819, 3),
-- Gul'dan (guldan.toml)
(38, 0, 9500900, 1), (38, 1, 9500904, 1), (38, 2, 9500908, 1), (38, 3, 9500916, 1), (38, 4, 9500920, 2), (38, 5, 9500923, 3),
-- Archimonde (archimonde.toml)
(39, 0, 9501000, 1), (39, 1, 9501004, 1), (39, 2, 9501008, 1), (39, 3, 9501012, 1), (39, 4, 9501020, 2), (39, 5, 9501023, 3),
-- Vol'jin (voljin.toml)
(40, 0, 9501100, 1), (40, 1, 9501104, 1), (40, 2, 9501108, 1), (40, 3, 9501112, 1), (40, 4, 9501116, 2), (40, 5, 9501119, 3),
-- Cairne (cairne.toml)
(41, 0, 9501200, 1), (41, 1, 9501204, 1), (41, 2, 9501208, 1), (41, 3, 9501212, 1), (41, 4, 9501216, 2), (41, 5, 9501219, 3),
-- Lor'themar (lorthemar.toml)
(42, 0, 9501300, 1), (42, 1, 9501304, 1), (42, 2, 9501308, 1), (42, 3, 9501312, 1), (42, 4, 9501320, 2), (42, 5, 9501323, 3),
-- Garrosh (garrosh.toml)
(43, 0, 9501400, 1), (43, 1, 9501404, 1), (43, 2, 9501408, 1), (43, 3, 9501412, 1), (43, 4, 9501420, 2), (43, 5, 9501423, 3),
-- Rey Jokkum (jokkum.toml)
(44, 0, 9501500, 1), (44, 1, 9501504, 1), (44, 2, 9501508, 1), (44, 3, 9501512, 1), (44, 4, 9501516, 2), (44, 5, 9501522, 3);

-- Atributos (por punto) segun el papel. PROVISIONAL.
--   tanque: aguante + armadura   cuerpo a cuerpo: fuerza + aguante   lanzador: intelecto + poder con hechizos
--   distancia: poder de ataque + aguante   apoyo: intelecto + poder con hechizos + aguante
DELETE FROM `eventwow_character_attribute` WHERE `CharacterId` IN (30, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44);
INSERT INTO `eventwow_character_attribute` (`CharacterId`, `Stat`, `Value`) VALUES
(30, 'sta', 18), (30, 'armor', 120), (30, 'sp', 10),
(32, 'int', 10), (32, 'sp', 20), (32, 'sta', 10),
(33, 'ap', 30), (33, 'sta', 10), (33, 'agi', 5),
(34, 'int', 12), (34, 'sp', 22), (34, 'sta', 8),
(35, 'str', 15), (35, 'sta', 12),
(36, 'sta', 20), (36, 'armor', 150),
(37, 'int', 12), (37, 'sp', 22), (37, 'sta', 8),
(38, 'int', 12), (38, 'sp', 22), (38, 'sta', 8),
(39, 'int', 10), (39, 'sp', 20), (39, 'sta', 12),
(40, 'int', 10), (40, 'sp', 15), (40, 'sta', 12),
(41, 'sta', 20), (41, 'armor', 150),
(42, 'ap', 25), (42, 'str', 8), (42, 'sta', 10),
(43, 'str', 15), (43, 'sta', 12),
(44, 'sta', 22), (44, 'armor', 140);
