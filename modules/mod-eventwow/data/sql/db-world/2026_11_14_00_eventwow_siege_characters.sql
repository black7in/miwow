-- EventWow: heroes del Asedio (juego 'asedio', mapa 751) para la fase de eleccion (Picking).
-- PROVISIONALES: valen para probar la eleccion; nombres, modelos, hechizos y stats se ajustan aqui sin compilar.
-- Todo con mana (el contenedor es druida; los hechizos con ira/energia/runas, formas o armas no sirven).
-- Hechizos existentes de nivel 80 (ninguno pide arma ni forma: comprobado en Spell.dbc).
-- Modelos de PNJ genericos: 26228 Argent Crusader, 19612 Kirin Tor Mage, 4249 Cenarion Druid, 21746 Dark Ranger.
DELETE FROM `eventwow_character` WHERE `Id` BETWEEN 10 AND 13;
INSERT INTO `eventwow_character` (`Id`, `Name`, `Description`, `Icon`, `DisplayId`, `Scale`, `Health`, `PowerType`, `MaxPower`, `VehicleEntry`) VALUES
(10, 'Cruzado de plata', 'Defensor cuerpo a cuerpo: aguanta en primera línea, aturde y abrasa a los que le rodean.', 'Interface\\Icons\\Spell_Holy_SealOfMight', 26228, 1.0, 9000, 0, 4000, 0),
(11, 'Mago del Kirin Tor', 'Lanzador de hechizos a distancia: mucho daño en área, poca vida.', 'Interface\\Icons\\Spell_Fire_FlameBolt', 19612, 1.0, 5000, 0, 6000, 0),
(12, 'Druida cenarion', 'Sanador: mantiene con vida al grupo e inmoviliza a los enemigos.', 'Interface\\Icons\\Spell_Nature_Rejuvenation', 4249, 1.0, 6500, 0, 6000, 0),
(13, 'Exploradora oscura', 'Daño de sombras sostenido: debilita a los enemigos con el tiempo y los hace huir.', 'Interface\\Icons\\Spell_Shadow_ShadowWordPain', 21746, 1.0, 6000, 0, 5000, 0);

DELETE FROM `eventwow_character_spell` WHERE `CharacterId` BETWEEN 10 AND 13;
INSERT INTO `eventwow_character_spell` (`CharacterId`, `Slot`, `SpellId`) VALUES
(10, 0, 48819),  -- Consagracion (rango 8)
(10, 1, 10308),  -- Martillo de justicia (rango 4)
(10, 2, 48817),  -- Colera Sagrada (rango 5)
(10, 3, 48825),  -- Choque Sagrado (rango 7)
(10, 4, 642),    -- Escudo divino
(11, 0, 42833),  -- Bola de Fuego (rango 16)
(11, 1, 42931),  -- Cono de frio (rango 8)
(11, 2, 42921),  -- Deflagracion Arcana (rango 10)
(11, 3, 42940),  -- Ventisca (rango 9)
(11, 4, 1953),   -- Traslacion
(12, 0, 48441),  -- Rejuvenecimiento (rango 15)
(12, 1, 48443),  -- Recrecimiento (rango 12)
(12, 2, 53251),  -- Crecimiento salvaje (rango 4)
(12, 3, 48463),  -- Fuego lunar (rango 14)
(12, 4, 53308),  -- Raices enredadoras (rango 8)
(13, 0, 48125),  -- Palabra de las Sombras: dolor (rango 12)
(13, 1, 48127),  -- Explosion mental (rango 13)
(13, 2, 48300),  -- Peste devoradora (rango 9)
(13, 3, 10890),  -- Alarido psiquico (rango 4)
(13, 4, 48066);  -- Palabra de poder: escudo (rango 14)

DELETE FROM `eventwow_character_stat` WHERE `CharacterId` BETWEEN 10 AND 13;
INSERT INTO `eventwow_character_stat` (`CharacterId`, `Stat`, `Value`) VALUES
(10, 'sta', 200),
(10, 'armor', 4000),
(10, 'sp', 300),
(11, 'int', 200),
(11, 'sp', 600),
(12, 'int', 150),
(12, 'spi', 150),
(12, 'sp', 500),
(13, 'sta', 100),
(13, 'int', 150),
(13, 'sp', 500);

DELETE FROM `eventwow_game_character` WHERE `GameId` = 'asedio';
INSERT INTO `eventwow_game_character` (`GameId`, `CharacterId`, `Sort`) VALUES
('asedio', 10, 0),
('asedio', 11, 1),
('asedio', 12, 2),
('asedio', 13, 3);
