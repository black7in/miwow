-- MiWow: protocolo cliente <-> servidor sobre addon messages (ver docs/protocolo.md).
-- Contraparte en el servidor: modules/mod-miwow/src/MiWowProtocol.cpp
--
-- Transporte: SendAddonMessage("MIWOW", <flag><payload>, "WHISPER", <propio nombre>).
-- El servidor lo intercepta (nunca lo reenvia) y responde con un whisper de addon cuyo emisor
-- es el propio jugador. flag: "=" completo, "+" fragmento (siguen mas), "." ultimo fragmento.
-- Payload: "<OP>\t<campo>\t<campo>..." (los campos no pueden contener "\t").

MIWOW_PROTOCOL = {
	PREFIX = "MIWOW",
	VERSION = 12,
	-- 255 (limite del core) - "MIWOW\t" - flag, con margen
	MAX_CHUNK = 240,
	DEBUG = true,
};

MIWOW_STR_PROTOCOL_ERROR = "Error del servidor: %s";

-- Textos de ERROR <codigo> [detalle]; %s = detalle
MIWOW_ERROR_TEXTS = {
	VERSION = "Versión del cliente incompatible con el servidor. Actualiza el parche.",
	MUTED = "Estás silenciado.",
	QUEUE_UNKNOWN_GAME = "Ese minijuego no existe.",
	QUEUE_DEAD = "No puedes apuntarte a un evento estando muerto.",
	QUEUE_IN_COMBAT = "No puedes apuntarte a un evento en combate.",
	QUEUE_IN_FLIGHT = "No puedes apuntarte a un evento mientras vuelas.",
	QUEUE_IN_INSTANCE = "No puedes apuntarte a un evento dentro de una mazmorra, banda o campo de batalla.",
	QUEUE_IN_BG_QUEUE = "No puedes apuntarte a un evento mientras estás en cola de campo de batalla.",
	QUEUE_GAME_UNAVAILABLE = "Este minijuego todavía no está disponible.",
	QUEUE_IN_MATCH = "Ya estás en una partida.",
	QUEUE_NOT_LEADER = "Solo el líder del grupo puede buscar partida.",
	QUEUE_SOLO_ONLY = "Este minijuego es individual: sal del grupo para buscar partida.",
	QUEUE_GROUP_TOO_BIG = "Grupo demasiado grande para este minijuego (máximo %s).",
	QUEUE_GROUP_OFFLINE = "%s no está conectado.",
	QUEUE_GROUP_BUSY = "%s no puede apuntarse ahora (en combate, muerto, en vuelo, en una mazmorra o en otra cola).",
	QUEUE_GROUP_CANCELLED = "%s ha cancelado la búsqueda.",
	QUEUE_GROUP_LOGOUT = "%s se ha desconectado: búsqueda cancelada.",
	QUEUE_GROUP_CHANGED = "El grupo ha cambiado: búsqueda cancelada.",
	QUEUE_GROUP_DECLINED = "%s rechazó la partida: búsqueda cancelada.",
	QUEUE_GROUP_NOT_ACCEPTED = "Alguien de tu grupo no aceptó a tiempo: búsqueda cancelada.",
	GROUP_IN_MATCH = "No puedes cambiar de grupo durante una partida.",
	GROUP_TARGET_IN_MATCH = "%s está en una partida.",
	MATCH_CREATE_FAILED = "No se pudo crear la partida. Inténtalo de nuevo.",
	MATCH_TELEPORT_FAILED = "No se pudo entrar en la partida.",
};

MiWow_Protocol = {
	handlers = {},
	listeners = {},
	buffer = nil,
	helloSent = false,
	connected = false,
	isGM = false,
	-- Catalogo recibido (GAMES): { id, icon, minPlayers, maxPlayers, name, description, playable, maxPartySize, inventorySlots,
	--   openSession }
	games = {},
};

function MiWow_Debug(text)
	if ( MIWOW_PROTOCOL.DEBUG ) then
		DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffMiWow:|r "..text);
	end
end

-- Un manejador por opcode recibido del servidor: func(campos)
function MiWow_RegisterHandler(op, func)
	MiWow_Protocol.handlers[op] = func;
end

-- Avisos internos del cliente (varios por evento): "CONNECTED", "GAMES", "MATCH" (entra/sale/cambia de estado),
-- "DEV_MODE"
function MiWow_RegisterListener(event, func)
	local list = MiWow_Protocol.listeners[event];
	if ( not list ) then
		list = {};
		MiWow_Protocol.listeners[event] = list;
	end
	tinsert(list, func);
end

function MiWow_FireListeners(event, ...)
	local list = MiWow_Protocol.listeners[event];
	if ( list ) then
		for _, func in ipairs(list) do
			func(...);
		end
	end
end

local function MiWow_IsUTF8Continuation(text, index)
	local byte = string.byte(text, index);
	return byte and byte >= 128 and byte < 192;
end

local function MiWow_SendChunk(flag, chunk)
	SendAddonMessage(MIWOW_PROTOCOL.PREFIX, flag..chunk, "WHISPER", UnitName("player"));
end

-- MiWow_Send("OP", campo1, campo2, ...)
function MiWow_Send(op, ...)
	local payload = op;
	for i = 1, select("#", ...) do
		local field = tostring((select(i, ...)));
		payload = payload.."\t"..(string.gsub(field, "\t", " "));
	end

	local length = string.len(payload);
	local maxChunk = MIWOW_PROTOCOL.MAX_CHUNK;
	if ( length <= maxChunk ) then
		MiWow_SendChunk("=", payload);
		return;
	end

	local first = 1;
	while ( first <= length ) do
		local last = first + maxChunk - 1;
		if ( last >= length ) then
			last = length;
		else
			-- No partir un caracter UTF-8 entre dos fragmentos
			while ( last > first and MiWow_IsUTF8Continuation(payload, last + 1) ) do
				last = last - 1;
			end
		end
		MiWow_SendChunk((last == length) and "." or "+", string.sub(payload, first, last));
		first = last + 1;
	end
end

local function MiWow_Dispatch(payload)
	local fields = { strsplit("\t", payload) };
	local op = table.remove(fields, 1);
	local handler = op and MiWow_Protocol.handlers[op];
	if ( not handler ) then
		MiWow_Debug("opcode desconocido: "..tostring(op));
		return;
	end
	handler(fields);
end

local function MiWow_OnAddonMessage(prefix, message, distribution, sender)
	if ( prefix ~= MIWOW_PROTOCOL.PREFIX ) then
		return;
	end
	-- Solo el servidor habla asi (whisper "de uno mismo"); el servidor descarta MIWOW de otros jugadores
	if ( distribution ~= "WHISPER" or sender ~= UnitName("player") ) then
		return;
	end

	local flag = string.sub(message, 1, 1);
	local data = string.sub(message, 2);
	if ( flag == "=" ) then
		MiWow_Protocol.buffer = nil;
		MiWow_Dispatch(data);
	elseif ( flag == "+" ) then
		MiWow_Protocol.buffer = (MiWow_Protocol.buffer or "")..data;
	elseif ( flag == "." ) then
		local complete = (MiWow_Protocol.buffer or "")..data;
		MiWow_Protocol.buffer = nil;
		MiWow_Dispatch(complete);
	end
end

-- Manejadores base ------------------------------------------------------------------------------

-- WELCOME <version> <rango: 0 jugador, 1 GM>
MiWow_RegisterHandler("WELCOME", function(fields)
	MiWow_Protocol.connected = true;
	MiWow_Protocol.isGM = tonumber(fields[2]) == 1;
	MiWow_Debug("conectado (protocolo v"..tostring(fields[1])..")");
	MiWow_FireListeners("CONNECTED");
end);

-- ERROR <codigo> [detalle...]
MiWow_RegisterHandler("ERROR", function(fields)
	local code = fields[1] or "?";
	if ( code == "VERSION" ) then
		MiWow_Protocol.connected = false;
	end

	local text = MIWOW_ERROR_TEXTS[code];
	if ( text ) then
		text = format(text, tostring(fields[2] or ""));
	else
		text = format(MIWOW_STR_PROTOCOL_ERROR, table.concat(fields, " "));
	end
	DEFAULT_CHAT_FRAME:AddMessage(text, 1, 0.2, 0.2);
	UIErrorsFrame:AddMessage(text, 1, 0.2, 0.2, 1.0);
end);

-- GAMES <n> (<id> <icono> <min> <max> <nombre> <descripcion> <jugable 0/1> <grupo max> <casillas> <sesion abierta 0/1>) x n
MiWow_RegisterHandler("GAMES", function(fields)
	local count = tonumber(fields[1]) or 0;
	local games = {};
	for i = 1, count do
		local base = 1 + (i - 1) * 10;
		tinsert(games, {
			id = fields[base + 1],
			icon = fields[base + 2],
			minPlayers = tonumber(fields[base + 3]),
			maxPlayers = tonumber(fields[base + 4]),
			name = fields[base + 5],
			description = fields[base + 6],
			playable = fields[base + 7] == "1",
			maxPartySize = tonumber(fields[base + 8]) or 1,
			inventorySlots = tonumber(fields[base + 9]) or 0,
			openSession = fields[base + 10] == "1",
		});
	end
	MiWow_Protocol.games = games;
	MiWow_Debug(count.." minijuego(s) recibido(s)");
	MiWow_FireListeners("GAMES");
end);

-- Eventos ---------------------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame", "MiWowProtocolFrame");
eventFrame:RegisterEvent("CHAT_MSG_ADDON");
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD");
eventFrame:SetScript("OnEvent", function(self, event, ...)
	if ( event == "CHAT_MSG_ADDON" ) then
		MiWow_OnAddonMessage(...);
	elseif ( event == "PLAYER_ENTERING_WORLD" ) then
		-- Una vez por carga del Lua (entrar al mundo o /reload), no en cada teleport
		if ( not MiWow_Protocol.helloSent ) then
			MiWow_Protocol.helloSent = true;
			MiWow_Send("HELLO", MIWOW_PROTOCOL.VERSION);
		end
	end
end);
