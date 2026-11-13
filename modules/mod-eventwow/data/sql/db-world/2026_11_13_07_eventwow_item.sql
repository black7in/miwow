-- EventWow: comportamiento de los objetos de tienda (EventWowShop.h). Sin fila = objeto normal.
-- Flags: 0x1 INSTANT = al comprarlo se destruye y sus stats de item_template (stat_type/stat_value, armadura)
--        se suman al jugador hasta el final de la partida (libros tipo Hero Siege).
CREATE TABLE IF NOT EXISTS `eventwow_item` (
    `Entry` INT UNSIGNED NOT NULL COMMENT 'item_template.entry',
    `Flags` INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '0x1 INSTANT',
    PRIMARY KEY (`Entry`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='EventWow: objetos de tienda';
