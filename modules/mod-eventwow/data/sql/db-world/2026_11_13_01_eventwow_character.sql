-- EventWow: personajes jugables de los minijuegos ("disfraces", EventWowCharacters.cpp / EventWowDisguise.cpp).
-- Solo esquema: los datos van en archivos aparte (DELETE + INSERT). Se cargan al arrancar el worldserver.
CREATE TABLE IF NOT EXISTS `eventwow_character` (
    `Id` INT UNSIGNED NOT NULL,
    `Name` VARCHAR(64) NOT NULL DEFAULT '',
    `Description` VARCHAR(255) NOT NULL DEFAULT '',
    `Icon` VARCHAR(128) NOT NULL DEFAULT '' COMMENT 'Textura del cliente (Interface\Icons\...)',
    `DisplayId` INT UNSIGNED NOT NULL DEFAULT 0 COMMENT 'CreatureDisplayInfo; 0 = modelo propio',
    `Scale` FLOAT NOT NULL DEFAULT 1,
    `Health` INT UNSIGNED NOT NULL DEFAULT 0 COMMENT 'Vida maxima fija; 0 = la del contenedor',
    `PowerType` TINYINT UNSIGNED NOT NULL DEFAULT 0 COMMENT '0 mana, 1 ira, 3 energia',
    `MaxPower` INT UNSIGNED NOT NULL DEFAULT 0 COMMENT 'Maximo fijo; 0 = el del contenedor. Ira/energia internas: 100 de ira = 1000',
    PRIMARY KEY (`Id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='EventWow: personajes de minijuego';

CREATE TABLE IF NOT EXISTS `eventwow_character_spell` (
    `CharacterId` INT UNSIGNED NOT NULL,
    `Slot` TINYINT UNSIGNED NOT NULL COMMENT 'Orden en la barra del HUD',
    `SpellId` INT UNSIGNED NOT NULL,
    PRIMARY KEY (`CharacterId`, `Slot`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='EventWow: hechizos de cada personaje de minijuego';

CREATE TABLE IF NOT EXISTS `eventwow_game_character` (
    `GameId` VARCHAR(32) NOT NULL COMMENT 'EventWowGameInfo::Id',
    `CharacterId` INT UNSIGNED NOT NULL,
    `Sort` TINYINT UNSIGNED NOT NULL DEFAULT 0 COMMENT 'Orden; el primero es el asignado por defecto',
    PRIMARY KEY (`GameId`, `CharacterId`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='EventWow: personajes que ofrece cada minijuego';
