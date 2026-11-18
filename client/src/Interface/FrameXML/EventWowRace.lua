-- EventWow: carreras (juegos "carrera" y "carrera_estelar"). Todo llega del servidor (EventWowGameRace.cpp):
--   RACE_INFO <vueltas>
--   RACE <vuelta> <vueltas> <posicion> <corredores> <ms carrera> <ms vuelta> <ms mejor vuelta> <contraria 0/1> <terminado 0/1>
--   RACE_EVENT LAP <vuelta> <ms vuelta> | FINAL_LAP | FELL | FINISH <posicion> <ms> | WINNER <nombre> <segundos>
--              | ITEM <hechizo> <hueco> | HIT <hechizo> | BLOCK   (v10: poderes en los huecos 1-5 de la barra de la moto)
--              | MOUNT   (v11: "¡Todos a sus motos!" en la cuenta atras)
--   RACE_RESULTS <final 0/1> <n> (<posicion> <nombre> <ms total, 0 = sin terminar> <ms mejor vuelta>) x n
-- Ver docs/protocolo.md.
--
--   Marcador (arriba a la derecha):  3.º / 8   Vuelta 2/3   Tiempo / Vuelta / Mejor
--   Aviso grande (centro, arriba):   ¡ÚLTIMA VUELTA! / ¡Te has caído! / ¡META! ...
--   Resultados (centro): tabla de posiciones; al terminar la carrera, boton "Salir" (ABANDON).

EVENTWOW_STR_RACE_POSITION = "%d.º|cff999999 / %d|r";
EVENTWOW_STR_RACE_LAP = "Vuelta |cffffffff%d/%d|r";
EVENTWOW_STR_RACE_TIME = "Tiempo |cffffffff%s|r";
EVENTWOW_STR_RACE_LAP_TIME = "Vuelta actual |cffffffff%s|r";
EVENTWOW_STR_RACE_BEST = "Mejor vuelta |cffffffff%s|r";
EVENTWOW_STR_RACE_WRONG_WAY = "¡DIRECCIÓN CONTRARIA!";
EVENTWOW_STR_RACE_NEW_LAP = "Vuelta %d/%d";
EVENTWOW_STR_RACE_FINAL_LAP = "¡ÚLTIMA VUELTA!";
EVENTWOW_STR_RACE_FELL = "¡Te has caído!";
EVENTWOW_STR_RACE_FINISH = "¡META! %d.º puesto";
EVENTWOW_STR_RACE_WINNER = "%s ha ganado la carrera: quedan %d s para terminar.";
EVENTWOW_STR_RACE_RESULTS = "Resultados";
EVENTWOW_STR_RACE_PROVISIONAL = "Clasificación provisional";
EVENTWOW_STR_RACE_WAITING = "Esperando a que terminen los demás...";
EVENTWOW_STR_RACE_NOT_FINISHED = "Sin terminar";
EVENTWOW_STR_RACE_EXIT = "Salir";
EVENTWOW_STR_RACE_HEADERS = { "Pos.", "Piloto", "Tiempo", "Mejor vuelta" };
EVENTWOW_STR_RACE_ITEM = "%s  |cffffffff(tecla %d)|r";
EVENTWOW_STR_RACE_HIT = "¡%s!";
EVENTWOW_STR_RACE_BLOCK = "¡El escudo te ha protegido!";
EVENTWOW_STR_RACE_MOUNT = "¡Todos a sus motos!";

local RACE_MAX_ROWS = 8;

EventWow_Race = {
	active = false,
	laps = 3,
	-- Ultimo RACE y el GetTime() en que llego (para que el reloj avance entre mensajes)
	data = nil,
	receivedAt = 0,
};

-- 83450 ms -> "1:23.45"
local function EventWowRace_FormatMs(ms)
	ms = math.max(0, ms or 0);
	local minutes = math.floor(ms / 60000);
	local seconds = (ms - minutes * 60000) / 1000;
	return format("%d:%05.2f", minutes, seconds);
end

-- Construccion -----------------------------------------------------------------------------------

local function EventWowRace_CreateFrames()
	-- Marcador
	local hud = CreateFrame("Frame", "EventWowRaceHud", UIParent);
	hud:SetSize(230, 118);
	hud:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -24, -150);
	hud:SetFrameStrata("MEDIUM");
	hud:SetBackdrop(EVENTWOW_PANEL.BACKDROP);
	hud:SetBackdropColor(unpack(EVENTWOW_PANEL.COLOR_SECTION));
	hud:SetBackdropBorderColor(unpack(EVENTWOW_PANEL.COLOR_BORDER));
	hud:Hide();

	local position = hud:CreateFontString("EventWowRacePosition", "ARTWORK");
	position:SetFont("Fonts\\FRIZQT__.TTF", 34, "THICKOUTLINE");
	position:SetPoint("TOPLEFT", hud, "TOPLEFT", 12, -10);
	position:SetTextColor(1, 0.82, 0);

	local lap = hud:CreateFontString("EventWowRaceLap", "ARTWORK", "GameFontNormalLarge");
	lap:SetPoint("TOPRIGHT", hud, "TOPRIGHT", -12, -18);
	lap:SetJustifyH("RIGHT");

	local total = hud:CreateFontString("EventWowRaceTotal", "ARTWORK", "GameFontNormal");
	total:SetPoint("TOPLEFT", position, "BOTTOMLEFT", 0, -8);
	local lapTime = hud:CreateFontString("EventWowRaceLapTime", "ARTWORK", "GameFontNormalSmall");
	lapTime:SetPoint("TOPLEFT", total, "BOTTOMLEFT", 0, -4);
	local best = hud:CreateFontString("EventWowRaceBest", "ARTWORK", "GameFontNormalSmall");
	best:SetPoint("TOPLEFT", lapTime, "BOTTOMLEFT", 0, -4);

	hud:SetScript("OnUpdate", function(self, elapsed)
		self.elapsed = (self.elapsed or 0) + elapsed;
		if ( self.elapsed >= 0.05 ) then
			self.elapsed = 0;
			EventWowRace_UpdateClock();
		end
	end);

	-- Aviso de direccion contraria (parpadea)
	local wrong = CreateFrame("Frame", "EventWowRaceWrongWay", UIParent);
	wrong:SetSize(600, 60);
	wrong:SetPoint("CENTER", UIParent, "CENTER", 0, 40);
	wrong:SetFrameStrata("HIGH");
	wrong:Hide();
	local wrongText = wrong:CreateFontString(nil, "OVERLAY");
	wrongText:SetFont("Fonts\\FRIZQT__.TTF", 36, "THICKOUTLINE");
	wrongText:SetPoint("CENTER");
	wrongText:SetTextColor(1, 0.15, 0.15);
	wrongText:SetText(EVENTWOW_STR_RACE_WRONG_WAY);
	wrong:SetScript("OnUpdate", function(self)
		self:SetAlpha(0.55 + 0.45 * math.abs(math.sin(GetTime() * 4)));
	end);

	-- Aviso grande (vueltas, caidas, meta)
	local notice = CreateFrame("Frame", "EventWowRaceNotice", UIParent);
	notice:SetSize(700, 70);
	notice:SetPoint("CENTER", UIParent, "CENTER", 0, 190);
	notice:SetFrameStrata("HIGH");
	notice:Hide();
	local noticeText = notice:CreateFontString("EventWowRaceNoticeText", "OVERLAY");
	noticeText:SetFont("Fonts\\FRIZQT__.TTF", 40, "THICKOUTLINE");
	noticeText:SetPoint("CENTER");
	notice:SetScript("OnUpdate", function(self)
		if ( self.hideAt and GetTime() >= self.hideAt ) then
			self.hideAt = nil;
			self:Hide();
		end
	end);

	-- Resultados
	local results = CreateFrame("Frame", "EventWowRaceResults", UIParent);
	results:SetSize(460, 92 + RACE_MAX_ROWS * 22);
	results:SetPoint("CENTER", UIParent, "CENTER", 0, -70);
	results:SetFrameStrata("DIALOG");
	results:SetBackdrop(EVENTWOW_PANEL.BACKDROP);
	results:SetBackdropColor(0.03, 0.03, 0.05, 0.92);
	results:SetBackdropBorderColor(unpack(EVENTWOW_PANEL.COLOR_BORDER));
	results:EnableMouse(true);
	results:Hide();

	local title = results:CreateFontString("EventWowRaceResultsTitle", "ARTWORK", "GameFontNormalLarge");
	title:SetPoint("TOP", results, "TOP", 0, -12);

	local columns = { 16, 64, 250, 350 };
	results.headers = {};
	for i, text in ipairs(EVENTWOW_STR_RACE_HEADERS) do
		local header = results:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall");
		header:SetPoint("TOPLEFT", results, "TOPLEFT", columns[i], -40);
		header:SetText(text);
	end

	results.rows = {};
	for i = 1, RACE_MAX_ROWS do
		local row = {};
		local y = -58 - (i - 1) * 22;
		for c = 1, 4 do
			local cell = results:CreateFontString(nil, "ARTWORK", "GameFontHighlight");
			cell:SetPoint("TOPLEFT", results, "TOPLEFT", columns[c], y);
			cell:SetJustifyH("LEFT");
			row[c] = cell;
		end
		results.rows[i] = row;
	end

	local status = results:CreateFontString("EventWowRaceResultsStatus", "ARTWORK", "GameFontHighlightSmall");
	status:SetPoint("BOTTOMLEFT", results, "BOTTOMLEFT", 16, 18);

	local exit = CreateFrame("Button", "EventWowRaceResultsExit", results, "UIPanelButtonTemplate");
	exit:SetSize(140, 24);
	exit:SetPoint("BOTTOMRIGHT", results, "BOTTOMRIGHT", -14, 12);
	exit:SetText(EVENTWOW_STR_RACE_EXIT);
	exit:SetScript("OnClick", function()
		EventWow_Send("ABANDON");
	end);
end

-- Actualizacion ----------------------------------------------------------------------------------

function EventWowRace_UpdateClock()
	local data = EventWow_Race.data;
	if ( not data ) then
		return;
	end
	-- Entre mensajes el reloj sigue corriendo (salvo terminado o fuera de "en juego")
	local extra = 0;
	if ( not data.finished and EventWow_Match.state == "RUNNING" ) then
		extra = (GetTime() - EventWow_Race.receivedAt) * 1000;
	end
	EventWowRaceTotal:SetText(format(EVENTWOW_STR_RACE_TIME, EventWowRace_FormatMs(data.total + extra)));
	if ( data.finished ) then
		EventWowRaceLapTime:SetText("");
	else
		EventWowRaceLapTime:SetText(format(EVENTWOW_STR_RACE_LAP_TIME, EventWowRace_FormatMs(data.lapTime + extra)));
	end
	if ( data.best > 0 ) then
		EventWowRaceBest:SetText(format(EVENTWOW_STR_RACE_BEST, EventWowRace_FormatMs(data.best)));
	else
		EventWowRaceBest:SetText(format(EVENTWOW_STR_RACE_BEST, "-"));
	end
end

local function EventWowRace_ShowNotice(text, seconds, r, g, b)
	EventWowRaceNoticeText:SetText(text);
	EventWowRaceNoticeText:SetTextColor(r or 1, g or 0.82, b or 0);
	EventWowRaceNotice.hideAt = GetTime() + (seconds or 2.5);
	EventWowRaceNotice:Show();
end

local function EventWowRace_Reset()
	EventWow_Race.active = false;
	EventWow_Race.data = nil;
	EventWowRaceHud:Hide();
	EventWowRaceWrongWay:Hide();
	EventWowRaceNotice:Hide();
	EventWowRaceResults:Hide();
end

-- Protocolo -------------------------------------------------------------------------------------

-- RACE_INFO <vueltas>: empieza una carrera (al llegar a la instancia)
EventWow_RegisterHandler("RACE_INFO", function(fields)
	EventWowRace_Reset();
	EventWow_Race.active = true;
	EventWow_Race.laps = tonumber(fields[1]) or 3;
end);

EventWow_RegisterHandler("RACE", function(fields)
	local data = {
		lap = tonumber(fields[1]) or 1,
		laps = tonumber(fields[2]) or EventWow_Race.laps,
		position = tonumber(fields[3]) or 1,
		racers = tonumber(fields[4]) or 1,
		total = tonumber(fields[5]) or 0,
		lapTime = tonumber(fields[6]) or 0,
		best = tonumber(fields[7]) or 0,
		wrongWay = fields[8] == "1",
		finished = fields[9] == "1",
	};
	EventWow_Race.active = true;
	EventWow_Race.data = data;
	EventWow_Race.receivedAt = GetTime();

	EventWowRacePosition:SetText(format(EVENTWOW_STR_RACE_POSITION, data.position, data.racers));
	EventWowRaceLap:SetText(format(EVENTWOW_STR_RACE_LAP, data.lap, data.laps));
	EventWowRace_UpdateClock();
	EventWowRaceHud:Show();
	if ( data.wrongWay and not data.finished ) then
		EventWowRaceWrongWay:Show();
	else
		EventWowRaceWrongWay:Hide();
	end
end);

EventWow_RegisterHandler("RACE_EVENT", function(fields)
	local event = fields[1];
	if ( event == "LAP" ) then
		EventWowRace_ShowNotice(format(EVENTWOW_STR_RACE_NEW_LAP, tonumber(fields[2]) or 0, EventWow_Race.laps), 2);
		PlaySound("igQuestListComplete");
	elseif ( event == "FINAL_LAP" ) then
		EventWowRace_ShowNotice(EVENTWOW_STR_RACE_FINAL_LAP, 3, 1, 0.5, 0.1);
		PlaySound("RaidWarning");
	elseif ( event == "FELL" ) then
		EventWowRace_ShowNotice(EVENTWOW_STR_RACE_FELL, 2, 1, 0.3, 0.3);
	elseif ( event == "FINISH" ) then
		local position = tonumber(fields[2]) or 0;
		EventWowRace_ShowNotice(format(EVENTWOW_STR_RACE_FINISH, position)..
			"  |cffffffff"..EventWowRace_FormatMs(tonumber(fields[3]) or 0).."|r", 5, 0.2, 1, 0.2);
		EventWowRaceWrongWay:Hide();
		PlaySound("LEVELUPSOUND");
	elseif ( event == "WINNER" ) then
		DEFAULT_CHAT_FRAME:AddMessage(format(EVENTWOW_STR_RACE_WINNER, fields[2] or "?", tonumber(fields[3]) or 0),
			1, 0.82, 0);
	elseif ( event == "ITEM" ) then
		-- Poder recogido de una caja: nombre del hechizo (Spell.dbc del parche)
		local name = GetSpellInfo(tonumber(fields[2]) or 0) or "?";
		EventWowRace_ShowNotice(format(EVENTWOW_STR_RACE_ITEM, name, tonumber(fields[3]) or 1), 2, 0.4, 0.8, 1);
		PlaySound("igMainMenuOptionCheckBoxOn");
	elseif ( event == "HIT" ) then
		local name = GetSpellInfo(tonumber(fields[2]) or 0) or "?";
		EventWowRace_ShowNotice(format(EVENTWOW_STR_RACE_HIT, name), 1.5, 1, 0.3, 0.3);
		PlaySound("RaidWarning");
	elseif ( event == "BLOCK" ) then
		EventWowRace_ShowNotice(EVENTWOW_STR_RACE_BLOCK, 1.5, 1, 1, 0.6);
	elseif ( event == "MOUNT" ) then
		EventWowRace_ShowNotice(EVENTWOW_STR_RACE_MOUNT, 3, 1, 0.82, 0);
		PlaySound("RaidWarning");
	end
end);

-- RACE_RESULTS <final 0/1> <n> (<posicion> <nombre> <ms total> <ms mejor vuelta>) x n
EventWow_RegisterHandler("RACE_RESULTS", function(fields)
	local final = fields[1] == "1";
	local count = tonumber(fields[2]) or 0;
	local results = EventWowRaceResults;
	local me = UnitName("player");

	for i = 1, RACE_MAX_ROWS do
		local row = results.rows[i];
		local base = 2 + (i - 1) * 4;
		if ( i <= count ) then
			local name = fields[base + 2] or "?";
			local total = tonumber(fields[base + 3]) or 0;
			local best = tonumber(fields[base + 4]) or 0;
			row[1]:SetText(fields[base + 1] or "");
			row[2]:SetText(name);
			row[3]:SetText(total > 0 and EventWowRace_FormatMs(total) or EVENTWOW_STR_RACE_NOT_FINISHED);
			row[4]:SetText(best > 0 and EventWowRace_FormatMs(best) or "-");
			local r, g, b = 1, 1, 1;
			if ( name == me ) then
				r, g, b = 1, 0.82, 0;
			elseif ( total == 0 ) then
				r, g, b = 0.6, 0.6, 0.6;
			end
			for c = 1, 4 do
				row[c]:SetTextColor(r, g, b);
			end
		else
			for c = 1, 4 do
				row[c]:SetText("");
			end
		end
	end

	-- Se muestra al terminar yo (provisional) y siempre al final de la carrera (con el boton de salir)
	local finished = EventWow_Race.data and EventWow_Race.data.finished;
	if ( final ) then
		EventWowRaceResultsTitle:SetText(EVENTWOW_STR_RACE_RESULTS);
		EventWowRaceResultsStatus:SetText("");
		EventWowRaceResultsExit:Show();
		EventWowRaceWrongWay:Hide();
		results:Show();
	elseif ( finished ) then
		EventWowRaceResultsTitle:SetText(EVENTWOW_STR_RACE_PROVISIONAL);
		EventWowRaceResultsStatus:SetText(EVENTWOW_STR_RACE_WAITING);
		EventWowRaceResultsExit:Hide();
		results:Show();
	end
end);

-- Fuera de la partida: todo oculto
EventWow_RegisterListener("MATCH", function()
	if ( not EventWow_Match.state ) then
		EventWowRace_Reset();
	end
end);

EventWowRace_CreateFrames();
