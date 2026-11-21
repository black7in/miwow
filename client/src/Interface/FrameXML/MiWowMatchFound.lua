-- MiWow: "Partida encontrada" (confirmacion tipo Dota 2). Contraparte: MiWowMatchMgr (propuestas).
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

MIWOW_STR_FOUND_TITLE = "¡PARTIDA ENCONTRADA!";
MIWOW_STR_FOUND_ACCEPTED = "Aceptado: |cffffffff%d/%d|r";
MIWOW_STR_FOUND_WAITING = "Esperando al resto de jugadores...";
MIWOW_STR_FOUND_ACCEPT = "Aceptar";
MIWOW_STR_FOUND_DECLINE = "Rechazar";
MIWOW_STR_FOUND_SECONDS = "%d s";
MIWOW_STR_FOUND_REQUEUED = "Alguien no aceptó la partida. Sigues en la cola.";
MIWOW_STR_FOUND_DECLINED = "Has rechazado la partida.";
MIWOW_STR_FOUND_MISSED = "No aceptaste la partida a tiempo: has salido de la cola.";

MiWow_MatchFound = {
	-- nil sin propuesta; si no: { id, gameId, total, accepted, iAccepted, declined, endTime, duration }
	current = nil,
};

local function MiWow_FindGame(id)
	for _, game in ipairs(MiWow_Protocol.games) do
		if ( game.id == id ) then
			return game;
		end
	end
	return nil;
end

local function MiWow_Notice(text)
	DEFAULT_CHAT_FRAME:AddMessage(text, 1, 0.82, 0);
	UIErrorsFrame:AddMessage(text, 1, 0.82, 0, 1.0);
end

function MiWowMatchFound_Update()
	local frame = MiWowMatchFoundFrame;
	local current = MiWow_MatchFound.current;
	if ( not current ) then
		frame:Hide();
		return;
	end

	local game = MiWow_FindGame(current.gameId);
	MiWowMatchFoundName:SetText(game and game.name or current.gameId);
	MiWowMatchFoundIcon:SetTexture(game and game.icon or "Interface\\Icons\\INV_Misc_QuestionMark");
	MiWowMatchFoundCount:SetText(format(MIWOW_STR_FOUND_ACCEPTED, current.accepted, current.total));

	if ( current.iAccepted ) then
		MiWowMatchFoundAcceptButton:Hide();
		MiWowMatchFoundDeclineButton:Hide();
		MiWowMatchFoundWaiting:Show();
	else
		MiWowMatchFoundAcceptButton:Show();
		MiWowMatchFoundDeclineButton:Show();
		MiWowMatchFoundWaiting:Hide();
	end
	frame:Show();
end

local function MiWow_UpdateTimer()
	local current = MiWow_MatchFound.current;
	if ( not current ) then
		return;
	end
	local left = math.max(0, current.endTime - GetTime());
	local ratio = (current.duration > 0) and (left / current.duration) or 0;
	MiWowMatchFoundTimer:SetValue(ratio);
	-- Verde -> rojo
	MiWowMatchFoundTimer:SetStatusBarColor(1 - ratio, ratio, 0);
	MiWowMatchFoundTimerText:SetText(format(MIWOW_STR_FOUND_SECONDS, math.ceil(left)));
end

local function MiWow_Respond(accept)
	local current = MiWow_MatchFound.current;
	if ( not current ) then
		return;
	end
	if ( accept ) then
		PlaySound("igMainMenuOptionCheckBoxOn");
		current.iAccepted = true;
		MiWow_Send("ACCEPT", current.id);
		MiWowMatchFound_Update();
	else
		PlaySound("igMainMenuOptionCheckBoxOff");
		current.declined = true;
		MiWow_Send("DECLINE", current.id);
		MiWowMatchFoundFrame:Hide();
	end
end

local function MiWow_CreateFrame()
	local f = CreateFrame("Frame", "MiWowMatchFoundFrame", UIParent);
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
	title:SetText(MIWOW_STR_FOUND_TITLE);

	local icon = f:CreateTexture("MiWowMatchFoundIcon", "ARTWORK");
	icon:SetSize(40, 40);
	icon:SetPoint("TOPLEFT", f, "TOPLEFT", 24, -50);

	local name = f:CreateFontString("MiWowMatchFoundName", "ARTWORK", "GameFontHighlightLarge");
	name:SetPoint("LEFT", icon, "RIGHT", 12, 0);
	name:SetPoint("RIGHT", f, "RIGHT", -24, 0);
	name:SetJustifyH("LEFT");

	-- Tiempo para aceptar
	local timer = CreateFrame("StatusBar", "MiWowMatchFoundTimer", f);
	timer:SetHeight(12);
	timer:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", 0, -12);
	timer:SetPoint("RIGHT", f, "RIGHT", -64, 0);
	timer:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar");
	timer:SetMinMaxValues(0, 1);
	local timerBg = timer:CreateTexture(nil, "BACKGROUND");
	timerBg:SetAllPoints(timer);
	timerBg:SetTexture(0, 0, 0, 0.6);

	local timerText = f:CreateFontString("MiWowMatchFoundTimerText", "ARTWORK", "GameFontHighlight");
	timerText:SetPoint("LEFT", timer, "RIGHT", 8, 0);

	local count = f:CreateFontString("MiWowMatchFoundCount", "ARTWORK", "GameFontNormal");
	count:SetPoint("TOPLEFT", timer, "BOTTOMLEFT", 0, -8);

	local accept = CreateFrame("Button", "MiWowMatchFoundAcceptButton", f, "UIPanelButtonTemplate");
	accept:SetSize(140, 30);
	accept:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -6, 16);
	accept:SetText(MIWOW_STR_FOUND_ACCEPT);
	accept:SetScript("OnClick", function() MiWow_Respond(true); end);

	local decline = CreateFrame("Button", "MiWowMatchFoundDeclineButton", f, "UIPanelButtonTemplate");
	decline:SetSize(140, 30);
	decline:SetPoint("BOTTOMLEFT", f, "BOTTOM", 6, 16);
	decline:SetText(MIWOW_STR_FOUND_DECLINE);
	decline:SetScript("OnClick", function() MiWow_Respond(false); end);

	local waiting = f:CreateFontString("MiWowMatchFoundWaiting", "ARTWORK", "GameFontHighlightLarge");
	waiting:SetPoint("BOTTOM", f, "BOTTOM", 0, 24);
	waiting:SetText(MIWOW_STR_FOUND_WAITING);

	local elapsed = 0;
	f:SetScript("OnUpdate", function(self, delta)
		elapsed = elapsed + delta;
		if ( elapsed >= 0.1 ) then
			elapsed = 0;
			MiWow_UpdateTimer();
		end
	end);

	f:Hide();
end

-- Protocolo -------------------------------------------------------------------------------------

-- MATCH_FOUND <id> <id juego> <segundos> <total> <aceptados> <tu: 0/1>
MiWow_RegisterHandler("MATCH_FOUND", function(fields)
	local seconds = tonumber(fields[3]) or 0;
	local isNew = not MiWow_MatchFound.current or MiWow_MatchFound.current.id ~= fields[1];
	MiWow_MatchFound.current = {
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
	MiWowMatchFound_Update();
	MiWow_UpdateTimer();
end);

-- MATCH_FOUND_STATUS <id> <aceptados> <total>
MiWow_RegisterHandler("MATCH_FOUND_STATUS", function(fields)
	local current = MiWow_MatchFound.current;
	if ( not current or current.id ~= fields[1] ) then
		return;
	end
	current.accepted = tonumber(fields[2]) or current.accepted;
	current.total = tonumber(fields[3]) or current.total;
	if ( not current.declined ) then
		MiWowMatchFound_Update();
	end
end);

-- MATCH_FOUND_END <id> ACCEPTED | REQUEUED | REMOVED
MiWow_RegisterHandler("MATCH_FOUND_END", function(fields)
	local current = MiWow_MatchFound.current;
	if ( not current or current.id ~= fields[1] ) then
		return;
	end
	MiWow_MatchFound.current = nil;
	MiWowMatchFoundFrame:Hide();

	local result = fields[2];
	if ( result == "REQUEUED" ) then
		MiWow_Notice(MIWOW_STR_FOUND_REQUEUED);
	elseif ( result == "REMOVED" ) then
		-- Si fue otro de tu grupo, el servidor manda ademas un ERROR con su nombre
		if ( current.declined ) then
			MiWow_Notice(MIWOW_STR_FOUND_DECLINED);
		elseif ( not current.iAccepted ) then
			MiWow_Notice(MIWOW_STR_FOUND_MISSED);
		end
	end
end);

-- Al reconectar el protocolo (/reload) el servidor reenvia MATCH_FOUND si sigue pendiente
MiWow_RegisterListener("CONNECTED", function()
	MiWow_MatchFound.current = nil;
	MiWowMatchFoundFrame:Hide();
end);

MiWow_CreateFrame();
