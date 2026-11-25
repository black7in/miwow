#include "MiWowConfig.h"
#include "MiWowProtocol.h"
#include "CryptoRandom.h"
#include "Group.h"
#include "Log.h"
#include "ObjectAccessor.h"
#include "Player.h"
#include "ScriptMgr.h"
#include <boost/asio/connect.hpp>
#include <boost/asio/executor_work_guard.hpp>
#include <boost/asio/io_context.hpp>
#include <boost/asio/ip/tcp.hpp>
#include <boost/asio/post.hpp>
#include <boost/asio/read_until.hpp>
#include <boost/asio/steady_timer.hpp>
#include <boost/asio/streambuf.hpp>
#include <boost/asio/write.hpp>
#include <atomic>
#include <deque>
#include <memory>
#include <mutex>
#include <optional>
#include <thread>
#include <unordered_map>

// Voz de grupo (fase 1, cliente web). Ver docs/voz.md.
//
// El audio NO pasa por aqui: va por WebRTC (LiveKit) desde el navegador. El worldserver es la autoridad de quien es
// quien y de con quien habla, y se lo dice al hub de voz (web/servidor/voice.js, dentro de server.js) por un enlace TCP
// local (este archivo es el cliente; reconecta solo):
//   -> HELLO <clave> | TICKET <nonce> <guid> <nombre> | ROOM <guid> <sala|""> | CMD <guid> mic|speaker 0/1 | GONE <guid>
//   <- WELCOME | STATE <guid> <voz> <en sala> <mic> <altavoz> <error> | SPEAK <guid> 0/1
// Al conectarse al protocolo MIWOW el jugador recibe VOICE_TOKEN <nonce>: server.js lo ve pasar por el tunel del
// cliente web y liga esa sesion del navegador a este personaje (el cliente de PC no pasa por el tunel: sin voz aun).
// Sala = grupo nativo (no banda: fase 1). Al jugador (Lua, MiWowVoice.lua): VOICE_STATE y VOICE_SPEAK.
namespace
{
    using boost::asio::ip::tcp;

    // Enlace con el hub: un hilo propio con su io_context. El hilo del mundo solo usa Send() y Poll().
    class VoiceLink
    {
    public:
        void Start(std::string host, uint16 port, std::string secret)
        {
            if (_thread.joinable())
                return;

            _host = std::move(host);
            _port = port;
            _secret = std::move(secret);
            _work.emplace(boost::asio::make_work_guard(_io));
            boost::asio::post(_io, [this]() { Connect(); });
            _thread = std::thread([this]() { _io.run(); });
        }

        void Stop()
        {
            if (!_thread.joinable())
                return;

            boost::asio::post(_io, [this]() { Close(); _timer.cancel(); });
            _work.reset();
            _io.stop();
            _thread.join();
        }

        // Desde el hilo del mundo. Sin enlace (o sin WELCOME) se descarta: al reconectar se reenvia todo.
        void Send(std::string line)
        {
            if (!_ready)
                return;

            boost::asio::post(_io, [this, line = std::move(line)]() mutable { Queue(std::move(line)); });
        }

        // Desde el hilo del mundo: lineas recibidas
        void Poll(std::vector<std::string>& out)
        {
            std::lock_guard<std::mutex> lock(_inLock);
            out.assign(std::make_move_iterator(_incoming.begin()), std::make_move_iterator(_incoming.end()));
            _incoming.clear();
        }

        bool IsReady() const { return _ready; }

        // true una vez tras cada WELCOME (hay que reenviar el estado de todos)
        bool TakeReconnected() { return _reconnected.exchange(false); }

    private:
        void Connect()
        {
            boost::system::error_code ec;
            auto address = boost::asio::ip::make_address(_host, ec);
            if (ec)
            {
                LOG_ERROR("module.miwow", "MiWow voz: MiWow.Voice.LinkHost '{}' no es una IP", _host);
                return;
            }

            uint32 const gen = ++_gen;
            _socket.async_connect(tcp::endpoint(address, _port), [this, gen](boost::system::error_code const& error)
            {
                if (gen != _gen)
                    return;
                if (error)
                    return Retry();

                boost::system::error_code ec;
                _socket.set_option(tcp::no_delay(true), ec);
                _readBuffer.consume(_readBuffer.size());
                _writing.clear();
                Queue("HELLO\t" + _secret);
                Read(gen);
            });
        }

        void Retry()
        {
            ++_gen; // los manejadores pendientes de esta conexion ya no hacen nada
            Close();
            _timer.expires_after(std::chrono::seconds(5));
            _timer.async_wait([this](boost::system::error_code const& error)
            {
                if (!error)
                    Connect();
            });
        }

        void Close()
        {
            if (_ready.exchange(false))
                LOG_INFO("module.miwow", "MiWow voz: enlace con el hub cerrado, reintentando");

            // La cola y el buffer de lectura se limpian al reconectar: una operacion abortada aun puede usarlos
            boost::system::error_code ec;
            _socket.close(ec);
        }

        void Read(uint32 gen)
        {
            boost::asio::async_read_until(_socket, _readBuffer, '\n', [this, gen](boost::system::error_code const& error, std::size_t length)
            {
                if (gen != _gen)
                    return;
                if (error)
                    return Retry();

                std::string line(boost::asio::buffers_begin(_readBuffer.data()), boost::asio::buffers_begin(_readBuffer.data()) + length);
                _readBuffer.consume(length);
                while (!line.empty() && (line.back() == '\n' || line.back() == '\r'))
                    line.pop_back();

                if (line == "WELCOME")
                {
                    LOG_INFO("module.miwow", "MiWow voz: enlazado con el hub {}:{}", _host, _port);
                    _ready = true;
                    _reconnected = true;
                }
                else if (_ready)
                {
                    std::lock_guard<std::mutex> lock(_inLock);
                    if (_incoming.size() < 10000)
                        _incoming.push_back(std::move(line));
                }

                Read(gen);
            });
        }

        void Queue(std::string line)
        {
            if (!_socket.is_open())
                return;

            _writing.push_back(std::make_shared<std::string>(std::move(line) + '\n'));
            if (_writing.size() == 1)
                Write(_gen);
        }

        void Write(uint32 gen)
        {
            // El texto va en un shared_ptr que guarda el manejador: sigue vivo aunque se vacie la cola
            std::shared_ptr<std::string> data = _writing.front();
            boost::asio::async_write(_socket, boost::asio::buffer(*data), [this, gen, data](boost::system::error_code const& error, std::size_t /*length*/)
            {
                if (gen != _gen)
                    return;
                if (error)
                    return Retry();

                _writing.pop_front();
                if (!_writing.empty())
                    Write(gen);
            });
        }

        boost::asio::io_context _io;
        std::optional<boost::asio::executor_work_guard<boost::asio::io_context::executor_type>> _work;
        tcp::socket _socket{ _io };
        boost::asio::steady_timer _timer{ _io };
        boost::asio::streambuf _readBuffer;
        std::deque<std::shared_ptr<std::string>> _writing; // solo en el hilo del enlace
        uint32 _gen = 0;                                    // conexion actual (solo en el hilo del enlace)
        std::mutex _inLock;
        std::deque<std::string> _incoming;
        std::atomic<bool> _ready{ false };
        std::atomic<bool> _reconnected{ false };
        std::thread _thread;
        std::string _host;
        uint16 _port = 0;
        std::string _secret;
    };

    VoiceLink Link;

    // Estado de voz de cada jugador conectado al protocolo (solo hilo del mundo)
    struct VoiceEntry
    {
        std::string Room;        // sala enviada al hub ("" = ninguna)
        bool Available = false;  // tiene la voz del navegador conectada (cliente web)
        bool InRoom = false;
        bool Mic = false;
        bool Speaker = true;
        bool Speaking = false;
        std::string Error;
    };

    std::unordered_map<ObjectGuid::LowType, VoiceEntry> Entries;

    std::string Join(std::initializer_list<std::string_view> fields)
    {
        std::string line;
        for (std::string_view field : fields)
        {
            if (!line.empty())
                line += '\t';
            for (char c : field)
                line += (c == '\t' || c == '\n' || c == '\r') ? ' ' : c;
        }
        return line;
    }

    std::vector<std::string_view> Split(std::string_view line)
    {
        std::vector<std::string_view> fields;
        std::size_t start = 0;
        while (true)
        {
            std::size_t tab = line.find('\t', start);
            fields.push_back(line.substr(start, tab == std::string_view::npos ? std::string_view::npos : tab - start));
            if (tab == std::string_view::npos)
                break;
            start = tab + 1;
        }
        return fields;
    }

    uint32 ToUInt(std::string_view text)
    {
        uint32 value = 0;
        for (char c : text)
        {
            if (c < '0' || c > '9')
                return 0;
            value = value * 10 + uint32(c - '0');
        }
        return value;
    }

    bool Enabled()
    {
        return sMiWowConfig.Enabled && sMiWowConfig.Voice.Enabled;
    }

    // Sala que le toca: su grupo nativo (las bandas, fuera en la fase 1)
    std::string RoomFor(Player* player)
    {
        Group* group = player->GetGroup();
        if (!group || group->isRaidGroup())
            return "";
        return "g" + std::to_string(group->GetGUID().GetCounter());
    }

    void SendState(Player* player, VoiceEntry const& entry)
    {
        MiWowMessage("VOICE_STATE")
            .Add(uint32(entry.Available))
            .Add(uint32(entry.InRoom))
            .Add(uint32(entry.Mic))
            .Add(uint32(entry.Speaker))
            .Add(entry.Error)
            .Send(player);
    }

    // VOICE_SPEAK al propio jugador y a los de su grupo que estan en su misma sala
    void BroadcastSpeaking(Player* player, VoiceEntry const& entry)
    {
        MiWowMessage message("VOICE_SPEAK");
        message.Add(player->GetName()).Add(uint32(entry.Speaking));
        message.Send(player);

        Group* group = player->GetGroup();
        if (!group || entry.Room.empty())
            return;

        for (GroupReference* itr = group->GetFirstMember(); itr; itr = itr->next())
        {
            Player* member = itr->GetSource();
            if (!member || member == player)
                continue;

            auto found = Entries.find(member->GetGUID().GetCounter());
            if (found != Entries.end() && found->second.Room == entry.Room)
                message.Send(member);
        }
    }

    // Nonce de un solo uso: el jugador lo recibe por MIWOW y el hub lo ve pasar por el tunel del cliente web
    void IssueTicket(Player* player)
    {
        std::array<uint8, 16> bytes;
        Acore::Crypto::GetRandomBytes(bytes);
        static char const* hex = "0123456789abcdef";
        std::string nonce;
        for (uint8 b : bytes)
        {
            nonce += hex[b >> 4];
            nonce += hex[b & 0xF];
        }

        VoiceEntry& entry = Entries[player->GetGUID().GetCounter()];
        entry.Room.clear(); // se vuelve a mandar en la siguiente comprobacion

        Link.Send(Join({ "TICKET", nonce, std::to_string(player->GetGUID().GetCounter()), player->GetName() }));
        MiWowMessage("VOICE_TOKEN").Add(nonce).Send(player);
    }

    void OnConnected(Player* player)
    {
        if (!Enabled())
            return;

        VoiceEntry& entry = Entries[player->GetGUID().GetCounter()];
        SendState(player, entry); // tras un /reload el Lua empieza de cero
        if (Link.IsReady())
            IssueTicket(player);
    }

    void OnDisconnected(Player* player)
    {
        auto found = Entries.find(player->GetGUID().GetCounter());
        if (found == Entries.end())
            return;

        if (found->second.Speaking)
        {
            found->second.Speaking = false;
            BroadcastSpeaking(player, found->second);
        }

        Link.Send(Join({ "GONE", std::to_string(player->GetGUID().GetCounter()) }));
        Entries.erase(found);
    }

    void HandleLinkLine(std::string const& line)
    {
        std::vector<std::string_view> f = Split(line);
        if (f.size() < 3)
            return;

        uint32 const low = ToUInt(f[1]);
        auto found = Entries.find(low);
        if (found == Entries.end())
            return;

        VoiceEntry& entry = found->second;
        Player* player = ObjectAccessor::FindConnectedPlayer(ObjectGuid::Create<HighGuid::Player>(low));
        if (!player)
            return;

        if (f[0] == "STATE" && f.size() >= 7)
        {
            bool const wasSpeaking = entry.Speaking;
            entry.Available = f[2] == "1";
            entry.InRoom = entry.Available && f[3] == "1";
            entry.Mic = entry.InRoom && f[4] == "1";
            entry.Speaker = f[5] == "1";
            entry.Error = std::string(f[6].substr(0, 32));
            if (!entry.Mic)
                entry.Speaking = false;

            SendState(player, entry);
            if (wasSpeaking && !entry.Speaking)
                BroadcastSpeaking(player, entry);
        }
        else if (f[0] == "SPEAK")
        {
            bool const speaking = f[2] == "1" && entry.Mic;
            if (speaking == entry.Speaking)
                return;

            entry.Speaking = speaking;
            BroadcastSpeaking(player, entry);
        }
    }

    // Botones del juego: VOICE_MIC 0/1, VOICE_SPEAKER 0/1 -> al navegador por el hub
    void HandleToggle(Player* player, MiWowProtocol::Args const& args, char const* what)
    {
        if (!Enabled() || args.empty())
            return;

        auto found = Entries.find(player->GetGUID().GetCounter());
        if (found == Entries.end())
            return;

        if (!found->second.Available)
        {
            SendState(player, found->second); // el Lua vuelve a esconder los botones
            return;
        }

        Link.Send(Join({ "CMD", std::to_string(player->GetGUID().GetCounter()), what, args[0] == "1" ? "1" : "0" }));
    }

    void Update(uint32 diff)
    {
        static uint32 roomTimer = 0;

        if (Link.TakeReconnected())
        {
            // Hub nuevo (o reiniciado): no sabe nada; nonces y salas otra vez para todos
            MiWowProtocol::ForEachConnected([](Player* player)
            {
                if (Enabled())
                    IssueTicket(player);
            });
            roomTimer = 0;
        }

        std::vector<std::string> lines;
        Link.Poll(lines);
        for (std::string const& line : lines)
            HandleLinkLine(line);

        // Sala de cada uno segun su grupo (cada segundo: cubre unirse, salir, disolver y pasar a banda)
        if (roomTimer > diff)
        {
            roomTimer -= diff;
            return;
        }
        roomTimer = 1000;

        if (!Link.IsReady())
            return;

        for (auto& [low, entry] : Entries)
        {
            Player* player = ObjectAccessor::FindConnectedPlayer(ObjectGuid::Create<HighGuid::Player>(low));
            if (!player)
                continue;

            std::string room = RoomFor(player);
            if (room == entry.Room)
                continue;

            if (entry.Speaking)
            {
                entry.Speaking = false;
                BroadcastSpeaking(player, entry); // a los de la sala vieja
            }

            entry.Room = std::move(room);
            Link.Send(Join({ "ROOM", std::to_string(low), entry.Room }));
        }
    }
}

class MiWow_VoiceWorldScript : public WorldScript
{
public:
    MiWow_VoiceWorldScript() : WorldScript("MiWow_VoiceWorldScript", {
        WORLDHOOK_ON_STARTUP,
        WORLDHOOK_ON_SHUTDOWN,
        WORLDHOOK_ON_UPDATE
    }) { }

    void OnStartup() override
    {
        MiWowConfig::VoiceConfig const& cfg = sMiWowConfig.Voice;
        if (!sMiWowConfig.Enabled || !cfg.Enabled)
            return;

        if (cfg.LinkSecret.empty())
        {
            LOG_ERROR("module.miwow", "MiWow voz: MiWow.Voice.LinkSecret vacio, voz desactivada");
            return;
        }

        LOG_INFO("module.miwow", "MiWow voz: enlace con el hub en {}:{}", cfg.LinkHost, cfg.LinkPort);
        Link.Start(cfg.LinkHost, cfg.LinkPort, cfg.LinkSecret);
    }

    void OnShutdown() override
    {
        Link.Stop();
    }

    void OnUpdate(uint32 diff) override
    {
        Update(diff);
    }
};

void AddSC_miwow_voice()
{
    new MiWow_VoiceWorldScript();
    MiWowProtocol::RegisterConnectListener(OnConnected);
    MiWowProtocol::RegisterDisconnectListener(OnDisconnected);
    MiWowProtocol::RegisterHandler("VOICE_MIC", [](Player* player, MiWowProtocol::Args const& args) { HandleToggle(player, args, "mic"); });
    MiWowProtocol::RegisterHandler("VOICE_SPEAKER", [](Player* player, MiWowProtocol::Args const& args) { HandleToggle(player, args, "speaker"); });
}
