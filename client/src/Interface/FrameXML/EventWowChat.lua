-- EventWow: chat del panel de eventos (el chat nativo funciona normal; esto es un anadido). Pestanas:
--   Global:  chat global de EventWow (CHAT por el protocolo).
--   Una por conversacion privada (susurros nativos): se abre al recibir o enviar un susurro, o al hacer clic en
--   un nombre. Contador de no leidos; clic derecho o "x" la cierra (el historial se conserva en la sesion).
--   Grupo:   chat de grupo nativo (CHAT_MSG_PARTY*). Fija (sin cerrar) mientras estas en un grupo, justo tras Global;
--            al salir del grupo desaparece y se borra su historial.
-- Contraparte en el servidor: modules/mod-eventwow/src/EventWowChat.cpp
--
--  - Susurros y grupo se ven tambien en el chat nativo (no se filtra nada).
--  - Alt+clic en un nombre: invitar al grupo.
--  - Texto que empieza por "/" -> comandos nativos (/reload, /w, /r...); por "." -> comandos de GM
--    (el core los intercepta antes de decirlos); el resto -> CHAT global o susurro segun la pestana.

EVENTWOW_CHAT = {
	MAX_LETTERS = 200,   -- igual que MaxMessageLength del servidor
	MAX_LINES = 250,
	MAX_CONVERSATIONS = 8,   -- pestanas privadas abiertas a la vez (se cierra la mas antigua sin leer)
	GM_BADGE = "|TInterface\\ChatFrame\\UI-ChatIcon-Blizz.blp:0:2:0:-3|t ",
	COLOR_TIME = "|cff808080",
	COLOR_PLAYER = "|cff99ccff",
	COLOR_GM = "|cff33ffcc",
	COLOR_WHISPER = { 1, 0.5, 1 },
	COLOR_PARTY = { 0.67, 0.67, 1 },
	PARTY_KEY = "#party",   -- clave de la conversacion de grupo (un nombre de jugador nunca lleva "#")
	-- Pestanas
	TAB_HEIGHT = 24,
	TAB_GLOBAL_WIDTH = 80,
	TAB_MIN_WIDTH = 70,
	TAB_MAX_WIDTH = 140,
	TAB_GAP = 2,
	COLOR_TAB = { 0.07, 0.08, 0.11, 0.85 },
	COLOR_TAB_HOVER = { 0.12, 0.13, 0.17, 0.95 },
	COLOR_TAB_ACTIVE = { 0.17, 0.18, 0.24, 1 },
	COLOR_TAB_LINE = { 0.35, 0.35, 0.4, 0.8 },
	COLOR_ACCENT_GLOBAL = { 1, 0.82, 0, 1 },
	COLOR_ACCENT_WHISPER = { 1, 0.5, 1, 1 },
	COLOR_ACCENT_PARTY = { 0.67, 0.67, 1, 1 },
	COLOR_BADGE = { 0.85, 0.2, 0.6, 1 },
};

EVENTWOW_STR_CHAT_TAB_GLOBAL = "Global";
EVENTWOW_STR_CHAT_ONLINE = "%d conectados";
EVENTWOW_STR_CHAT_PLACEHOLDER = "Escribe un mensaje... (Intro)";
EVENTWOW_STR_CHAT_PLACEHOLDER_WHISPER = "Mensaje para %s... (Intro)";
EVENTWOW_STR_CHAT_TAB_PARTY = "Grupo";
EVENTWOW_STR_CHAT_PLACEHOLDER_PARTY = "Mensaje para el grupo... (Intro)";
EVENTWOW_STR_CHAT_FROM = "%s: ";
EVENTWOW_STR_CHAT_TO = "Tú: ";
EVENTWOW_STR_CHAT_AFK = "%s está ausente: ";
EVENTWOW_STR_CHAT_DND = "%s no quiere ser molestado: ";
EVENTWOW_STR_CHAT_CLOSE_TOOLTIP = "Cerrar (clic derecho)";
EVENTWOW_STR_CHAT_SEND = "Enviar";

EventWow_Chat = {
	onlineCount = nil,
	-- "global" o la clave (nombre en minusculas) de una conversacion
	activeTab = "global",
	-- clave -> { name, lines = { {text, r, g, b} }, unread, open }
	conversations = {},
	-- claves de las pestanas abiertas, en orden
	order = {},
	-- [0] = Global, [1..n] = conversaciones (reutilizadas)
	tabs = {},
};

local function EventWow_EscapeText(text)
	return (string.gsub(text or "", "|", "||"));
end

-- Nombre clicable (abre su conversacion)
local function EventWow_PlayerLink(name, color)
	return "|Hplayer:"..name.."|h"..(color or "")..name..(color and "|r" or "").."|h";
end

local function EventWow_TimeStamp(unixTime)
	return EVENTWOW_CHAT.COLOR_TIME.."["..date("%H:%M", unixTime).."]|r ";
end

local function EventWow_Key(name)
	return string.lower(name);
end

-- Pestanas ----------------------------------------------------------------------------------------

local function EventWow_SetColor(texture, color)
	texture:SetTexture(color[1], color[2], color[3], color[4]);
end

local function EventWow_UpdatePlaceholder()
	local editBox = EventWowChatEditBox;
	if ( not editBox ) then
		return;
	end
	local conversation = EventWow_Chat.conversations[EventWow_Chat.activeTab];
	if ( conversation and conversation.party ) then
		EventWowChatPlaceholder:SetText(EVENTWOW_STR_CHAT_PLACEHOLDER_PARTY);
	elseif ( conversation ) then
		EventWowChatPlaceholder:SetText(format(EVENTWOW_STR_CHAT_PLACEHOLDER_WHISPER, conversation.name));
	else
		EventWowChatPlaceholder:SetText(EVENTWOW_STR_CHAT_PLACEHOLDER);
	end
	if ( editBox:HasFocus() or editBox:GetText() ~= "" ) then
		EventWowChatPlaceholder:Hide();
	else
		EventWowChatPlaceholder:Show();
	end
end

-- Aspecto de una pestana segun activa / raton encima / no leidos
local function EventWow_PaintTab(tab)
	local active = EventWow_Chat.activeTab == tab.key;
	if ( active ) then
		EventWow_SetColor(tab.bg, EVENTWOW_CHAT.COLOR_TAB_ACTIVE);
		tab.accent:Show();
		tab.label:SetTextColor(1, 1, 1);
	else
		EventWow_SetColor(tab.bg, tab.hover and EVENTWOW_CHAT.COLOR_TAB_HOVER or EVENTWOW_CHAT.COLOR_TAB);
		tab.accent:Hide();
		if ( tab.hover ) then
			tab.label:SetTextColor(0.9, 0.9, 0.9);
		else
			tab.label:SetTextColor(0.6, 0.6, 0.65);
		end
	end

	local conversation = EventWow_Chat.conversations[tab.key];
	local unread = conversation and conversation.unread or 0;
	if ( unread > 0 ) then
		tab.badgeText:SetText(unread > 99 and "99+" or unread);
		tab.badge:SetWidth(math.max(16, tab.badgeText:GetStringWidth() + 8));
		tab.badge:Show();
		if ( not active ) then
			tab.label:SetTextColor(unpack(EVENTWOW_CHAT.COLOR_WHISPER));
		end
	else
		tab.badge:Hide();
	end

	if ( tab.close ) then
		if ( (active or tab.hover) and not tab.isParty ) then
			tab.close:Show();
		else
			tab.close:Hide();
		end
	end
end

local function EventWow_CreateTab(parent, index)
	local tab = CreateFrame("Button", "EventWowChatTab"..index, parent);
	tab:SetHeight(EVENTWOW_CHAT.TAB_HEIGHT);
	tab:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp");

	tab.bg = tab:CreateTexture(nil, "BACKGROUND");
	tab.bg:SetAllPoints(tab);

	-- Linea de color arriba de la pestana activa
	tab.accent = tab:CreateTexture(nil, "ARTWORK");
	tab.accent:SetHeight(2);
	tab.accent:SetPoint("TOPLEFT", tab, "TOPLEFT", 0, 0);
	tab.accent:SetPoint("TOPRIGHT", tab, "TOPRIGHT", 0, 0);

	tab.label = tab:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall");
	tab.label:SetHeight(12);
	tab.label:SetJustifyH("CENTER");

	-- Contador de no leidos
	tab.badge = CreateFrame("Frame", nil, tab);
	tab.badge:SetHeight(14);
	tab.badge:SetPoint("RIGHT", tab, "RIGHT", -18, 0);
	local badgeBg = tab.badge:CreateTexture(nil, "BACKGROUND");
	badgeBg:SetAllPoints(tab.badge);
	EventWow_SetColor(badgeBg, EVENTWOW_CHAT.COLOR_BADGE);
	tab.badgeText = tab.badge:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall");
	tab.badgeText:SetPoint("CENTER", tab.badge, "CENTER", 0, 0);
	tab.badge:Hide();

	tab:SetScript("OnEnter", function(self)
		self.hover = true;
		EventWow_PaintTab(self);
	end);
	tab:SetScript("OnLeave", function(self)
		self.hover = nil;
		EventWow_PaintTab(self);
	end);
	return tab;
end

-- Pestana Global (index 0) o de conversacion (index >= 1, reutilizadas)
local function EventWow_GetTab(index)
	local tab = EventWow_Chat.tabs[index];
	if ( tab ) then
		return tab;
	end

	tab = EventWow_CreateTab(EventWowChatFrame, index);
	EventWow_Chat.tabs[index] = tab;
	if ( index == 0 ) then
		tab.key = "global";
		EventWow_SetColor(tab.accent, EVENTWOW_CHAT.COLOR_ACCENT_GLOBAL);
		tab.label:SetPoint("LEFT", tab, "LEFT", 6, 0);
		tab.label:SetPoint("RIGHT", tab, "RIGHT", -6, 0);
		tab.label:SetText(EVENTWOW_STR_CHAT_TAB_GLOBAL);
		tab:SetScript("OnClick", function(self)
			PlaySound("igMainMenuOptionCheckBoxOn");
			EventWowChat_SelectTab("global");
		end);
		return tab;
	end

	tab.label:SetPoint("LEFT", tab, "LEFT", 8, 0);
	tab.label:SetPoint("RIGHT", tab.badge, "LEFT", -4, 0);

	local close = CreateFrame("Button", nil, tab);
	close:SetSize(14, 14);
	close:SetPoint("RIGHT", tab, "RIGHT", -3, 0);
	close:SetNormalFontObject(GameFontDisableSmall);
	close:SetHighlightFontObject(GameFontHighlightSmall);
	close:SetText("x");
	close:SetScript("OnClick", function()
		EventWowChat_CloseConversation(tab.key);
	end);
	close:SetScript("OnEnter", function(self)
		tab.hover = true;
		EventWow_PaintTab(tab);
		GameTooltip:SetOwner(self, "ANCHOR_TOP");
		GameTooltip:SetText(EVENTWOW_STR_CHAT_CLOSE_TOOLTIP);
	end);
	close:SetScript("OnLeave", function()
		tab.hover = nil;
		EventWow_PaintTab(tab);
		GameTooltip:Hide();
	end);
	tab.close = close;

	tab:SetScript("OnClick", function(self, button)
		if ( button == "LeftButton" ) then
			PlaySound("igMainMenuOptionCheckBoxOn");
			EventWowChat_SelectTab(self.key);
		else
			EventWowChat_CloseConversation(self.key);
		end
	end);
	return tab;
end

-- Coloca las pestanas: Global + una por conversacion abierta, repartiendo el ancho disponible
function EventWowChat_LayoutTabs()
	local frame = EventWowChatFrame;
	if ( not frame ) then
		return;
	end

	local global = EventWow_GetTab(0);
	global:SetWidth(EVENTWOW_CHAT.TAB_GLOBAL_WIDTH);
	global:ClearAllPoints();
	global:SetPoint("BOTTOMLEFT", EventWowChatTabLine, "TOPLEFT", 0, 0);
	EventWow_PaintTab(global);

	local count = #EventWow_Chat.order;
	local width = EVENTWOW_CHAT.TAB_MAX_WIDTH;
	if ( count > 0 ) then
		local available = (frame:GetWidth() or 0) - 20 - EVENTWOW_CHAT.TAB_GLOBAL_WIDTH - EventWowChatOnlineText:GetStringWidth() - 16;
		width = math.floor(available / count) - EVENTWOW_CHAT.TAB_GAP;
		width = math.max(EVENTWOW_CHAT.TAB_MIN_WIDTH, math.min(EVENTWOW_CHAT.TAB_MAX_WIDTH, width));
	end

	local previous = global;
	for i, key in ipairs(EventWow_Chat.order) do
		local tab = EventWow_GetTab(i);
		local conversation = EventWow_Chat.conversations[key];
		tab.key = key;
		tab.isParty = conversation.party;
		tab.label:SetText(conversation.name);
		EventWow_SetColor(tab.accent, conversation.party and EVENTWOW_CHAT.COLOR_ACCENT_PARTY or EVENTWOW_CHAT.COLOR_ACCENT_WHISPER);
		tab:SetWidth(width);
		tab:ClearAllPoints();
		tab:SetPoint("BOTTOMLEFT", previous, "BOTTOMRIGHT", EVENTWOW_CHAT.TAB_GAP, 0);
		tab:Show();
		EventWow_PaintTab(tab);
		previous = tab;
	end
	for i = count + 1, #EventWow_Chat.tabs do
		EventWow_Chat.tabs[i]:Hide();
		EventWow_Chat.tabs[i].key = nil;
	end
end

-- Rellena el marco de mensajes privados con el historial de la conversacion activa
local function EventWow_ShowConversation(conversation)
	local messages = EventWowChatPrivateMessages;
	messages:Clear();
	for _, line in ipairs(conversation.lines) do
		messages:AddMessage(line[1], line[2], line[3], line[4]);
	end
end

function EventWowChat_SelectTab(key)
	local conversation = EventWow_Chat.conversations[key];
	if ( not conversation or not conversation.open ) then
		conversation = nil;
		key = "global";
	end
	EventWow_Chat.activeTab = key;

	if ( conversation ) then
		conversation.unread = 0;
		EventWow_ShowConversation(conversation);
		EventWowChatMessages:Hide();
		EventWowChatPrivateMessages:Show();
	else
		EventWowChatPrivateMessages:Hide();
		EventWowChatMessages:Show();
	end
	EventWowChat_LayoutTabs();
	EventWow_UpdatePlaceholder();
end

-- Abre (o devuelve) la conversacion con name. Si hay demasiadas, cierra la mas antigua sin leer.
function EventWowChat_OpenConversation(name)
	local key = EventWow_Key(name);
	local conversation = EventWow_Chat.conversations[key];
	if ( not conversation ) then
		conversation = { name = name, lines = {}, unread = 0 };
		EventWow_Chat.conversations[key] = conversation;
	end
	conversation.name = name;  -- mayusculas tal como las manda el servidor

	if ( not conversation.open ) then
		if ( #EventWow_Chat.order >= EVENTWOW_CHAT.MAX_CONVERSATIONS ) then
			for _, oldKey in ipairs(EventWow_Chat.order) do
				local old = EventWow_Chat.conversations[oldKey];
				if ( oldKey ~= EventWow_Chat.activeTab and old.unread == 0 and not old.party ) then
					EventWowChat_CloseConversation(oldKey);
					break;
				end
			end
		end
		conversation.open = true;
		tinsert(EventWow_Chat.order, key);
		EventWowChat_LayoutTabs();
	end
	return conversation, key;
end

-- Cierra la pestana; el historial se conserva por si se vuelve a abrir.
-- La de grupo no se cierra a mano (force: al salir del grupo)
function EventWowChat_CloseConversation(key, force)
	local conversation = EventWow_Chat.conversations[key];
	if ( not conversation or not conversation.open or (conversation.party and not force) ) then
		return;
	end
	conversation.open = nil;
	conversation.unread = 0;
	for i, orderKey in ipairs(EventWow_Chat.order) do
		if ( orderKey == key ) then
			tremove(EventWow_Chat.order, i);
			break;
		end
	end
	GameTooltip:Hide();
	if ( EventWow_Chat.activeTab == key ) then
		EventWowChat_SelectTab("global");
	else
		EventWowChat_LayoutTabs();
	end
end

-- Mensajes --------------------------------------------------------------------------------------

function EventWowChat_AddMessage(text, r, g, b)
	if ( EventWowChatMessages ) then
		EventWowChatMessages:AddMessage(text, r or 1, g or 1, b or 1);
	end
end

-- Linea en una conversacion ya abierta
local function EventWow_AddConversationLine(conversation, key, text, incoming, color)
	local r, g, b = unpack(color);
	tinsert(conversation.lines, { text, r, g, b });
	if ( #conversation.lines > EVENTWOW_CHAT.MAX_LINES ) then
		tremove(conversation.lines, 1);
	end

	if ( EventWow_Chat.activeTab == key ) then
		EventWowChatPrivateMessages:AddMessage(text, r, g, b);
	elseif ( incoming ) then
		conversation.unread = conversation.unread + 1;
		EventWowChat_LayoutTabs();
	end
end

-- Pestana Grupo: existe mientras estes en un grupo (justo detras de Global)
local function EventWow_UpdatePartyConversation()
	local key = EVENTWOW_CHAT.PARTY_KEY;
	local conversation = EventWow_Chat.conversations[key];
	if ( GetNumPartyMembers() > 0 ) then
		if ( conversation and conversation.open ) then
			return;
		end
		if ( not conversation ) then
			conversation = { name = EVENTWOW_STR_CHAT_TAB_PARTY, lines = {}, unread = 0, party = true };
			EventWow_Chat.conversations[key] = conversation;
		end
		conversation.open = true;
		tinsert(EventWow_Chat.order, 1, key);
		EventWowChat_LayoutTabs();
	elseif ( conversation ) then
		EventWowChat_CloseConversation(key, true);
		EventWow_Chat.conversations[key] = nil;
	end
end

local function EventWow_AddPartyMessage(text, incoming)
	EventWow_UpdatePartyConversation();
	local conversation = EventWow_Chat.conversations[EVENTWOW_CHAT.PARTY_KEY];
	if ( conversation ) then
		EventWow_AddConversationLine(conversation, EVENTWOW_CHAT.PARTY_KEY, text, incoming, EVENTWOW_CHAT.COLOR_PARTY);
	end
end

-- Anade una linea a la conversacion con name (la abre si hace falta)
local function EventWow_AddPrivateMessage(name, text, incoming)
	local conversation, key = EventWowChat_OpenConversation(name);
	EventWow_AddConversationLine(conversation, key, text, incoming, EVENTWOW_CHAT.COLOR_WHISPER);
end

-- CHAT <unix time> <rango> <nombre> <texto>
local function EventWow_OnChatMessage(fields)
	local unixTime = tonumber(fields[1]) or 0;
	local isGM = tonumber(fields[2]) == 1;
	local name = EventWow_EscapeText(fields[3]);
	local text = EventWow_EscapeText(fields[4]);

	local line = EventWow_TimeStamp(unixTime);
	if ( isGM ) then
		line = line..EVENTWOW_CHAT.GM_BADGE..EventWow_PlayerLink(name, EVENTWOW_CHAT.COLOR_GM);
	else
		line = line..EventWow_PlayerLink(name, EVENTWOW_CHAT.COLOR_PLAYER);
	end
	EventWowChat_AddMessage(line..": "..text, 1, 1, 1);
end

-- ONLINE <n>
local function EventWow_OnOnline(fields)
	EventWow_Chat.onlineCount = tonumber(fields[1]);
	if ( EventWowChatOnlineText ) then
		EventWowChatOnlineText:SetText(format(EVENTWOW_STR_CHAT_ONLINE, EventWow_Chat.onlineCount or 0));
		EventWowChat_LayoutTabs();
	end
end

-- "No hay ningun jugador con el nombre X." -> tambien en su pestana si esta abierta
local notFoundPattern = (string.gsub(ERR_CHAT_PLAYER_NOT_FOUND_S, "([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"));
notFoundPattern = "^"..(string.gsub(notFoundPattern, "%%%%s", "(.+)")).."$";

-- Susurros y grupo (eventos nativos del chat)
local function EventWow_OnWhisperEvent(self, event, text, name)
	if ( event == "PARTY_MEMBERS_CHANGED" or event == "PLAYER_ENTERING_WORLD" ) then
		EventWow_UpdatePartyConversation();
		return;
	end

	if ( event == "CHAT_MSG_PARTY" or event == "CHAT_MSG_PARTY_LEADER" ) then
		if ( not name or name == "" ) then
			return;
		end
		local line = EventWow_TimeStamp(time());
		if ( event == "CHAT_MSG_PARTY_LEADER" ) then
			line = line..EVENTWOW_GROUP.LEADER_ICON.." ";
		end
		local own = name == UnitName("player");
		EventWow_AddPartyMessage(line..(own and name or EventWow_PlayerLink(name))..": "..EventWow_EscapeText(text), not own);
		return;
	end

	if ( event == "CHAT_MSG_SYSTEM" ) then
		local missing = string.match(text or "", notFoundPattern);
		local conversation = missing and EventWow_Chat.conversations[EventWow_Key(missing)];
		if ( conversation and conversation.open ) then
			EventWow_AddPrivateMessage(conversation.name, EventWow_TimeStamp(time())..EventWow_EscapeText(text), false);
		end
		return;
	end

	if ( not name or name == "" ) then
		return;
	end
	local line = EventWow_TimeStamp(time());
	text = EventWow_EscapeText(text);

	if ( event == "CHAT_MSG_WHISPER" ) then
		-- El filtro corta el manejador nativo antes de recordar a quien responder con /r
		ChatEdit_SetLastTellTarget(name);
		EventWow_AddPrivateMessage(name, line..format(EVENTWOW_STR_CHAT_FROM, EventWow_PlayerLink(name))..text, true);
		PlaySound("TellMessage");
	elseif ( event == "CHAT_MSG_WHISPER_INFORM" ) then
		ChatEdit_SetLastToldTarget(name);
		EventWow_AddPrivateMessage(name, line..EVENTWOW_STR_CHAT_TO..text, false);
		-- Enviado desde otra pestana (/w Nombre ...): se pasa a la conversacion
		if ( EventWow_Chat.activeTab ~= EventWow_Key(name) ) then
			EventWowChat_SelectTab(EventWow_Key(name));
		end
	elseif ( event == "CHAT_MSG_AFK" ) then
		EventWow_AddPrivateMessage(name, line..format(EVENTWOW_STR_CHAT_AFK, name)..text, false);
	elseif ( event == "CHAT_MSG_DND" ) then
		EventWow_AddPrivateMessage(name, line..format(EVENTWOW_STR_CHAT_DND, name)..text, false);
	end
end

local function EventWow_SendNative(text)
	-- Mismo camino que la caja nativa: comandos con barra, /w, /r, /s...
	local editBox = ChatFrame1EditBox;
	editBox:SetAttribute("chatType", "SAY");
	editBox:SetText(text);
	ChatEdit_SendText(editBox, 1);
	editBox:SetText("");
	editBox:SetAttribute("chatType", "SAY");
end

function EventWowChat_Submit(editBox)
	local text = strtrim(editBox:GetText() or "");
	editBox:SetText("");
	if ( text == "" ) then
		return;
	end
	editBox:AddHistoryLine(text);

	local first = string.sub(text, 1, 1);
	local conversation = EventWow_Chat.conversations[EventWow_Chat.activeTab];
	if ( first == "/" ) then
		EventWow_SendNative(text);
	elseif ( first == "." ) then
		SendChatMessage(text, "SAY");
	elseif ( conversation and conversation.party ) then
		SendChatMessage(text, "PARTY");
	elseif ( conversation ) then
		SendChatMessage(text, "WHISPER", nil, conversation.name);
	else
		EventWow_Send("CHAT", text);
	end
end

-- Marco -----------------------------------------------------------------------------------------

-- Clic en un nombre: abrir su conversacion. Alt+clic: invitar al grupo (como en el chat nativo).
local function EventWow_OnHyperlinkClick(self, link)
	local kind, name = strsplit(":", link);
	if ( kind ~= "player" or not name or name == "" or name == UnitName("player") ) then
		return;
	end
	if ( IsAltKeyDown() ) then
		InviteUnit(name);
		return;
	end
	local _, key = EventWowChat_OpenConversation(name);
	EventWowChat_SelectTab(key);
	EventWowChatEditBox:SetFocus();
end

local function EventWow_CreateMessages(parent, name)
	local messages = CreateFrame("ScrollingMessageFrame", name, parent);
	messages:SetPoint("TOPLEFT", EventWowChatTabLine, "BOTTOMLEFT", 4, -6);
	messages:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -10, 36);
	messages:SetFontObject(ChatFontNormal);
	messages:SetJustifyH("LEFT");
	messages:SetFading(false);
	messages:SetMaxLines(EVENTWOW_CHAT.MAX_LINES);
	messages:SetHyperlinksEnabled(true);
	messages:SetScript("OnHyperlinkClick", EventWow_OnHyperlinkClick);
	messages:EnableMouseWheel(true);
	messages:SetScript("OnMouseWheel", function(self, delta)
		if ( delta > 0 ) then
			if ( IsShiftKeyDown() ) then self:ScrollToTop(); else self:ScrollUp(); end
		else
			if ( IsShiftKeyDown() ) then self:ScrollToBottom(); else self:ScrollDown(); end
		end
	end);
	return messages;
end

function EventWowChat_Create(parent)
	local f = CreateFrame("Frame", "EventWowChatFrame", parent);

	-- Linea bajo las pestanas (las pestanas se apoyan en ella)
	local line = f:CreateTexture("EventWowChatTabLine", "ARTWORK");
	line:SetHeight(1);
	line:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -6 - EVENTWOW_CHAT.TAB_HEIGHT);
	line:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6 - EVENTWOW_CHAT.TAB_HEIGHT);
	EventWow_SetColor(line, EVENTWOW_CHAT.COLOR_TAB_LINE);

	local online = f:CreateFontString("EventWowChatOnlineText", "ARTWORK", "GameFontHighlightSmall");
	online:SetPoint("BOTTOMRIGHT", line, "TOPRIGHT", -4, 7);
	if ( EventWow_Chat.onlineCount ) then
		online:SetText(format(EVENTWOW_STR_CHAT_ONLINE, EventWow_Chat.onlineCount));
	end

	-- Caja de texto + boton
	local send = CreateFrame("Button", "EventWowChatSendButton", f, "UIPanelButtonTemplate");
	send:SetSize(80, 22);
	send:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 8);
	send:SetText(EVENTWOW_STR_CHAT_SEND);

	local editBox = CreateFrame("EditBox", "EventWowChatEditBox", f, "InputBoxTemplate");
	editBox:SetHeight(22);
	editBox:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 8);
	editBox:SetPoint("RIGHT", send, "LEFT", -8, 0);
	editBox:SetAutoFocus(false);
	editBox:SetMaxLetters(EVENTWOW_CHAT.MAX_LETTERS);
	editBox:SetHistoryLines(30);
	editBox:SetFontObject(ChatFontNormal);

	local placeholder = editBox:CreateFontString("EventWowChatPlaceholder", "ARTWORK", "GameFontDisable");
	placeholder:SetPoint("LEFT", editBox, "LEFT", 2, 0);
	placeholder:SetPoint("RIGHT", editBox, "RIGHT", -2, 0);
	placeholder:SetJustifyH("LEFT");

	editBox:SetScript("OnEnterPressed", function(self)
		EventWowChat_Submit(self);
		self:ClearFocus();
	end);
	editBox:SetScript("OnEscapePressed", function(self)
		self:ClearFocus();
	end);
	editBox:SetScript("OnEditFocusGained", EventWow_UpdatePlaceholder);
	editBox:SetScript("OnEditFocusLost", EventWow_UpdatePlaceholder);
	editBox:SetScript("OnTextChanged", EventWow_UpdatePlaceholder);

	send:SetScript("OnClick", function()
		EventWowChat_Submit(editBox);
	end);

	EventWow_CreateMessages(f, "EventWowChatMessages");
	EventWow_CreateMessages(f, "EventWowChatPrivateMessages");

	f:SetScript("OnSizeChanged", EventWowChat_LayoutTabs);
	EventWowChat_SelectTab("global");
	return f;
end

-- Arranque --------------------------------------------------------------------------------------

local whisperFrame = CreateFrame("Frame", "EventWowChatWhisperFrame");
whisperFrame:RegisterEvent("CHAT_MSG_WHISPER");
whisperFrame:RegisterEvent("CHAT_MSG_WHISPER_INFORM");
whisperFrame:RegisterEvent("CHAT_MSG_AFK");
whisperFrame:RegisterEvent("CHAT_MSG_DND");
whisperFrame:RegisterEvent("CHAT_MSG_SYSTEM");
whisperFrame:RegisterEvent("CHAT_MSG_PARTY");
whisperFrame:RegisterEvent("CHAT_MSG_PARTY_LEADER");
whisperFrame:RegisterEvent("PARTY_MEMBERS_CHANGED");
whisperFrame:RegisterEvent("PLAYER_ENTERING_WORLD");
whisperFrame:SetScript("OnEvent", EventWow_OnWhisperEvent);

EventWow_RegisterHandler("CHAT", EventWow_OnChatMessage);
EventWow_RegisterHandler("ONLINE", EventWow_OnOnline);
