-- EventWow: parkour (juego "parkour", sesion siempre abierta). Todo llega del servidor (EventWowGameParkour.cpp):
--   PARKOUR_INFO <n secciones> <nombre 1> ... <nombre n>
--   PARKOUR <seccion> <caidas> <ms> <estado: 0 salida, 1 corriendo, 2 meta> <ms mejor, 0 = ninguno>
--   PARKOUR_EVENT CHECKPOINT <seccion> | FALL | FINISH <ms> <record 0/1> | PLAYER_FINISH <nombre> <ms> | RESTART
--   PARKOUR_RANK <n> (<nombre> <ms>) x n
--   Cliente -> servidor: PARKOUR_RESTART
-- Ver docs/protocolo.md.
--
--   Marcador (arriba a la derecha):   Seccion 2/5  La Biblioteca Arcana / Tiempo / Caidas / Mejor  [Reiniciar]
--   Clasificacion de la sesion (debajo del marcador): hasta 10 tiempos
--   Aviso grande (centro, arriba):    ¡Punto de control! / ¡Has caído! / ¡CIMA! ...

EVENTWOW_STR_PARKOUR_SECTION = "Sección |cffffffff%d/%d|r";
EVENTWOW_STR_PARKOUR_TIME = "Tiempo |cffffffff%s|r";
EVENTWOW_STR_PARKOUR_FALLS = "Caídas |cffffffff%d|r";
EVENTWOW_STR_PARKOUR_BEST = "Tu mejor |cffffffff%s|r";
EVENTWOW_STR_PARKOUR_AT_START = "Salta de la plataforma para empezar";
EVENTWOW_STR_PARKOUR_FINISHED = "¡Has llegado a la cima!";
EVENTWOW_STR_PARKOUR_RESTART = "Reiniciar";
EVENTWOW_STR_PARKOUR_RESTART_CONFIRM = "¿Volver a la salida con el cronómetro a cero?";
EVENTWOW_STR_PARKOUR_CHECKPOINT = "¡Punto de control!";
EVENTWOW_STR_PARKOUR_FELL = "¡Has caído!";
EVENTWOW_STR_PARKOUR_FINISH = "¡CIMA!  %s";
EVENTWOW_STR_PARKOUR_RECORD = "¡Nuevo récord personal!";
EVENTWOW_STR_PARKOUR_PLAYER_FINISH = "%s ha llegado a la cima en %s.";
EVENTWOW_STR_PARKOUR_RANK = "Mejores de la sesión";
EVENTWOW_STR_PARKOUR_NO_RANK = "Nadie ha llegado a la cima todavía.";

local PARKOUR_RANK_ROWS = 10;

EventWow_Parkour = {
	sections = {},
	-- Ultimo PARKOUR y el GetTime() en que llego (el reloj avanza solo entre mensajes)
	data = nil,
	receivedAt = 0,
};

-- 83450 ms -> "1:23.45"
local function EventWowParkour_FormatMs(ms)
	ms = math.max(0, ms or 0);
	local minutes = math.floor(ms / 60000);
	local seconds = (ms - minutes * 60000) / 1000;
	return format("%d:%05.2f", minutes, seconds);
end

-- Construccion -----------------------------------------------------------------------------------

local function EventWowParkour_CreateFrames()
	-- Marcador
	local hud = CreateFrame("Frame", "EventWowParkourHud", UIParent);
	hud:SetSize(250, 132);
	hud:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -24, -150);
	hud:SetFrameStrata("MEDIUM");
	hud:SetBackdrop(EVENTWOW_PANEL.BACKDROP);
	hud:SetBackdropColor(unpack(EVENTWOW_PANEL.COLOR_SECTION));
	hud:SetBackdropBorderColor(unpack(EVENTWOW_PANEL.COLOR_BORDER));
	hud:Hide();

	local section = hud:CreateFontString("EventWowParkourSection", "ARTWORK", "GameFontNormalLarge");
	section:SetPoint("TOPLEFT", hud, "TOPLEFT", 12, -12);
	local sectionName = hud:CreateFontString("EventWowParkourSectionName", "ARTWORK", "GameFontHighlight");
	sectionName:SetPoint("TOPLEFT", section, "BOTTOMLEFT", 0, -4);
	sectionName:SetWidth(226);
	sectionName:SetJustifyH("LEFT");

	local clock = hud:CreateFontString("EventWowParkourTime", "ARTWORK");
	clock:SetFont("Fonts\\FRIZQT__.TTF", 22, "OUTLINE");
	clock:SetPoint("TOPLEFT", sectionName, "BOTTOMLEFT", 0, -8);
	clock:SetTextColor(1, 0.82, 0);
	local falls = hud:CreateFontString("EventWowParkourFalls", "ARTWORK", "GameFontNormalSmall");
	falls:SetPoint("TOPLEFT", clock, "BOTTOMLEFT", 0, -6);
	local best = hud:CreateFontString("EventWowParkourBest", "ARTWORK", "GameFontNormalSmall");
	best:SetPoint("LEFT", falls, "RIGHT", 16, 0);
	local hint = hud:CreateFontString("EventWowParkourHint", "ARTWORK", "GameFontDisableSmall");
	hint:SetPoint("BOTTOMLEFT", hud, "BOTTOMLEFT", 12, 12);
	hint:SetWidth(140);
	hint:SetJustifyH("LEFT");

	local restart = CreateFrame("Button", "EventWowParkourRestart", hud, "UIPanelButtonTemplate");
	restart:SetSize(90, 22);
	restart:SetPoint("BOTTOMRIGHT", hud, "BOTTOMRIGHT", -10, 8);
	restart:SetText(EVENTWOW_STR_PARKOUR_RESTART);
	restart:SetScript("OnClick", function()
		StaticPopup_Show("EVENTWOW_PARKOUR_RESTART");
	end);

	hud:SetScript("OnUpdate", function(self, elapsed)
		self.elapsed = (self.elapsed or 0) + elapsed;
		if ( self.elapsed >= 0.05 ) then
			self.elapsed = 0;
			EventWowParkour_UpdateClock();
		end
	end);

	-- Clasificacion de la sesion
	local rank = CreateFrame("Frame", "EventWowParkourRank", UIParent);
	rank:SetSize(250, 40 + PARKOUR_RANK_ROWS * 16);
	rank:SetPoint("TOPRIGHT", hud, "BOTTOMRIGHT", 0, -6);
	rank:SetFrameStrata("MEDIUM");
	rank:SetBackdrop(EVENTWOW_PANEL.BACKDROP);
	rank:SetBackdropColor(unpack(EVENTWOW_PANEL.COLOR_SECTION));
	rank:SetBackdropBorderColor(unpack(EVENTWOW_PANEL.COLOR_BORDER));
	rank:Hide();
	local rankTitle = rank:CreateFontString(nil, "ARTWORK", "GameFontNormal");
	rankTitle:SetPoint("TOPLEFT", rank, "TOPLEFT", 12, -10);
	rankTitle:SetText(EVENTWOW_STR_PARKOUR_RANK);
	rank.rows = {};
	for i = 1, PARKOUR_RANK_ROWS do
		local y = -30 - (i - 1) * 16;
		local name = rank:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall");
		name:SetPoint("TOPLEFT", rank, "TOPLEFT", 12, y);
		name:SetWidth(150);
		name:SetJustifyH("LEFT");
		local time = rank:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall");
		time:SetPoint("TOPRIGHT", rank, "TOPRIGHT", -12, y);
		time:SetJustifyH("RIGHT");
		rank.rows[i] = { name = name, time = time };
	end

	-- Aviso grande
	local notice = CreateFrame("Frame", "EventWowParkourNotice", UIParent);
	notice:SetSize(700, 100);
	notice:SetPoint("CENTER", UIParent, "CENTER", 0, 190);
	notice:SetFrameStrata("HIGH");
	notice:Hide();
	local noticeText = notice:CreateFontString("EventWowParkourNoticeText", "OVERLAY");
	noticeText:SetFont("Fonts\\FRIZQT__.TTF", 40, "THICKOUTLINE");
	noticeText:SetPoint("TOP", notice, "TOP", 0, 0);
	local noticeSub = notice:CreateFontString("EventWowParkourNoticeSub", "OVERLAY");
	noticeSub:SetFont("Fonts\\FRIZQT__.TTF", 20, "OUTLINE");
	noticeSub:SetPoint("TOP", noticeText, "BOTTOM", 0, -6);
	notice:SetScript("OnUpdate", function(self)
		if ( self.hideAt and GetTime() >= self.hideAt ) then
			self.hideAt = nil;
			self:Hide();
		end
	end);
end

StaticPopupDialogs["EVENTWOW_PARKOUR_RESTART"] = {
	text = EVENTWOW_STR_PARKOUR_RESTART_CONFIRM,
	button1 = YES,
	button2 = NO,
	OnAccept = function()
		EventWow_Send("PARKOUR_RESTART");
	end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
};

-- Actualizacion ----------------------------------------------------------------------------------

function EventWowParkour_UpdateClock()
	local data = EventWow_Parkour.data;
	if ( not data ) then
		return;
	end
	local ms = data.elapsed;
	if ( data.state == 1 ) then
		ms = ms + (GetTime() - EventWow_Parkour.receivedAt) * 1000;
	end
	EventWowParkourTime:SetText(format(EVENTWOW_STR_PARKOUR_TIME, EventWowParkour_FormatMs(ms)));
end

local function EventWowParkour_ShowNotice(text, sub, seconds, r, g, b)
	EventWowParkourNoticeText:SetText(text);
	EventWowParkourNoticeText:SetTextColor(r or 1, g or 0.82, b or 0);
	EventWowParkourNoticeSub:SetText(sub or "");
	EventWowParkourNotice.hideAt = GetTime() + (seconds or 2.5);
	EventWowParkourNotice:Show();
end

local function EventWowParkour_Reset()
	EventWow_Parkour.data = nil;
	EventWowParkourHud:Hide();
	EventWowParkourRank:Hide();
	EventWowParkourNotice:Hide();
	StaticPopup_Hide("EVENTWOW_PARKOUR_RESTART");
end

local function EventWowParkour_SectionName(index)
	return EventWow_Parkour.sections[index] or "";
end

-- Protocolo -------------------------------------------------------------------------------------

-- PARKOUR_INFO <n> <nombres...>: al llegar a la instancia
EventWow_RegisterHandler("PARKOUR_INFO", function(fields)
	EventWowParkour_Reset();
	local count = tonumber(fields[1]) or 0;
	local sections = {};
	for i = 1, count do
		sections[i] = fields[1 + i] or "";
	end
	EventWow_Parkour.sections = sections;
end);

EventWow_RegisterHandler("PARKOUR", function(fields)
	local data = {
		section = tonumber(fields[1]) or 1,
		falls = tonumber(fields[2]) or 0,
		elapsed = tonumber(fields[3]) or 0,
		state = tonumber(fields[4]) or 0,
		best = tonumber(fields[5]) or 0,
	};
	EventWow_Parkour.data = data;
	EventWow_Parkour.receivedAt = GetTime();

	EventWowParkourSection:SetText(format(EVENTWOW_STR_PARKOUR_SECTION, data.section,
		math.max(#EventWow_Parkour.sections, data.section)));
	EventWowParkourSectionName:SetText(EventWowParkour_SectionName(data.section));
	EventWowParkourFalls:SetText(format(EVENTWOW_STR_PARKOUR_FALLS, data.falls));
	EventWowParkourBest:SetText(format(EVENTWOW_STR_PARKOUR_BEST,
		data.best > 0 and EventWowParkour_FormatMs(data.best) or "-"));
	if ( data.state == 0 ) then
		EventWowParkourHint:SetText(EVENTWOW_STR_PARKOUR_AT_START);
	elseif ( data.state == 2 ) then
		EventWowParkourHint:SetText(EVENTWOW_STR_PARKOUR_FINISHED);
	else
		EventWowParkourHint:SetText("");
	end
	EventWowParkour_UpdateClock();
	EventWowParkourHud:Show();
	EventWowParkourRank:Show();
end);

EventWow_RegisterHandler("PARKOUR_EVENT", function(fields)
	local event = fields[1];
	if ( event == "CHECKPOINT" ) then
		EventWowParkour_ShowNotice(EVENTWOW_STR_PARKOUR_CHECKPOINT,
			EventWowParkour_SectionName(tonumber(fields[2]) or 0), 3, 0.4, 0.8, 1);
		PlaySound("igQuestListComplete");
	elseif ( event == "FALL" ) then
		EventWowParkour_ShowNotice(EVENTWOW_STR_PARKOUR_FELL, nil, 1.5, 1, 0.3, 0.3);
	elseif ( event == "FINISH" ) then
		local ms = tonumber(fields[2]) or 0;
		EventWowParkour_ShowNotice(format(EVENTWOW_STR_PARKOUR_FINISH, EventWowParkour_FormatMs(ms)),
			fields[3] == "1" and EVENTWOW_STR_PARKOUR_RECORD or nil, 6, 0.2, 1, 0.2);
		PlaySound("LEVELUPSOUND");
	elseif ( event == "PLAYER_FINISH" ) then
		DEFAULT_CHAT_FRAME:AddMessage(format(EVENTWOW_STR_PARKOUR_PLAYER_FINISH, fields[2] or "?",
			EventWowParkour_FormatMs(tonumber(fields[3]) or 0)), 1, 0.82, 0);
	elseif ( event == "RESTART" ) then
		EventWowParkourNotice:Hide();
	end
end);

-- PARKOUR_RANK <n> (<nombre> <ms>) x n
EventWow_RegisterHandler("PARKOUR_RANK", function(fields)
	local count = tonumber(fields[1]) or 0;
	local rows = EventWowParkourRank.rows;
	local me = UnitName("player");
	for i = 1, PARKOUR_RANK_ROWS do
		local row = rows[i];
		if ( i <= count ) then
			local name = fields[2 + (i - 1) * 2] or "?";
			row.name:SetText(i..". "..name);
			row.time:SetText(EventWowParkour_FormatMs(tonumber(fields[3 + (i - 1) * 2]) or 0));
			local r, g, b = 1, 1, 1;
			if ( name == me ) then
				r, g, b = 1, 0.82, 0;
			end
			row.name:SetTextColor(r, g, b);
			row.time:SetTextColor(r, g, b);
		elseif ( i == 1 ) then
			row.name:SetText(EVENTWOW_STR_PARKOUR_NO_RANK);
			row.name:SetTextColor(0.6, 0.6, 0.6);
			row.time:SetText("");
		else
			row.name:SetText("");
			row.time:SetText("");
		end
	end
	EventWowParkourRank:SetHeight(40 + math.max(1, count) * 16);
end);

-- Fuera de la partida (vuelta al lobby): todo oculto
EventWow_RegisterListener("MATCH", function()
	if ( not EventWow_Match.state ) then
		EventWowParkour_Reset();
	end
end);

EventWowParkour_CreateFrames();
