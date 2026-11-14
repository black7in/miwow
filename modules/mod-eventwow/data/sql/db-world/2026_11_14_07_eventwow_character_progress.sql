-- EventWow: progresion de heroes en partida (EventWowProgress, docs/heroes.md): tipo de cada habilidad de la ficha
-- y stats de cada punto de "Atributos".
-- Idempotente (MySQL 8 no tiene ADD COLUMN IF NOT EXISTS): la columna solo se anade si no existe.
SET @eventwow_sql = IF((SELECT COUNT(*) FROM `information_schema`.`COLUMNS` WHERE `TABLE_SCHEMA` = DATABASE()
    AND `TABLE_NAME` = 'eventwow_character_spell' AND `COLUMN_NAME` = 'Kind') = 0,
    'ALTER TABLE `eventwow_character_spell`
        ADD COLUMN `Kind` TINYINT UNSIGNED NOT NULL DEFAULT 0
        COMMENT ''0 = fija (siempre), 1 = basica (4 rangos: niveles 1/3/5/7), 2 = definitiva (6/12/18), 3 = suprema (nivel maximo, sin punto)'' AFTER `SpellId`',
    'DO 0');
PREPARE `eventwow_stmt` FROM @eventwow_sql;
EXECUTE `eventwow_stmt`;
DEALLOCATE PREPARE `eventwow_stmt`;

CREATE TABLE IF NOT EXISTS `eventwow_character_attribute` (
    `CharacterId` INT UNSIGNED NOT NULL,
    `Stat` VARCHAR(16) NOT NULL COMMENT 'clave de EventWowStats (str, sta, armor...)',
    `Value` INT NOT NULL DEFAULT 0 COMMENT 'por cada punto de Atributos',
    PRIMARY KEY (`CharacterId`, `Stat`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='EventWow: stats de cada punto de Atributos de un heroe';

-- Arthas, caballero de la Muerte (ficha 31): 4 basicas, definitiva, suprema. Fuera de partidas con progresion
-- (p. ej. .eventwow hero 31) el tipo no importa: se aprende todo.
UPDATE `eventwow_character_spell` SET `Kind` = 1 WHERE `CharacterId` = 31 AND `Slot` BETWEEN 0 AND 3;
UPDATE `eventwow_character_spell` SET `Kind` = 2 WHERE `CharacterId` = 31 AND `Slot` = 4;
UPDATE `eventwow_character_spell` SET `Kind` = 3 WHERE `CharacterId` = 31 AND `Slot` = 5;

-- Atributos de Arthas (PROVISIONAL): por punto
DELETE FROM `eventwow_character_attribute` WHERE `CharacterId` = 31;
INSERT INTO `eventwow_character_attribute` (`CharacterId`, `Stat`, `Value`) VALUES
(31, 'str', 10),
(31, 'sta', 15),
(31, 'armor', 100);
