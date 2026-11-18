-- EventWow: panel de eventos (minijuegos + chat global). Generico: todo lo que muestra llega del servidor
-- (GAMES, QUEUE_STATUS...), el cliente no conoce ningun minijuego. Ver docs/protocolo.md.
--
--  +-----------------------------------------------------------+
--  | EVENTWOW                                    <nombre>  [X] |  barra superior
--  +----------------------+------------------------------------+
--  | MINIJUEGOS (lista)   | detalle + Buscar partida / en cola |
--  +----------------------+------------------------------------+
--  | CHAT GLOBAL (EventWowChat.lua)                            |
--  +-----------------------------------------------------------+
-- Ventana centrada (se arrastra por la barra superior) que se abre y cierra con el boton del minimapa,
-- /eventwow o Esc; cerrada dentro de una partida (EventWow_SetMode, EventWow.lua). El reparto interior es
-- proporcional (EventWowPanel_Layout) y el numero de filas de la lista depende del alto disponible.

EVENTWOW_PANEL = {
	WIDTH = 960,          -- tamano de la ventana (menos si la pantalla no da: SCREEN_MARGIN por lado)
	HEIGHT = 640,
	SCREEN_MARGIN = 40,
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
	COLOR_PANEL = { 0.04, 0.05, 0.08, 0.94 },
	COLOR_SECTION = { 0, 0, 0, 0.45 },
	COLOR_BORDER = { 0.35, 0.35, 0.4, 1 },
};

EVENTWOW_STR_PANEL_TITLE = "EVENTWOW";
EVENTWOW_STR_PANEL_MINIMAP_TITLE = "Eventos";
EVENTWOW_STR_PANEL_MINIMAP_HINT = "Clic: abrir o cerrar el panel (/eventwow)";
EVENTWOW_STR_PANEL_MINIMAP_QUEUED = "Buscando partida: %s";
EVENTWOW_STR_PANEL_MINIMAP_MATCH = "En partida";
EVENTWOW_STR_PANEL_IN_MATCH = "No disponible durante una partida.";
EVENTWOW_STR_PANEL_GAMES = "MINIJUEGOS";
EVENTWOW_STR_PANEL_CONNECTING = "Conectando con el servidor...";
EVENTWOW_STR_PANEL_NO_GAMES = "No hay minijuegos disponibles.";
EVENTWOW_STR_PANEL_SOLO = "Solitario";
EVENTWOW_STR_PANEL_PLAYERS = "%d-%d jugadores";
EVENTWOW_STR_PANEL_PARTY = "%s  ·  en grupo hasta %d";
EVENTWOW_STR_PANEL_NO_PARTY = "%s  ·  sin grupos";
EVENTWOW_STR_PANEL_SEARCH = "Buscar partida";
EVENTWOW_STR_PANEL_SEARCH_GROUP = "Buscar partida en grupo (%d)";
-- Sesion siempre abierta (p. ej. el parkour): se entra directamente, sin cola
EVENTWOW_STR_PANEL_JOIN = "Entrar";
EVENTWOW_STR_PANEL_JOIN_GROUP = "Entrar en grupo (%d)";
EVENTWOW_STR_PANEL_OPEN_SESSION = "Sesión abierta (hasta %d)";
EVENTWOW_STR_PANEL_NOT_LEADER = "Solo el líder busca partida";
EVENTWOW_STR_PANEL_SOLO_ONLY = "Individual: sal del grupo";
EVENTWOW_STR_PANEL_GROUP_TOO_BIG = "Grupo demasiado grande (máx. %d)";
EVENTWOW_STR_PANEL_QUEUED = "Buscando partida: %s  |cffffffff%s|r";
EVENTWOW_STR_PANEL_FOUND = "Partida encontrada: %s. Esperando confirmación...";
EVENTWOW_STR_PANEL_QUEUED_GROUP ="Buscando partida en grupo (%d): %s  |cffffffff%s|r";
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
	if ( game.openSession ) then
		return format(EVENTWOW_STR_PANEL_OPEN_SESSION, game.maxPlayers or 1);
	end
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
		local players = EventWow_PlayersText(game);
		if ( (game.maxPartySize or 1) > 1 ) then
			players = format(EVENTWOW_STR_PANEL_PARTY, players, game.maxPartySize);
		elseif ( (game.maxPlayers or 1) > 1 ) then
			players = format(EVENTWOW_STR_PANEL_NO_PARTY, players);
		end
		EventWowPanelDetailPlayers:SetText(players);
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
	-- EventWowMatch.lua carga despues que este archivo
	local loading = EventWowMatch_IsLoading and EventWowMatch_IsLoading();
	if ( EventWow_Panel.queue or loading ) then
		EventWowPanelSearchButton:Hide();
		EventWowPanelQueue:Show();
		EventWowPanel_UpdateQueueText();
	else
		EventWowPanelQueue:Hide();
		EventWowPanelSearchButton:Show();
		-- En grupo busca el lider por todos (EventWowGroup.lua); el servidor lo vuelve a comprobar
		local size = EventWowGroup_GetSize();
		local open = hasGame and game.openSession;
		local text, enabled = open and EVENTWOW_STR_PANEL_JOIN or EVENTWOW_STR_PANEL_SEARCH,
			hasGame and game.playable and EventWow_Protocol.connected;
		if ( hasGame and not game.playable ) then
			text = EVENTWOW_STR_PANEL_UNAVAILABLE;
		elseif ( hasGame and size > 1 ) then
			if ( not EventWowGroup_IsLeaderOrSolo() ) then
				text, enabled = EVENTWOW_STR_PANEL_NOT_LEADER, false;
			elseif ( (game.maxPartySize or 1) <= 1 ) then
				text, enabled = EVENTWOW_STR_PANEL_SOLO_ONLY, false;
			elseif ( size > game.maxPartySize ) then
				text, enabled = format(EVENTWOW_STR_PANEL_GROUP_TOO_BIG, game.maxPartySize), false;
			else
				text = format(open and EVENTWOW_STR_PANEL_JOIN_GROUP or EVENTWOW_STR_PANEL_SEARCH_GROUP, size);
			end
		end
		EventWowPanelSearchButton:SetText(text);
		if ( enabled ) then
			EventWowPanelSearchButton:Enable();
		else
			EventWowPanelSearchButton:Disable();
		end
	end
end

function EventWowPanel_UpdateQueueText()
	if ( EventWowMatch_IsLoading and EventWowMatch_IsLoading() ) then
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
	if ( EventWow_MatchFound and EventWow_MatchFound.current ) then
		EventWowPanelQueueText:SetText(format(EVENTWOW_STR_PANEL_FOUND, name));
		return;
	end
	local elapsed = EventWow_FormatElapsed(GetTime() - queue.startTime);
	if ( queue.players > 1 ) then
		EventWowPanelQueueText:SetText(format(EVENTWOW_STR_PANEL_QUEUED_GROUP, queue.players, name, elapsed));
	else
		EventWowPanelQueueText:SetText(format(EVENTWOW_STR_PANEL_QUEUED, name, elapsed));
	end
end

function EventWowPanel_Update()
	-- Seleccion por defecto: el primero (o el que siga existiendo)
	if ( not EventWow_FindGame(EventWow_Panel.selectedId) ) then
		local first = EventWow_Protocol.games[1];
		EventWow_Panel.selectedId = first and first.id or nil;
	end
	EventWowPanel_UpdateList();
	EventWowPanel_UpdateDetail();
	EventWowPanel_UpdateMinimapButton();
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

	local close = CreateFrame("Button", "EventWowPanelCloseButton", bar, "UIPanelCloseButton");
	close:SetPoint("RIGHT", bar, "RIGHT", 2, 0);
	close:SetScript("OnClick", function()
		EventWowPanel:Hide();
	end);

	local name = bar:CreateFontString("EventWowPanelPlayerName", "ARTWORK", "GameFontHighlight");
	name:SetPoint("RIGHT", close, "LEFT", -8, 0);

	-- Arrastrar la ventana por la barra
	bar:EnableMouse(true);
	bar:RegisterForDrag("LeftButton");
	bar:SetScript("OnDragStart", function()
		EventWowPanel:StartMoving();
	end);
	bar:SetScript("OnDragStop", function()
		EventWowPanel:StopMovingOrSizing();
	end);
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
		-- Con una partida encontrada pendiente, cancelar es rechazarla (EventWowMatchFound.lua)
		if ( EventWow_MatchFound and EventWow_MatchFound.current ) then
			EventWow_MatchFound.current.declined = true;
		end
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

-- Tamano de la ventana: EVENTWOW_PANEL.WIDTH x HEIGHT, o menos si la pantalla no da
function EventWowPanel_Resize()
	local margin = EVENTWOW_PANEL.SCREEN_MARGIN * 2;
	local width = math.min(EVENTWOW_PANEL.WIDTH, UIParent:GetWidth() - margin);
	local height = math.min(EVENTWOW_PANEL.HEIGHT, UIParent:GetHeight() - margin);
	EventWowPanel:SetSize(math.floor(width), math.floor(height));
end

local function EventWow_CreatePanel()
	local panel = CreateFrame("Frame", "EventWowPanel", UIParent);
	panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0);
	panel:SetFrameStrata("MEDIUM");
	panel:SetToplevel(true);
	panel:EnableMouse(true);
	panel:SetMovable(true);
	panel:SetClampedToScreen(true);
	EventWow_ApplyBackdrop(panel, EVENTWOW_PANEL.COLOR_PANEL);
	EventWowPanel_Resize();
	-- Esc la cierra (CloseSpecialWindows)
	tinsert(UISpecialFrames, "EventWowPanel");

	EventWow_CreateTopBar(panel);
	EventWow_CreateGameList(panel);
	EventWow_CreateDetail(panel);

	-- Abajo: chat (izq.) + social: grupo y amigos (der., ancho fijo)
	local social = EventWowSocial_Create(panel);
	social:SetPoint("TOPRIGHT", EventWowPanelDetail, "BOTTOMRIGHT", 0, -EVENTWOW_PANEL.GAP);
	social:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -EVENTWOW_PANEL.MARGIN, EVENTWOW_PANEL.MARGIN);
	EventWow_ApplyBackdrop(social, EVENTWOW_PANEL.COLOR_SECTION);

	local chat = EventWowChat_Create(panel);
	chat:SetPoint("TOPLEFT", EventWowPanelGameList, "BOTTOMLEFT", 0, -EVENTWOW_PANEL.GAP);
	chat:SetPoint("BOTTOMRIGHT", social, "BOTTOMLEFT", -EVENTWOW_PANEL.GAP, 0);
	EventWow_ApplyBackdrop(chat, EVENTWOW_PANEL.COLOR_SECTION);

	panel:SetScript("OnSizeChanged", EventWowPanel_Layout);
	panel:SetScript("OnShow", function()
		PlaySound("igCharacterInfoOpen");
		EventWowPanel_Resize();
		EventWowPanel_Layout();
		EventWowPanel_UpdatePlayerName();
		EventWowPanel_Update();
	end);
	panel:SetScript("OnHide", function()
		PlaySound("igCharacterInfoClose");
		EventWowChatEditBox:ClearFocus();
	end);
	panel:Hide();
end

-- Abrir / cerrar (boton del minimapa, /eventwow). Dentro de una partida no se abre.
function EventWowPanel_Toggle()
	if ( EventWowPanel:IsShown() ) then
		EventWowPanel:Hide();
	elseif ( EventWow_UI.mode == "match" ) then
		UIErrorsFrame:AddMessage(EVENTWOW_STR_PANEL_IN_MATCH, 1, 0.2, 0.2, 1.0);
	else
		EventWowPanel:Show();
	end
end

-- Boton del minimapa -------------------------------------------------------------------------------

EVENTWOW_MINIMAP_BUTTON = {
	ICON = "Interface\\Icons\\INV_BannerPVP_02",
	ANGLE = -70,    -- grados (0 = derecha, 90 = arriba): abajo a la derecha, entre el zoom y el borde inferior
	RADIUS = 80,
	COLOR_QUEUED = { 0.2, 1, 0.2 },
};

local function EventWow_MinimapButtonTooltip(button)
	GameTooltip:SetOwner(button, "ANCHOR_LEFT");
	GameTooltip:SetText(EVENTWOW_STR_PANEL_MINIMAP_TITLE);
	if ( EventWow_UI and EventWow_UI.mode == "match" ) then
		GameTooltip:AddLine(EVENTWOW_STR_PANEL_MINIMAP_MATCH, 1, 1, 1);
	elseif ( EventWow_Panel.queue ) then
		local game = EventWow_FindGame(EventWow_Panel.queue.gameId);
		local color = EVENTWOW_MINIMAP_BUTTON.COLOR_QUEUED;
		GameTooltip:AddLine(format(EVENTWOW_STR_PANEL_MINIMAP_QUEUED, game and game.name or EventWow_Panel.queue.gameId),
			color[1], color[2], color[3]);
	end
	GameTooltip:AddLine(EVENTWOW_STR_PANEL_MINIMAP_HINT, 0.8, 0.8, 0.8);
	GameTooltip:Show();
end

-- Borde verde mientras se busca partida (o se entra en una); tooltip al dia
function EventWowPanel_UpdateMinimapButton()
	local button = EventWowMinimapButton;
	if ( not button ) then
		return;
	end
	local busy = EventWow_Panel.queue ~= nil or (EventWowMatch_IsLoading and EventWowMatch_IsLoading());
	if ( busy ) then
		local color = EVENTWOW_MINIMAP_BUTTON.COLOR_QUEUED;
		button.border:SetVertexColor(color[1], color[2], color[3]);
	else
		button.border:SetVertexColor(1, 1, 1);
	end
	if ( GameTooltip:IsOwned(button) ) then
		EventWow_MinimapButtonTooltip(button);
	end
end

local function EventWow_CreateMinimapButton()
	local button = CreateFrame("Button", "EventWowMinimapButton", Minimap);
	button:SetSize(31, 31);
	button:SetFrameStrata("MEDIUM");
	button:SetFrameLevel(8);
	local angle = math.rad(EVENTWOW_MINIMAP_BUTTON.ANGLE);
	button:SetPoint("CENTER", Minimap, "CENTER",
		EVENTWOW_MINIMAP_BUTTON.RADIUS * math.cos(angle), EVENTWOW_MINIMAP_BUTTON.RADIUS * math.sin(angle));
	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD");

	local background = button:CreateTexture(nil, "BACKGROUND");
	background:SetSize(20, 20);
	background:SetPoint("TOPLEFT", button, "TOPLEFT", 7, -5);
	background:SetTexture("Interface\\Minimap\\UI-Minimap-Background");

	local icon = button:CreateTexture(nil, "ARTWORK");
	icon:SetSize(17, 17);
	icon:SetPoint("TOPLEFT", button, "TOPLEFT", 7, -6);
	icon:SetTexture(EVENTWOW_MINIMAP_BUTTON.ICON);
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92);
	button.icon = icon;

	local border = button:CreateTexture(nil, "OVERLAY");
	border:SetSize(53, 53);
	border:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0);
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder");
	button.border = border;

	button:SetScript("OnMouseDown", function(self)
		self.icon:SetPoint("TOPLEFT", self, "TOPLEFT", 8, -7);
	end);
	button:SetScript("OnMouseUp", function(self)
		self.icon:SetPoint("TOPLEFT", self, "TOPLEFT", 7, -6);
	end);
	button:SetScript("OnClick", function()
		EventWowPanel_Toggle();
	end);
	button:SetScript("OnEnter", EventWow_MinimapButtonTooltip);
	button:SetScript("OnLeave", function()
		GameTooltip:Hide();
	end);
end

-- Protocolo -------------------------------------------------------------------------------------

-- QUEUE_STATUS QUEUED <id> <segundos> <jugadores> | QUEUE_STATUS NONE
EventWow_RegisterHandler("QUEUE_STATUS", function(fields)
	if ( fields[1] == "QUEUED" ) then
		EventWow_Panel.queue = {
			gameId = fields[2],
			startTime = GetTime() - (tonumber(fields[3]) or 0),
			players = tonumber(fields[4]) or 1,
		};
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
EventWow_CreatePanel();
EventWow_CreateMinimapButton();
