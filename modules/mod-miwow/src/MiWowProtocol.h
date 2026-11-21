#ifndef MOD_MIWOW_PROTOCOL_H
#define MOD_MIWOW_PROTOCOL_H

#include "Define.h"
#include "ObjectGuid.h"
#include <functional>
#include <string>
#include <string_view>
#include <type_traits>
#include <vector>

class Player;

// Protocolo cliente <-> servidor sobre addon messages (ver docs/protocolo.md).
//
// Transporte: whisper con idioma LANG_ADDON y texto "MIWOW\t<flag><payload>".
//   - Cliente -> servidor: SendAddonMessage("MIWOW", ..., "WHISPER", <su propio nombre>).
//     El modulo lo intercepta en OnPlayerCanUseChat y nunca lo reenvia.
//   - Servidor -> cliente: whisper de addon con emisor = el propio jugador.
//   - flag: '=' mensaje completo, '+' fragmento (siguen mas), '.' ultimo fragmento.
//     Los addon messages se limitan a 255 caracteres (ChatHandler.cpp), por eso se fragmenta.
// Payload: "<OP>\t<campo>\t<campo>..." (los campos no pueden contener '\t').
//
// Conexion: el cliente manda HELLO <version> al entrar al mundo (y tras /reload). Si la version
// coincide, el jugador pasa a "conectado" (recibe WELCOME y los broadcasts) y se avisa a los
// ConnectListener, que le envian su estado (catalogo, historial de chat, cola...).
namespace MiWowProtocol
{
    constexpr std::string_view Prefix = "MIWOW";
    constexpr uint32 Version = 12;

    // Campos del mensaje sin el opcode. Apuntan al mensaje recibido: solo validos durante la llamada.
    using Args = std::vector<std::string_view>;
    using Handler = std::function<void(Player* player, Args const& args)>;
    using PlayerListener = std::function<void(Player* player)>;

    // Manejador de un opcode recibido del cliente (solo se llama si el jugador esta conectado,
    // salvo HELLO, que gestiona el propio protocolo)
    void RegisterHandler(std::string_view op, Handler handler);

    // Tras cada HELLO valido (tambien al reconectar con /reload)
    void RegisterConnectListener(PlayerListener listener);
    // Al hacer logout un jugador conectado (ya no cuenta en GetConnectedCount)
    void RegisterDisconnectListener(PlayerListener listener);

    // Completo HELLO (y no ha hecho logout)
    bool IsConnected(ObjectGuid guid);
    std::size_t GetConnectedCount();
    void ForEachConnected(std::function<void(Player* player)> const& func);
}

class MiWowMessage
{
public:
    explicit MiWowMessage(std::string_view op) : _payload(op) { }

    MiWowMessage& Add(std::string_view field);

    template<typename T, std::enable_if_t<std::is_arithmetic_v<T>, int> = 0>
    MiWowMessage& Add(T value)
    {
        return Add(std::string_view(std::to_string(value)));
    }

    std::string const& GetPayload() const { return _payload; }

    void Send(Player* player) const;
    // A todos los jugadores conectados
    void Broadcast() const;

private:
    std::string _payload;
};

#endif
