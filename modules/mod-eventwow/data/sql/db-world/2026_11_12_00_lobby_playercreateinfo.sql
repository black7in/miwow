-- EventWow: los personajes nacen directamente en el lobby (sin teleport en el primer login).
-- Debe coincidir con EventWow.Lobby.* y EventWow.Character.Race/Class de mod_eventwow.conf
-- (el modulo lo comprueba al arrancar y avisa en el log si no coincide).
-- Lobby provisional: Isla de los GM (mapa 1, zona 876).
UPDATE `playercreateinfo`
SET `map` = 1, `zone` = 876, `position_x` = 16226.2, `position_y` = 16257, `position_z` = 13.2022, `orientation` = 1.65007
WHERE `race` = 1 AND `class` = 1;
