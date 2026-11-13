-- EventWow: "Partida encontrada" (confirmacion tipo Dota 2). Contraparte: EventWowMatchMgr (propuestas).
--   MATCH_FOUND <id> <id juego> <segundos para aceptar> <total> <aceptados> <tu: 0/1>
--   MATCH_FOUND_STATUS <id> <aceptados> <total>
--   MATCH_FOUND_END <id> ACCEPTED | REQUEUED | REMOVED
-- Responde ACCEPT <id> / DECLINE <id>. Si todos aceptan, el servidor crea la partida (MATCH_STATE LOADING).
-- Si alguien rechaza o no acepta a tiempo: su entrada (el o su grupo) sale de la cola y el resto vuelve a ella.
--
--          +--------------------------------------+
--          |        ¡PARTIDA ENCONTRADA!          |
--          |   [icono] <juego>                    |
--          |   [=========-------]  12 s           |   tiempo para aceptar
--          |   Aceptado: 2/5                      |
--          |      [ Aceptar ]  [ Rechazar ]       |   (tras aceptar: "Esperando al resto...")
--          +--------------------------------------+

EVENTWOW_STR_FOUND_TITLE = "¡PARTIDA ENCONTRADA!";
EVENTWOW_STR_FOUND_ACCEPTED = "Aceptado: |cffffffff%d/%d|r";
EVENTWOW_STR_FOUND_WAITING = "Esperando al resto de jugadores...";
EVENTWOW_STR_FOUND_ACCEPT = "Aceptar";
EVENTWOW_STR_FOUND_DECLINE = "Rechazar";
EVENTWOW_STR_FOUND_SECONDS = "%d s";
EVENTWOW_STR_FOUND_REQUEUED = "Alguien no aceptó la partida. Sigues en la cola.";
EVENTWOW_STR_FOUND_DECLINED = "Has rechazado la partida.";
EVENTWOW_STR_FOUND_MISSED = "No aceptaste la partida a tiempo: has salido de la cola.";

EventWow_MatchFound = {
	-- nil sin propuesta; si no: { id, gameId, total, accepted, iAccepted, declined, endTime, duration }
	current = nil,
};

local function EventWow_FindGame(id)
	for _, game in ipairs(EventWow_Protocol.games) do
		if ( game.id == id ) then
			return game;
		end
	end
	return nil;
end

local function EventWow_Notice(text)
	DEFAULT_CHAT_FRAME:AddMessage(text, 1, 0.82, 0);
	UIErrorsFrame:AddMessage(text, 1, 0.82, 0, 1.0);
end

function EventWowMatchFound_Update()
	local frame = EventWowMatchFoundFrame;
	local current = EventWow_MatchFound.current;
	if ( not current ) then
		frame:Hide();
		return;
	end

	local game = EventWow_FindGame(current.gameId);
	EventWowMatchFoundName:SetText(game and game.name or current.gameId);
	EventWowMatchFoundIcon:SetTexture(game and game.icon or "Interface\\Icons\\INV_Misc_QuestionMark");
	EventWowMatchFoundCount:SetText(format(EVENTWOW_STR_FOUND_ACCEPTED, current.accepted, current.total));

	if ( current.iAccepted ) then
		EventWowMatchFoundAcceptButton:Hide();
		EventWowMatchFoundDeclineButton:Hide();
		EventWowMatchFoundWaiting:Show();
	else
		EventWowMatchFoundAcceptButton:Show();
		EventWowMatchFoundDeclineButton:Show();
		EventWowMatchFoundWaiting:Hide();
	end
	frame:Show();
end

local function EventWow_UpdateTimer()
	local current = EventWow_MatchFound.current;
	if ( not current ) then
		return;
	end
	local left = math.max(0, current.endTime - GetTime());
	local ratio = (current.duration > 0) and (left / current.duration) or 0;
	EventWowMatchFoundTimer:SetValue(ratio);
	-- Verde -> rojo
	EventWowMatchFoundTimer:SetStatusBarColor(1 - ratio, ratio, 0);
	EventWowMatchFoundTimerText:SetText(format(EVENTWOW_STR_FOUND_SECONDS, math.ceil(left)));
end

local function EventWow_Respond(accept)
	local current = EventWow_MatchFound.current;
	if ( not current ) then
		return;
	end
	if ( accept ) then
		PlaySound("igMainMenuOptionCheckBoxOn");
		current.iAccepted = true;
		EventWow_Send("ACCEPT", current.id);
		EventWowMatchFound_Update();
	else
		PlaySound("igMainMenuOptionCheckBoxOff");
		current.declined = true;
		EventWow_Send("DECLINE", current.id);
		EventWowMatchFoundFrame:Hide();
	end
end

local function EventWow_CreateFrame()
	local f = CreateFrame("Frame", "EventWowMatchFoundFrame", UIParent);
	f:SetSize(380, 200);
	f:SetPoint("CENTER", UIParent, "CENTER", 0, 120);
	f:SetFrameStrata("FULLSCREEN_DIALOG");
	f:EnableMouse(true);
	f:SetBackdrop({
		bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	});
	f:SetBackdropColor(0.04, 0.05, 0.08, 0.95);
	f:SetBackdropBorderColor(1, 0.82, 0, 1);

	local title = f:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge");
	title:SetPoint("TOP", f, "TOP", 0, -16);
	title:SetText(EVENTWOW_STR_FOUND_TITLE);

	local icon = f:CreateTexture("EventWowMatchFoundIcon", "ARTWORK");
	icon:SetSize(40, 40);
	icon:SetPoint("TOPLEFT", f, "TOPLEFT", 24, -50);

	local name = f:CreateFontString("EventWowMatchFoundName", "ARTWORK", "GameFontHighlightLarge");
	name:SetPoint("LEFT", icon, "RIGHT", 12, 0);
	name:SetPoint("RIGHT", f, "RIGHT", -24, 0);
	name:SetJustifyH("LEFT");

	-- Tiempo para aceptar
	local timer = CreateFrame("StatusBar", "EventWowMatchFoundTimer", f);
	timer:SetHeight(12);
	timer:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", 0, -12);
	timer:SetPoint("RIGHT", f, "RIGHT", -64, 0);
	timer:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar");
	timer:SetMinMaxValues(0, 1);
	local timerBg = timer:CreateTexture(nil, "BACKGROUND");
	timerBg:SetAllPoints(timer);
	timerBg:SetTexture(0, 0, 0, 0.6);

	local timerText = f:CreateFontString("EventWowMatchFoundTimerText", "ARTWORK", "GameFontHighlight");
	timerText:SetPoint("LEFT", timer, "RIGHT", 8, 0);

	local count = f:CreateFontString("EventWowMatchFoundCount", "ARTWORK", "GameFontNormal");
	count:SetPoint("TOPLEFT", timer, "BOTTOMLEFT", 0, -8);

	local accept = CreateFrame("Button", "EventWowMatchFoundAcceptButton", f, "UIPanelButtonTemplate");
	accept:SetSize(140, 30);
	accept:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -6, 16);
	accept:SetText(EVENTWOW_STR_FOUND_ACCEPT);
	accept:SetScript("OnClick", function() EventWow_Respond(true); end);

	local decline = CreateFrame("Button", "EventWowMatchFoundDeclineButton", f, "UIPanelButtonTemplate");
	decline:SetSize(140, 30);
	decline:SetPoint("BOTTOMLEFT", f, "BOTTOM", 6, 16);
	decline:SetText(EVENTWOW_STR_FOUND_DECLINE);
	decline:SetScript("OnClick", function() EventWow_Respond(false); end);

	local waiting = f:CreateFontString("EventWowMatchFoundWaiting", "ARTWORK", "GameFontHighlightLarge");
	waiting:SetPoint("BOTTOM", f, "BOTTOM", 0, 24);
	waiting:SetText(EVENTWOW_STR_FOUND_WAITING);

	local elapsed = 0;
	f:SetScript("OnUpdate", function(self, delta)
		elapsed = elapsed + delta;
		if ( elapsed >= 0.1 ) then
			elapsed = 0;
			EventWow_UpdateTimer();
		end
	end);

	f:Hide();
end

-- Protocolo -------------------------------------------------------------------------------------

-- MATCH_FOUND <id> <id juego> <segundos> <total> <aceptados> <tu: 0/1>
EventWow_RegisterHandler("MATCH_FOUND", function(fields)
	local seconds = tonumber(fields[3]) or 0;
	local isNew = not EventWow_MatchFound.current or EventWow_MatchFound.current.id ~= fields[1];
	EventWow_MatchFound.current = {
		id = fields[1],
		gameId = fields[2],
		total = tonumber(fields[4]) or 1,
		accepted = tonumber(fields[5]) or 0,
		iAccepted = fields[6] == "1",
		endTime = GetTime() + seconds,
		duration = math.max(seconds, 1),
	};
	if ( isNew ) then
		PlaySound("ReadyCheck");
	end
	EventWowMatchFound_Update();
	EventWow_UpdateTimer();
end);

-- MATCH_FOUND_STATUS <id> <aceptados> <total>
EventWow_RegisterHandler("MATCH_FOUND_STATUS", function(fields)
	local current = EventWow_MatchFound.current;
	if ( not current or current.id ~= fields[1] ) then
		return;
	end
	current.accepted = tonumber(fields[2]) or current.accepted;
	current.total = tonumber(fields[3]) or current.total;
	if ( not current.declined ) then
		EventWowMatchFound_Update();
	end
end);

-- MATCH_FOUND_END <id> ACCEPTED | REQUEUED | REMOVED
EventWow_RegisterHandler("MATCH_FOUND_END", function(fields)
	local current = EventWow_MatchFound.current;
	if ( not current or current.id ~= fields[1] ) then
		return;
	end
	EventWow_MatchFound.current = nil;
	EventWowMatchFoundFrame:Hide();

	local result = fields[2];
	if ( result == "REQUEUED" ) then
		EventWow_Notice(EVENTWOW_STR_FOUND_REQUEUED);
	elseif ( result == "REMOVED" ) then
		-- Si fue otro de tu grupo, el servidor manda ademas un ERROR con su nombre
		if ( current.declined ) then
			EventWow_Notice(EVENTWOW_STR_FOUND_DECLINED);
		elseif ( not current.iAccepted ) then
			EventWow_Notice(EVENTWOW_STR_FOUND_MISSED);
		end
	end
end);

-- Al reconectar el protocolo (/reload) el servidor reenvia MATCH_FOUND si sigue pendiente
EventWow_RegisterListener("CONNECTED", function()
	EventWow_MatchFound.current = nil;
	EventWowMatchFoundFrame:Hide();
end);

EventWow_CreateFrame();
