// Punto de entrada del modulo. El nombre de la funcion lo fija AzerothCore:
// "Add" + nombre de la carpeta del modulo (con '-' -> '_') + "Scripts".
// Cada archivo con scripts nuevos debe registrar aqui su AddSC_*().
void AddSC_eventwow_config();
void AddSC_eventwow_character();
void AddSC_eventwow_lobby();
void AddSC_eventwow_protocol();
void AddSC_eventwow_games();
void AddSC_eventwow_chat();
void AddSC_eventwow_matches();
void AddSC_eventwow_dev_mode();
void AddSC_eventwow_groups();
void AddSC_eventwow_characters();
void AddSC_eventwow_disguise();
void AddSC_eventwow_stats();
void AddSC_eventwow_shop();
void AddSC_eventwow_inventory();
void AddSC_eventwow_weapons();
void AddSC_eventwow_pick_creature();

// Minijuegos (games/). Se registran antes que las maquetas: el orden es el del panel.
void AddSC_eventwow_game_siege();
void AddSC_eventwow_game_test();

void Addmod_eventwowScripts()
{
    AddSC_eventwow_config();
    AddSC_eventwow_character();
    AddSC_eventwow_lobby();
    AddSC_eventwow_protocol();
    AddSC_eventwow_game_siege();
    AddSC_eventwow_game_test();
    AddSC_eventwow_games();
    AddSC_eventwow_chat();
    AddSC_eventwow_matches();
    AddSC_eventwow_dev_mode();
    AddSC_eventwow_groups();
    AddSC_eventwow_characters();
    AddSC_eventwow_disguise();
    AddSC_eventwow_stats();
    AddSC_eventwow_shop();
    AddSC_eventwow_inventory();
    AddSC_eventwow_weapons();
    AddSC_eventwow_pick_creature();
}
