-- EventWow: logout instantaneo para todos los jugadores.
-- Por defecto solo el rol de moderador (194) tiene RBAC_PERM_INSTANT_LOGOUT (1); el resto espera
-- 20 s fuera de zonas de descanso (MiscHandler.cpp HandleLogoutRequestOpcode). En EventWow salir
-- es volver al login: sin espera. 195 = "Role: Sec Level Player" (heredado por todos los niveles).
DELETE FROM `rbac_linked_permissions` WHERE `id` = 195 AND `linkedId` = 1;
INSERT INTO `rbac_linked_permissions` (`id`, `linkedId`) VALUES (195, 1);
