-- EventWow: habilidades de Arthas, caballero de la Muerte (ficha 31; hechizos en data/spells/arthas.toml).
-- PROVISIONAL hasta el sistema de niveles/puntos (docs/heroes.md): rango 1 de cada habilidad, todas a la vez.
-- Orden = casillas de la barra: 4 basicas, definitiva, suprema.
DELETE FROM `eventwow_character_spell` WHERE `CharacterId` = 31;
INSERT INTO `eventwow_character_spell` (`CharacterId`, `Slot`, `SpellId`) VALUES
(31, 0, 9500100),  -- Golpe de Escarcha
(31, 1, 9500104),  -- Espiral de la Muerte
(31, 2, 9500108),  -- Muerte y Descomposicion
(31, 3, 9500112),  -- Aura de Escarcha (pasiva)
(31, 4, 9500116),  -- Levantar a un muerto (definitiva)
(31, 5, 9500122);  -- Furia de la Agonia de Escarcha (suprema)
