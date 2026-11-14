-- EventWow: armas visuales de heroes (se ven con .eventwow weapon / el disfraz, nunca se equipan ni se venden).
-- Rango reservado 9500200-9500299. Copias de armas de PNJ con otro tipo de envainado: los arcos de PNJ llevan
-- sheath = 0 (no se dibujan envainados), asi que con el arma guardada el heroe no se veia con el arco.
-- 9500200: arco de Sylvanas (42775) envainado tipo 1 (espalda). Elegido frente al tipo 2 (diagonal, como los
-- bastones), probado por el usuario. Va en la mano derecha: la ranura de distancia no se dibuja.
-- (9500201 = prueba del tipo 2, descartada: se borra.)
DELETE FROM `item_template` WHERE `entry` IN (9500200, 9500201);
CREATE TEMPORARY TABLE `eventwow_tmp_item` SELECT * FROM `item_template` WHERE `entry` = 42775;
UPDATE `eventwow_tmp_item` SET `entry` = 9500200, `name` = 'Arco de Sylvanas', `sheath` = 1;
INSERT INTO `item_template` SELECT * FROM `eventwow_tmp_item`;
DROP TEMPORARY TABLE `eventwow_tmp_item`;

-- item_dbc desde item_template (ver _08): el cliente lee el envainado de su Item.dbc
DELETE FROM `item_dbc` WHERE `ID` IN (9500200, 9500201);
INSERT INTO `item_dbc` (`ID`, `ClassID`, `SubclassID`, `Sound_Override_Subclassid`, `Material`, `DisplayInfoID`,
    `InventoryType`, `SheatheType`)
SELECT `entry`, `class`, `subclass`, `SoundOverrideSubclass`, `Material`, `displayid`, `InventoryType`, `sheath`
FROM `item_template` WHERE `entry` = 9500200;
