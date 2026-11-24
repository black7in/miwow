-- MiWow: partida en curso (HUD generico). Todo lo que muestra llega del servidor:
--   MATCH_STATE <NONE | LOADING|WAITING|COUNTDOWN|RUNNING|ENDED> <id juego> <segundos>
--   MATCH_HUD <linea> [<linea>...] (objetivo; cada linea, trozos " - " de "Etiqueta: valor")
--   MATCH_RESPAWN <segundos> (has muerto: reapareces en N; 0 = ya)
--   MATCH_END <WIN|LOSE|NONE> <texto>
--   MATCH_CHOICE <id> <titulo> <texto> <segundos> <nombre> <detalle> [<nombre> <detalle>...]  (ventana de eleccion)
--   MATCH_CHOICE_END                                         (cerrarla: ya se eligio o se acabo el tiempo)
--   MATCH_SHOP <titulo> <moneda> <cantidad> (<id> <categoria> <icono> <nombre> <detalle> <precio>)...  (tienda)
--   MATCH_SHOP_CLOSE                                         (cerrarla: lejos del vendedor, fin de partida)
-- y manda CHOOSE <id> <n> (opcion elegida, desde 1) para la ventana de eleccion, SHOP_BUY <id> / SHOP_CLOSE para la
-- tienda.
-- y manda ABANDON para salir (el servidor te devuelve a donde estabas). Ver docs/protocolo.md.
--
-- LOADING: el servidor ya nos esta llevando a la instancia; seguimos en modo mundo (el panel muestra
-- "Entrando..."). Desde WAITING (ya dentro) hasta NONE (de vuelta a donde estabas): modo partida
-- (MiWow_SetMode, MiWow.lua): mundo visible + este HUD.
--
--     ....::::  <juego>  ::::....  [Abandonar]   MiWowMatchHud (arriba, centrado): franja oscura que se
--     ..::::     Tiempo: 0:25    ::::..             difumina a los lados, sin marco
--     ..::  Etapa 1/5: Los vrykul   ::..            Etiqueta en dorado, valor en blanco
--     ..::  Torre: 100 %    Oro: 40  ::..
--                3 / ¡VICTORIA!                     MiWowMatchBigText (centro)

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

-- "Etiqueta: valor - Etiqueta: valor" -> etiqueta dorada, valor blanco, trozos separados por espacios
local function MiWow_FormatHudLine(line)
	local parts = {};
	local start = 1;
	while ( true ) do
		local from, to = string.find(line, " - ", start, true);
		local segment = string.sub(line, start, (from or 0) - 1);
		local label, value = string.match(segment, "^(.-):%s+(.+)$");
		if ( label ) then
			tinsert(parts, "|cffffd100" .. label .. ":|r |cffffffff" .. value .. "|r");
		else
			tinsert(parts, "|cffffffff" .. segment .. "|r");
		end
		if ( not from ) then
			break;
		end
		start = to + 1;
	end
	return table.concat(parts, "     ");
end

local function MiWow_FormatHud(fields)
	local lines = {};
	for _, line in ipairs(fields) do
		if ( line ~= "" ) then
			tinsert(lines, MiWow_FormatHudLine(line));
		end
	end
	return table.concat(lines, "\n");
end

-- Alto de la franja segun las lineas del objetivo
local function MiWow_LayoutHud()
	local objective = MiWowMatchHudObjective;
	local height = 50;
	if ( (objective:GetText() or "") ~= "" ) then
		height = height + objective:GetStringHeight() + 6;
	end
	MiWowMatchHud:SetHeight(height);
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
	MiWow_LayoutHud();
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
	hud:SetSize(520, 50);
	hud:SetPoint("TOP", UIParent, "TOP", 0, -16);
	hud:SetFrameStrata("MEDIUM");
	hud:Hide();

	-- Franja oscura: opaca en el centro y transparente en los extremos (dos mitades con degradado)
	local left = hud:CreateTexture(nil, "BACKGROUND");
	left:SetTexture("Interface\\Buttons\\WHITE8X8");
	left:SetPoint("TOPLEFT", hud, "TOPLEFT");
	left:SetPoint("BOTTOMRIGHT", hud, "BOTTOM");
	left:SetGradientAlpha("HORIZONTAL", 0, 0, 0, 0, 0, 0, 0, 0.6);
	local right = hud:CreateTexture(nil, "BACKGROUND");
	right:SetTexture("Interface\\Buttons\\WHITE8X8");
	right:SetPoint("TOPLEFT", hud, "TOP");
	right:SetPoint("BOTTOMRIGHT", hud, "BOTTOMRIGHT");
	right:SetGradientAlpha("HORIZONTAL", 0, 0, 0, 0.6, 0, 0, 0, 0);

	local title = hud:CreateFontString("MiWowMatchHudTitle", "ARTWORK", "GameFontNormalLarge");
	title:SetPoint("TOP", hud, "TOP", 0, -8);
	title:SetShadowOffset(1, -1);

	-- Linea dorada bajo el titulo, tambien difuminada a los lados
	local lineLeft = hud:CreateTexture(nil, "ARTWORK");
	lineLeft:SetTexture("Interface\\Buttons\\WHITE8X8");
	lineLeft:SetHeight(1);
	lineLeft:SetPoint("TOPLEFT", hud, "TOPLEFT", 60, -29);
	lineLeft:SetPoint("TOPRIGHT", hud, "TOP", 0, -29);
	lineLeft:SetGradientAlpha("HORIZONTAL", 1, 0.82, 0, 0, 1, 0.82, 0, 0.8);
	local lineRight = hud:CreateTexture(nil, "ARTWORK");
	lineRight:SetTexture("Interface\\Buttons\\WHITE8X8");
	lineRight:SetHeight(1);
	lineRight:SetPoint("TOPLEFT", hud, "TOP", 0, -29);
	lineRight:SetPoint("TOPRIGHT", hud, "TOPRIGHT", -60, -29);
	lineRight:SetGradientAlpha("HORIZONTAL", 1, 0.82, 0, 0.8, 1, 0.82, 0, 0);

	local status = hud:CreateFontString("MiWowMatchHudStatus", "ARTWORK", "GameFontHighlightSmall");
	status:SetPoint("TOP", hud, "TOP", 0, -34);

	local objective = hud:CreateFontString("MiWowMatchHudObjective", "ARTWORK", "GameFontHighlight");
	objective:SetPoint("TOP", status, "BOTTOM", 0, -6);
	objective:SetWidth(500);
	objective:SetJustifyH("CENTER");
	objective:SetSpacing(3);
	objective:SetShadowOffset(1, -1);

	-- Abandonar: boton pequeno en el extremo derecho de la franja
	local abandon = CreateFrame("Button", "MiWowMatchHudAbandon", hud, "UIPanelButtonTemplate");
	abandon:SetSize(84, 20);
	abandon:SetPoint("TOPRIGHT", hud, "TOPRIGHT", -6, -6);
	abandon:SetNormalFontObject("GameFontNormalSmall");
	abandon:SetHighlightFontObject("GameFontHighlightSmall");
	abandon:SetText(MIWOW_STR_MATCH_ABANDON);
	abandon:SetScript("OnClick", function()
		if ( MiWow_Match.state == "ENDED" ) then
			MiWow_Send("ABANDON");
		else
			StaticPopup_Show("MIWOW_ABANDON_MATCH");
		end
	end);

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
	MiWowMatchChoiceFrame:Hide();
	MiWowMatchShop_Close();
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

-- MATCH_HUD <linea> [<linea>...]
MiWow_RegisterHandler("MATCH_HUD", function(fields)
	MiWow_Match.hud = MiWow_FormatHud(fields);
	if ( MiWowMatchHud:IsShown() ) then
		MiWowMatchHudObjective:SetText(MiWow_Match.hud);
		MiWow_LayoutHud();
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

-- Ventana de eleccion (MATCH_CHOICE): titulo, texto y una fila por opcion (nombre + detalle) -------------------
--
--          +--------------------------------------+
--          |              <titulo>                |
--          |   <texto>                            |
--          |  +--------------------------------+  |
--          |  | <nombre>                       |  |   una fila por opcion (clic = elegir)
--          |  | <detalle>                      |  |
--          |  +--------------------------------+  |
--          |              0:45                    |   tiempo para elegir (0 = sin tiempo)
--          +--------------------------------------+

MIWOW_CHOICE_MAX_OPTIONS = 6;
MIWOW_STR_CHOICE_TIME = "Tiempo para elegir: |cffffffff%s|r";

MiWow_MatchChoice = { id = nil, endTime = nil };

local function MiWow_CreateChoice()
	local f = CreateFrame("Frame", "MiWowMatchChoiceFrame", UIParent);
	f:SetWidth(400);
	f:SetPoint("CENTER", UIParent, "CENTER", 0, 60);
	f:SetFrameStrata("DIALOG");
	f:EnableMouse(true);
	f:SetBackdrop({
		bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	});
	f:SetBackdropColor(0.04, 0.05, 0.08, 0.95);
	f:SetBackdropBorderColor(1, 0.82, 0, 1);
	f:Hide();

	local title = f:CreateFontString("MiWowMatchChoiceTitle", "ARTWORK", "GameFontNormalHuge");
	title:SetPoint("TOP", f, "TOP", 0, -16);

	local text = f:CreateFontString("MiWowMatchChoiceText", "ARTWORK", "GameFontHighlight");
	text:SetPoint("TOP", title, "BOTTOM", 0, -10);
	text:SetWidth(352);
	text:SetJustifyH("CENTER");

	for i = 1, MIWOW_CHOICE_MAX_OPTIONS do
		local b = CreateFrame("Button", "MiWowMatchChoiceOption" .. i, f);
		b:SetSize(352, 44);
		b:SetBackdrop({
			bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 12,
			insets = { left = 3, right = 3, top = 3, bottom = 3 },
		});
		b:SetBackdropColor(0.1, 0.1, 0.14, 0.9);
		b:SetBackdropBorderColor(0.35, 0.35, 0.4, 1);
		local highlight = b:CreateTexture(nil, "HIGHLIGHT");
		highlight:SetTexture("Interface\\Buttons\\UI-Listbox-Highlight2");
		highlight:SetBlendMode("ADD");
		highlight:SetPoint("TOPLEFT", b, "TOPLEFT", 4, -4);
		highlight:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -4, 4);
		highlight:SetVertexColor(1, 0.82, 0, 0.35);

		local name = b:CreateFontString("MiWowMatchChoiceOption" .. i .. "Name", "ARTWORK", "GameFontNormalLarge");
		name:SetPoint("TOPLEFT", b, "TOPLEFT", 12, -7);
		local info = b:CreateFontString("MiWowMatchChoiceOption" .. i .. "Info", "ARTWORK", "GameFontHighlightSmall");
		info:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -3);
		info:SetPoint("RIGHT", b, "RIGHT", -12, 0);
		info:SetJustifyH("LEFT");

		b:SetID(i);
		b:SetScript("OnClick", function(self)
			if ( MiWow_MatchChoice.id ) then
				PlaySound("igMainMenuOptionCheckBoxOn");
				MiWow_Send("CHOOSE", MiWow_MatchChoice.id, self:GetID());
			end
		end);
		b:Hide();
	end

	local timer = f:CreateFontString("MiWowMatchChoiceTimer", "ARTWORK", "GameFontNormalSmall");
	timer:SetPoint("BOTTOM", f, "BOTTOM", 0, 14);

	local elapsed = 0;
	f:SetScript("OnUpdate", function(self, delta)
		elapsed = elapsed + delta;
		if ( elapsed < 0.2 ) then
			return;
		end
		elapsed = 0;
		local endTime = MiWow_MatchChoice.endTime;
		if ( endTime ) then
			MiWowMatchChoiceTimer:SetText(format(MIWOW_STR_CHOICE_TIME, MiWow_FormatTime(endTime - GetTime())));
		else
			MiWowMatchChoiceTimer:SetText("");
		end
	end);
end

-- MATCH_CHOICE <id> <titulo> <texto> <segundos> (<nombre> <detalle>)...
MiWow_RegisterHandler("MATCH_CHOICE", function(fields)
	local choice = MiWow_MatchChoice;
	choice.id = fields[1];
	local seconds = tonumber(fields[4]) or 0;
	choice.endTime = (seconds > 0) and (GetTime() + seconds) or nil;

	MiWowMatchChoiceTitle:SetText(fields[2] or "");
	MiWowMatchChoiceText:SetText(fields[3] or "");

	local previous = MiWowMatchChoiceText;
	local shown = 0;
	for i = 1, MIWOW_CHOICE_MAX_OPTIONS do
		local button = _G["MiWowMatchChoiceOption" .. i];
		local name = fields[3 + i * 2];
		if ( name ) then
			_G["MiWowMatchChoiceOption" .. i .. "Name"]:SetText(name);
			_G["MiWowMatchChoiceOption" .. i .. "Info"]:SetText(fields[4 + i * 2] or "");
			button:ClearAllPoints();
			button:SetPoint("TOP", previous, "BOTTOM", 0, (i == 1) and -14 or -6);
			button:Show();
			previous = button;
			shown = shown + 1;
		else
			button:Hide();
		end
	end

	MiWowMatchChoiceFrame:SetHeight(16 + 30 + 10 + MiWowMatchChoiceText:GetStringHeight() + 14 + shown * 50 + 34);
	MiWowMatchChoiceFrame:Show();
end);

-- MATCH_CHOICE_END
MiWow_RegisterHandler("MATCH_CHOICE_END", function()
	MiWow_MatchChoice.id = nil;
	MiWow_MatchChoice.endTime = nil;
	MiWowMatchChoiceFrame:Hide();
end);

-- Tienda de la partida (MATCH_SHOP): pestanas por categoria y una cuadricula de articulos -----------------------
--
--          +-----------------------------------------------------+
--          |                <titulo>                         [X] |
--          |  (o) Oro del castillo: 120                          |
--          |  [Atributos] [Ataque] [Hechizos] [Defensa]          |
--          |  +-----------------------+ +-----------------------+ |
--          |  |[ico] Fuerza +25    40o| |[ico] Agilidad +25  40o| |   clic = comprar
--          |  |      Llevas +50       | |      Sin comprar      | |   (precio en rojo si no llega)
--          |  +-----------------------+ +-----------------------+ |
--          +-----------------------------------------------------+

MIWOW_SHOP_COLUMNS = 2;
MIWOW_SHOP_ROWS = 6;
MIWOW_SHOP_MAX_TABS = 6;
MIWOW_SHOP_COIN = "Interface\\Icons\\INV_Misc_Coin_02";

MiWow_MatchShop = {
	open = false,
	amount = 0,
	-- categorias en orden; items[categoria] = { {id, icon, name, detail, price}, ... }
	categories = {},
	items = {},
	selected = nil,
};

local function MiWowShop_Refresh()
	local shop = MiWow_MatchShop;
	MiWowMatchShopAmount:SetText(MiWowMatchShop.currency .. ": |cffffffff" .. shop.amount .. "|r");

	for i = 1, MIWOW_SHOP_MAX_TABS do
		local tab = _G["MiWowMatchShopTab" .. i];
		local category = shop.categories[i];
		if ( category ) then
			tab:SetText(category);
			tab:Show();
			if ( category == shop.selected ) then
				tab:LockHighlight();
			else
				tab:UnlockHighlight();
			end
		else
			tab:Hide();
		end
	end

	local items = shop.items[shop.selected] or {};
	for i = 1, MIWOW_SHOP_COLUMNS * MIWOW_SHOP_ROWS do
		local button = _G["MiWowMatchShopItem" .. i];
		local item = items[i];
		if ( item ) then
			local affordable = item.price <= shop.amount;
			button.itemId = item.id;
			_G["MiWowMatchShopItem" .. i .. "Icon"]:SetTexture(item.icon);
			_G["MiWowMatchShopItem" .. i .. "Icon"]:SetDesaturated(not affordable);
			_G["MiWowMatchShopItem" .. i .. "Name"]:SetText(item.name);
			_G["MiWowMatchShopItem" .. i .. "Detail"]:SetText(item.detail);
			local price = _G["MiWowMatchShopItem" .. i .. "Price"];
			price:SetText(item.price);
			if ( affordable ) then
				price:SetTextColor(1, 0.82, 0);
			else
				price:SetTextColor(1, 0.25, 0.25);
			end
			button:Show();
		else
			button.itemId = nil;
			button:Hide();
		end
	end
end

function MiWowMatchShop_Close()
	MiWow_MatchShop.open = false;
	if ( MiWowMatchShop ) then
		MiWowMatchShop:Hide();
	end
end

local function MiWow_CreateShop()
	local f = CreateFrame("Frame", "MiWowMatchShop", UIParent);
	f:SetSize(560, 120 + MIWOW_SHOP_ROWS * 52);
	f:SetPoint("CENTER", UIParent, "CENTER", 0, 40);
	f:SetFrameStrata("DIALOG");
	f:EnableMouse(true);
	f:SetMovable(true);
	f:RegisterForDrag("LeftButton");
	f:SetScript("OnDragStart", f.StartMoving);
	f:SetScript("OnDragStop", f.StopMovingOrSizing);
	f:SetBackdrop({
		bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	});
	f:SetBackdropColor(0.04, 0.05, 0.08, 0.95);
	f:SetBackdropBorderColor(1, 0.82, 0, 1);
	f.currency = "";
	f:Hide();
	-- Esc la cierra
	tinsert(UISpecialFrames, "MiWowMatchShop");
	f:SetScript("OnHide", function()
		if ( MiWow_MatchShop.open ) then
			MiWow_MatchShop.open = false;
			MiWow_Send("SHOP_CLOSE");
		end
	end);

	local title = f:CreateFontString("MiWowMatchShopTitle", "ARTWORK", "GameFontNormalLarge");
	title:SetPoint("TOP", f, "TOP", 0, -14);

	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton");
	close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2);

	local coin = f:CreateTexture(nil, "ARTWORK");
	coin:SetSize(20, 20);
	coin:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -40);
	coin:SetTexture(MIWOW_SHOP_COIN);
	local amount = f:CreateFontString("MiWowMatchShopAmount", "ARTWORK", "GameFontNormal");
	amount:SetPoint("LEFT", coin, "RIGHT", 6, 0);

	for i = 1, MIWOW_SHOP_MAX_TABS do
		local tab = CreateFrame("Button", "MiWowMatchShopTab" .. i, f, "UIPanelButtonTemplate");
		tab:SetSize(100, 22);
		tab:SetPoint("TOPLEFT", f, "TOPLEFT", 16 + (i - 1) * 104, -68);
		tab:SetScript("OnClick", function(self)
			MiWow_MatchShop.selected = self:GetText();
			PlaySound("igCharacterInfoTab");
			MiWowShop_Refresh();
		end);
		tab:Hide();
	end

	for i = 1, MIWOW_SHOP_COLUMNS * MIWOW_SHOP_ROWS do
		local column = (i - 1) % MIWOW_SHOP_COLUMNS;
		local row = math.floor((i - 1) / MIWOW_SHOP_COLUMNS);
		local b = CreateFrame("Button", "MiWowMatchShopItem" .. i, f);
		b:SetSize(258, 48);
		b:SetPoint("TOPLEFT", f, "TOPLEFT", 16 + column * 266, -100 - row * 52);
		b:SetBackdrop({
			bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 12,
			insets = { left = 3, right = 3, top = 3, bottom = 3 },
		});
		b:SetBackdropColor(0.1, 0.1, 0.14, 0.9);
		b:SetBackdropBorderColor(0.35, 0.35, 0.4, 1);
		local highlight = b:CreateTexture(nil, "HIGHLIGHT");
		highlight:SetTexture("Interface\\Buttons\\UI-Listbox-Highlight2");
		highlight:SetBlendMode("ADD");
		highlight:SetPoint("TOPLEFT", b, "TOPLEFT", 4, -4);
		highlight:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -4, 4);
		highlight:SetVertexColor(1, 0.82, 0, 0.35);

		local icon = b:CreateTexture("MiWowMatchShopItem" .. i .. "Icon", "ARTWORK");
		icon:SetSize(36, 36);
		icon:SetPoint("LEFT", b, "LEFT", 6, 0);

		local priceCoin = b:CreateTexture(nil, "ARTWORK");
		priceCoin:SetSize(14, 14);
		priceCoin:SetPoint("RIGHT", b, "RIGHT", -8, 0);
		priceCoin:SetTexture(MIWOW_SHOP_COIN);
		local price = b:CreateFontString("MiWowMatchShopItem" .. i .. "Price", "ARTWORK", "GameFontNormal");
		price:SetPoint("RIGHT", priceCoin, "LEFT", -3, 0);

		local name = b:CreateFontString("MiWowMatchShopItem" .. i .. "Name", "ARTWORK", "GameFontHighlight");
		name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, 1);
		name:SetPoint("RIGHT", price, "LEFT", -6, 0);
		name:SetJustifyH("LEFT");
		local detail = b:CreateFontString("MiWowMatchShopItem" .. i .. "Detail", "ARTWORK", "GameFontDisableSmall");
		detail:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -3);
		-- Hasta el borde de la casilla (debajo del precio): los textos largos se parten en dos lineas
		detail:SetPoint("RIGHT", b, "RIGHT", -8, 0);
		detail:SetJustifyH("LEFT");
		detail:SetJustifyV("TOP");
		detail:SetHeight(22);

		b:SetScript("OnClick", function(self)
			if ( self.itemId and MiWow_MatchShop.open ) then
				PlaySound("igMainMenuOptionCheckBoxOn");
				MiWow_Send("SHOP_BUY", self.itemId);
			end
		end);
		b:Hide();
	end
end

-- MATCH_SHOP <titulo> <moneda> <cantidad> (<id> <categoria> <icono> <nombre> <detalle> <precio>)...
MiWow_RegisterHandler("MATCH_SHOP", function(fields)
	local shop = MiWow_MatchShop;
	shop.amount = tonumber(fields[3]) or 0;
	shop.categories = {};
	shop.items = {};
	local i = 4;
	while ( fields[i + 5] ) do
		local category = fields[i + 1];
		if ( not shop.items[category] ) then
			shop.items[category] = {};
			tinsert(shop.categories, category);
		end
		tinsert(shop.items[category], {
			id = fields[i], icon = fields[i + 2], name = fields[i + 3], detail = fields[i + 4],
			price = tonumber(fields[i + 5]) or 0,
		});
		i = i + 6;
	end
	if ( not shop.selected or not shop.items[shop.selected] ) then
		shop.selected = shop.categories[1];
	end

	MiWowMatchShopTitle:SetText(fields[1] or "");
	MiWowMatchShop.currency = fields[2] or "";
	if ( not shop.open ) then
		shop.open = true;
		PlaySound("igCharacterInfoOpen");
	end
	MiWowShop_Refresh();
	MiWowMatchShop:Show();
end);

-- MATCH_SHOP_CLOSE
MiWow_RegisterHandler("MATCH_SHOP_CLOSE", function()
	MiWowMatchShop_Close();
end);

MiWow_CreateHud();
MiWow_CreateChoice();
MiWow_CreateShop();
