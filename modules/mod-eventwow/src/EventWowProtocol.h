#ifndef MOD_EVENTWOW_PROTOCOL_H
#define MOD_EVENTWOW_PROTOCOL_H

#include "Define.h"
#include <functional>
#include <string>
#include <string_view>
#include <type_traits>
#include <vector>

class Player;

// Protocolo cliente <-> servidor sobre addon messages (ver docs/protocolo.md).
//
// Transporte: whisper con idioma LANG_ADDON y texto "EWOW\t<flag><payload>".
//   - Cliente -> servidor: SendAddonMessage("EWOW", ..., "WHISPER", <su propio nombre>).
//     El modulo lo intercepta en OnPlayerCanUseChat y nunca lo reenvia.
//   - Servidor -> cliente: whisper de addon con emisor = el propio jugador.
//   - flag: '=' mensaje completo, '+' fragmento (siguen mas), '.' ultimo fragmento.
//     Los addon messages se limitan a 255 caracteres (ChatHandler.cpp), por eso se fragmenta.
// Payload: "<OP>\t<campo>\t<campo>..." (los campos no pueden contener '\t').
namespace EventWowProtocol
{
    constexpr std::string_view Prefix = "EWOW";
    constexpr uint32 Version = 1;

    using Args = std::vector<std::string_view>;
    using Handler = std::function<void(Player* player, Args const& args)>;

    // Registra el manejador de un opcode recibido del cliente (args = campos sin el opcode)
    void RegisterHandler(std::string_view op, Handler handler);
}

class EventWowMessage
{
public:
    explicit EventWowMessage(std::string_view op) : _payload(op) { }

    EventWowMessage& Add(std::string_view field);

    template<typename T, std::enable_if_t<std::is_arithmetic_v<T>, int> = 0>
    EventWowMessage& Add(T value)
    {
        return Add(std::string_view(std::to_string(value)));
    }

    std::string const& GetPayload() const { return _payload; }

    void Send(Player* player) const;

private:
    std::string _payload;
};

#endif
