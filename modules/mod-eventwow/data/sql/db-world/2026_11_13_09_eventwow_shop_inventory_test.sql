-- EventWow: prueba del inventario de partida (EventWowInventory): un arma que no se equipa y aun asi da sus stats y
-- su pasiva ("Equipar:") mientras ocupa una de las 6 casillas.
-- 9500004: copia de Grieving Spellblade (39200: Aguante, Intelecto, hechizo de equipar) sin vinculacion, 100 oro.
DELETE FROM `item_template` WHERE `entry` = 9500004;
CREATE TEMPORARY TABLE `eventwow_tmp_item` SELECT * FROM `item_template` WHERE `entry` = 39200;
UPDATE `eventwow_tmp_item` SET `entry` = 9500004, `name` = 'Espada de prueba', `bonding` = 0, `AllowableClass` = -1,
    `AllowableRace` = -1, `RequiredLevel` = 0, `BuyPrice` = 1000000, `SellPrice` = 500000,
    `description` = 'Funciona desde el inventario: no hace falta equiparla.';
INSERT INTO `item_template` SELECT * FROM `eventwow_tmp_item`;
DROP TEMPORARY TABLE `eventwow_tmp_item`;

-- item_dbc desde item_template (ver _08)
DELETE FROM `item_dbc` WHERE `ID` = 9500004;
INSERT INTO `item_dbc` (`ID`, `ClassID`, `SubclassID`, `Sound_Override_Subclassid`, `Material`, `DisplayInfoID`,
    `InventoryType`, `SheatheType`)
SELECT `entry`, `class`, `subclass`, `SoundOverrideSubclass`, `Material`, `displayid`, `InventoryType`, `sheath`
FROM `item_template` WHERE `entry` = 9500004;

DELETE FROM `npc_vendor` WHERE `entry` = 9500100 AND `item` = 9500004;
INSERT INTO `npc_vendor` (`entry`, `slot`, `item`, `maxcount`, `incrtime`, `ExtendedCost`) VALUES
(9500100, 5, 9500004, 0, 0, 0);
