-- EventWow: partida en curso (HUD generico). Todo lo que muestra llega del servidor:
--   MATCH_STATE <NONE | LOADING|WAITING|COUNTDOWN|RUNNING|ENDED> <id juego> <segundos>
--   MATCH_HUD <texto del objetivo>
--   MATCH_RESPAWN <segundos> (has muerto: reapareces en N; 0 = ya)
--   MATCH_END <WIN|LOSE|NONE> <texto>
-- y manda ABANDON para volver al lobby. Ver docs/protocolo.md.
--
-- LOADING: el servidor ya nos esta llevando a la instancia; seguimos en modo lobby (el panel muestra
-- "Entrando..."). Desde WAITING (ya dentro) hasta NONE (de vuelta en el lobby): modo partida
-- (EventWow_SetMode, EventWow.lua): mundo visible + este HUD.
--
--          +--------------------------------------+
--          |  <juego>                  [Abandonar] |   EventWowMatchHud (arriba, centrado)
--          |  Tiempo: 0:25                         |
--          |  <objetivo>                           |
--          +--------------------------------------+
--                         3 / ¡VICTORIA!               EventWowMatchBigText (centro)

EVENTWOW_STR_MATCH_WAITING = "Esperando al resto de jugadores...";
EVENTWOW_STR_MATCH_COUNTDOWN = "La partida empieza en %d";
EVENTWOW_STR_MATCH_TIME = "Tiempo: |cffffffff%s|r";
EVENTWOW_STR_MATCH_RUNNING = "¡En juego!";
EVENTWOW_STR_MATCH_RETURNING = "Volviendo al lobby en %d...";
EVENTWOW_STR_MATCH_ABANDON = "Abandonar";
EVENTWOW_STR_MATCH_BACK = "Volver al lobby";
EVENTWOW_STR_MATCH_ABANDON_CONFIRM = "¿Abandonar la partida y volver al lobby?";
EVENTWOW_STR_MATCH_GO = "¡YA!";
EVENTWOW_STR_MATCH_RESPAWN = "Reapareces en %d";
EVENTWOW_STR_MATCH_RESULT = {
	WIN = { text = "¡VICTORIA!", color = { 0.2, 1, 0.2 } },
	LOSE = { text = "DERROTA", color = { 1, 0.2, 0.2 } },
	NONE = { text = "FIN DE LA PARTIDA", color = { 1, 0.82, 0 } },
};

EventWow_Match = {
	-- nil fuera de partida; si no, el ultimo MATCH_STATE
	state = nil,
	gameId = nil,
	-- GetTime() en que acaba el estado actual (nil = sin tiempo)
	endTime = nil,
	hud = "",
	result = nil,
	summary = nil,
};

function EventWowMatch_IsLoading()
	return EventWow_Match.state == "LOADING";
end

local function EventWow_GameName(id)
	for _, game in ipairs(EventWow_Protocol.games) do
		if ( game.id == id ) then
			return game.name;
		end
	end
	return id or "";
end

local function EventWow_FormatTime(seconds)
	seconds = math.max(0, math.ceil(seconds));
	return format("%d:%02d", math.floor(seconds / 60), seconds % 60);
end

local function EventWow_RemainingSeconds()
	if ( not EventWow_Match.endTime ) then
		return nil;
	end
	return math.max(0, EventWow_Match.endTime - GetTime());
end

local function EventWow_ShowBigText(text, summary, r, g, b)
	EventWowMatchBigText:SetText(text);
	EventWowMatchBigSummary:SetText(summary or "");
	EventWowMatchBigText:SetTextColor(r or 1, g or 0.82, b or 0);
	EventWowMatchBigTextFrame:Show();
end

local function EventWow_HideBigText()
	EventWowMatchBigTextFrame:Hide();
end

-- Actualizacion ---------------------------------------------------------------------------------

function EventWowMatch_UpdateHud()
	local match = EventWow_Match;
	local state = match.state;
	local remaining = EventWow_RemainingSeconds();

	if ( state == "WAITING" ) then
		EventWowMatchHudStatus:SetText(EVENTWOW_STR_MATCH_WAITING);
	elseif ( state == "COUNTDOWN" ) then
		local seconds = math.ceil(remaining or 0);
		EventWowMatchHudStatus:SetText(format(EVENTWOW_STR_MATCH_COUNTDOWN, seconds));
		if ( seconds > 0 ) then
			EventWow_ShowBigText(tostring(seconds));
		end
	elseif ( state == "RUNNING" ) then
		if ( remaining ) then
			EventWowMatchHudStatus:SetText(format(EVENTWOW_STR_MATCH_TIME, EventWow_FormatTime(remaining)));
		else
			EventWowMatchHudStatus:SetText(EVENTWOW_STR_MATCH_RUNNING);
		end
	elseif ( state == "ENDED" ) then
		EventWowMatchHudStatus:SetText(format(EVENTWOW_STR_MATCH_RETURNING, math.ceil(remaining or 0)));
	end
end

local function EventWow_RefreshHud()
	local match = EventWow_Match;
	EventWowMatchHudTitle:SetText(EventWow_GameName(match.gameId));
	EventWowMatchHudObjective:SetText(match.hud or "");
	if ( match.state == "ENDED" ) then
		EventWowMatchHudAbandon:SetText(EVENTWOW_STR_MATCH_BACK);
	else
		EventWowMatchHudAbandon:SetText(EVENTWOW_STR_MATCH_ABANDON);
	end
	EventWowMatch_UpdateHud();
end

-- Construccion ----------------------------------------------------------------------------------

local function EventWow_CreateHud()
	local hud = CreateFrame("Frame", "EventWowMatchHud", UIParent);
	hud:SetSize(440, 84);
	hud:SetPoint("TOP", UIParent, "TOP", 0, -24);
	hud:SetFrameStrata("MEDIUM");
	hud:SetBackdrop(EVENTWOW_PANEL.BACKDROP);
	hud:SetBackdropColor(unpack(EVENTWOW_PANEL.COLOR_SECTION));
	hud:SetBackdropBorderColor(unpack(EVENTWOW_PANEL.COLOR_BORDER));
	hud:Hide();

	local abandon = CreateFrame("Button", "EventWowMatchHudAbandon", hud, "UIPanelButtonTemplate");
	abandon:SetSize(120, 22);
	abandon:SetPoint("TOPRIGHT", hud, "TOPRIGHT", -10, -10);
	abandon:SetText(EVENTWOW_STR_MATCH_ABANDON);
	abandon:SetScript("OnClick", function()
		if ( EventWow_Match.state == "ENDED" ) then
			EventWow_Send("ABANDON");
		else
			StaticPopup_Show("EVENTWOW_ABANDON_MATCH");
		end
	end);

	local title = hud:CreateFontString("EventWowMatchHudTitle", "ARTWORK", "GameFontNormalLarge");
	title:SetPoint("TOPLEFT", hud, "TOPLEFT", 14, -12);
	title:SetPoint("RIGHT", abandon, "LEFT", -8, 0);
	title:SetJustifyH("LEFT");

	local status = hud:CreateFontString("EventWowMatchHudStatus", "ARTWORK", "GameFontHighlight");
	status:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6);
	status:SetPoint("RIGHT", hud, "RIGHT", -14, 0);
	status:SetJustifyH("LEFT");

	local objective = hud:CreateFontString("EventWowMatchHudObjective", "ARTWORK", "GameFontHighlightSmall");
	objective:SetPoint("TOPLEFT", status, "BOTTOMLEFT", 0, -6);
	objective:SetPoint("RIGHT", hud, "RIGHT", -14, 0);
	objective:SetJustifyH("LEFT");

	local elapsed = 0;
	hud:SetScript("OnUpdate", function(self, delta)
		elapsed = elapsed + delta;
		if ( elapsed >= 0.2 ) then
			elapsed = 0;
			EventWowMatch_UpdateHud();
		end
	end);

	-- Texto grande en el centro: cuenta atras y resultado
	local bigFrame = CreateFrame("Frame", "EventWowMatchBigTextFrame", UIParent);
	bigFrame:SetSize(600, 120);
	bigFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 120);
	bigFrame:SetFrameStrata("HIGH");
	bigFrame:Hide();

	local big = bigFrame:CreateFontString("EventWowMatchBigText", "OVERLAY");
	big:SetFont("Fonts\\FRIZQT__.TTF", 56, "THICKOUTLINE");
	big:SetPoint("CENTER", bigFrame, "CENTER", 0, 0);

	local summary = bigFrame:CreateFontString("EventWowMatchBigSummary", "OVERLAY", "GameFontHighlightLarge");
	summary:SetPoint("TOP", big, "BOTTOM", 0, -8);
end

StaticPopupDialogs["EVENTWOW_ABANDON_MATCH"] = {
	text = EVENTWOW_STR_MATCH_ABANDON_CONFIRM,
	button1 = YES,
	button2 = NO,
	OnAccept = function()
		EventWow_Send("ABANDON");
	end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
};

-- Protocolo -------------------------------------------------------------------------------------

local function EventWow_LeaveMatch()
	local match = EventWow_Match;
	match.state = nil;
	match.gameId = nil;
	match.endTime = nil;
	match.hud = "";
	match.result = nil;
	match.summary = nil;
	StaticPopup_Hide("EVENTWOW_ABANDON_MATCH");
	EventWowMatchHud:Hide();
	EventWowMatchBigTextFrame:SetScript("OnUpdate", nil);
	EventWow_HideBigText();
	EventWow_SetMode("lobby");
end

-- MATCH_STATE NONE | MATCH_STATE <estado> <id juego> <segundos>
EventWow_RegisterHandler("MATCH_STATE", function(fields)
	local match = EventWow_Match;
	local state = fields[1];
	if ( state == "NONE" ) then
		local wasInMatch = match.state ~= nil;
		EventWow_LeaveMatch();
		if ( wasInMatch ) then
			EventWowPanel_Update();
		end
		return;
	end

	local previous = match.state;
	if ( match.gameId ~= fields[2] ) then
		-- Partida nueva: limpiar la anterior
		match.hud = "";
		match.result = nil;
		match.summary = nil;
	end
	match.state = state;
	match.gameId = fields[2];
	local seconds = tonumber(fields[3]) or 0;
	match.endTime = (seconds > 0) and (GetTime() + seconds) or nil;

	if ( state == "LOADING" ) then
		EventWowPanel_Update();
		return;
	end

	EventWow_SetMode("match");
	EventWowMatchHud:Show();
	if ( state == "RUNNING" and previous == "COUNTDOWN" ) then
		EventWow_ShowBigText(EVENTWOW_STR_MATCH_GO, nil, 0.2, 1, 0.2);
		-- Se oculta solo a los 1.5 s (salvo que llegue otro texto antes)
		local shownAt = GetTime();
		EventWowMatchBigTextFrame:SetScript("OnUpdate", function(self)
			if ( GetTime() - shownAt > 1.5 ) then
				self:SetScript("OnUpdate", nil);
				if ( EventWowMatchBigText:GetText() == EVENTWOW_STR_MATCH_GO ) then
					self:Hide();
				end
			end
		end);
	elseif ( state ~= "COUNTDOWN" and state ~= "ENDED" ) then
		EventWow_HideBigText();
	end
	EventWow_RefreshHud();
end);

-- MATCH_HUD <texto>
EventWow_RegisterHandler("MATCH_HUD", function(fields)
	EventWow_Match.hud = fields[1] or "";
	if ( EventWowMatchHud:IsShown() ) then
		EventWowMatchHudObjective:SetText(EventWow_Match.hud);
	end
end);

-- MATCH_END <WIN|LOSE|NONE> <texto>
EventWow_RegisterHandler("MATCH_END", function(fields)
	local result = EVENTWOW_STR_MATCH_RESULT[fields[1]] or EVENTWOW_STR_MATCH_RESULT.NONE;
	local summary = fields[2] or "";
	EventWow_Match.result = fields[1];
	EventWow_Match.summary = summary;

	EventWowMatchBigTextFrame:SetScript("OnUpdate", nil);
	EventWow_ShowBigText(result.text, summary, unpack(result.color));

	local line = result.text;
	if ( summary ~= "" ) then
		line = line.." "..summary;
	end
	DEFAULT_CHAT_FRAME:AddMessage(line, unpack(result.color));
end);

-- MATCH_RESPAWN <segundos>
EventWow_RegisterHandler("MATCH_RESPAWN", function(fields)
	local seconds = tonumber(fields[1]) or 0;
	local frame = EventWowMatchBigTextFrame;
	if ( seconds <= 0 ) then
		frame:SetScript("OnUpdate", nil);
		EventWow_HideBigText();
		return;
	end

	-- La reaparicion es automatica: sin el dialogo de "Liberar espiritu"
	StaticPopup_Hide("DEATH");
	local endTime = GetTime() + seconds;
	local function Refresh()
		local left = math.max(1, math.ceil(endTime - GetTime()));
		EventWow_ShowBigText(format(EVENTWOW_STR_MATCH_RESPAWN, left), nil, 1, 0.3, 0.3);
	end
	Refresh();
	frame:SetScript("OnUpdate", function(self)
		if ( GetTime() >= endTime ) then
			self:SetScript("OnUpdate", nil);
			return;
		end
		Refresh();
	end);
end);

EventWow_CreateHud();
