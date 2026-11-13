// Punto de entrada del modulo. El nombre de la funcion lo fija AzerothCore:
// "Add" + nombre de la carpeta del modulo (con '-' -> '_') + "Scripts".
// Cada archivo con scripts nuevos debe registrar aqui su AddSC_*().
void AddSC_eventwow_config();
void AddSC_eventwow_character();
void AddSC_eventwow_lobby();
void AddSC_eventwow_protocol();
void AddSC_eventwow_games();

void Addmod_eventwowScripts()
{
    AddSC_eventwow_config();
    AddSC_eventwow_character();
    AddSC_eventwow_lobby();
    AddSC_eventwow_protocol();
    AddSC_eventwow_games();
}
