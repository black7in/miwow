-- EventWow: vehiculo opcional por personaje de minijuego (EventWowDisguise.cpp).
ALTER TABLE `eventwow_character`
    ADD COLUMN `VehicleEntry` INT UNSIGNED NOT NULL DEFAULT 0
    COMMENT 'creature_template con VehicleId: va siempre montado (asiento 0); 0 = a pie' AFTER `MaxPower`;
