-- EventWow: armas visibles y PNJ de eleccion en el mundo por personaje (EventWowCharacters.h).
-- Idempotente (MySQL 8 no tiene ADD COLUMN IF NOT EXISTS): solo se anaden si no existen, asi el actualizador no
-- falla si ya se aplico a mano.
SET @eventwow_sql = IF((SELECT COUNT(*) FROM `information_schema`.`COLUMNS` WHERE `TABLE_SCHEMA` = DATABASE()
    AND `TABLE_NAME` = 'eventwow_character' AND `COLUMN_NAME` = 'WeaponMainHand') = 0,
    'ALTER TABLE `eventwow_character`
        ADD COLUMN `WeaponMainHand` INT UNSIGNED NOT NULL DEFAULT 0
        COMMENT ''item_template visible en la mano derecha (solo aspecto); 0 = sin arma'' AFTER `VehicleEntry`,
        ADD COLUMN `WeaponOffHand` INT UNSIGNED NOT NULL DEFAULT 0
        COMMENT ''item_template visible en la mano izquierda (solo aspecto); 0 = sin arma'' AFTER `WeaponMainHand`,
        ADD COLUMN `PickCreature` INT UNSIGNED NOT NULL DEFAULT 0
        COMMENT ''creature_template del PNJ de eleccion en el mundo (nombre + dialogo); 0 = ninguno'' AFTER `WeaponOffHand`',
    'DO 0');
PREPARE `eventwow_stmt` FROM @eventwow_sql;
EXECUTE `eventwow_stmt`;
DEALLOCATE PREPARE `eventwow_stmt`;
