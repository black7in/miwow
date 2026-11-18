-- EventWow (servidor tradicional): deshace 2026_11_13_00_rbac_instant_logout (borrado del modulo), que daba logout
-- instantaneo (permiso 1) a todos los jugadores (rol 195). Vuelve lo de AzerothCore: solo moderadores en adelante;
-- el resto espera 20 s fuera de zonas de descanso. Idempotente.
DELETE FROM `rbac_linked_permissions` WHERE `id` = 195 AND `linkedId` = 1;
