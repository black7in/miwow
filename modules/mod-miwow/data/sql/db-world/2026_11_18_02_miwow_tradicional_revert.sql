-- MiWow (servidor tradicional): deshace los cambios del "contenedor" (elfo de la noche druida del servidor de
-- eventos) en una BD donde ya se aplicaron. Los SQL originales se borraron del modulo:
--   2026_11_12_00_lobby_playercreateinfo / 2026_11_13_00_lobby_playercreateinfo_druid (nacer en la Isla de los GM)
--   2026_11_16_01_miwow_druid_weapon_skills (druida con todas las armas)
--   2026_11_16_02_miwow_druid_no_relic (druida sin ranura de reliquia en ChrClasses.dbc del cliente)
-- Idempotente: deja los valores originales de AzerothCore (data/sql/base/db_world).

-- Lugar de nacimiento original: elfo de la noche druida en Teldrassil (Canada Umbria), humano guerrero en Villadorada
UPDATE `playercreateinfo`
SET `map` = 1, `zone` = 141, `position_x` = 10311.3, `position_y` = 832.463, `position_z` = 1326.41, `orientation` = 5.69632
WHERE `race` = 4 AND `class` = 11;

UPDATE `playercreateinfo`
SET `map` = 0, `zone` = 12, `position_x` = -8949.95, `position_y` = -132.493, `position_z` = 83.5312, `orientation` = 0
WHERE `race` = 1 AND `class` = 1;

-- Habilidades y competencias de armas del druida (filas solo de MiWow: la tabla base de AC esta vacia)
DELETE FROM `skillraceclassinfo_dbc` WHERE `ID` BETWEEN 9500000 AND 9500008;
DELETE FROM `playercreateinfo_skills` WHERE `raceMask` = 0 AND `classMask` = 1024 AND `comment` LIKE 'MiWow:%';
DELETE FROM `playercreateinfo_spell_custom` WHERE `racemask` = 0 AND `classmask` = 1024 AND `Note` LIKE 'MiWow:%';

-- Ranura de reliquia del druida: sin la fila, servidor y Build-Dbc usan el ChrClasses.dbc original
DELETE FROM `chrclasses_dbc` WHERE `ID` = 11;
