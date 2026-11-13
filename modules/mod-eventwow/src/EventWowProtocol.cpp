#include "EventWowProtocol.h"
#include "Chat.h"
#include "DataMap.h"
#include "EventWowConfig.h"
#include "Log.h"
#include "Player.h"
#include "ScriptMgr.h"
#include "SharedDefines.h"
#include "Tokenize.h"
#include "WorldPacket.h"
#include <algorithm>
#include <map>

namespace
{
    constexpr char FlagComplete = '=';
    constexpr char FlagMore = '+';
    constexpr char FlagLast = '.';

    // 255 (limite del core) - "EWOW\t" - flag, con margen
    constexpr std::size_t MaxChunkSize = 240;
    // Tamano maximo de un mensaje reensamblado recibido del cliente
    constexpr std::size_t MaxIncomingSize = 2048;

    // Fragmentos pendientes de un jugador (en Player::CustomData: sin mapas globales ni punteros guardados)
    struct IncomingBuffer : public DataMap::Base
    {
        std::string Data;
    };

    std::map<std::string, EventWowProtocol::Handler, std::less<>>& GetHandlers()
    {
        static std::map<std::string, EventWowProtocol::Handler, std::less<>> handlers;
        return handlers;
    }

    // "EWOW\t..."
    bool IsProtocolMessage(std::string_view msg)
    {
        std::string_view const prefix = EventWowProtocol::Prefix;
        return msg.size() > prefix.size() && msg.substr(0, prefix.size()) == prefix && msg[prefix.size()] == '\t';
    }

    bool IsUtf8Continuation(char c)
    {
        return (static_cast<uint8>(c) & 0xC0) == 0x80;
    }

    void SendChunk(Player* player, char flag, std::string_view chunk)
    {
        std::string text;
        text.reserve(EventWowProtocol::Prefix.size() + 2 + chunk.size());
        text.append(EventWowProtocol::Prefix);
        text += '\t';
        text += flag;
        text.append(chunk);

        WorldPacket data;
        ChatHandler::BuildChatPacket(data, CHAT_MSG_WHISPER, LANG_ADDON, player, player, text);
        player->SendDirectMessage(&data);
    }

    void Dispatch(Player* player, std::string_view payload)
    {
        EventWowProtocol::Args args = Acore::Tokenize(payload, '\t', true);
        if (args.empty() || args.front().empty())
            return;

        std::string_view const op = args.front();
        args.erase(args.begin());

        auto& handlers = GetHandlers();
        auto itr = handlers.find(op);
        if (itr == handlers.end())
        {
            LOG_DEBUG("module.eventwow", "EventWow: opcode desconocido '{}' de {}", op, player->GetName());
            EventWowMessage("ERROR").Add("UNKNOWN_OP").Add(op).Send(player);
            return;
        }

        itr->second(player, args);
    }

    // Devuelve true si msg es un mensaje del protocolo (se consume aunque sea invalido)
    bool HandleIncoming(Player* player, std::string_view msg)
    {
        if (!IsProtocolMessage(msg))
            return false;

        std::string_view body = msg.substr(EventWowProtocol::Prefix.size() + 1);
        if (body.empty())
            return true;

        char const flag = body.front();
        std::string_view const data = body.substr(1);

        IncomingBuffer* buffer = player->CustomData.GetDefault<IncomingBuffer>("EventWowProtocol");
        switch (flag)
        {
            case FlagComplete:
                buffer->Data.clear();
                Dispatch(player, data);
                break;
            case FlagMore:
            case FlagLast:
                if (buffer->Data.size() + data.size() > MaxIncomingSize)
                {
                    LOG_WARN("module.eventwow", "EventWow: mensaje de {} supera {} bytes, descartado",
                        player->GetName(), MaxIncomingSize);
                    buffer->Data.clear();
                    break;
                }

                buffer->Data.append(data);
                if (flag == FlagLast)
                {
                    std::string const complete = std::move(buffer->Data);
                    buffer->Data.clear();
                    Dispatch(player, complete);
                }
                break;
            default:
                LOG_DEBUG("module.eventwow", "EventWow: flag invalido '{}' de {}", flag, player->GetName());
                break;
        }

        return true;
    }
}

void EventWowProtocol::RegisterHandler(std::string_view op, Handler handler)
{
    GetHandlers()[std::string(op)] = std::move(handler);
}

EventWowMessage& EventWowMessage::Add(std::string_view field)
{
    _payload += '\t';
    std::size_t const start = _payload.size();
    _payload.append(field);
    // '\t' es el separador de campos
    std::replace(_payload.begin() + start, _payload.end(), '\t', ' ');
    return *this;
}

void EventWowMessage::Send(Player* player) const
{
    std::string_view payload = _payload;
    if (payload.size() <= MaxChunkSize)
    {
        SendChunk(player, FlagComplete, payload);
        return;
    }

    while (!payload.empty())
    {
        std::size_t size = std::min(payload.size(), MaxChunkSize);
        // No partir un caracter UTF-8 entre dos fragmentos
        while (size > 1 && size < payload.size() && IsUtf8Continuation(payload[size]))
            --size;

        SendChunk(player, size == payload.size() ? FlagLast : FlagMore, payload.substr(0, size));
        payload.remove_prefix(size);
    }
}

// Intercepta los addon messages con prefijo EWOW: los del whisper se procesan, y en ningun canal
// se reenvian (asi un jugador no puede hacerse pasar por el servidor ante otro cliente).
class EventWow_ProtocolPlayerScript : public PlayerScript
{
public:
    EventWow_ProtocolPlayerScript() : PlayerScript("EventWow_ProtocolPlayerScript", {
        PLAYERHOOK_CAN_PLAYER_USE_PRIVATE_CHAT,
        PLAYERHOOK_CAN_PLAYER_USE_GROUP_CHAT,
        PLAYERHOOK_CAN_PLAYER_USE_GUILD_CHAT
    }) { }

    using PlayerScript::OnPlayerCanUseChat;

    // Handler::args apuntan al mensaje recibido: solo son validos durante la llamada al manejador
    bool OnPlayerCanUseChat(Player* player, uint32 /*type*/, uint32 language, std::string& msg,
        Player* /*receiver*/) override
    {
        if (language != LANG_ADDON || !sEventWowConfig.Enabled)
            return true;

        return !HandleIncoming(player, msg);
    }

    bool OnPlayerCanUseChat(Player* /*player*/, uint32 /*type*/, uint32 language, std::string& msg,
        Group* /*group*/) override
    {
        return language != LANG_ADDON || !IsProtocolMessage(msg);
    }

    bool OnPlayerCanUseChat(Player* /*player*/, uint32 /*type*/, uint32 language, std::string& msg,
        Guild* /*guild*/) override
    {
        return language != LANG_ADDON || !IsProtocolMessage(msg);
    }
};

void AddSC_eventwow_protocol()
{
    new EventWow_ProtocolPlayerScript();
}
