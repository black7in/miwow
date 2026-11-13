-- EventWow: panel del lobby (minijuegos + chat global). Generico: todo lo que muestra llega del servidor
-- (GAMES, QUEUE_STATUS...), el cliente no conoce ningun minijuego. Ver docs/protocolo.md.
--
--  +-----------------------------------------------------------+
--  | EVENTWOW                                 <nombre>  [Menu] |  barra superior
--  +----------------------+------------------------------------+
--  | MINIJUEGOS (lista)   | detalle + Buscar partida / en cola |
--  +----------------------+------------------------------------+
--  | CHAT GLOBAL (EventWowChat.lua)                            |
--  +-----------------------------------------------------------+
-- Visible solo en modo lobby (EventWow_SetMode, EventWow.lua).
-- Ocupa toda la pantalla (UIParent) en cualquier resolucion: el reparto interior es proporcional
-- (EventWowPanel_Layout) y el numero de filas de la lista depende del alto disponible.

EVENTWOW_PANEL = {
	MARGIN = 8,
	GAP = 6,
	TOP_BAR_HEIGHT = 36,
	GAMES_HEIGHT_RATIO = 0.55,  -- parte del alto (sin barra superior) para juegos; el resto, chat
	LIST_WIDTH_RATIO = 0.32,
	LIST_MIN_WIDTH = 280,
	MAX_ROWS = 20,
	ROW_HEIGHT = 40,
	BACKDROP = {
		bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 14,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	},
	COLOR_PANEL = { 0.04, 0.05, 0.08, 0.6 },  -- deja ver la portada del lobby
	COLOR_SECTION = { 0, 0, 0, 0.45 },
	COLOR_BORDER = { 0.35, 0.35, 0.4, 1 },
};

EVENTWOW_STR_PANEL_TITLE = "EVENTWOW";
EVENTWOW_STR_PANEL_MENU = "Menú";
EVENTWOW_STR_PANEL_HIDE = "Ocultar panel";
EVENTWOW_STR_PANEL_GAMES = "MINIJUEGOS";
EVENTWOW_STR_PANEL_CONNECTING = "Conectando con el servidor...";
EVENTWOW_STR_PANEL_NO_GAMES = "No hay minijuegos disponibles.";
EVENTWOW_STR_PANEL_SOLO = "Solitario";
EVENTWOW_STR_PANEL_PLAYERS = "%d-%d jugadores";
EVENTWOW_STR_PANEL_SEARCH = "Buscar partida";
EVENTWOW_STR_PANEL_QUEUED = "Buscando partida: %s  |cffffffff%s|r";
EVENTWOW_STR_PANEL_CANCEL = "Cancelar";
EVENTWOW_STR_PANEL_UNAVAILABLE = "Próximamente";
EVENTWOW_STR_PANEL_ENTERING = "Partida encontrada: %s. Entrando...";

EventWow_Panel = {
	selectedId = nil,
	offset = 0,
	visibleRows = 1,  -- lo calcula EventWowPanel_Layout segun el alto
	-- { gameId, startTime (GetTime()) } o nil
	queue = nil,
};

local function EventWow_ApplyBackdrop(frame, color)
	frame:SetBackdrop(EVENTWOW_PANEL.BACKDROP);
	frame:SetBackdropColor(unpack(color));
	frame:SetBackdropBorderColor(unpack(EVENTWOW_PANEL.COLOR_BORDER));
end

local function EventWow_FindGame(id)
	for _, game in ipairs(EventWow_Protocol.games) do
		if ( game.id == id ) then
			return game;
		end
	end
	return nil;
end

local function EventWow_PlayersText(game)
	if ( (game.maxPlayers or 1) <= 1 ) then
		return EVENTWOW_STR_PANEL_SOLO;
	end
	return format(EVENTWOW_STR_PANEL_PLAYERS, game.minPlayers or 1, game.maxPlayers);
end

local function EventWow_FormatElapsed(seconds)
	seconds = math.max(0, math.floor(seconds));
	return format("%d:%02d", math.floor(seconds / 60), seconds % 60);
end

-- Actualizacion ---------------------------------------------------------------------------------

function EventWowPanel_UpdateList()
	local games = EventWow_Protocol.games;
	local visibleRows = EventWow_Panel.visibleRows;
	local maxOffset = math.max(0, #games - visibleRows);
	EventWow_Panel.offset = math.min(math.max(EventWow_Panel.offset, 0), maxOffset);

	for i = 1, EVENTWOW_PANEL.MAX_ROWS do
		local row = _G["EventWowGameRow"..i];
		local game = (i <= visibleRows) and games[i + EventWow_Panel.offset];
		if ( game ) then
			row.gameId = game.id;
			row.icon:SetTexture(game.icon);
			row.name:SetText(game.name);
			row.players:SetText(EventWow_PlayersText(game));
			if ( game.id == EventWow_Panel.selectedId ) then
				row.selected:Show();
			else
				row.selected:Hide();
			end
			row:Show();
		else
			row.gameId = nil;
			row:Hide();
		end
	end
end

function EventWowPanel_UpdateDetail()
	local game = EventWow_FindGame(EventWow_Panel.selectedId);
	local hasGame = game ~= nil;

	if ( hasGame ) then
		EventWowPanelDetailIcon:SetTexture(game.icon);
		EventWowPanelDetailIcon:Show();
		EventWowPanelDetailName:SetText(game.name);
		EventWowPanelDetailPlayers:SetText(EventWow_PlayersText(game));
		EventWowPanelDetailDescription:SetText(game.description);
		EventWowPanelDetailMessage:SetText("");
	else
		EventWowPanelDetailIcon:Hide();
		EventWowPanelDetailName:SetText("");
		EventWowPanelDetailPlayers:SetText("");
		EventWowPanelDetailDescription:SetText("");
		if ( not EventWow_Protocol.connected ) then
			EventWowPanelDetailMessage:SetText(EVENTWOW_STR_PANEL_CONNECTING);
		else
			EventWowPanelDetailMessage:SetText(EVENTWOW_STR_PANEL_NO_GAMES);
		end
	end

	-- Una sola cola: si estas en cola (o entrando en una partida) se ve su estado (aunque mires otro juego)
	if ( EventWow_Panel.queue or EventWowMatch_IsLoading() ) then
		EventWowPanelSearchButton:Hide();
		EventWowPanelQueue:Show();
		EventWowPanel_UpdateQueueText();
	else
		EventWowPanelQueue:Hide();
		EventWowPanelSearchButton:Show();
		if ( hasGame and not game.playable ) then
			EventWowPanelSearchButton:SetText(EVENTWOW_STR_PANEL_UNAVAILABLE);
		else
			EventWowPanelSearchButton:SetText(EVENTWOW_STR_PANEL_SEARCH);
		end
		if ( hasGame and game.playable and EventWow_Protocol.connected ) then
			EventWowPanelSearchButton:Enable();
		else
			EventWowPanelSearchButton:Disable();
		end
	end
end

function EventWowPanel_UpdateQueueText()
	if ( EventWowMatch_IsLoading() ) then
		local game = EventWow_FindGame(EventWow_Match.gameId);
		EventWowPanelQueueText:SetText(format(EVENTWOW_STR_PANEL_ENTERING, game and game.name or tostring(EventWow_Match.gameId)));
		EventWowPanelQueueCancel:Hide();
		return;
	end
	EventWowPanelQueueCancel:Show();

	local queue = EventWow_Panel.queue;
	if ( not queue ) then
		return;
	end
	local game = EventWow_FindGame(queue.gameId);
	local name = game and game.name or queue.gameId;
	EventWowPanelQueueText:SetText(format(EVENTWOW_STR_PANEL_QUEUED, name, EventWow_FormatElapsed(GetTime() - queue.startTime)));
end

function EventWowPanel_Update()
	-- Seleccion por defecto: el primero (o el que siga existiendo)
	if ( not EventWow_FindGame(EventWow_Panel.selectedId) ) then
		local first = EventWow_Protocol.games[1];
		EventWow_Panel.selectedId = first and first.id or nil;
	end
	EventWowPanel_UpdateList();
	EventWowPanel_UpdateDetail();
end

function EventWowPanel_SelectGame(id)
	EventWow_Panel.selectedId = id;
	EventWowPanel_Update();
end

-- Construccion ----------------------------------------------------------------------------------

local function EventWow_CreateTopBar(panel)
	local bar = CreateFrame("Frame", "EventWowPanelTopBar", panel);
	bar:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -8);
	bar:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -8);
	bar:SetHeight(EVENTWOW_PANEL.TOP_BAR_HEIGHT);
	EventWow_ApplyBackdrop(bar, EVENTWOW_PANEL.COLOR_SECTION);

	local title = bar:CreateFontString("EventWowPanelTitle", "ARTWORK", "GameFontNormalHuge");
	title:SetPoint("LEFT", bar, "LEFT", 12, 0);
	title:SetText(EVENTWOW_STR_PANEL_TITLE);

	local menu = CreateFrame("Button", "EventWowPanelMenuButton", bar, "UIPanelButtonTemplate");
	menu:SetSize(80, 22);
	menu:SetPoint("RIGHT", bar, "RIGHT", -8, 0);
	menu:SetText(EVENTWOW_STR_PANEL_MENU);
	menu:SetScript("OnClick", function()
		if ( GameMenuFrame:IsShown() ) then
			PlaySound("igMainMenuQuit");
			HideUIPanel(GameMenuFrame);
		else
			PlaySound("igMainMenuOpen");
			ShowUIPanel(GameMenuFrame);
		end
	end);

	local name = bar:CreateFontString("EventWowPanelPlayerName", "ARTWORK", "GameFontHighlight");
	name:SetPoint("RIGHT", menu, "LEFT", -12, 0);

	-- Solo en modo dev (.gm on o .dev on): interfaz nativa sin tocar ningun flag
	local hide = CreateFrame("Button", "EventWowPanelHideButton", bar, "UIPanelButtonTemplate");
	hide:SetSize(120, 22);
	hide:SetPoint("LEFT", title, "RIGHT", 16, 0);
	hide:SetText(EVENTWOW_STR_PANEL_HIDE);
	hide:SetScript("OnClick", function()
		EventWow_SetPanelHidden(true);
	end);
	hide:Hide();
end

function EventWowPanel_UpdatePlayerName()
	local text = UnitName("player") or "";
	if ( EventWow_Protocol.isGM ) then
		text = EVENTWOW_CHAT.GM_BADGE..text;
	end
	EventWowPanelPlayerName:SetText(text);
end

local function EventWow_CreateGameRow(list, index)
	local row = CreateFrame("Button", "EventWowGameRow"..index, list);
	row:SetHeight(EVENTWOW_PANEL.ROW_HEIGHT);
	row:SetPoint("TOPLEFT", list, "TOPLEFT", 8, -28 - (index - 1) * (EVENTWOW_PANEL.ROW_HEIGHT + 2));
	row:SetPoint("RIGHT", list, "RIGHT", -8, 0);
	row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD");

	local selected = row:CreateTexture(nil, "BACKGROUND");
	selected:SetAllPoints(row);
	selected:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight");
	selected:SetBlendMode("ADD");
	selected:SetVertexColor(1, 0.82, 0);
	selected:Hide();
	row.selected = selected;

	local icon = row:CreateTexture(nil, "ARTWORK");
	icon:SetSize(32, 32);
	icon:SetPoint("LEFT", row, "LEFT", 4, 0);
	row.icon = icon;

	local players = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall");
	players:SetPoint("RIGHT", row, "RIGHT", -6, 0);
	row.players = players;

	local name = row:CreateFontString(nil, "ARTWORK", "GameFontNormal");
	name:SetPoint("LEFT", icon, "RIGHT", 8, 0);
	name:SetPoint("RIGHT", players, "LEFT", -6, 0);
	name:SetJustifyH("LEFT");
	row.name = name;

	row:SetScript("OnClick", function(self)
		if ( self.gameId ) then
			PlaySound("igMainMenuOptionCheckBoxOn");
			EventWowPanel_SelectGame(self.gameId);
		end
	end);
	row:Hide();
end

local function EventWow_CreateGameList(panel)
	local list = CreateFrame("Frame", "EventWowPanelGameList", panel);
	list:SetPoint("TOPLEFT", EventWowPanelTopBar, "BOTTOMLEFT", 0, -EVENTWOW_PANEL.GAP);
	-- Tamano: EventWowPanel_Layout
	EventWow_ApplyBackdrop(list, EVENTWOW_PANEL.COLOR_SECTION);

	local title = list:CreateFontString("EventWowPanelGamesTitle", "ARTWORK", "GameFontNormal");
	title:SetPoint("TOPLEFT", list, "TOPLEFT", 10, -8);
	title:SetText(EVENTWOW_STR_PANEL_GAMES);

	for i = 1, EVENTWOW_PANEL.MAX_ROWS do
		EventWow_CreateGameRow(list, i);
	end

	list:EnableMouseWheel(true);
	list:SetScript("OnMouseWheel", function(self, delta)
		EventWow_Panel.offset = EventWow_Panel.offset - delta;
		EventWowPanel_UpdateList();
	end);
end

local function EventWow_CreateDetail(panel)
	local detail = CreateFrame("Frame", "EventWowPanelDetail", panel);
	detail:SetPoint("TOPLEFT", EventWowPanelGameList, "TOPRIGHT", EVENTWOW_PANEL.GAP, 0);
	detail:SetPoint("BOTTOMLEFT", EventWowPanelGameList, "BOTTOMRIGHT", EVENTWOW_PANEL.GAP, 0);
	detail:SetPoint("RIGHT", EventWowPanelTopBar, "RIGHT", 0, 0);
	EventWow_ApplyBackdrop(detail, EVENTWOW_PANEL.COLOR_SECTION);

	local icon = detail:CreateTexture("EventWowPanelDetailIcon", "ARTWORK");
	icon:SetSize(56, 56);
	icon:SetPoint("TOPLEFT", detail, "TOPLEFT", 16, -16);

	local name = detail:CreateFontString("EventWowPanelDetailName", "ARTWORK", "GameFontNormalHuge");
	name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 12, -4);
	name:SetPoint("RIGHT", detail, "RIGHT", -16, 0);
	name:SetJustifyH("LEFT");

	local players = detail:CreateFontString("EventWowPanelDetailPlayers", "ARTWORK", "GameFontHighlight");
	players:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -6);

	local description = detail:CreateFontString("EventWowPanelDetailDescription", "ARTWORK", "GameFontHighlight");
	description:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", 0, -16);
	-- Hasta encima del boton / estado de cola
	description:SetPoint("BOTTOMRIGHT", detail, "BOTTOMRIGHT", -16, 70);
	description:SetJustifyH("LEFT");
	description:SetJustifyV("TOP");

	-- Conectando / sin juegos
	local message = detail:CreateFontString("EventWowPanelDetailMessage", "ARTWORK", "GameFontNormalLarge");
	message:SetPoint("CENTER", detail, "CENTER", 0, 20);

	local search = CreateFrame("Button", "EventWowPanelSearchButton", detail, "UIPanelButtonTemplate");
	search:SetSize(220, 32);
	search:SetPoint("BOTTOM", detail, "BOTTOM", 0, 20);
	search:SetText(EVENTWOW_STR_PANEL_SEARCH);
	search:SetScript("OnClick", function()
		if ( EventWow_Panel.selectedId ) then
			PlaySound("igMainMenuOptionCheckBoxOn");
			EventWow_Send("QUEUE", EventWow_Panel.selectedId);
		end
	end);

	-- Estado de la cola (sustituye al boton)
	local queue = CreateFrame("Frame", "EventWowPanelQueue", detail);
	queue:SetPoint("BOTTOMLEFT", detail, "BOTTOMLEFT", 16, 16);
	queue:SetPoint("BOTTOMRIGHT", detail, "BOTTOMRIGHT", -16, 16);
	queue:SetHeight(40);
	EventWow_ApplyBackdrop(queue, { 0.1, 0.25, 0.1, 0.6 });
	queue:Hide();

	local cancel = CreateFrame("Button", "EventWowPanelQueueCancel", queue, "UIPanelButtonTemplate");
	cancel:SetSize(100, 24);
	cancel:SetPoint("RIGHT", queue, "RIGHT", -8, 0);
	cancel:SetText(EVENTWOW_STR_PANEL_CANCEL);
	cancel:SetScript("OnClick", function()
		PlaySound("igMainMenuOptionCheckBoxOff");
		EventWow_Send("LEAVE");
	end);

	local queueText = queue:CreateFontString("EventWowPanelQueueText", "ARTWORK", "GameFontNormal");
	queueText:SetPoint("LEFT", queue, "LEFT", 12, 0);
	queueText:SetPoint("RIGHT", cancel, "LEFT", -8, 0);
	queueText:SetJustifyH("LEFT");

	local elapsed = 0;
	queue:SetScript("OnUpdate", function(self, delta)
		elapsed = elapsed + delta;
		if ( elapsed >= 0.5 ) then
			elapsed = 0;
			EventWowPanel_UpdateQueueText();
		end
	end);
end

-- Reparto proporcional al tamano de la pantalla (se llama al mostrar y al cambiar de resolucion/escala)
function EventWowPanel_Layout()
	local panel = EventWowPanel;
	local width, height = panel:GetWidth(), panel:GetHeight();
	if ( not width or width <= 0 or not height or height <= 0 ) then
		return;
	end

	local margin, gap = EVENTWOW_PANEL.MARGIN, EVENTWOW_PANEL.GAP;
	local content = height - margin * 2 - EVENTWOW_PANEL.TOP_BAR_HEIGHT - gap * 2;
	local gamesHeight = math.floor(content * EVENTWOW_PANEL.GAMES_HEIGHT_RATIO);
	local listWidth = math.max(EVENTWOW_PANEL.LIST_MIN_WIDTH, math.floor((width - margin * 2) * EVENTWOW_PANEL.LIST_WIDTH_RATIO));
	EventWowPanelGameList:SetSize(listWidth, gamesHeight);

	-- Filas que caben bajo el titulo de la lista (28 px)
	local rows = math.floor((gamesHeight - 28 - margin) / (EVENTWOW_PANEL.ROW_HEIGHT + 2));
	EventWow_Panel.visibleRows = math.max(1, math.min(EVENTWOW_PANEL.MAX_ROWS, rows));
	EventWowPanel_UpdateList();
end

local function EventWow_CreatePanel()
	-- Toda la pantalla: sin borde, fondo semitransparente sobre la portada del lobby
	local panel = CreateFrame("Frame", "EventWowPanel", UIParent);
	panel:SetAllPoints(UIParent);
	panel:SetFrameStrata("MEDIUM");
	panel:EnableMouse(true);
	panel:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground" });
	panel:SetBackdropColor(unpack(EVENTWOW_PANEL.COLOR_PANEL));

	EventWow_CreateTopBar(panel);
	EventWow_CreateGameList(panel);
	EventWow_CreateDetail(panel);

	local chat = EventWowChat_Create(panel);
	chat:SetPoint("TOPLEFT", EventWowPanelGameList, "BOTTOMLEFT", 0, -EVENTWOW_PANEL.GAP);
	chat:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -EVENTWOW_PANEL.MARGIN, EVENTWOW_PANEL.MARGIN);
	EventWow_ApplyBackdrop(chat, EVENTWOW_PANEL.COLOR_SECTION);

	panel:SetScript("OnSizeChanged", EventWowPanel_Layout);
	panel:SetScript("OnShow", function()
		EventWowPanel_Layout();
		EventWowPanel_UpdatePlayerName();
		EventWowPanel_Update();
	end);
	panel:Hide();
end

-- Protocolo -------------------------------------------------------------------------------------

-- QUEUE_STATUS QUEUED <id> <segundos> | QUEUE_STATUS NONE
EventWow_RegisterHandler("QUEUE_STATUS", function(fields)
	if ( fields[1] == "QUEUED" ) then
		EventWow_Panel.queue = { gameId = fields[2], startTime = GetTime() - (tonumber(fields[3]) or 0) };
	else
		EventWow_Panel.queue = nil;
	end
	EventWowPanel_Update();
end);

EventWow_RegisterListener("CONNECTED", function()
	EventWowPanel_UpdatePlayerName();
	EventWowPanel_Update();
end);
EventWow_RegisterListener("GAMES", EventWowPanel_Update);
EventWow_RegisterListener("DEV_MODE", function()
	if ( EventWow_UI.dev ) then
		EventWowPanelHideButton:Show();
	else
		EventWowPanelHideButton:Hide();
	end
end);

EventWow_CreatePanel();
