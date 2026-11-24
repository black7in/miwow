// Punto de entrada del modulo. El nombre de la funcion lo fija AzerothCore:
// "Add" + nombre de la carpeta del modulo (con '-' -> '_') + "Scripts".
// Cada archivo con scripts nuevos debe registrar aqui su AddSC_*().
void AddSC_miwow_config();
void AddSC_miwow_lobby();
void AddSC_miwow_protocol();
void AddSC_miwow_games();
void AddSC_miwow_matches();
void AddSC_miwow_dev_mode();
void AddSC_miwow_groups();
void AddSC_miwow_vehicle();
void AddSC_miwow_spell_lock();
void AddSC_miwow_stats();
void AddSC_miwow_rewards();

// Temporadas de hermandad (guild/)
void AddSC_miwow_guild();
void AddSC_miwow_guild_protocol();

// Minijuegos (games/). Se registran antes que las maquetas: el orden es el del panel.
void AddSC_miwow_game_castle();
void AddSC_miwow_game_parkour();
void AddSC_miwow_game_race();
void AddSC_miwow_game_test();

void Addmod_miwowScripts()
{
    AddSC_miwow_config();
    AddSC_miwow_lobby();
    AddSC_miwow_protocol();
    AddSC_miwow_game_castle();
    AddSC_miwow_game_parkour();
    AddSC_miwow_game_race();
    AddSC_miwow_game_test();
    AddSC_miwow_games();
    AddSC_miwow_matches();
    AddSC_miwow_dev_mode();
    AddSC_miwow_groups();
    AddSC_miwow_vehicle();
    AddSC_miwow_spell_lock();
    AddSC_miwow_stats();
    AddSC_miwow_rewards();
    AddSC_miwow_guild();
    AddSC_miwow_guild_protocol();
}
