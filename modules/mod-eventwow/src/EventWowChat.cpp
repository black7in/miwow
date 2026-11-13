#include "DataMap.h"
#include "EventWowProtocol.h"
#include "GameTime.h"
#include "Log.h"
#include "Player.h"
#include "ScriptMgr.h"
#include "Util.h"
#include "WorldSession.h"
#include <algorithm>
#include <deque>

// Chat global del lobby, por el protocolo propio (no canales nativos): los jugadores son invisibles
// entre si y el servidor controla longitud, frecuencia, silencios y el historial.
//
//   Cliente -> servidor: CHAT <texto>
//   Servidor -> cliente: CHAT <unix time> <rango> <nombre> <texto>   (rango: 0 jugador, 1 GM)
//                        ONLINE <jugadores conectados>
//                        ERROR MUTED | CHAT_RATE | CHAT_TOO_LONG
namespace
{
    constexpr std::size_t MaxMessageLength = 200; // caracteres (no bytes)
    constexpr std::size_t HistorySize = 50;

    // Limite de frecuencia: rafaga de 3 mensajes, se recupera 1 por segundo
    constexpr float RateBurst = 3.0f;
    constexpr float RatePerSecond = 1.0f;

    enum ChatRank : uint8
    {
        CHAT_RANK_PLAYER = 0,
        CHAT_RANK_GM     = 1
    };

    struct ChatEntry
    {
        uint32 Time;
        uint8 Rank;
        std::string Name;
        std::string Text;
    };

    // Solo se toca desde el hilo del mundo (CMSG_MESSAGECHAT es PROCESS_THREADUNSAFE)
    std::deque<ChatEntry> History;

    struct ChatRateLimit : public DataMap::Base
    {
        Milliseconds Last = 0ms;
        float Tokens = RateBurst;
    };

    EventWowMessage BuildChatMessage(ChatEntry const& entry)
    {
        EventWowMessage message("CHAT");
        message.Add(entry.Time).Add(entry.Rank).Add(entry.Name).Add(entry.Text);
        return message;
    }

    bool ConsumeRateToken(Player* player)
    {
        ChatRateLimit* rate = player->CustomData.GetDefault<ChatRateLimit>("EventWowChatRate");
        Milliseconds const now = GameTime::GetGameTimeMS();
        float const elapsed = static_cast<float>((now - rate->Last).count()) / 1000.0f;
        rate->Last = now;
        rate->Tokens = std::min(RateBurst, rate->Tokens + elapsed * RatePerSecond);

        if (rate->Tokens < 1.0f)
            return false;

        rate->Tokens -= 1.0f;
        return true;
    }

    // Quita espacios en los extremos y sustituye caracteres de control por espacios.
    // Los '|' (codigos de color/enlace del cliente) los escapa el cliente al mostrar.
    std::string CleanText(std::string_view text)
    {
        std::string clean(text);
        std::replace_if(clean.begin(), clean.end(), [](char c) { return static_cast<uint8>(c) < 0x20; }, ' ');

        std::size_t const first = clean.find_first_not_of(' ');
        if (first == std::string::npos)
            return {};

        std::size_t const last = clean.find_last_not_of(' ');
        return clean.substr(first, last - first + 1);
    }

    void BroadcastOnline()
    {
        EventWowMessage("ONLINE").Add(static_cast<uint32>(EventWowProtocol::GetConnectedCount())).Broadcast();
    }

    void HandleChat(Player* player, EventWowProtocol::Args const& args)
    {
        if (args.empty())
            return;

        if (!player->CanSpeak())
        {
            EventWowMessage("ERROR").Add("MUTED").Send(player);
            return;
        }

        std::string text = CleanText(args[0]);
        std::wstring wtext;
        if (text.empty() || !Utf8toWStr(text, wtext))
            return;

        if (wtext.size() > MaxMessageLength)
        {
            EventWowMessage("ERROR").Add("CHAT_TOO_LONG").Add(static_cast<uint32>(MaxMessageLength)).Send(player);
            return;
        }

        if (!ConsumeRateToken(player))
        {
            EventWowMessage("ERROR").Add("CHAT_RATE").Send(player);
            return;
        }

        ChatEntry entry;
        entry.Time = static_cast<uint32>(GameTime::GetGameTime().count());
        entry.Rank = player->GetSession()->GetSecurity() > SEC_PLAYER ? CHAT_RANK_GM : CHAT_RANK_PLAYER;
        entry.Name = player->GetName();
        entry.Text = std::move(text);

        LOG_INFO("module.eventwow.chat", "[Global] {} ({}): {}", entry.Name, player->GetGUID().ToString(), entry.Text);

        BuildChatMessage(entry).Broadcast();

        History.push_back(std::move(entry));
        while (History.size() > HistorySize)
            History.pop_front();
    }

    void OnConnect(Player* player)
    {
        for (ChatEntry const& entry : History)
            BuildChatMessage(entry).Send(player);

        BroadcastOnline();
    }

    void OnDisconnect(Player* /*player*/)
    {
        BroadcastOnline();
    }
}

void AddSC_eventwow_chat()
{
    EventWowProtocol::RegisterHandler("CHAT", HandleChat);
    EventWowProtocol::RegisterConnectListener(OnConnect);
    EventWowProtocol::RegisterDisconnectListener(OnDisconnect);
}
