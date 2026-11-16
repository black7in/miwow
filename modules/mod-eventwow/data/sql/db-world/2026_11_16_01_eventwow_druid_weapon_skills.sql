-- EventWow: el contenedor (druida) puede usar TODAS las armas: habilidades de armas que el druida no tiene en 3.3.5.
-- 1) skillraceclassinfo_dbc: sin fila para la clase, el core no da la habilidad (LearnDefaultSkill, .learn) y la
--    borra al cargar el personaje. Build-Dbc copia estas filas (ID >= 9500000) al SkillRaceClassInfo.dbc del cliente.
--    Flags 128 y resto a 0 como las filas originales de cada habilidad (todas las razas jugables).
-- 2) playercreateinfo_skills: LearnDefaultSkills la da en CADA login (Player::LoadFromDB), tambien a personajes ya
--    creados; valor = maximo del nivel (AlwaysMaxSkillForLevel = 1).
-- 3) playercreateinfo_spell_custom: hechizo de competencia (efecto PROFICIENCY: dejar equipar). No se aprende solo con
--    la habilidad porque su SkillLineAbility excluye al druida. Necesita PlayerStart.CustomSpells = 1 (mod_eventwow.conf).
-- Todo para druida (classMask 1024), cualquier raza (raceMask 0).

DELETE FROM `skillraceclassinfo_dbc` WHERE `ID` BETWEEN 9500000 AND 9500008;
INSERT INTO `skillraceclassinfo_dbc` (`ID`, `SkillID`, `RaceMask`, `ClassMask`, `Flags`, `MinLevel`, `SkillTierID`, `SkillCostIndex`) VALUES
(9500000,  43, 2047, 1024, 128, 0, 0, 0), -- Espadas
(9500001,  44, 2047, 1024, 128, 0, 0, 0), -- Hachas
(9500002,  45, 2047, 1024, 128, 0, 0, 0), -- Arcos
(9500003,  46, 2047, 1024, 128, 0, 0, 0), -- Armas de fuego
(9500004,  55, 2047, 1024, 128, 0, 0, 0), -- Espadas de dos manos
(9500005, 172, 2047, 1024, 128, 0, 0, 0), -- Hachas de dos manos
(9500006, 176, 2047, 1024, 128, 0, 0, 0), -- Arrojadizas
(9500007, 226, 2047, 1024, 128, 0, 0, 0), -- Ballestas
(9500008, 228, 2047, 1024, 128, 0, 0, 0); -- Varitas

DELETE FROM `playercreateinfo_skills` WHERE `raceMask` = 0 AND `classMask` = 1024 AND `skill` IN (43, 44, 45, 46, 55, 160, 172, 176, 226, 228, 229, 473);
INSERT INTO `playercreateinfo_skills` (`raceMask`, `classMask`, `skill`, `rank`, `comment`) VALUES
(0, 1024,  43, 0, 'EventWow: Druid - Swords'),
(0, 1024,  44, 0, 'EventWow: Druid - Axes'),
(0, 1024,  45, 0, 'EventWow: Druid - Bows'),
(0, 1024,  46, 0, 'EventWow: Druid - Guns'),
(0, 1024,  55, 0, 'EventWow: Druid - Two-Handed Swords'),
(0, 1024, 172, 0, 'EventWow: Druid - Two-Handed Axes'),
(0, 1024, 176, 0, 'EventWow: Druid - Thrown'),
(0, 1024, 226, 0, 'EventWow: Druid - Crossbows'),
(0, 1024, 228, 0, 'EventWow: Druid - Wands'),
-- Estas tres el druida las tiene en SkillRaceClassInfo pero solo con instructor
(0, 1024, 160, 0, 'EventWow: Druid - Two-Handed Maces'),
(0, 1024, 229, 0, 'EventWow: Druid - Polearms'),
(0, 1024, 473, 0, 'EventWow: Druid - Fist Weapons');

DELETE FROM `playercreateinfo_spell_custom` WHERE `racemask` = 0 AND `classmask` = 1024 AND `Spell` IN (201, 196, 264, 266, 202, 197, 2567, 5011, 5009, 199, 200, 15590);
INSERT INTO `playercreateinfo_spell_custom` (`racemask`, `classmask`, `Spell`, `Note`) VALUES
(0, 1024,  201, 'EventWow: Espadas'),
(0, 1024,  196, 'EventWow: Hachas'),
(0, 1024,  264, 'EventWow: Arcos'),
(0, 1024,  266, 'EventWow: Armas de fuego'),
(0, 1024,  202, 'EventWow: Espadas de dos manos'),
(0, 1024,  197, 'EventWow: Hachas de dos manos'),
(0, 1024, 2567, 'EventWow: Arrojadizas'),
(0, 1024, 5011, 'EventWow: Ballestas'),
(0, 1024, 5009, 'EventWow: Varitas'),
(0, 1024,  199, 'EventWow: Mazas de dos manos'),
(0, 1024,  200, 'EventWow: Armas de asta'),
(0, 1024, 15590, 'EventWow: Armas de puno');
