-- MiWow: temporadas de hermandad, estado (src/guild/MiWowGuildSeason.cpp). Definiciones en la BD world
-- (db-world/2026_11_21_01_miwow_guild.sql). Tablas propias: NO se tocan `guild` ni `guild_member` del core.
-- Idempotente: el updater de AC lo reaplica si cambia.

-- Estado global (una sola fila, Id = 1; la crea el modulo al arrancar)
CREATE TABLE IF NOT EXISTS `miwow_guild_state` (
    `Id`            TINYINT UNSIGNED NOT NULL DEFAULT 1,
    `SeasonId`      INT UNSIGNED     NOT NULL DEFAULT 1,
    `StartTime`     INT UNSIGNED     NOT NULL DEFAULT 0 COMMENT 'Unix: inicio de la temporada',
    `DailyExpires`  INT UNSIGNED     NOT NULL DEFAULT 0 COMMENT 'Unix: rotacion del tablon diario',
    `WeeklyExpires` INT UNSIGNED     NOT NULL DEFAULT 0 COMMENT 'Unix: rotacion del tablon semanal',
    PRIMARY KEY (`Id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='MiWow: estado de la temporada de hermandad';

-- Progreso de cada hermandad en la temporada actual (se pone a 0 al cambiar de temporada)
CREATE TABLE IF NOT EXISTS `miwow_guild_progress` (
    `GuildId` INT UNSIGNED    NOT NULL,
    `Points`  BIGINT UNSIGNED NOT NULL DEFAULT 0 COMMENT 'Puntos de temporada',
    `Perks`   INT UNSIGNED    NOT NULL DEFAULT 0 COMMENT 'Ventajas desbloqueadas (bit = PerkId)',
    PRIMARY KEY (`GuildId`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='MiWow: puntos de temporada por hermandad';

-- Por personaje. GuildId = hermandad con la que se gano (si no coincide al hacer login, cambio de hermandad
-- estando desconectado: expulsado, disuelta...)
CREATE TABLE IF NOT EXISTS `miwow_guild_member` (
    `Guid`         INT UNSIGNED NOT NULL,
    `GuildId`      INT UNSIGNED NOT NULL DEFAULT 0,
    `Reputation`   INT UNSIGNED NOT NULL DEFAULT 0 COMMENT 'Reputacion personal (permanente)',
    `Contribution` INT UNSIGNED NOT NULL DEFAULT 0 COMMENT 'Puntos aportados esta temporada',
    `DailyPoints`  INT UNSIGNED NOT NULL DEFAULT 0 COMMENT 'Puntos aportados hoy (limite diario)',
    `DailyDay`     INT UNSIGNED NOT NULL DEFAULT 0 COMMENT 'Dia (unix / 86400) de DailyPoints',
    PRIMARY KEY (`Guid`),
    KEY `idx_guild` (`GuildId`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='MiWow: reputacion y contribucion de hermandad';

-- Misiones de grupo ya entregadas por cada hermandad mientras estan en el tablon (se borran al rotar)
CREATE TABLE IF NOT EXISTS `miwow_guild_claim` (
    `GuildId`   INT UNSIGNED NOT NULL,
    `QuestId`   INT UNSIGNED NOT NULL,
    `ClaimedBy` INT UNSIGNED NOT NULL COMMENT 'Guid del personaje que la entrego',
    `ClaimedAt` INT UNSIGNED NOT NULL COMMENT 'Unix',
    PRIMARY KEY (`GuildId`, `QuestId`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='MiWow: misiones de grupo reclamadas';

-- Misiones de hermandad que no se completaron en grupo (CanCompleteQuest): no se completan hasta abandonarlas y
-- volver a aceptarlas
CREATE TABLE IF NOT EXISTS `miwow_guild_quest_block` (
    `Guid`    INT UNSIGNED NOT NULL,
    `QuestId` INT UNSIGNED NOT NULL,
    PRIMARY KEY (`Guid`, `QuestId`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='MiWow: misiones de hermandad bloqueadas';

-- Misiones activas en el tablon
CREATE TABLE IF NOT EXISTS `miwow_guild_board` (
    `QuestId` INT UNSIGNED     NOT NULL,
    `Board`   TINYINT UNSIGNED NOT NULL COMMENT '0 diaria, 1 semanal',
    PRIMARY KEY (`QuestId`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='MiWow: tablon de hermandad activo';

-- Objetos activos del intendente en la temporada actual
CREATE TABLE IF NOT EXISTS `miwow_guild_vendor_active` (
    `ItemEntry` INT UNSIGNED NOT NULL,
    `SeasonId`  INT UNSIGNED NOT NULL,
    PRIMARY KEY (`ItemEntry`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='MiWow: objetos del intendente de hermandad';

-- Clasificacion final de cada temporada
CREATE TABLE IF NOT EXISTS `miwow_guild_history` (
    `SeasonId`  INT UNSIGNED     NOT NULL,
    `Position`  TINYINT UNSIGNED NOT NULL,
    `GuildId`   INT UNSIGNED     NOT NULL,
    `GuildName` VARCHAR(24)      NOT NULL DEFAULT '',
    `Points`    BIGINT UNSIGNED  NOT NULL DEFAULT 0,
    PRIMARY KEY (`SeasonId`, `Position`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='MiWow: clasificacion final de las temporadas';
