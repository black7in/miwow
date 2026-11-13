-- EventWow: el contenedor pasa a ser elfo de la noche druida (EventWow.Character.Race/Class = 4/11).
-- Nace directamente en el lobby (sin teleport en el primer login); debe coincidir con EventWow.Lobby.*
-- (el modulo lo comprueba al arrancar y avisa en el log si no coincide).
-- Lobby provisional: Isla de los GM (mapa 1, zona 876).
UPDATE `playercreateinfo`
SET `map` = 1, `zone` = 876, `position_x` = 16226.2, `position_y` = 16257, `position_z` = 13.2022, `orientation` = 1.65007
WHERE `race` = 4 AND `class` = 11;

-- Humano guerrero (contenedor anterior, 2026_11_12_00_lobby_playercreateinfo.sql): vuelve a Villadorada (valor original de AC).
UPDATE `playercreateinfo`
SET `map` = 0, `zone` = 12, `position_x` = -8949.95, `position_y` = -132.493, `position_z` = 83.5312, `orientation` = 0
WHERE `race` = 1 AND `class` = 1;
