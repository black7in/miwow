-- EventWow: chat global (sustituye al chat nativo).
-- Contraparte en el servidor: modules/mod-eventwow/src/EventWowChat.cpp
--
--  - El chat nativo (ChatFrame1-10, pestanas, dock, botones) se oculta siempre, pero sigue existiendo:
--    todo lo que mostraria ChatFrame1 (mensajes del sistema, errores, /script print...) se copia aqui.
--  - El panel crea el marco con EventWowChat_Create(parent) y lo coloca.
--  - Texto que empieza por "/" -> comandos nativos (/reload, /script...); por "." -> comandos de GM
--    (el core los intercepta antes de decirlos); el resto -> CHAT por el protocolo.

EVENTWOW_CHAT = {
	MAX_LETTERS = 200,   -- igual que MaxMessageLength del servidor
	MAX_LINES = 250,
	GM_BADGE = "|TInterface\\ChatFrame\\UI-ChatIcon-Blizz.blp:0:2:0:-3|t ",
	COLOR_TIME = "|cff808080",
	COLOR_PLAYER = "|cff99ccff",
	COLOR_GM = "|cff33ffcc",
};

EVENTWOW_STR_CHAT_TITLE = "CHAT GLOBAL";
EVENTWOW_STR_CHAT_ONLINE = "%d conectados";
EVENTWOW_STR_CHAT_PLACEHOLDER = "Escribe un mensaje... (Intro)";
EVENTWOW_STR_CHAT_SEND = "Enviar";

-- Marcos nativos del chat que se ocultan (las pestanas las reparenta FCF al acoplar: se ocultan aparte)
EVENTWOW_NATIVE_CHAT_FRAMES = {
	"GeneralDockManager",
	"ChatFrameMenuButton",
	"FriendsMicroButton",
};

EventWow_Chat = {
	onlineCount = nil,
};

local hiddenParent = CreateFrame("Frame", "EventWowChatHiddenParent", UIParent);
hiddenParent:Hide();

local function EventWow_EscapeText(text)
	return (string.gsub(text or "", "|", "||"));
end

-- Ocultar el chat nativo ------------------------------------------------------------------------

local function EventWow_HideNativeChatFrame(frame)
	if ( not frame ) then
		return;
	end
	frame:SetParent(hiddenParent);

	local tab = _G[frame:GetName().."Tab"];
	if ( tab ) then
		tab:Hide();
		hooksecurefunc(tab, "Show", function(self)
			self:Hide();
		end);
	end
end

local function EventWow_HideNativeChat()
	for i = 1, NUM_CHAT_WINDOWS do
		EventWow_HideNativeChatFrame(_G["ChatFrame"..i]);
	end
	for _, name in ipairs(EVENTWOW_NATIVE_CHAT_FRAMES) do
		if ( _G[name] ) then
			_G[name]:SetParent(hiddenParent);
		end
	end

	-- Ventanas temporales (p.ej. una pestana por susurro)
	local openTemporaryWindow = FCF_OpenTemporaryWindow;
	FCF_OpenTemporaryWindow = function(...)
		local frame = openTemporaryWindow(...);
		EventWow_HideNativeChatFrame(frame);
		return frame;
	end

	-- Intro / "/" abren nuestra caja en vez de la nativa
	local openChat = ChatFrame_OpenChat;
	ChatFrame_OpenChat = function(text, chatFrame)
		local editBox = EventWowChatEditBox;
		if ( editBox and editBox:IsVisible() ) then
			editBox:SetFocus();
			if ( text and text ~= "" ) then
				editBox:SetText(text);
			end
			return editBox;
		end
		return openChat(text, chatFrame);
	end
end

-- Mensajes --------------------------------------------------------------------------------------

function EventWowChat_AddMessage(text, r, g, b)
	if ( EventWowChatMessages ) then
		EventWowChatMessages:AddMessage(text, r or 1, g or 1, b or 1);
	end
end

-- CHAT <unix time> <rango> <nombre> <texto>
local function EventWow_OnChatMessage(fields)
	local time = tonumber(fields[1]) or 0;
	local isGM = tonumber(fields[2]) == 1;
	local name = EventWow_EscapeText(fields[3]);
	local text = EventWow_EscapeText(fields[4]);

	local line = EVENTWOW_CHAT.COLOR_TIME.."["..date("%H:%M", time).."]|r ";
	if ( isGM ) then
		line = line..EVENTWOW_CHAT.GM_BADGE..EVENTWOW_CHAT.COLOR_GM..name.."|r";
	else
		line = line..EVENTWOW_CHAT.COLOR_PLAYER..name.."|r";
	end
	EventWowChat_AddMessage(line..": "..text, 1, 1, 1);
end

-- ONLINE <n>
local function EventWow_OnOnline(fields)
	EventWow_Chat.onlineCount = tonumber(fields[1]);
	if ( EventWowChatOnlineText ) then
		EventWowChatOnlineText:SetText(format(EVENTWOW_STR_CHAT_ONLINE, EventWow_Chat.onlineCount or 0));
	end
end

local function EventWow_SendNative(text)
	-- Mismo camino que la caja nativa: comandos con barra, /w, /s...
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
	if ( first == "/" ) then
		EventWow_SendNative(text);
	elseif ( first == "." ) then
		SendChatMessage(text, "SAY");
	else
		EventWow_Send("CHAT", text);
	end
end

-- Marco -----------------------------------------------------------------------------------------

local function EventWow_UpdatePlaceholder(editBox)
	if ( editBox:HasFocus() or editBox:GetText() ~= "" ) then
		EventWowChatPlaceholder:Hide();
	else
		EventWowChatPlaceholder:Show();
	end
end

function EventWowChat_Create(parent)
	local f = CreateFrame("Frame", "EventWowChatFrame", parent);

	local title = f:CreateFontString("EventWowChatTitle", "ARTWORK", "GameFontNormal");
	title:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -8);
	title:SetText(EVENTWOW_STR_CHAT_TITLE);

	local online = f:CreateFontString("EventWowChatOnlineText", "ARTWORK", "GameFontHighlightSmall");
	online:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -9);
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
	placeholder:SetText(EVENTWOW_STR_CHAT_PLACEHOLDER);

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

	-- Mensajes
	local messages = CreateFrame("ScrollingMessageFrame", "EventWowChatMessages", f);
	messages:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -26);
	messages:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 36);
	messages:SetFontObject(ChatFontNormal);
	messages:SetJustifyH("LEFT");
	messages:SetFading(false);
	messages:SetMaxLines(EVENTWOW_CHAT.MAX_LINES);
	messages:EnableMouseWheel(true);
	messages:SetScript("OnMouseWheel", function(self, delta)
		if ( delta > 0 ) then
			if ( IsShiftKeyDown() ) then self:ScrollToTop(); else self:ScrollUp(); end
		else
			if ( IsShiftKeyDown() ) then self:ScrollToBottom(); else self:ScrollDown(); end
		end
	end);

	return f;
end

-- Arranque --------------------------------------------------------------------------------------

EventWow_HideNativeChat();

-- Todo lo que llega al chat nativo principal (sistema, errores, avisos del servidor, /script print...)
hooksecurefunc(ChatFrame1, "AddMessage", function(self, text, r, g, b)
	EventWowChat_AddMessage(text, r, g, b);
end);

EventWow_RegisterHandler("CHAT", EventWow_OnChatMessage);
EventWow_RegisterHandler("ONLINE", EventWow_OnOnline);
