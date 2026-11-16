-- EventWow: el contenedor (druida) sin ranura de reliquia, para que use armas a distancia de verdad (arcos, armas de
-- fuego, ballestas, arrojadizas, varitas) con municion, envainado y animaciones.
-- ChrClasses.dbc `Flags` bit 0x08 = la ranura de distancia es de reliquia (UnitHasRelicSlot): lo tienen exactamente
-- Paladin 0x3A, Caballero de la Muerte 0x7A, Chaman 0x1A y Druida 0x0A; ninguna otra clase. Druida 0x0A -> 0x02.
-- Solo lo usa el cliente (ChrClassesEntryfmt del core ignora la columna): Build-Dbc copia esta fila (ExtraRanges
-- "chrclasses_dbc" = ID 11) al ChrClasses.dbc del parche. Resto de la fila = la original (esES en el hueco 6,
-- Name_Lang_zhCN; ingles en enUS para el servidor).

DELETE FROM `chrclasses_dbc` WHERE `ID` = 11;
INSERT INTO `chrclasses_dbc` VALUES
(11, 0, 0, 1,
 'Druid', '', '', '', '', '', 'Druida', '', '', '', '', '', '', '', '', '', 16712191,
 '', '', '', '', '', '', 'Druida', '', '', '', '', '', '', '', '', '', 16712172,
 '', '', '', '', '', '', 'Druida', '', '', '', '', '', '', '', '', '', 16712172,
 'DRUID', 7, 2, 0, 0);
