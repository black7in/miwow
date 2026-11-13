// Punto de entrada del modulo. El nombre de la funcion lo fija AzerothCore:
// "Add" + nombre de la carpeta del modulo (con '-' -> '_') + "Scripts".
void AddSC_eventwow_config();
void AddSC_eventwow_character();

void Addmod_eventwowScripts()
{
    AddSC_eventwow_config();
    AddSC_eventwow_character();
}
