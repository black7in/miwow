-- EventWow: ataque basico de los heroes (docs/heroes.md, "Ataque basico"; EventWowDisguise). Con AttackSpeed la
-- casilla 1 de la barra es el ataque y el clic derecho lo usa:
--   AutoAttackSpell 0  -> "Atacar" nativo cuerpo a cuerpo con un arma invisible AttackMin-AttackMax (+AttackPerLevel
--                         por nivel sobre el 1) cada AttackSpeed ms
--   AutoAttackSpell N  -> disparo automatico (data/spells/ataques.toml) cada AttackSpeed ms; el dano es del hechizo
-- Idempotente (MySQL 8 no tiene ADD COLUMN IF NOT EXISTS): cada columna solo se anade si no existe.
SET @eventwow_sql = IF((SELECT COUNT(*) FROM `information_schema`.`COLUMNS` WHERE `TABLE_SCHEMA` = DATABASE()
    AND `TABLE_NAME` = 'eventwow_character' AND `COLUMN_NAME` = 'AutoAttackSpell') = 0,
    'ALTER TABLE `eventwow_character` ADD COLUMN `AutoAttackSpell` INT UNSIGNED NOT NULL DEFAULT 0 COMMENT ''disparo automatico (0 = Atacar cuerpo a cuerpo)'' AFTER `PickCreature`',
    'DO 0');
PREPARE `eventwow_stmt` FROM @eventwow_sql;
EXECUTE `eventwow_stmt`;
DEALLOCATE PREPARE `eventwow_stmt`;

SET @eventwow_sql = IF((SELECT COUNT(*) FROM `information_schema`.`COLUMNS` WHERE `TABLE_SCHEMA` = DATABASE()
    AND `TABLE_NAME` = 'eventwow_character' AND `COLUMN_NAME` = 'AttackMin') = 0,
    'ALTER TABLE `eventwow_character` ADD COLUMN `AttackMin` FLOAT NOT NULL DEFAULT 0 COMMENT ''dano minimo del arma invisible a nivel 1'' AFTER `AutoAttackSpell`',
    'DO 0');
PREPARE `eventwow_stmt` FROM @eventwow_sql;
EXECUTE `eventwow_stmt`;
DEALLOCATE PREPARE `eventwow_stmt`;

SET @eventwow_sql = IF((SELECT COUNT(*) FROM `information_schema`.`COLUMNS` WHERE `TABLE_SCHEMA` = DATABASE()
    AND `TABLE_NAME` = 'eventwow_character' AND `COLUMN_NAME` = 'AttackMax') = 0,
    'ALTER TABLE `eventwow_character` ADD COLUMN `AttackMax` FLOAT NOT NULL DEFAULT 0 COMMENT ''dano maximo del arma invisible a nivel 1'' AFTER `AttackMin`',
    'DO 0');
PREPARE `eventwow_stmt` FROM @eventwow_sql;
EXECUTE `eventwow_stmt`;
DEALLOCATE PREPARE `eventwow_stmt`;

SET @eventwow_sql = IF((SELECT COUNT(*) FROM `information_schema`.`COLUMNS` WHERE `TABLE_SCHEMA` = DATABASE()
    AND `TABLE_NAME` = 'eventwow_character' AND `COLUMN_NAME` = 'AttackPerLevel') = 0,
    'ALTER TABLE `eventwow_character` ADD COLUMN `AttackPerLevel` FLOAT NOT NULL DEFAULT 0 COMMENT ''dano del arma invisible por nivel sobre el 1'' AFTER `AttackMax`',
    'DO 0');
PREPARE `eventwow_stmt` FROM @eventwow_sql;
EXECUTE `eventwow_stmt`;
DEALLOCATE PREPARE `eventwow_stmt`;

SET @eventwow_sql = IF((SELECT COUNT(*) FROM `information_schema`.`COLUMNS` WHERE `TABLE_SCHEMA` = DATABASE()
    AND `TABLE_NAME` = 'eventwow_character' AND `COLUMN_NAME` = 'AttackSpeed') = 0,
    'ALTER TABLE `eventwow_character` ADD COLUMN `AttackSpeed` INT UNSIGNED NOT NULL DEFAULT 0 COMMENT ''ms entre golpes o disparos (0 = sin ataque basico)'' AFTER `AttackPerLevel`',
    'DO 0');
PREPARE `eventwow_stmt` FROM @eventwow_sql;
EXECUTE `eventwow_stmt`;
DEALLOCATE PREPARE `eventwow_stmt`;

-- Heroes del Asedio. PROVISIONAL.
-- Cuerpo a cuerpo: Arthas (30, 31), Thrall, Varian, Tirion, Cairne, Lor'themar, Garrosh, Jokkum
UPDATE `eventwow_character` SET `AutoAttackSpell` = 0, `AttackMin` = 40, `AttackMax` = 60, `AttackPerLevel` = 8, `AttackSpeed` = 2000
    WHERE `Id` IN (30, 31, 32, 35, 36, 41, 42, 43, 44);
-- Sylvanas: disparo fisico; lanzadores: disparo magico de su escuela
UPDATE `eventwow_character` SET `AutoAttackSpell` = 9509020, `AttackMin` = 0, `AttackMax` = 0, `AttackPerLevel` = 0, `AttackSpeed` = 2000 WHERE `Id` = 33;
UPDATE `eventwow_character` SET `AutoAttackSpell` = 9509021, `AttackMin` = 0, `AttackMax` = 0, `AttackPerLevel` = 0, `AttackSpeed` = 2000 WHERE `Id` IN (34, 37);
UPDATE `eventwow_character` SET `AutoAttackSpell` = 9509022, `AttackMin` = 0, `AttackMax` = 0, `AttackPerLevel` = 0, `AttackSpeed` = 2000 WHERE `Id` = 38;
UPDATE `eventwow_character` SET `AutoAttackSpell` = 9509023, `AttackMin` = 0, `AttackMax` = 0, `AttackPerLevel` = 0, `AttackSpeed` = 2000 WHERE `Id` = 39;
UPDATE `eventwow_character` SET `AutoAttackSpell` = 9509024, `AttackMin` = 0, `AttackMax` = 0, `AttackPerLevel` = 0, `AttackSpeed` = 2000 WHERE `Id` = 40;

-- Sylvanas: su ataque usa el poder de ataque a distancia (rap) y la agilidad (que tambien lo sube)
DELETE FROM `eventwow_character_attribute` WHERE `CharacterId` = 33;
INSERT INTO `eventwow_character_attribute` (`CharacterId`, `Stat`, `Value`) VALUES
(33, 'agi', 8), (33, 'rap', 30), (33, 'sta', 10);
