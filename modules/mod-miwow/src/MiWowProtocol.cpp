#include "MiWowProtocol.h"
#include "Chat.h"
#include "DataMap.h"
#include "MiWowConfig.h"
#include "Log.h"
#include "ObjectAccessor.h"
#include "ObjectGuid.h"
#include "Player.h"
#include "ScriptMgr.h"
#include "SharedDefines.h"
#include "StringConvert.h"
#include "Tokenize.h"
#include "WorldPacket.h"
#include "WorldSession.h"
#include <algorithm>
#include <map>
#include <mutex>

namespace
{
    constexpr char FlagComplete = '=';
    constexpr char FlagMore = '+';
    constexpr char FlagLast = '.';

    // 255 (limite del core) - "MIWOW\t" - flag, con margen
    constexpr std::size_t MaxChunkSize = 240;
    // Tamano maximo de un mensaje reensamblado recibido del cliente
    constexpr std::size_t MaxIncomingSize = 2048;

    // Fragmentos pendientes de un jugador (en Player::CustomData: sin mapas globales ni punteros guardados)
    struct IncomingBuffer : public DataMap::Base
    {
        std::string Data;
    };

    std::map<std::string, MiWowProtocol::Handler, std::less<>>& GetHandlers()
    {
        static std::map<std::string, MiWowProtocol::Handler, std::less<>> handlers;
        return handlers;
    }

    std::vector<MiWowProtocol::PlayerListener>& GetConnectListeners()
    {
        static std::vector<MiWowProtocol::PlayerListener> listeners;
        return listeners;
    }

    std::vector<MiWowProtocol::PlayerListener>& GetDisconnectListeners()
    {
        static std::vector<MiWowProtocol::PlayerListener> listeners;
        return listeners;
    }

    // Jugadores que completaron HELLO. Mutex por si algun logout llega fuera del hilo del mundo.
    std::mutex ConnectedLock;
    GuidUnorderedSet Connected;

    // HELLO <version>
    void HandleHello(Player* player, MiWowProtocol::Args const& args)
    {
        Optional<uint32> version = args.empty() ? std::nullopt : Acore::StringTo<uint32>(args[0]);
        if (version != MiWowProtocol::Version)
        {
            LOG_DEBUG("module.miwow", "MiWow: {} usa protocolo {}, servidor {}",
                player->GetName(), args.empty() ? "?" : args[0], MiWowProtocol::Version);
            MiWowMessage("ERROR").Add("VERSION").Add(MiWowProtocol::Version).Send(player);
            return;
        }

        {
            std::lock_guard<std::mutex> lock(ConnectedLock);
            Connected.insert(player->GetGUID());
        }

        // WELCOME <version> <rango: 0 jugador, 1 GM> (el panel muestra el distintivo)
        uint8 const rank = player->GetSession()->GetSecurity() > SEC_PLAYER ? 1 : 0;
        MiWowMessage("WELCOME").Add(MiWowProtocol::Version).Add(rank).Send(player);
        for (auto const& listener : GetConnectListeners())
            listener(player);
    }

    // "MIWOW\t..."
    bool IsProtocolMessage(std::string_view msg)
    {
        std::string_view const prefix = MiWowProtocol::Prefix;
        return msg.size() > prefix.size() && msg.substr(0, prefix.size()) == prefix && msg[prefix.size()] == '\t';
    }

    bool IsUtf8Continuation(char c)
    {
        return (static_cast<uint8>(c) & 0xC0) == 0x80;
    }

    void SendChunk(Player* player, char flag, std::string_view chunk)
    {
        std::string text;
        text.reserve(MiWowProtocol::Prefix.size() + 2 + chunk.size());
        text.append(MiWowProtocol::Prefix);
        text += '\t';
        text += flag;
        text.append(chunk);

        WorldPacket data;
        ChatHandler::BuildChatPacket(data, CHAT_MSG_WHISPER, LANG_ADDON, player, player, text);
        player->SendDirectMessage(&data);
    }

    void Dispatch(Player* player, std::string_view payload)
    {
        MiWowProtocol::Args args = Acore::Tokenize(payload, '\t', true);
        if (args.empty() || args.front().empty())
            return;

        std::string_view const op = args.front();
        args.erase(args.begin());

        if (op == "HELLO")
        {
            HandleHello(player, args);
            return;
        }

        if (!MiWowProtocol::IsConnected(player->GetGUID()))
        {
            LOG_DEBUG("module.miwow", "MiWow: '{}' de {} antes de HELLO, ignorado", op, player->GetName());
            return;
        }

        auto& handlers = GetHandlers();
        auto itr = handlers.find(op);
        if (itr == handlers.end())
        {
            LOG_DEBUG("module.miwow", "MiWow: opcode desconocido '{}' de {}", op, player->GetName());
            MiWowMessage("ERROR").Add("UNKNOWN_OP").Add(op).Send(player);
            return;
        }

        itr->second(player, args);
    }

    // Devuelve true si msg es un mensaje del protocolo (se consume aunque sea invalido)
    bool HandleIncoming(Player* player, std::string_view msg)
    {
        if (!IsProtocolMessage(msg))
            return false;

        std::string_view body = msg.substr(MiWowProtocol::Prefix.size() + 1);
        if (body.empty())
            return true;

        char const flag = body.front();
        std::string_view const data = body.substr(1);

        IncomingBuffer* buffer = player->CustomData.GetDefault<IncomingBuffer>("MiWowProtocol");
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
                    LOG_WARN("module.miwow", "MiWow: mensaje de {} supera {} bytes, descartado",
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
                LOG_DEBUG("module.miwow", "MiWow: flag invalido '{}' de {}", flag, player->GetName());
                break;
        }

        return true;
    }
}

void MiWowProtocol::RegisterHandler(std::string_view op, Handler handler)
{
    GetHandlers()[std::string(op)] = std::move(handler);
}

void MiWowProtocol::RegisterConnectListener(PlayerListener listener)
{
    GetConnectListeners().push_back(std::move(listener));
}

void MiWowProtocol::RegisterDisconnectListener(PlayerListener listener)
{
    GetDisconnectListeners().push_back(std::move(listener));
}

bool MiWowProtocol::IsConnected(ObjectGuid guid)
{
    std::lock_guard<std::mutex> lock(ConnectedLock);
    return Connected.count(guid) != 0;
}

std::size_t MiWowProtocol::GetConnectedCount()
{
    std::lock_guard<std::mutex> lock(ConnectedLock);
    return Connected.size();
}

void MiWowProtocol::ForEachConnected(std::function<void(Player* player)> const& func)
{
    std::vector<ObjectGuid> guids;
    {
        std::lock_guard<std::mutex> lock(ConnectedLock);
        guids.assign(Connected.begin(), Connected.end());
    }

    for (ObjectGuid const& guid : guids)
        if (Player* player = ObjectAccessor::FindConnectedPlayer(guid))
            func(player);
}

MiWowMessage& MiWowMessage::Add(std::string_view field)
{
    _payload += '\t';
    std::size_t const start = _payload.size();
    _payload.append(field);
    // '\t' es el separador de campos
    std::replace(_payload.begin() + start, _payload.end(), '\t', ' ');
    return *this;
}

void MiWowMessage::Send(Player* player) const
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

void MiWowMessage::Broadcast() const
{
    // Un paquete por jugador: el emisor del whisper debe ser el propio receptor
    MiWowProtocol::ForEachConnected([this](Player* player) { Send(player); });
}

// Intercepta los addon messages con prefijo MIWOW: los del whisper se procesan, y en ningun canal
// se reenvian (asi un jugador no puede hacerse pasar por el servidor ante otro cliente).
class MiWow_ProtocolPlayerScript : public PlayerScript
{
public:
    MiWow_ProtocolPlayerScript() : PlayerScript("MiWow_ProtocolPlayerScript", {
        PLAYERHOOK_CAN_PLAYER_USE_PRIVATE_CHAT,
        PLAYERHOOK_CAN_PLAYER_USE_GROUP_CHAT,
        PLAYERHOOK_CAN_PLAYER_USE_GUILD_CHAT,
        PLAYERHOOK_ON_LOGOUT
    }) { }

    using PlayerScript::OnPlayerCanUseChat;

    void OnPlayerLogout(Player* player) override
    {
        std::size_t erased = 0;
        {
            std::lock_guard<std::mutex> lock(ConnectedLock);
            erased = Connected.erase(player->GetGUID());
        }

        if (erased)
            for (auto const& listener : GetDisconnectListeners())
                listener(player);
    }

    bool OnPlayerCanUseChat(Player* player, uint32 /*type*/, uint32 language, std::string& msg,
        Player* /*receiver*/) override
    {
        if (language != LANG_ADDON || !sMiWowConfig.Enabled)
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

void AddSC_miwow_protocol()
{
    new MiWow_ProtocolPlayerScript();
}
