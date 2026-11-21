-- MiWow: temporadas de hermandad, definiciones (src/guild/MiWowGuildSeason.cpp). El estado va en la BD characters
-- (db-characters/2026_11_21_00_miwow_guild.sql). Tablas propias: NO se toca `quest_template_addon` ni otra tabla
-- del core (salvo filas nuevas de objetos/PNJ/misiones en nuestro rango 9500000-9599999 y la categoria 400 de
-- QuestSort).
-- Se cargan al arrancar el servidor. Idempotente: el updater de AC lo reaplica si cambia.

-- Misiones de hermandad. Una mision del core (quest_template) pasa a serlo con una fila aqui; con QuestSortID = -400
-- sale en la categoria "Hermandad" del registro de misiones (QuestSort 400, abajo). Las que estan en el tablon las
-- ofrece el tablon (objeto MiWow.Guild.BoardObject) y se entregan en el.
--   Puntos: individual = en cada entrega (pocos); de grupo = solo la primera entrega de la hermandad mientras sigue
--   en el tablon (mas). La reputacion personal, siempre, a cada uno.
--   Bandas: para que los objetivos avancen en banda, QuestInfoID 62/88/89 en quest_template (nativo).
--   Board: 0 diaria, 1 semanal (de que tablon sale; que se repita cada dia/semana lo deciden las Flags de la mision)
--   Toda mision de hermandad necesita hermandad para COMPLETARSE (objetivos cumplidos; no confundir con entregarla).
--   RequiredMembers: 0 = individual (los puntos cuentan siempre); N = al completarse (p. ej. al morir el jefe) hay que
--     ir en grupo con N miembros de la hermandad (contando al personaje) en el mismo mapa; si no, no se completa y hay
--     que abandonarla y repetirla. Los puntos solo cuentan la primera vez que la entrega la hermandad mientras sigue
--     en el tablon (las demas entregas, solo reputacion)
CREATE TABLE IF NOT EXISTS `miwow_guild_quest` (
    `QuestId`         INT UNSIGNED     NOT NULL,
    `Board`           TINYINT UNSIGNED NOT NULL DEFAULT 0 COMMENT '0 diaria, 1 semanal',
    `Points`          INT UNSIGNED     NOT NULL DEFAULT 0 COMMENT 'Puntos de temporada para la hermandad',
    `Reputation`      INT UNSIGNED     NOT NULL DEFAULT 0 COMMENT 'Reputacion personal para quien la entrega',
    `RequiredMembers` TINYINT UNSIGNED NOT NULL DEFAULT 0 COMMENT '0 individual, N miembros en el grupo',
    `Enabled`         TINYINT UNSIGNED NOT NULL DEFAULT 1,
    PRIMARY KEY (`QuestId`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='MiWow: misiones de hermandad';

-- Ventajas: al llegar la hermandad a Points en la temporada, todos sus miembros aprenden el hechizo PASIVO SpellId
-- (libro de hechizos, como un racial; valen en todas partes). PerkId 0-31.
-- Hechizos: data/spells/hermandad.toml (9504000-9504099). Effect: las del mismo Effect son rangos (solo se lleva la
-- de mas puntos). mount/xp/reputation/honor = lo hace el aura; gold/hearth/repair/vendor/resurrect/mail/profession =
-- lo hace el modulo con el valor del efecto 1 del hechizo (el mismo numero que sale en el tooltip).
-- Solo definiciones: se recrea (la primera version no tenia Effect).
DROP TABLE IF EXISTS `miwow_guild_perk`;
CREATE TABLE `miwow_guild_perk` (
    `PerkId`  TINYINT UNSIGNED NOT NULL,
    `Points`  INT UNSIGNED     NOT NULL,
    `SpellId` INT UNSIGNED     NOT NULL,
    `Effect`  VARCHAR(16)      NOT NULL DEFAULT '' COMMENT 'Grupo de rangos / efecto del modulo',
    PRIMARY KEY (`PerkId`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='MiWow: ventajas de hermandad';

-- Rangos de reputacion personal (Rank 0 = el inicial, Reputation 0)
CREATE TABLE IF NOT EXISTS `miwow_guild_rank` (
    `Rank`       TINYINT UNSIGNED NOT NULL,
    `Name`       VARCHAR(32)      NOT NULL,
    `Reputation` INT UNSIGNED     NOT NULL,
    PRIMARY KEY (`Rank`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='MiWow: rangos de reputacion de hermandad';

-- Objetos de la tienda de la hermandad (ventana propia, la abre el intendente MiWow.Guild.VendorCreature). Cada
-- temporada salen MiWow.Guild.Vendor.ItemCount al azar. Se compran con oro (Price, en cobre; 0 = el precio de compra
-- del objeto) y la cantidad es la de compra del objeto (BuyCount). Solo definiciones: se recrea (la tabla de la
-- primera version usaba ExtendedCost).
DROP TABLE IF EXISTS `miwow_guild_vendor`;
CREATE TABLE `miwow_guild_vendor` (
    `ItemEntry` INT UNSIGNED     NOT NULL,
    `Rank`      TINYINT UNSIGNED NOT NULL DEFAULT 0 COMMENT 'Rango de reputacion minimo para comprarlo',
    `Price`     INT UNSIGNED     NOT NULL DEFAULT 0 COMMENT 'Cobre; 0 = BuyPrice del objeto',
    `Enabled`   TINYINT UNSIGNED NOT NULL DEFAULT 1,
    PRIMARY KEY (`ItemEntry`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='MiWow: tienda de la hermandad';

-- Temporadas. Sin fila: nombre "Temporada N" y duracion MiWow.Guild.Season.Days. DurationDays 0 = sin fin.
CREATE TABLE IF NOT EXISTS `miwow_guild_season` (
    `SeasonId`     INT UNSIGNED      NOT NULL,
    `Name`         VARCHAR(64)       NOT NULL DEFAULT '',
    `DurationDays` SMALLINT UNSIGNED NOT NULL DEFAULT 30,
    PRIMARY KEY (`SeasonId`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='MiWow: temporadas de hermandad';

-- Premios al acabar la temporada, por correo al lider. SeasonId 0 = para las temporadas sin premios propios.
CREATE TABLE IF NOT EXISTS `miwow_guild_prize` (
    `SeasonId`  INT UNSIGNED      NOT NULL,
    `Position`  TINYINT UNSIGNED  NOT NULL COMMENT '1 primero, 2 segundo, 3 tercero...',
    `ItemEntry` INT UNSIGNED      NOT NULL,
    `ItemCount` SMALLINT UNSIGNED NOT NULL DEFAULT 1,
    PRIMARY KEY (`SeasonId`, `Position`, `ItemEntry`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='MiWow: premios de temporada de hermandad';

-- Rangos
DELETE FROM `miwow_guild_rank`;
INSERT INTO `miwow_guild_rank` (`Rank`, `Name`, `Reputation`) VALUES
(0, 'Recluta',  0),
(1, 'Iniciado', 3000),
(2, 'Hermano',  9000),
(3, 'Veterano', 21000),
(4, 'Guardián', 42000),
(5, 'Leyenda',  75000);

DELETE FROM `miwow_guild_season` WHERE `SeasonId` = 1;
INSERT INTO `miwow_guild_season` (`SeasonId`, `Name`, `DurationDays`) VALUES
(1, 'Temporada 1', 30);

-- Categoria "Hermandad" del registro de misiones (QuestSortID -400). Build-Dbc la mete en el QuestSort.dbc del
-- cliente (rango propio 400); el servidor la fusiona con su DBC.
DELETE FROM `questsort_dbc` WHERE `ID` = 400;
INSERT INTO `questsort_dbc` (`ID`, `SortName_Lang_enUS`, `SortName_Lang_enGB`, `SortName_Lang_koKR`, `SortName_Lang_frFR`,
    `SortName_Lang_deDE`, `SortName_Lang_enCN`, `SortName_Lang_zhCN`, `SortName_Lang_enTW`, `SortName_Lang_zhTW`,
    `SortName_Lang_esES`, `SortName_Lang_esMX`, `SortName_Lang_ruRU`, `SortName_Lang_ptPT`, `SortName_Lang_ptBR`,
    `SortName_Lang_itIT`, `SortName_Lang_Unk`, `SortName_Lang_Mask`) VALUES
(400, 'Guild', 'Guild', 'Guild', 'Guilde', 'Gilde', 'Guild', 'Guild', 'Guild', 'Guild',
    'Hermandad', 'Hermandad', 'Guild', 'Guild', 'Guild', 'Guild', 'Guild', 16712190);

-- Tablon de la hermandad (objeto 9500200, MiWow.Guild.BoardObject): da y recoge las misiones de hermandad (las pone
-- el modulo en memoria: no usar gameobject_queststarter/ender con el). Copia del "Wanted Board" (2713, tipo 2
-- QUESTGIVER). Se coloca con .gobject add 9500200.
-- Intendente de la hermandad (PNJ 9500201, MiWow.Guild.VendorCreature, cualquier faccion: 35): abre la tienda de la
-- hermandad (ventana del cliente). Copia de Lyesa Steelbrow (5049). Se coloca con .npc add 9500201.
-- (9500200 fue antes un PNJ "Heraldo": se borra)
DELETE FROM `creature_template` WHERE `entry` IN (9500200, 9500201);
DELETE FROM `creature_template_model` WHERE `CreatureID` IN (9500200, 9500201);
DELETE FROM `creature_queststarter` WHERE `id` = 9500200;
DELETE FROM `creature_questender` WHERE `id` = 9500200;
DELETE FROM `npc_vendor` WHERE `entry` = 9500201;
DELETE FROM `gameobject_template` WHERE `entry` = 9500200;
DELETE FROM `gameobject_template_addon` WHERE `entry` = 9500200;
DELETE FROM `gameobject_queststarter` WHERE `id` = 9500200;
DELETE FROM `gameobject_questender` WHERE `id` = 9500200;

CREATE TEMPORARY TABLE `miwow_tmp_template` SELECT * FROM `gameobject_template` WHERE `entry` = 2713;
UPDATE `miwow_tmp_template` SET `entry` = 9500200, `name` = 'Tablón de la hermandad', `ScriptName` = 'go_miwow_guild_board',
    `AIName` = '', `size` = 1.2;
INSERT INTO `gameobject_template` SELECT * FROM `miwow_tmp_template`;
DROP TEMPORARY TABLE `miwow_tmp_template`;

CREATE TEMPORARY TABLE `miwow_tmp_template` SELECT * FROM `creature_template` WHERE `entry` = 5049;
UPDATE `miwow_tmp_template` SET `entry` = 9500201, `name` = 'Intendente de la hermandad', `subname` = 'Hermandad',
    `npcflag` = 1, `faction` = 35, `gossip_menu_id` = 0, `ScriptName` = 'npc_miwow_guild_vendor', `AIName` = '',
    `minlevel` = 80, `maxlevel` = 80;
INSERT INTO `creature_template` SELECT * FROM `miwow_tmp_template`;
DROP TEMPORARY TABLE `miwow_tmp_template`;

INSERT INTO `creature_template_model` (`CreatureID`, `Idx`, `CreatureDisplayID`, `DisplayScale`, `Probability`, `VerifiedBuild`) VALUES
(9500201, 0, 2999, 1, 1, 0);

-- Textos: 9500200 = tablon (solo se ve sin el parche del cliente, con la lista nativa); 9500201 = intendente sin
-- hermandad
DELETE FROM `npc_text` WHERE `ID` IN (9500200, 9500201);
INSERT INTO `npc_text` (`ID`, `text0_0`, `text0_1`, `Probability0`) VALUES
(9500200, 'El tablón de la hermandad cambia cada día y cada semana. Cada misión entregada suma puntos de temporada a tu hermandad y reputación para ti.',
          'El tablón de la hermandad cambia cada día y cada semana. Cada misión entregada suma puntos de temporada a tu hermandad y reputación para ti.', 1),
(9500201, 'Solo atiendo a miembros de una hermandad. Vuelve cuando tengas una.',
          'Solo atiendo a miembros de una hermandad. Vuelve cuando tengas una.', 1);

-- ---------------------------------------------------------------------------------------------------------------
-- CONTENIDO DE PRUEBA (sustituir por el real): cuatro misiones sin objetivos (se completan al aceptarlas y se
-- entregan en el tablon; la de grupo, por tanto, hay que ACEPTARLA en grupo), una ventaja, premios y la tienda.
-- ---------------------------------------------------------------------------------------------------------------
-- Flags: 4096 = diaria, 32768 = semanal, 8 = se puede compartir. QuestType 2 = normal.
DELETE FROM `quest_template` WHERE `ID` BETWEEN 9500000 AND 9500003;
DELETE FROM `quest_template_addon` WHERE `ID` BETWEEN 9500000 AND 9500003;
DELETE FROM `quest_offer_reward` WHERE `ID` BETWEEN 9500000 AND 9500003;
DELETE FROM `quest_request_items` WHERE `ID` BETWEEN 9500000 AND 9500003;
INSERT INTO `quest_template` (`ID`, `QuestType`, `QuestLevel`, `MinLevel`, `QuestSortID`, `SuggestedGroupNum`, `Flags`,
    `LogTitle`, `LogDescription`, `QuestDescription`, `QuestCompletionLog`) VALUES
(9500000, 2, -1, 1, -400, 0, 4096,
    'Patrulla de la hermandad', 'Entrégala en el tablón de la hermandad.',
    'La hermandad necesita ojos en los caminos. Date una vuelta e informa en el tablón.', 'Vuelve al tablón de la hermandad.'),
(9500001, 2, -1, 1, -400, 0, 4096,
    'Suministros para la hermandad', 'Entrégala en el tablón de la hermandad.',
    'Nos faltan provisiones. Cualquier ayuda cuenta.', 'Vuelve al tablón de la hermandad.'),
(9500002, 2, -1, 1, -400, 0, 4096,
    'Recado urgente', 'Entrégala en el tablón de la hermandad.',
    'Hay un recado que no puede esperar. ¿Echas una mano?', 'Vuelve al tablón de la hermandad.'),
(9500003, 2, -1, 1, -400, 2, 32768 | 8,
    'Reunión de la hermandad', 'Acepta la misión en grupo con otro miembro de tu hermandad (no tiene objetivos: se completa al aceptarla).',
    'Una hermandad se demuestra unida. Venid al menos dos miembros juntos.', 'Vuelve al tablón de la hermandad.');

INSERT INTO `quest_offer_reward` (`ID`, `RewardText`) VALUES
(9500000, 'Buen trabajo. La hermandad te lo agradece.'),
(9500001, 'Buen trabajo. La hermandad te lo agradece.'),
(9500002, 'Buen trabajo. La hermandad te lo agradece.'),
(9500003, 'Así se hace. Juntos llegaremos lejos.');

DELETE FROM `miwow_guild_quest` WHERE `QuestId` BETWEEN 9500000 AND 9500003;
INSERT INTO `miwow_guild_quest` (`QuestId`, `Board`, `Points`, `Reputation`, `RequiredMembers`) VALUES
(9500000, 0, 20, 400, 0),
(9500001, 0, 15, 250, 0),
(9500002, 0, 10, 150, 0),
(9500003, 1, 300, 1500, 2);

-- Ventajas (inspiradas en las de hermandad de Cataclysm). Los puntos son los del diseno original (5.000 ... 150.000)
-- con las intermedias repartidas.
DELETE FROM `miwow_guild_perk`;
INSERT INTO `miwow_guild_perk` (`PerkId`, `Points`, `SpellId`, `Effect`) VALUES
(0,    2500, 9504000, 'mount'),  -- ¡A montar!: +10 % velocidad con montura (no se acumula)
(1,    5000, 9504001, 'xp'),  -- Via rapida 1: +5 % experiencia (muertes y misiones)
(2,   10000, 9504002, 'reputation'),  -- Popularidad 1: +5 % reputacion
(3,   15000, 9504003, 'gold'),  -- Flujo de oro 1: +5 % del dinero despojado al banco de la hermandad
(4,   20000, 9504004, 'hearth'),  -- Hogar presto: piedra de hogar 15 min antes
(5,   25000, 9504005, 'repair'),  -- Reparaciones de hermandad: -10 % al reparar
(6,   35000, 9504006, 'vendor'),  -- Regateo: -5 % en los vendedores
(7,   45000, 9504007, 'resurrect'),  -- Vuelta a la vida: +50 % salud/mana al resucitar
(8,   55000, 9504008, 'mail'),  -- Correo de hermandad: correo instantaneo entre miembros
(9,   65000, 9504009, 'profession'),  -- Horas extra: 10 % de un punto extra de profesion
(10,  75000, 9504010, 'xp'),  -- Via rapida 2: +10 %
(11,  90000, 9504011, 'honor'),  -- Mencion honorifica 1: +5 % honor
(12, 110000, 9504012, 'reputation'),  -- Popularidad 2: +10 %
(13, 130000, 9504013, 'gold'),  -- Flujo de oro 2: +10 %
(14, 150000, 9504014, 'honor');  -- Mencion honorifica 2: +10 %

-- Premios de prueba (todas las temporadas sin premios propios): una bolsa para cada puesto del podio
DELETE FROM `miwow_guild_prize` WHERE `SeasonId` = 0;
INSERT INTO `miwow_guild_prize` (`SeasonId`, `Position`, `ItemEntry`, `ItemCount`) VALUES
(0, 1, 38082, 1),  -- Bolsa "Gigantique"
(0, 2, 41599, 1),  -- Bolsa de tejido de escarcha
(0, 3, 21841, 1);  -- Bolsa de tejido abisal

-- Tienda de prueba: bolsas y tabardo de hermandad (Price en cobre: 10000 = 1 oro; 0 = precio del objeto)
DELETE FROM `miwow_guild_vendor`;
INSERT INTO `miwow_guild_vendor` (`ItemEntry`, `Rank`, `Price`) VALUES
(5976,  0, 0),        -- Tabardo de hermandad
(4500,  0, 0),        -- Mochila de viajero
(21841, 1, 200000),   -- Bolsa de tejido abisal (20 oro)
(41599, 2, 500000),   -- Bolsa de tejido de escarcha (50 oro)
(38082, 3, 1000000);  -- Bolsa "Gigantique" (100 oro)
