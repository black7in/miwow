-- EventWow (servidor tradicional): sin heroes (decision del usuario 2026-11-21: se entra a los eventos con el
-- personaje y el equipo propios). El codigo (progresion, armas, inventario de partida, tienda, juego "asedio",
-- prueba de tienda, scripts de hechizos de heroes, fase de eleccion de personaje) y sus SQL se han
-- borrado del modulo; esto quita sus datos de una BD donde ya se aplicaron.
-- Tampoco hay "disfraces" (decision del usuario 2026-11-21: cada uno va con su personaje; el vehiculo de la carrera
-- lo pone EventWowVehicle): fuera las tablas de fichas de personaje.
-- Se queda: vehiculos 9500000/9500001, criaturas de la carrera 9500010-9500012, hechizos de la carrera (9502xxx) y
-- del parkour (9503xxx).
-- Idempotente.

DROP TABLE IF EXISTS `eventwow_game_character`;
DROP TABLE IF EXISTS `eventwow_character_spell`;
DROP TABLE IF EXISTS `eventwow_character_stat`;
DROP TABLE IF EXISTS `eventwow_character`;

-- Objetos: libros y espada de la tienda (9500000-9500004) y armas de heroes (9500200-9500299)
DELETE FROM `npc_vendor` WHERE `entry` = 9500100;
DELETE FROM `item_template` WHERE `entry` BETWEEN 9500000 AND 9500299;
DELETE FROM `item_dbc` WHERE `ID` BETWEEN 9500000 AND 9500299;

-- Criaturas: mercader (9500100), PNJ de eleccion (9500300-9500317) e invocaciones de heroes (9500400-9500499)
DELETE FROM `npc_text` WHERE `ID` BETWEEN 9500300 AND 9500399;
DELETE FROM `creature_template_addon` WHERE `entry` = 9500100 OR `entry` BETWEEN 9500300 AND 9500499;
DELETE FROM `creature_template_spell` WHERE `CreatureID` = 9500100 OR `CreatureID` BETWEEN 9500300 AND 9500499;
DELETE FROM `creature_template_model` WHERE `CreatureID` = 9500100 OR `CreatureID` BETWEEN 9500300 AND 9500499;
DELETE FROM `creature_template` WHERE `entry` = 9500100 OR `entry` BETWEEN 9500300 AND 9500499;

-- Hechizos propios de heroes: todo 9500000-9509999 salvo la carrera (9502xxx) y el parkour (9503xxx)
DELETE FROM `spell_script_names` WHERE `spell_id` BETWEEN 9500000 AND 9509999
    AND `spell_id` NOT BETWEEN 9502000 AND 9503999;
DELETE FROM `spell_bonus_data` WHERE `entry` BETWEEN 9500000 AND 9509999
    AND `entry` NOT BETWEEN 9502000 AND 9503999;
DELETE FROM `spell_ranks` WHERE `first_spell_id` BETWEEN 9500000 AND 9509999
    AND `first_spell_id` NOT BETWEEN 9502000 AND 9503999;
DELETE FROM `spell_dbc` WHERE `ID` BETWEEN 9500000 AND 9509999
    AND `ID` NOT BETWEEN 9502000 AND 9503999;

-- Tablas que ya no lee nadie (tienda, atributos de la progresion)
DROP TABLE IF EXISTS `eventwow_item`;
DROP TABLE IF EXISTS `eventwow_character_attribute`;
