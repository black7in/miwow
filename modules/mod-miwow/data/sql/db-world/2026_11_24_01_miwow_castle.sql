-- MiWow: criaturas de la defensa del castillo (juego "castillo", mapa 755; src/games/MiWowGameCastle.cpp).
-- Nivel 80 (exp 2: vida y dano base de WotLK), sin botin ni oro (y sin XP/reputacion: MiWowRewards en los mapas de
-- evento). La dificultad se ajusta con HealthModifier / DamageModifier; los hechizos los lanza la IA del modulo.
-- Oleadas de 20+ enemigos: los normales son flojos uno a uno (vida 0,3-1,3, dano 0,45-1,1).
--   9500500       Torre del castillo: su vida = la del castillo (seleccionable: se ve su barra de vida). Modelo propio
--                 40000 (torre de Lordaeron, abajo). Sin regeneracion; la IA no se mueve, no ataca, no vuelve a casa
--                 y no se deja curar.
--   9500501       Defensor del castillo (los 3 guardias)
--   9500502       Portal de la Legion: decorado (no seleccionable) donde salen las oleadas
--   9500503       Intendente del castillo: vende mejoras de stats con el oro del castillo (gossip del modulo)
--   95005x0-x9    Invasores de la etapa x (1-5); x9 = jefe de la etapa
-- Facciones: 14 (monstruo: hostil a los jugadores, sin grupo de "amigos") contra 250 (escoltado: amistosa con
-- todos los jugadores, hostil a los monstruos; su grupo es el de los jugadores, asi que los monstruos los atacan).
DELETE FROM `creature_template` WHERE `entry` BETWEEN 9500500 AND 9500599;
DELETE FROM `creature_template_model` WHERE `CreatureID` BETWEEN 9500500 AND 9500599;
DELETE FROM `creature_template_addon` WHERE `entry` BETWEEN 9500500 AND 9500599;
DELETE FROM `creature_template_spell` WHERE `CreatureID` BETWEEN 9500500 AND 9500599;
INSERT INTO `creature_template` (`entry`, `name`, `subname`, `minlevel`, `maxlevel`, `exp`, `faction`, `npcflag`,
    `speed_walk`, `speed_run`, `detection_range`, `rank`, `DamageModifier`, `BaseAttackTime`, `RangeAttackTime`,
    `unit_class`, `unit_flags`, `unit_flags2`, `type`, `type_flags`, `lootid`, `mingold`, `maxgold`, `AIName`,
    `MovementType`, `HealthModifier`, `ManaModifier`, `ArmorModifier`, `ExperienceModifier`, `RegenHealth`,
    `flags_extra`, `ScriptName`, `VerifiedBuild`) VALUES
(9500500, 'Torre del castillo', '', 80, 80, 2, 250, 0, 1, 1.14286, 20, 0, 0.0, 2000, 2000, 1, 0, 0, 9, 0, 0, 0, 0, '', 0, 40.0, 1, 1, 0, 0, 0, 'npc_miwow_castle_gate', 0),
(9500502, 'Portal de la Legión', '', 80, 80, 2, 35, 0, 1, 1.14286, 20, 0, 1, 2000, 2000, 1, 33555202, 0, 10, 0, 0, 0, 0, '', 0, 1, 1, 1, 0, 1, 0, '', 0),
(9500503, 'Intendente del castillo', 'Mejoras de la partida', 80, 80, 2, 35, 1, 1, 1.14286, 20, 0, 1, 2000, 2000, 1, 768, 0, 7, 0, 0, 0, 0, '', 0, 10, 1, 1, 0, 1, 0, 'npc_miwow_castle_vendor', 0),
(9500501, 'Defensor del castillo', 'Guardia', 80, 80, 2, 250, 0, 1, 1.14286, 20, 0, 1.5, 2000, 2000, 1, 0, 0, 7, 0, 0, 0, 0, '', 0, 4.0, 1, 1, 0, 1, 0, 'npc_miwow_castle_guard', 0),
(9500510, 'Guerrero Desollador', '', 80, 80, 2, 14, 0, 1, 1.14286, 20, 0, 0.38, 2000, 2000, 1, 0, 0, 7, 0, 0, 0, 0, '', 0, 0.3, 1, 1, 0, 1, 0, 'npc_miwow_castle_invader', 0),
(9500511, 'Rompehuesos vrykul', '', 80, 80, 2, 14, 0, 1, 1.14286, 20, 0, 0.45, 2000, 2000, 1, 0, 0, 7, 0, 0, 0, 0, '', 0, 0.42, 1, 1, 0, 1, 0, 'npc_miwow_castle_invader', 0),
(9500519, 'Jarl Skarn el Despiadado', 'Señor de la guerra vrykul', 80, 80, 2, 14, 0, 1, 1.14286, 20, 1, 1.2, 2000, 2000, 1, 0, 0, 7, 0, 0, 0, 0, '', 0, 8.0, 1, 1, 0, 1, 0, 'npc_miwow_castle_invader', 0),
(9500520, 'Huargo sanguinario', '', 80, 80, 2, 14, 0, 1, 1.3, 20, 0, 0.52, 2000, 2000, 1, 0, 0, 1, 0, 0, 0, 0, '', 0, 0.36, 1, 1, 0, 1, 0, 'npc_miwow_castle_invader', 0),
(9500521, 'Huargo colmilloacerado', '', 80, 80, 2, 14, 0, 1, 1.3, 20, 0, 0.6, 2000, 2000, 1, 0, 0, 1, 0, 0, 0, 0, '', 0, 0.48, 1, 1, 0, 1, 0, 'npc_miwow_castle_invader', 0),
(9500529, 'Colmillo Gris', 'Alfa de la jauría', 80, 80, 2, 14, 0, 1, 1.3, 20, 1, 1.4, 2000, 2000, 1, 0, 0, 1, 0, 0, 0, 0, '', 0, 10.0, 1, 1, 0, 1, 0, 'npc_miwow_castle_invader', 0),
(9500530, 'Necrófago hambriento', '', 80, 80, 2, 14, 0, 1, 1.14286, 20, 0, 0.68, 2000, 2000, 1, 0, 0, 6, 0, 0, 0, 0, '', 0, 0.48, 1, 1, 0, 1, 0, 'npc_miwow_castle_invader', 0),
(9500531, 'Nigromante de la Plaga', '', 80, 80, 2, 14, 0, 1, 1.14286, 20, 0, 0.45, 2000, 2000, 8, 0, 0, 6, 0, 0, 0, 0, '', 0, 0.42, 1, 1, 0, 1, 0, 'npc_miwow_castle_invader', 0),
(9500539, 'Carnepútrida', 'Abominación de la Plaga', 80, 80, 2, 14, 0, 1, 1.14286, 20, 1, 1.6, 2000, 2000, 1, 0, 0, 6, 0, 0, 0, 0, '', 0, 12.0, 1, 1, 0, 1, 0, 'npc_miwow_castle_invader', 0),
(9500540, 'Elemental de tierra furioso', '', 80, 80, 2, 14, 0, 1, 1.14286, 20, 0, 0.83, 2000, 2000, 1, 0, 0, 4, 0, 0, 0, 0, '', 0, 0.72, 1, 1, 0, 1, 0, 'npc_miwow_castle_invader', 0),
(9500541, 'Elemental de tormenta', '', 80, 80, 2, 14, 0, 1, 1.14286, 20, 0, 0.6, 2000, 2000, 8, 0, 0, 4, 0, 0, 0, 0, '', 0, 0.54, 1, 1, 0, 1, 0, 'npc_miwow_castle_invader', 0),
(9500549, 'Gromm', 'El Corazón de Piedra', 80, 80, 2, 14, 0, 1, 1.14286, 20, 1, 1.8, 2000, 2000, 1, 0, 0, 4, 0, 0, 0, 0, '', 0, 14.0, 1, 1, 0, 1, 0, 'npc_miwow_castle_invader', 0),
(9500550, 'Diablillo vil', '', 80, 80, 2, 14, 0, 1, 1.14286, 20, 0, 0.6, 2000, 2000, 8, 0, 0, 3, 0, 0, 0, 0, '', 0, 0.36, 1, 1, 0, 1, 0, 'npc_miwow_castle_invader', 0),
(9500551, 'Guardia vil', '', 80, 80, 2, 14, 0, 1, 1.14286, 20, 0, 0.98, 2000, 2000, 1, 0, 0, 3, 0, 0, 0, 0, '', 0, 0.84, 1, 1, 0, 1, 0, 'npc_miwow_castle_invader', 0),
(9500552, 'Infernal', '', 80, 80, 2, 14, 0, 1, 1.14286, 20, 0, 1.12, 2000, 2000, 1, 0, 0, 3, 0, 0, 0, 0, '', 0, 1.32, 1, 1, 0, 1, 0, 'npc_miwow_castle_invader', 0),
(9500559, 'Kazrath', 'Señor del Terror', 80, 80, 2, 14, 0, 1, 1.14286, 20, 1, 2.0, 2000, 2000, 1, 0, 0, 3, 0, 0, 0, 0, '', 0, 18.0, 1, 1, 0, 1, 0, 'npc_miwow_castle_invader', 0);
INSERT INTO `creature_template_model` (`CreatureID`, `Idx`, `CreatureDisplayID`, `DisplayScale`, `Probability`, `VerifiedBuild`) VALUES
(9500500, 0, 40000, 1.0, 1, 0),
(9500502, 0, 27735, 1.0, 1, 0),
(9500501, 0, 25920, 1.0, 1, 0),
(9500503, 0, 13384, 1.0, 1, 0),
(9500510, 0, 22143, 1.0, 1, 0),
(9500511, 0, 22297, 1.0, 1, 0),
(9500519, 0, 22297, 1.6, 1, 0),
(9500520, 0, 22088, 1.0, 1, 0),
(9500521, 0, 22611, 1.0, 1, 0),
(9500529, 0, 22003, 1.8, 1, 0),
(9500530, 0, 571, 1.0, 1, 0),
(9500531, 0, 23181, 1.0, 1, 0),
(9500539, 0, 24711, 1.2, 1, 0),
(9500540, 0, 22675, 1.0, 1, 0),
(9500541, 0, 5561, 1.0, 1, 0),
(9500549, 0, 14506, 2.0, 1, 0),
(9500550, 0, 16890, 1.0, 1, 0),
(9500551, 0, 14255, 1.0, 1, 0),
(9500552, 0, 17312, 1.0, 1, 0),
(9500559, 0, 17887, 1.0, 1, 0);

-- Modelo de la torre: una torre de Lordaeron (M2 de decorado, 12 x 14 x 48 yd) como criatura, a escala 0,6 (~29 yd).
-- IDs propios fuera del rango 9500000 (el cliente dimensiona las tablas por el ID mas alto): CreatureModelData
-- 3500-3599 (el cliente llega a 3440) y CreatureDisplayInfo 40000-40099 (llega a 32754); ver tools/Build-Dbc.ps1.
-- Copia de los valores del estandarte del Alba Argenta (display 26196, modelo 2881: otro decorado como criatura).
DELETE FROM `creaturemodeldata_dbc` WHERE `ID` = 3500;
INSERT INTO `creaturemodeldata_dbc` (`ID`, `Flags`, `ModelName`, `SizeClass`, `ModelScale`, `BloodID`,
    `FootprintTextureID`, `FootprintTextureLength`, `FootprintTextureWidth`, `FootprintParticleScale`, `FoleyMaterialID`,
    `FootstepShakeSize`, `DeathThudShakeSize`, `SoundID`, `CollisionWidth`, `CollisionHeight`, `MountHeight`,
    `GeoBoxMinX`, `GeoBoxMinY`, `GeoBoxMinZ`, `GeoBoxMaxX`, `GeoBoxMaxY`, `GeoBoxMaxZ`, `WorldEffectScale`,
    `AttachedEffectScale`, `MissileCollisionRadius`, `MissileCollisionPush`, `MissileCollisionRaise`)
VALUES (3500, 0, 'World\\GENERIC\\UNDEAD\\PASSIVE DOODADS\\LordaeronTowers\\UndercityTower01.mdx', 0, 1, 3, 4, 18, 12, 1, 0,
    0, 0, 2721, 6, 48, 0, -6.2, -7.1, -0.4, 6.2, 7.1, 48.3, 1, 1, 0, 0, 0);

DELETE FROM `creaturedisplayinfo_dbc` WHERE `ID` = 40000;
INSERT INTO `creaturedisplayinfo_dbc` (`ID`, `ModelID`, `SoundID`, `ExtendedDisplayInfoID`, `CreatureModelScale`,
    `CreatureModelAlpha`, `TextureVariation_1`, `TextureVariation_2`, `TextureVariation_3`, `PortraitTextureName`,
    `BloodLevel`, `BloodID`, `NPCSoundID`, `ParticleColorID`, `CreatureGeosetData`, `ObjectEffectPackageID`)
VALUES (40000, 3500, 0, 0, 0.6, 255, '', '', '', '', 0, 0, 0, 0, 0, 0);

-- Alcance: los enemigos golpean la torre desde su borde (el radio de la torre a escala 0,6 es ~4 yd)
DELETE FROM `creature_model_info` WHERE `DisplayID` = 40000;
INSERT INTO `creature_model_info` (`DisplayID`, `BoundingRadius`, `CombatReach`, `Gender`, `DisplayID_Other_Gender`,
    `VerifiedBuild`) VALUES (40000, 4, 6, 2, 0, 0);

-- Texto del intendente (gossip: las mejoras y el oro los pone el modulo)
DELETE FROM `npc_text` WHERE `ID` IN (9500503, 9500504);
INSERT INTO `npc_text` (`ID`, `text0_0`, `text0_1`, `Probability0`) VALUES
(9500503, 'Cada invasor que cae deja oro en las arcas del castillo. Gástalo aquí en mejoras: se acumulan durante la partida y se pierden al salir.',
          'Cada invasor que cae deja oro en las arcas del castillo. Gástalo aquí en mejoras: se acumulan durante la partida y se pierden al salir.', 1);
