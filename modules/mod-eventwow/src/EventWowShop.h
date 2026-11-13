#ifndef MOD_EVENTWOW_SHOP_H
#define MOD_EVENTWOW_SHOP_H

#include "Define.h"
#include <unordered_map>

// Tienda de partida: todo nativo (ventana de vendedor, oro, bolsas, objetos de item_template).
//  - Moneda = oro de WoW, que solo existe dentro de la partida: el estado base lo pone a 0 y vacia las bolsas
//    (EventWowLobby::RestoreBaseState, y en cada login).
//  - Vendedores = PNJ con npc_vendor normal (rango de criaturas de EventWow), invocados por cada juego.
//  - Objetos propios en el rango de entradas 9500000-9599999 (item_template; Item.dbc del cliente: pendiente).
//  - eventwow_item marca como se comportan los objetos de la tienda:
//      INSTANT: al comprarlo se destruye y sus stats de item_template (stat_type/stat_value, armadura) se suman
//               al jugador con EventWowStats (libros tipo Hero Siege: nunca llegan a la mochila).
//    Sin fila = objeto normal (mochila, consumible con su hechizo, equipable...).
enum EventWowItemFlags : uint32
{
    EVENTWOW_ITEM_FLAG_INSTANT = 0x1
};

class EventWowShop
{
public:
    static EventWowShop& Instance();

    // Al arrancar (BD world ya cargada)
    void Load();

    uint32 GetFlags(uint32 itemEntry) const;
    bool IsInstant(uint32 itemEntry) const { return GetFlags(itemEntry) & EVENTWOW_ITEM_FLAG_INSTANT; }

private:
    std::unordered_map<uint32, uint32> _itemFlags;
};

#define sEventWowShop EventWowShop::Instance()

#endif
