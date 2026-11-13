-- EventWow: prototipo de tienda (juego test_shop).
-- Objetos propios: rango reservado 9500000-9599999 de item_template (sin Item.dbc en el cliente todavia: el icono
-- puede salir como "?"). Vendedores propios: criaturas 9500100+ (mismo rango que los vehiculos).

-- Libros de stats instantaneos: copia de la Pocion de sanacion runica (33447) sin hechizo ni nivel requerido
DELETE FROM `item_template` WHERE `entry` BETWEEN 9500000 AND 9500003;

CREATE TEMPORARY TABLE `eventwow_tmp_item` SELECT * FROM `item_template` WHERE `entry` = 33447;
UPDATE `eventwow_tmp_item` SET `subclass` = 8, `displayid` = 1143, `Quality` = 2, `BuyCount` = 1, `BuyPrice` = 500000,
    `SellPrice` = 0, `ItemLevel` = 1, `RequiredLevel` = 0, `stackable` = 1, `Material` = -1, `spellid_1` = 0,
    `spellcharges_1` = 0, `spellcategory_1` = 0, `spellcategorycooldown_1` = 0, `stat_type1` = 0,
    `stat_value1` = 0, `description` = 'Se aprende al comprarlo: dura hasta el final de la partida.';

UPDATE `eventwow_tmp_item` SET `entry` = 9500000, `name` = 'Libro de Fuerza', `stat_type1` = 4, `stat_value1` = 20;
INSERT INTO `item_template` SELECT * FROM `eventwow_tmp_item`;
UPDATE `eventwow_tmp_item` SET `entry` = 9500001, `name` = 'Libro de Intelecto', `stat_type1` = 5, `stat_value1` = 20;
INSERT INTO `item_template` SELECT * FROM `eventwow_tmp_item`;
UPDATE `eventwow_tmp_item` SET `entry` = 9500002, `name` = 'Libro de Poder con hechizos', `stat_type1` = 45, `stat_value1` = 50;
INSERT INTO `item_template` SELECT * FROM `eventwow_tmp_item`;
UPDATE `eventwow_tmp_item` SET `entry` = 9500003, `name` = 'Libro de Aguante', `stat_type1` = 7, `stat_value1` = 20;
INSERT INTO `item_template` SELECT * FROM `eventwow_tmp_item`;
DROP TEMPORARY TABLE `eventwow_tmp_item`;

-- Item.dbc: el servidor fusiona item_dbc con su Item.dbc al arrancar (no hace falta tocar sus archivos) y, con
-- DBC.EnforceItemAttributes = 1 (por defecto), corrige item_template con estos valores: se copian de item_template
-- para que nunca difieran. El cliente recibe el mismo Item.dbc en patch-4.MPQ (tools/Build-Dbc.ps1).
DELETE FROM `item_dbc` WHERE `ID` BETWEEN 9500000 AND 9500003;
INSERT INTO `item_dbc` (`ID`, `ClassID`, `SubclassID`, `Sound_Override_Subclassid`, `Material`, `DisplayInfoID`,
    `InventoryType`, `SheatheType`)
SELECT `entry`, `class`, `subclass`, `SoundOverrideSubclass`, `Material`, `displayid`, `InventoryType`, `sheath`
FROM `item_template` WHERE `entry` BETWEEN 9500000 AND 9500003;

DELETE FROM `eventwow_item` WHERE `Entry` BETWEEN 9500000 AND 9500003;
INSERT INTO `eventwow_item` (`Entry`, `Flags`) VALUES
(9500000, 1),
(9500001, 1),
(9500002, 1),
(9500003, 1);

-- 9500100: Mercader de partida, copia de Kixxle (8305) sin script; amistoso con todos (faccion 35), solo vendedor
DELETE FROM `creature_template` WHERE `entry` = 9500100;
DELETE FROM `creature_template_model` WHERE `CreatureID` = 9500100;
DELETE FROM `npc_vendor` WHERE `entry` = 9500100;

CREATE TEMPORARY TABLE `eventwow_tmp_template` SELECT * FROM `creature_template` WHERE `entry` = 8305;
UPDATE `eventwow_tmp_template` SET `entry` = 9500100, `name` = 'Mercader', `subname` = 'Tienda de partida',
    `faction` = 35, `npcflag` = 128, `gossip_menu_id` = 0, `ScriptName` = '', `AIName` = '', `minlevel` = 80, `maxlevel` = 80;
INSERT INTO `creature_template` SELECT * FROM `eventwow_tmp_template`;
DROP TEMPORARY TABLE `eventwow_tmp_template`;

CREATE TEMPORARY TABLE `eventwow_tmp_model` SELECT * FROM `creature_template_model` WHERE `CreatureID` = 8305;
UPDATE `eventwow_tmp_model` SET `CreatureID` = 9500100;
INSERT INTO `creature_template_model` SELECT * FROM `eventwow_tmp_model`;
DROP TEMPORARY TABLE `eventwow_tmp_model`;

INSERT INTO `npc_vendor` (`entry`, `slot`, `item`, `maxcount`, `incrtime`, `ExtendedCost`) VALUES
(9500100, 0, 9500000, 0, 0, 0),
(9500100, 1, 9500001, 0, 0, 0),
(9500100, 2, 9500002, 0, 0, 0),
(9500100, 3, 9500003, 0, 0, 0),
(9500100, 4, 33447, 0, 0, 0);  -- Pocion de sanacion runica: objeto normal (mochila, se usa)

-- El juego de la tienda usa al Piromano goblin
DELETE FROM `eventwow_game_character` WHERE `GameId` = 'test_shop';
INSERT INTO `eventwow_game_character` (`GameId`, `CharacterId`, `Sort`) VALUES
('test_shop', 1, 0);

-- Arreglo: los iconos de los personajes de prueba se guardaron sin barras ('\I' en MySQL es 'I')
UPDATE `eventwow_character` SET `Icon` = 'Interface\\Icons\\Spell_Fire_FlameBolt' WHERE `Id` = 1;
UPDATE `eventwow_character` SET `Icon` = 'Interface\\Icons\\Spell_Nature_Swiftness' WHERE `Id` = 2;
