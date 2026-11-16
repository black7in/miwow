-- EventWow: armas de los heroes EQUIPADAS de verdad durante el disfraz (EventWowWeapons::Equip, docs/heroes.md
-- "Ataque basico"). Antes solo eran visibles: un disparo automatico sin arma de distancia equipada no se animaba
-- (el cliente elige la animacion segun el arma de la ranura de distancia).
--
-- Armas propias 9500200-9500299: copias del aspecto de las armas de PNJ de cada heroe (docs/heroes-modelos.md),
-- equipables por cualquiera (las equipa el servidor), sin stats, sin durabilidad, nivel 0, ligadas, sin precio.
-- Dano y velocidad normales de su tipo (provisional, poco importa: el dano cuerpo a cuerpo es el de la ficha,
-- escalado a la velocidad del arma, y el de los disparos el del hechizo).
-- (9500201-9500209 libres: 9500201 lo borra _03.)

-- 1) Ficha: arma de distancia (idempotente: solo si no existe)
SET @eventwow_sql = IF((SELECT COUNT(*) FROM `information_schema`.`COLUMNS` WHERE `TABLE_SCHEMA` = DATABASE()
    AND `TABLE_NAME` = 'eventwow_character' AND `COLUMN_NAME` = 'WeaponRanged') = 0,
    'ALTER TABLE `eventwow_character` ADD COLUMN `WeaponRanged` INT UNSIGNED NOT NULL DEFAULT 0 COMMENT ''arma de distancia equipada (item_template)'' AFTER `WeaponOffHand`',
    'DO 0');
PREPARE `eventwow_stmt` FROM @eventwow_sql;
EXECUTE `eventwow_stmt`;
DEALLOCATE PREPARE `eventwow_stmt`;

-- 2) Armas
DELETE FROM `item_template` WHERE `entry` = 9500200 OR `entry` BETWEEN 9500210 AND 9500222;
CREATE TEMPORARY TABLE `eventwow_tmp_item` SELECT * FROM `item_template`
    WHERE `entry` IN (42775, 37579, 36942, 12183, 2177, 45899, 13262, 23450, 53835, 14084, 14882, 24038, 23428, 40770);

UPDATE `eventwow_tmp_item` SET `entry` = 9500200, `name` = 'Arco de Sylvanas', `sheath` = 1 WHERE `entry` = 42775; -- envainado en la espalda (probado, ver _03)
UPDATE `eventwow_tmp_item` SET `entry` = 9500210, `name` = 'Martillo de Arthas', `subclass` = 5, `InventoryType` = 17 WHERE `entry` = 37579; -- el de PNJ es de una mano: a dos manos
UPDATE `eventwow_tmp_item` SET `entry` = 9500211, `name` = 'Agonía de Escarcha' WHERE `entry` = 36942;
UPDATE `eventwow_tmp_item` SET `entry` = 9500212, `name` = 'Martillo Maldito' WHERE `entry` = 12183;
UPDATE `eventwow_tmp_item` SET `entry` = 9500213, `name` = 'Bastón de Jaina' WHERE `entry` = 2177;
UPDATE `eventwow_tmp_item` SET `entry` = 9500214, `name` = 'Espada de Varian' WHERE `entry` = 45899;
UPDATE `eventwow_tmp_item` SET `entry` = 9500215, `name` = 'La Crematoria' WHERE `entry` = 13262;
UPDATE `eventwow_tmp_item` SET `entry` = 9500216, `name` = 'Daga de Gul''dan' WHERE `entry` = 23450;
UPDATE `eventwow_tmp_item` SET `entry` = 9500217, `name` = 'Espada de Vol''jin' WHERE `entry` = 53835;
UPDATE `eventwow_tmp_item` SET `entry` = 9500218, `name` = 'Tótem de Cairne' WHERE `entry` = 14084;
UPDATE `eventwow_tmp_item` SET `entry` = 9500219, `name` = 'Guja de Lor''themar' WHERE `entry` = 14882;
UPDATE `eventwow_tmp_item` SET `entry` = 9500220, `name` = 'Escudo de Lor''themar' WHERE `entry` = 24038;
UPDATE `eventwow_tmp_item` SET `entry` = 9500221, `name` = 'Hacha de Garrosh' WHERE `entry` = 23428;
UPDATE `eventwow_tmp_item` SET `entry` = 9500222, `name` = 'Maza de Jokkum' WHERE `entry` = 40770;

-- Comun: sin stats, hechizos, durabilidad, requisitos ni precio
UPDATE `eventwow_tmp_item` SET `Quality` = 1, `Flags` = 0, `FlagsExtra` = 0, `BuyCount` = 1, `BuyPrice` = 0, `SellPrice` = 0,
    `AllowableClass` = -1, `AllowableRace` = -1, `ItemLevel` = 1, `RequiredLevel` = 0, `RequiredSkill` = 0,
    `RequiredSkillRank` = 0, `requiredspell` = 0, `requiredhonorrank` = 0, `RequiredCityRank` = 0,
    `RequiredReputationFaction` = 0, `RequiredReputationRank` = 0, `maxcount` = 0, `stackable` = 1, `ContainerSlots` = 0,
    `stat_type1` = 0, `stat_value1` = 0, `stat_type2` = 0, `stat_value2` = 0, `stat_type3` = 0, `stat_value3` = 0,
    `stat_type4` = 0, `stat_value4` = 0, `stat_type5` = 0, `stat_value5` = 0, `stat_type6` = 0, `stat_value6` = 0,
    `stat_type7` = 0, `stat_value7` = 0, `stat_type8` = 0, `stat_value8` = 0, `stat_type9` = 0, `stat_value9` = 0,
    `stat_type10` = 0, `stat_value10` = 0, `ScalingStatDistribution` = 0, `ScalingStatValue` = 0,
    `dmg_min1` = 0, `dmg_max1` = 0, `dmg_type1` = 0, `dmg_min2` = 0, `dmg_max2` = 0, `dmg_type2` = 0, `armor` = 0,
    `holy_res` = 0, `fire_res` = 0, `nature_res` = 0, `frost_res` = 0, `shadow_res` = 0, `arcane_res` = 0,
    `ammo_type` = 0, `RangedModRange` = 0,
    `spellid_1` = 0, `spelltrigger_1` = 0, `spellid_2` = 0, `spelltrigger_2` = 0, `spellid_3` = 0, `spelltrigger_3` = 0,
    `spellid_4` = 0, `spelltrigger_4` = 0, `spellid_5` = 0, `spelltrigger_5` = 0,
    `bonding` = 1, `description` = '', `startquest` = 0, `lockid` = 0, `RandomProperty` = 0, `RandomSuffix` = 0,
    `block` = 0, `itemset` = 0, `MaxDurability` = 0, `area` = 0, `Map` = 0, `BagFamily` = 0,
    `socketColor_1` = 0, `socketColor_2` = 0, `socketColor_3` = 0, `socketBonus` = 0, `GemProperties` = 0,
    `RequiredDisenchantSkill` = -1, `DisenchantID` = 0, `ArmorDamageModifier` = 0, `duration` = 0,
    `ItemLimitCategory` = 0, `HolidayId` = 0, `ScriptName` = '', `flagsCustom` = 0;

-- Dano y velocidad normales de su tipo (ms)
UPDATE `eventwow_tmp_item` SET `dmg_min1` = 6, `dmg_max1` = 10, `delay` = 2600
    WHERE `class` = 2 AND `subclass` IN (0, 4, 7);         -- hacha, maza, espada de una mano
UPDATE `eventwow_tmp_item` SET `dmg_min1` = 4, `dmg_max1` = 7, `delay` = 1800
    WHERE `class` = 2 AND `subclass` = 15;                 -- daga
UPDATE `eventwow_tmp_item` SET `dmg_min1` = 11, `dmg_max1` = 18, `delay` = 3600
    WHERE `class` = 2 AND `subclass` IN (1, 5, 8);         -- hacha, maza, espada de dos manos
UPDATE `eventwow_tmp_item` SET `dmg_min1` = 10, `dmg_max1` = 16, `delay` = 3300
    WHERE `class` = 2 AND `subclass` = 10;                 -- baston
-- RangedModRange: % del alcance de los hechizos de la ranura de distancia, lo calcula el CLIENTE (el de PNJ lleva 0:
-- "fuera de rango" a cualquier distancia). 100 = como un arco de jugador.
UPDATE `eventwow_tmp_item` SET `dmg_min1` = 6, `dmg_max1` = 11, `delay` = 2800, `RangedModRange` = 100
    WHERE `class` = 2 AND `subclass` IN (2, 3, 16, 18);    -- arco, escopeta, arrojadiza, ballesta
UPDATE `eventwow_tmp_item` SET `delay` = 0
    WHERE `class` = 4;                                     -- escudo

INSERT INTO `item_template` SELECT * FROM `eventwow_tmp_item`;
DROP TEMPORARY TABLE `eventwow_tmp_item`;

-- item_dbc desde item_template (ver _08): el cliente dibuja las armas con su Item.dbc (tools/Build-Dbc.ps1)
DELETE FROM `item_dbc` WHERE `ID` = 9500200 OR `ID` BETWEEN 9500210 AND 9500222;
INSERT INTO `item_dbc` (`ID`, `ClassID`, `SubclassID`, `Sound_Override_Subclassid`, `Material`, `DisplayInfoID`,
    `InventoryType`, `SheatheType`)
SELECT `entry`, `class`, `subclass`, `SoundOverrideSubclass`, `Material`, `displayid`, `InventoryType`, `sheath`
FROM `item_template` WHERE `entry` = 9500200 OR `entry` BETWEEN 9500210 AND 9500222;

-- 3) Fichas del Asedio: armas propias (Kel'Thuzad y Archimonde sin arma)
UPDATE `eventwow_character` SET `WeaponMainHand` = 9500210, `WeaponOffHand` = 0, `WeaponRanged` = 0 WHERE `Id` = 30;
UPDATE `eventwow_character` SET `WeaponMainHand` = 9500211, `WeaponOffHand` = 0, `WeaponRanged` = 0 WHERE `Id` = 31;
UPDATE `eventwow_character` SET `WeaponMainHand` = 9500212, `WeaponOffHand` = 0, `WeaponRanged` = 0 WHERE `Id` = 32;
UPDATE `eventwow_character` SET `WeaponMainHand` = 0, `WeaponOffHand` = 0, `WeaponRanged` = 9500200 WHERE `Id` = 33;
UPDATE `eventwow_character` SET `WeaponMainHand` = 9500213, `WeaponOffHand` = 0, `WeaponRanged` = 0 WHERE `Id` = 34;
UPDATE `eventwow_character` SET `WeaponMainHand` = 9500214, `WeaponOffHand` = 0, `WeaponRanged` = 0 WHERE `Id` = 35;
UPDATE `eventwow_character` SET `WeaponMainHand` = 9500215, `WeaponOffHand` = 0, `WeaponRanged` = 0 WHERE `Id` = 36;
UPDATE `eventwow_character` SET `WeaponMainHand` = 9500216, `WeaponOffHand` = 0, `WeaponRanged` = 0 WHERE `Id` = 38;
UPDATE `eventwow_character` SET `WeaponMainHand` = 9500217, `WeaponOffHand` = 0, `WeaponRanged` = 0 WHERE `Id` = 40;
UPDATE `eventwow_character` SET `WeaponMainHand` = 9500218, `WeaponOffHand` = 0, `WeaponRanged` = 0 WHERE `Id` = 41;
UPDATE `eventwow_character` SET `WeaponMainHand` = 9500219, `WeaponOffHand` = 9500220, `WeaponRanged` = 0 WHERE `Id` = 42;
UPDATE `eventwow_character` SET `WeaponMainHand` = 9500221, `WeaponOffHand` = 9500221, `WeaponRanged` = 0 WHERE `Id` = 43;
UPDATE `eventwow_character` SET `WeaponMainHand` = 9500222, `WeaponOffHand` = 0, `WeaponRanged` = 0 WHERE `Id` = 44;
