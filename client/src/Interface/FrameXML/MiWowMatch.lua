-- MiWow: partida en curso (HUD generico). Todo lo que muestra llega del servidor:
--   MATCH_STATE <NONE | LOADING|WAITING|COUNTDOWN|RUNNING|ENDED> <id juego> <segundos>
--   MATCH_HUD <texto del objetivo>
--   MATCH_RESPAWN <segundos> (has muerto: reapareces en N; 0 = ya)
--   MATCH_END <WIN|LOSE|NONE> <texto>
-- y manda ABANDON para salir (el servidor te devuelve a donde estabas). Ver docs/protocolo.md.
--
-- LOADING: el servidor ya nos esta llevando a la instancia; seguimos en modo mundo (el panel muestra
-- "Entrando..."). Desde WAITING (ya dentro) hasta NONE (de vuelta a donde estabas): modo partida
-- (MiWow_SetMode, MiWow.lua): mundo visible + este HUD.
--
--          +--------------------------------------+
--          |  <juego>                  [Abandonar] |   MiWowMatchHud (arriba, centrado)
--          |  Tiempo: 0:25                         |
--          |  <objetivo>                           |
--          +--------------------------------------+
--                         3 / ¡VICTORIA!               MiWowMatchBigText (centro)

MIWOW_STR_MATCH_WAITING = "Esperando al resto de jugadores...";
MIWOW_STR_MATCH_COUNTDOWN = "La partida empieza en %d";
MIWOW_STR_MATCH_TIME = "Tiempo: |cffffffff%s|r";
MIWOW_STR_MATCH_RUNNING = "¡En juego!";
MIWOW_STR_MATCH_RETURNING = "Volviendo en %d...";
MIWOW_STR_MATCH_ABANDON = "Abandonar";
MIWOW_STR_MATCH_BACK = "Salir";
MIWOW_STR_MATCH_ABANDON_CONFIRM = "¿Abandonar la partida? Volverás a donde estabas.";
MIWOW_STR_MATCH_GO = "¡YA!";
MIWOW_STR_MATCH_RESPAWN = "Reapareces en %d";
MIWOW_STR_MATCH_RESULT = {
	WIN = { text = "¡VICTORIA!", color = { 0.2, 1, 0.2 } },
	LOSE = { text = "DERROTA", color = { 1, 0.2, 0.2 } },
	NONE = { text = "FIN DE LA PARTIDA", color = { 1, 0.82, 0 } },
};

MiWow_Match = {
	-- nil fuera de partida; si no, el ultimo MATCH_STATE
	state = nil,
	gameId = nil,
	-- GetTime() en que acaba el estado actual (nil = sin tiempo)
	endTime = nil,
	hud = "",
	result = nil,
	summary = nil,
};

function MiWowMatch_IsLoading()
	return MiWow_Match.state == "LOADING";
end

local function MiWow_GameName(id)
	for _, game in ipairs(MiWow_Protocol.games) do
		if ( game.id == id ) then
			return game.name;
		end
	end
	return id or "";
end

local function MiWow_FormatTime(seconds)
	seconds = math.max(0, math.ceil(seconds));
	return format("%d:%02d", math.floor(seconds / 60), seconds % 60);
end

local function MiWow_RemainingSeconds()
	if ( not MiWow_Match.endTime ) then
		return nil;
	end
	return math.max(0, MiWow_Match.endTime - GetTime());
end

local function MiWow_ShowBigText(text, summary, r, g, b)
	MiWowMatchBigText:SetText(text);
	MiWowMatchBigSummary:SetText(summary or "");
	MiWowMatchBigText:SetTextColor(r or 1, g or 0.82, b or 0);
	MiWowMatchBigTextFrame:Show();
end

local function MiWow_HideBigText()
	MiWowMatchBigTextFrame:Hide();
end

-- Actualizacion ---------------------------------------------------------------------------------

function MiWowMatch_UpdateHud()
	local match = MiWow_Match;
	local state = match.state;
	local remaining = MiWow_RemainingSeconds();

	if ( state == "WAITING" ) then
		MiWowMatchHudStatus:SetText(MIWOW_STR_MATCH_WAITING);
	elseif ( state == "COUNTDOWN" ) then
		local seconds = math.ceil(remaining or 0);
		MiWowMatchHudStatus:SetText(format(MIWOW_STR_MATCH_COUNTDOWN, seconds));
		if ( seconds > 0 ) then
			MiWow_ShowBigText(tostring(seconds));
		end
	elseif ( state == "RUNNING" ) then
		if ( remaining ) then
			MiWowMatchHudStatus:SetText(format(MIWOW_STR_MATCH_TIME, MiWow_FormatTime(remaining)));
		else
			MiWowMatchHudStatus:SetText(MIWOW_STR_MATCH_RUNNING);
		end
	elseif ( state == "ENDED" ) then
		MiWowMatchHudStatus:SetText(format(MIWOW_STR_MATCH_RETURNING, math.ceil(remaining or 0)));
	end
end

local function MiWow_RefreshHud()
	local match = MiWow_Match;
	MiWowMatchHudTitle:SetText(MiWow_GameName(match.gameId));
	MiWowMatchHudObjective:SetText(match.hud or "");
	if ( match.state == "ENDED" ) then
		MiWowMatchHudAbandon:SetText(MIWOW_STR_MATCH_BACK);
	else
		MiWowMatchHudAbandon:SetText(MIWOW_STR_MATCH_ABANDON);
	end
	MiWowMatch_UpdateHud();
end

-- Construccion ----------------------------------------------------------------------------------

local function MiWow_CreateHud()
	local hud = CreateFrame("Frame", "MiWowMatchHud", UIParent);
	hud:SetSize(440, 84);
	hud:SetPoint("TOP", UIParent, "TOP", 0, -24);
	hud:SetFrameStrata("MEDIUM");
	hud:SetBackdrop(MIWOW_PANEL.BACKDROP);
	hud:SetBackdropColor(unpack(MIWOW_PANEL.COLOR_SECTION));
	hud:SetBackdropBorderColor(unpack(MIWOW_PANEL.COLOR_BORDER));
	hud:Hide();

	local abandon = CreateFrame("Button", "MiWowMatchHudAbandon", hud, "UIPanelButtonTemplate");
	abandon:SetSize(120, 22);
	abandon:SetPoint("TOPRIGHT", hud, "TOPRIGHT", -10, -10);
	abandon:SetText(MIWOW_STR_MATCH_ABANDON);
	abandon:SetScript("OnClick", function()
		if ( MiWow_Match.state == "ENDED" ) then
			MiWow_Send("ABANDON");
		else
			StaticPopup_Show("MIWOW_ABANDON_MATCH");
		end
	end);

	local title = hud:CreateFontString("MiWowMatchHudTitle", "ARTWORK", "GameFontNormalLarge");
	title:SetPoint("TOPLEFT", hud, "TOPLEFT", 14, -12);
	title:SetPoint("RIGHT", abandon, "LEFT", -8, 0);
	title:SetJustifyH("LEFT");

	local status = hud:CreateFontString("MiWowMatchHudStatus", "ARTWORK", "GameFontHighlight");
	status:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6);
	status:SetPoint("RIGHT", hud, "RIGHT", -14, 0);
	status:SetJustifyH("LEFT");

	local objective = hud:CreateFontString("MiWowMatchHudObjective", "ARTWORK", "GameFontHighlightSmall");
	objective:SetPoint("TOPLEFT", status, "BOTTOMLEFT", 0, -6);
	objective:SetPoint("RIGHT", hud, "RIGHT", -14, 0);
	objective:SetJustifyH("LEFT");

	local elapsed = 0;
	hud:SetScript("OnUpdate", function(self, delta)
		elapsed = elapsed + delta;
		if ( elapsed >= 0.2 ) then
			elapsed = 0;
			MiWowMatch_UpdateHud();
		end
	end);

	-- Texto grande en el centro: cuenta atras y resultado
	local bigFrame = CreateFrame("Frame", "MiWowMatchBigTextFrame", UIParent);
	bigFrame:SetSize(600, 120);
	bigFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 120);
	bigFrame:SetFrameStrata("HIGH");
	bigFrame:Hide();

	local big = bigFrame:CreateFontString("MiWowMatchBigText", "OVERLAY");
	big:SetFont("Fonts\\FRIZQT__.TTF", 56, "THICKOUTLINE");
	big:SetPoint("CENTER", bigFrame, "CENTER", 0, 0);

	local summary = bigFrame:CreateFontString("MiWowMatchBigSummary", "OVERLAY", "GameFontHighlightLarge");
	summary:SetPoint("TOP", big, "BOTTOM", 0, -8);
end

StaticPopupDialogs["MIWOW_ABANDON_MATCH"] = {
	text = MIWOW_STR_MATCH_ABANDON_CONFIRM,
	button1 = YES,
	button2 = NO,
	OnAccept = function()
		MiWow_Send("ABANDON");
	end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
};

-- Protocolo -------------------------------------------------------------------------------------

local function MiWow_LeaveMatch()
	local match = MiWow_Match;
	match.state = nil;
	match.gameId = nil;
	match.endTime = nil;
	match.hud = "";
	match.result = nil;
	match.summary = nil;
	StaticPopup_Hide("MIWOW_ABANDON_MATCH");
	MiWowMatchHud:Hide();
	MiWowMatchBigTextFrame:SetScript("OnUpdate", nil);
	MiWow_HideBigText();
	MiWow_SetMode("world");
	MiWow_FireListeners("MATCH");
end

-- Juego de la partida actual (catalogo GAMES) o nil
function MiWowMatch_GetGame()
	local id = MiWow_Match.gameId;
	if ( not id ) then
		return nil;
	end
	for _, game in ipairs(MiWow_Protocol.games) do
		if ( game.id == id ) then
			return game;
		end
	end
	return nil;
end

-- En partida con el mundo visible (no en la carga)
function MiWowMatch_IsActive()
	local state = MiWow_Match.state;
	return state ~= nil and state ~= "LOADING";
end

-- MATCH_STATE NONE | MATCH_STATE <estado> <id juego> <segundos>
MiWow_RegisterHandler("MATCH_STATE", function(fields)
	local match = MiWow_Match;
	local state = fields[1];
	if ( state == "NONE" ) then
		local wasInMatch = match.state ~= nil;
		MiWow_LeaveMatch();
		if ( wasInMatch ) then
			MiWowPanel_Update();
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
		MiWowPanel_Update();
		return;
	end

	MiWow_SetMode("match");
	MiWowMatchHud:Show();
	if ( previous ~= state ) then
		MiWow_FireListeners("MATCH");
	end
	if ( state == "RUNNING" and previous == "COUNTDOWN" ) then
		MiWow_ShowBigText(MIWOW_STR_MATCH_GO, nil, 0.2, 1, 0.2);
		-- Se oculta solo a los 1.5 s (salvo que llegue otro texto antes)
		local shownAt = GetTime();
		MiWowMatchBigTextFrame:SetScript("OnUpdate", function(self)
			if ( GetTime() - shownAt > 1.5 ) then
				self:SetScript("OnUpdate", nil);
				if ( MiWowMatchBigText:GetText() == MIWOW_STR_MATCH_GO ) then
					self:Hide();
				end
			end
		end);
	elseif ( state ~= "COUNTDOWN" and state ~= "ENDED" ) then
		MiWow_HideBigText();
	end
	MiWow_RefreshHud();
end);

-- MATCH_HUD <texto>
MiWow_RegisterHandler("MATCH_HUD", function(fields)
	MiWow_Match.hud = fields[1] or "";
	if ( MiWowMatchHud:IsShown() ) then
		MiWowMatchHudObjective:SetText(MiWow_Match.hud);
	end
end);

-- MATCH_END <WIN|LOSE|NONE> <texto>
MiWow_RegisterHandler("MATCH_END", function(fields)
	local result = MIWOW_STR_MATCH_RESULT[fields[1]] or MIWOW_STR_MATCH_RESULT.NONE;
	local summary = fields[2] or "";
	MiWow_Match.result = fields[1];
	MiWow_Match.summary = summary;

	MiWowMatchBigTextFrame:SetScript("OnUpdate", nil);
	MiWow_ShowBigText(result.text, summary, unpack(result.color));

	local line = result.text;
	if ( summary ~= "" ) then
		line = line.." "..summary;
	end
	DEFAULT_CHAT_FRAME:AddMessage(line, unpack(result.color));
end);

-- MATCH_RESPAWN <segundos>
MiWow_RegisterHandler("MATCH_RESPAWN", function(fields)
	local seconds = tonumber(fields[1]) or 0;
	local frame = MiWowMatchBigTextFrame;
	if ( seconds <= 0 ) then
		frame:SetScript("OnUpdate", nil);
		MiWow_HideBigText();
		return;
	end

	-- La reaparicion es automatica: sin el dialogo de "Liberar espiritu"
	StaticPopup_Hide("DEATH");
	local endTime = GetTime() + seconds;
	local function Refresh()
		local left = math.max(1, math.ceil(endTime - GetTime()));
		MiWow_ShowBigText(format(MIWOW_STR_MATCH_RESPAWN, left), nil, 1, 0.3, 0.3);
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

MiWow_CreateHud();
