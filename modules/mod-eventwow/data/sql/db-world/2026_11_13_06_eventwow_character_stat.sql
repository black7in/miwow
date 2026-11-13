-- EventWow: bonificaciones de stats por personaje de minijuego (EventWowStats.h). Se aplican como las de un
-- objeto equipado: el motor calcula lo derivado con sus formulas nativas (Fuerza -> poder de ataque, etc.).
-- Stat: str, agi, sta, int, spi, health, mana, armor, ap, rap, sp, crit, haste, hit, expertise, dodge, parry,
--       block, resilience, armorpen, spellpen, mp5, hp5
CREATE TABLE IF NOT EXISTS `eventwow_character_stat` (
    `CharacterId` INT UNSIGNED NOT NULL,
    `Stat` VARCHAR(16) NOT NULL,
    `Value` INT NOT NULL DEFAULT 0,
    PRIMARY KEY (`CharacterId`, `Stat`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='EventWow: bonificaciones de stats de cada personaje de minijuego';

-- Prueba: el Piromano goblin con algo de Aguante, Intelecto y poder con hechizos
DELETE FROM `eventwow_character_stat` WHERE `CharacterId` = 1;
INSERT INTO `eventwow_character_stat` (`CharacterId`, `Stat`, `Value`) VALUES
(1, 'sta', 100),
(1, 'int', 100),
(1, 'sp', 300);
