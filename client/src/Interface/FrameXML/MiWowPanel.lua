-- MiWow: panel de eventos (solo minijuegos: chat, grupo y amigos son los nativos de WoW). Generico: todo lo que
-- muestra llega del servidor (GAMES, QUEUE_STATUS...), el cliente no conoce ningun minijuego. Ver docs/protocolo.md.
--
--  +-----------------------------------------------+
--  | EVENTOS                                   [X] |  barra superior (se arrastra)
--  +-----------------+-----------------------------+
--  | lista de juegos | detalle                     |
--  |                 | Buscar partida / en cola    |
--  +-----------------+-----------------------------+
-- Ventana pequena sobre la interfaz normal (no oculta nada) que se abre y cierra con el boton del minimapa,
-- /miwow o Esc; cerrada dentro de una partida (MiWow_SetMode, MiWow.lua). La cola en grupo usa el grupo
-- nativo: busca el lider por todos.

MIWOW_PANEL = {
	WIDTH = 860,          -- tamano de la ventana (menos si la pantalla no da: SCREEN_MARGIN por lado)
	HEIGHT = 560,
	SCREEN_MARGIN = 40,
	MARGIN = 8,
	GAP = 6,
	TOP_BAR_HEIGHT = 36,
	LIST_WIDTH_RATIO = 0.36,
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

MIWOW_STR_PANEL_TITLE = "EVENTOS";
MIWOW_STR_PANEL_MINIMAP_TITLE = "Eventos";
MIWOW_STR_PANEL_MINIMAP_HINT = "Clic: abrir o cerrar el panel (/miwow)";
MIWOW_STR_PANEL_MINIMAP_QUEUED = "Buscando partida: %s";
MIWOW_STR_PANEL_MINIMAP_MATCH = "En partida";
MIWOW_STR_PANEL_IN_MATCH = "No disponible durante una partida.";
MIWOW_STR_PANEL_GAMES = "MINIJUEGOS";
MIWOW_STR_PANEL_CONNECTING = "Conectando con el servidor...";
MIWOW_STR_PANEL_NO_GAMES = "No hay minijuegos disponibles.";
MIWOW_STR_PANEL_SOLO = "Solitario";
MIWOW_STR_PANEL_PLAYERS = "%d-%d jugadores";
MIWOW_STR_PANEL_PARTY = "%s  ·  en grupo hasta %d";
MIWOW_STR_PANEL_NO_PARTY = "%s  ·  sin grupos";
MIWOW_STR_PANEL_SEARCH = "Buscar partida";
MIWOW_STR_PANEL_SEARCH_GROUP = "Buscar partida en grupo (%d)";
-- Sesion siempre abierta (p. ej. el parkour): se entra directamente, sin cola
MIWOW_STR_PANEL_JOIN = "Entrar";
MIWOW_STR_PANEL_JOIN_GROUP = "Entrar en grupo (%d)";
MIWOW_STR_PANEL_OPEN_SESSION = "Sesión abierta (hasta %d)";
MIWOW_STR_PANEL_NOT_LEADER = "Solo el líder busca partida";
MIWOW_STR_PANEL_SOLO_ONLY = "Individual: sal del grupo";
MIWOW_STR_PANEL_GROUP_TOO_BIG = "Grupo demasiado grande (máx. %d)";
MIWOW_STR_PANEL_QUEUED = "Buscando partida: %s  |cffffffff%s|r";
MIWOW_STR_PANEL_FOUND = "Partida encontrada: %s. Esperando confirmación...";
MIWOW_STR_PANEL_QUEUED_GROUP ="Buscando partida en grupo (%d): %s  |cffffffff%s|r";
MIWOW_STR_PANEL_CANCEL = "Cancelar";
MIWOW_STR_PANEL_UNAVAILABLE = "Próximamente";
MIWOW_STR_PANEL_ENTERING = "Partida encontrada: %s. Entrando...";

MiWow_Panel = {
	selectedId = nil,
	offset = 0,
	visibleRows = 1,  -- lo calcula MiWowPanel_Layout segun el alto
	-- { gameId, startTime (GetTime()) } o nil
	queue = nil,
};

local function MiWow_ApplyBackdrop(frame, color)
	frame:SetBackdrop(MIWOW_PANEL.BACKDROP);
	frame:SetBackdropColor(unpack(color));
	frame:SetBackdropBorderColor(unpack(MIWOW_PANEL.COLOR_BORDER));
end

-- Grupo nativo (grupo o banda): tamano y si puede buscar partida (lider o sin grupo)
local function MiWow_GroupSize()
	local raid = GetNumRaidMembers();
	if ( raid > 0 ) then
		return raid;
	end
	return GetNumPartyMembers() + 1;
end

local function MiWow_IsLeaderOrSolo()
	if ( GetNumRaidMembers() > 0 ) then
		return IsRaidLeader() and true or false;
	end
	return GetNumPartyMembers() == 0 or (IsPartyLeader() and true or false);
end

local function MiWow_FindGame(id)
	for _, game in ipairs(MiWow_Protocol.games) do
		if ( game.id == id ) then
			return game;
		end
	end
	return nil;
end

local function MiWow_PlayersText(game)
	if ( game.openSession ) then
		return format(MIWOW_STR_PANEL_OPEN_SESSION, game.maxPlayers or 1);
	end
	if ( (game.maxPlayers or 1) <= 1 ) then
		return MIWOW_STR_PANEL_SOLO;
	end
	return format(MIWOW_STR_PANEL_PLAYERS, game.minPlayers or 1, game.maxPlayers);
end

local function MiWow_FormatElapsed(seconds)
	seconds = math.max(0, math.floor(seconds));
	return format("%d:%02d", math.floor(seconds / 60), seconds % 60);
end

-- Actualizacion ---------------------------------------------------------------------------------

function MiWowPanel_UpdateList()
	local games = MiWow_Protocol.games;
	local visibleRows = MiWow_Panel.visibleRows;
	local maxOffset = math.max(0, #games - visibleRows);
	MiWow_Panel.offset = math.min(math.max(MiWow_Panel.offset, 0), maxOffset);

	for i = 1, MIWOW_PANEL.MAX_ROWS do
		local row = _G["MiWowGameRow"..i];
		local game = (i <= visibleRows) and games[i + MiWow_Panel.offset];
		if ( game ) then
			row.gameId = game.id;
			row.icon:SetTexture(game.icon);
			row.name:SetText(game.name);
			row.players:SetText(MiWow_PlayersText(game));
			if ( game.id == MiWow_Panel.selectedId ) then
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

function MiWowPanel_UpdateDetail()
	local game = MiWow_FindGame(MiWow_Panel.selectedId);
	local hasGame = game ~= nil;

	if ( hasGame ) then
		MiWowPanelDetailIcon:SetTexture(game.icon);
		MiWowPanelDetailIcon:Show();
		MiWowPanelDetailName:SetText(game.name);
		local players = MiWow_PlayersText(game);
		if ( (game.maxPartySize or 1) > 1 ) then
			players = format(MIWOW_STR_PANEL_PARTY, players, game.maxPartySize);
		elseif ( (game.maxPlayers or 1) > 1 ) then
			players = format(MIWOW_STR_PANEL_NO_PARTY, players);
		end
		MiWowPanelDetailPlayers:SetText(players);
		MiWowPanelDetailDescription:SetText(game.description);
		MiWowPanelDetailMessage:SetText("");
	else
		MiWowPanelDetailIcon:Hide();
		MiWowPanelDetailName:SetText("");
		MiWowPanelDetailPlayers:SetText("");
		MiWowPanelDetailDescription:SetText("");
		if ( not MiWow_Protocol.connected ) then
			MiWowPanelDetailMessage:SetText(MIWOW_STR_PANEL_CONNECTING);
		else
			MiWowPanelDetailMessage:SetText(MIWOW_STR_PANEL_NO_GAMES);
		end
	end

	-- Una sola cola: si estas en cola (o entrando en una partida) se ve su estado (aunque mires otro juego)
	-- MiWowMatch.lua carga despues que este archivo
	local loading = MiWowMatch_IsLoading and MiWowMatch_IsLoading();
	if ( MiWow_Panel.queue or loading ) then
		MiWowPanelSearchButton:Hide();
		MiWowPanelQueue:Show();
		MiWowPanel_UpdateQueueText();
	else
		MiWowPanelQueue:Hide();
		MiWowPanelSearchButton:Show();
		-- En grupo busca el lider por todos; el servidor lo vuelve a comprobar
		local size = MiWow_GroupSize();
		local open = hasGame and game.openSession;
		local text, enabled = open and MIWOW_STR_PANEL_JOIN or MIWOW_STR_PANEL_SEARCH,
			hasGame and game.playable and MiWow_Protocol.connected;
		if ( hasGame and not game.playable ) then
			text = MIWOW_STR_PANEL_UNAVAILABLE;
		elseif ( hasGame and size > 1 ) then
			if ( not MiWow_IsLeaderOrSolo() ) then
				text, enabled = MIWOW_STR_PANEL_NOT_LEADER, false;
			elseif ( (game.maxPartySize or 1) <= 1 ) then
				text, enabled = MIWOW_STR_PANEL_SOLO_ONLY, false;
			elseif ( size > game.maxPartySize ) then
				text, enabled = format(MIWOW_STR_PANEL_GROUP_TOO_BIG, game.maxPartySize), false;
			else
				text = format(open and MIWOW_STR_PANEL_JOIN_GROUP or MIWOW_STR_PANEL_SEARCH_GROUP, size);
			end
		end
		MiWowPanelSearchButton:SetText(text);
		if ( enabled ) then
			MiWowPanelSearchButton:Enable();
		else
			MiWowPanelSearchButton:Disable();
		end
	end
end

function MiWowPanel_UpdateQueueText()
	if ( MiWowMatch_IsLoading and MiWowMatch_IsLoading() ) then
		local game = MiWow_FindGame(MiWow_Match.gameId);
		MiWowPanelQueueText:SetText(format(MIWOW_STR_PANEL_ENTERING, game and game.name or tostring(MiWow_Match.gameId)));
		MiWowPanelQueueCancel:Hide();
		return;
	end
	MiWowPanelQueueCancel:Show();

	local queue = MiWow_Panel.queue;
	if ( not queue ) then
		return;
	end
	local game = MiWow_FindGame(queue.gameId);
	local name = game and game.name or queue.gameId;
	if ( MiWow_MatchFound and MiWow_MatchFound.current ) then
		MiWowPanelQueueText:SetText(format(MIWOW_STR_PANEL_FOUND, name));
		return;
	end
	local elapsed = MiWow_FormatElapsed(GetTime() - queue.startTime);
	if ( queue.players > 1 ) then
		MiWowPanelQueueText:SetText(format(MIWOW_STR_PANEL_QUEUED_GROUP, queue.players, name, elapsed));
	else
		MiWowPanelQueueText:SetText(format(MIWOW_STR_PANEL_QUEUED, name, elapsed));
	end
end

function MiWowPanel_Update()
	-- Seleccion por defecto: el primero (o el que siga existiendo)
	if ( not MiWow_FindGame(MiWow_Panel.selectedId) ) then
		local first = MiWow_Protocol.games[1];
		MiWow_Panel.selectedId = first and first.id or nil;
	end
	MiWowPanel_UpdateList();
	MiWowPanel_UpdateDetail();
	MiWowPanel_UpdateMinimapButton();
end

function MiWowPanel_SelectGame(id)
	MiWow_Panel.selectedId = id;
	MiWowPanel_Update();
end

-- Construccion ----------------------------------------------------------------------------------

local function MiWow_CreateTopBar(panel)
	local bar = CreateFrame("Frame", "MiWowPanelTopBar", panel);
	bar:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -8);
	bar:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -8);
	bar:SetHeight(MIWOW_PANEL.TOP_BAR_HEIGHT);
	MiWow_ApplyBackdrop(bar, MIWOW_PANEL.COLOR_SECTION);

	local title = bar:CreateFontString("MiWowPanelTitle", "ARTWORK", "GameFontNormalHuge");
	title:SetPoint("LEFT", bar, "LEFT", 12, 0);
	title:SetText(MIWOW_STR_PANEL_TITLE);

	local close = CreateFrame("Button", "MiWowPanelCloseButton", bar, "UIPanelCloseButton");
	close:SetPoint("RIGHT", bar, "RIGHT", 2, 0);
	close:SetScript("OnClick", function()
		MiWowPanel:Hide();
	end);

	-- Arrastrar la ventana por la barra
	bar:EnableMouse(true);
	bar:RegisterForDrag("LeftButton");
	bar:SetScript("OnDragStart", function()
		MiWowPanel:StartMoving();
	end);
	bar:SetScript("OnDragStop", function()
		MiWowPanel:StopMovingOrSizing();
	end);
end

local function MiWow_CreateGameRow(list, index)
	local row = CreateFrame("Button", "MiWowGameRow"..index, list);
	row:SetHeight(MIWOW_PANEL.ROW_HEIGHT);
	row:SetPoint("TOPLEFT", list, "TOPLEFT", 8, -28 - (index - 1) * (MIWOW_PANEL.ROW_HEIGHT + 2));
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
			MiWowPanel_SelectGame(self.gameId);
		end
	end);
	row:Hide();
end

local function MiWow_CreateGameList(panel)
	local list = CreateFrame("Frame", "MiWowPanelGameList", panel);
	list:SetPoint("TOPLEFT", MiWowPanelTopBar, "BOTTOMLEFT", 0, -MIWOW_PANEL.GAP);
	-- Tamano: MiWowPanel_Layout
	MiWow_ApplyBackdrop(list, MIWOW_PANEL.COLOR_SECTION);

	local title = list:CreateFontString("MiWowPanelGamesTitle", "ARTWORK", "GameFontNormal");
	title:SetPoint("TOPLEFT", list, "TOPLEFT", 10, -8);
	title:SetText(MIWOW_STR_PANEL_GAMES);

	for i = 1, MIWOW_PANEL.MAX_ROWS do
		MiWow_CreateGameRow(list, i);
	end

	list:EnableMouseWheel(true);
	list:SetScript("OnMouseWheel", function(self, delta)
		MiWow_Panel.offset = MiWow_Panel.offset - delta;
		MiWowPanel_UpdateList();
	end);
end

local function MiWow_CreateDetail(panel)
	local detail = CreateFrame("Frame", "MiWowPanelDetail", panel);
	detail:SetPoint("TOPLEFT", MiWowPanelGameList, "TOPRIGHT", MIWOW_PANEL.GAP, 0);
	detail:SetPoint("BOTTOMLEFT", MiWowPanelGameList, "BOTTOMRIGHT", MIWOW_PANEL.GAP, 0);
	detail:SetPoint("RIGHT", MiWowPanelTopBar, "RIGHT", 0, 0);
	MiWow_ApplyBackdrop(detail, MIWOW_PANEL.COLOR_SECTION);

	local icon = detail:CreateTexture("MiWowPanelDetailIcon", "ARTWORK");
	icon:SetSize(56, 56);
	icon:SetPoint("TOPLEFT", detail, "TOPLEFT", 16, -16);

	local name = detail:CreateFontString("MiWowPanelDetailName", "ARTWORK", "GameFontNormalHuge");
	name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 12, -4);
	name:SetPoint("RIGHT", detail, "RIGHT", -16, 0);
	name:SetJustifyH("LEFT");

	local players = detail:CreateFontString("MiWowPanelDetailPlayers", "ARTWORK", "GameFontHighlight");
	players:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -6);

	local description = detail:CreateFontString("MiWowPanelDetailDescription", "ARTWORK", "GameFontHighlight");
	description:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", 0, -16);
	-- Hasta encima del boton / estado de cola
	description:SetPoint("BOTTOMRIGHT", detail, "BOTTOMRIGHT", -16, 70);
	description:SetJustifyH("LEFT");
	description:SetJustifyV("TOP");

	-- Conectando / sin juegos
	local message = detail:CreateFontString("MiWowPanelDetailMessage", "ARTWORK", "GameFontNormalLarge");
	message:SetPoint("CENTER", detail, "CENTER", 0, 20);

	local search = CreateFrame("Button", "MiWowPanelSearchButton", detail, "UIPanelButtonTemplate");
	search:SetSize(220, 32);
	search:SetPoint("BOTTOM", detail, "BOTTOM", 0, 20);
	search:SetText(MIWOW_STR_PANEL_SEARCH);
	search:SetScript("OnClick", function()
		if ( MiWow_Panel.selectedId ) then
			PlaySound("igMainMenuOptionCheckBoxOn");
			MiWow_Send("QUEUE", MiWow_Panel.selectedId);
		end
	end);

	-- Estado de la cola (sustituye al boton)
	local queue = CreateFrame("Frame", "MiWowPanelQueue", detail);
	queue:SetPoint("BOTTOMLEFT", detail, "BOTTOMLEFT", 16, 16);
	queue:SetPoint("BOTTOMRIGHT", detail, "BOTTOMRIGHT", -16, 16);
	queue:SetHeight(40);
	MiWow_ApplyBackdrop(queue, { 0.1, 0.25, 0.1, 0.6 });
	queue:Hide();

	local cancel = CreateFrame("Button", "MiWowPanelQueueCancel", queue, "UIPanelButtonTemplate");
	cancel:SetSize(100, 24);
	cancel:SetPoint("RIGHT", queue, "RIGHT", -8, 0);
	cancel:SetText(MIWOW_STR_PANEL_CANCEL);
	cancel:SetScript("OnClick", function()
		PlaySound("igMainMenuOptionCheckBoxOff");
		-- Con una partida encontrada pendiente, cancelar es rechazarla (MiWowMatchFound.lua)
		if ( MiWow_MatchFound and MiWow_MatchFound.current ) then
			MiWow_MatchFound.current.declined = true;
		end
		MiWow_Send("LEAVE");
	end);

	local queueText = queue:CreateFontString("MiWowPanelQueueText", "ARTWORK", "GameFontNormal");
	queueText:SetPoint("LEFT", queue, "LEFT", 12, 0);
	queueText:SetPoint("RIGHT", cancel, "LEFT", -8, 0);
	queueText:SetJustifyH("LEFT");

	local elapsed = 0;
	queue:SetScript("OnUpdate", function(self, delta)
		elapsed = elapsed + delta;
		if ( elapsed >= 0.5 ) then
			elapsed = 0;
			MiWowPanel_UpdateQueueText();
		end
	end);
end

-- Reparto proporcional al tamano de la pantalla (se llama al mostrar y al cambiar de resolucion/escala)
function MiWowPanel_Layout()
	local panel = MiWowPanel;
	local width, height = panel:GetWidth(), panel:GetHeight();
	if ( not width or width <= 0 or not height or height <= 0 ) then
		return;
	end

	local margin, gap = MIWOW_PANEL.MARGIN, MIWOW_PANEL.GAP;
	local gamesHeight = height - margin * 2 - MIWOW_PANEL.TOP_BAR_HEIGHT - gap;
	local listWidth = math.max(MIWOW_PANEL.LIST_MIN_WIDTH, math.floor((width - margin * 2) * MIWOW_PANEL.LIST_WIDTH_RATIO));
	MiWowPanelGameList:SetSize(listWidth, gamesHeight);

	-- Filas que caben bajo el titulo de la lista (28 px)
	local rows = math.floor((gamesHeight - 28 - margin) / (MIWOW_PANEL.ROW_HEIGHT + 2));
	MiWow_Panel.visibleRows = math.max(1, math.min(MIWOW_PANEL.MAX_ROWS, rows));
	MiWowPanel_UpdateList();
end

-- Tamano de la ventana: MIWOW_PANEL.WIDTH x HEIGHT, o menos si la pantalla no da
function MiWowPanel_Resize()
	local margin = MIWOW_PANEL.SCREEN_MARGIN * 2;
	local width = math.min(MIWOW_PANEL.WIDTH, UIParent:GetWidth() - margin);
	local height = math.min(MIWOW_PANEL.HEIGHT, UIParent:GetHeight() - margin);
	MiWowPanel:SetSize(math.floor(width), math.floor(height));
end

local function MiWow_CreatePanel()
	local panel = CreateFrame("Frame", "MiWowPanel", UIParent);
	panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0);
	panel:SetFrameStrata("MEDIUM");
	panel:SetToplevel(true);
	panel:EnableMouse(true);
	panel:SetMovable(true);
	panel:SetClampedToScreen(true);
	MiWow_ApplyBackdrop(panel, MIWOW_PANEL.COLOR_PANEL);
	MiWowPanel_Resize();
	-- Esc la cierra (CloseSpecialWindows)
	tinsert(UISpecialFrames, "MiWowPanel");

	MiWow_CreateTopBar(panel);
	MiWow_CreateGameList(panel);
	MiWow_CreateDetail(panel);

	panel:SetScript("OnSizeChanged", MiWowPanel_Layout);
	panel:SetScript("OnShow", function()
		PlaySound("igCharacterInfoOpen");
		MiWowPanel_Resize();
		MiWowPanel_Layout();
		MiWowPanel_Update();
	end);
	panel:SetScript("OnHide", function()
		PlaySound("igCharacterInfoClose");
	end);
	panel:Hide();
end

-- Abrir / cerrar (boton del minimapa, /miwow). Dentro de una partida no se abre.
function MiWowPanel_Toggle()
	if ( MiWowPanel:IsShown() ) then
		MiWowPanel:Hide();
	elseif ( MiWow_UI.mode == "match" ) then
		UIErrorsFrame:AddMessage(MIWOW_STR_PANEL_IN_MATCH, 1, 0.2, 0.2, 1.0);
	else
		MiWowPanel:Show();
	end
end

-- Boton del minimapa -------------------------------------------------------------------------------

MIWOW_MINIMAP_BUTTON = {
	ICON = "Interface\\Icons\\INV_BannerPVP_02",
	ANGLE = -70,    -- grados (0 = derecha, 90 = arriba): abajo a la derecha, entre el zoom y el borde inferior
	RADIUS = 80,
	COLOR_QUEUED = { 0.2, 1, 0.2 },
};

local function MiWow_MinimapButtonTooltip(button)
	GameTooltip:SetOwner(button, "ANCHOR_LEFT");
	GameTooltip:SetText(MIWOW_STR_PANEL_MINIMAP_TITLE);
	if ( MiWow_UI and MiWow_UI.mode == "match" ) then
		GameTooltip:AddLine(MIWOW_STR_PANEL_MINIMAP_MATCH, 1, 1, 1);
	elseif ( MiWow_Panel.queue ) then
		local game = MiWow_FindGame(MiWow_Panel.queue.gameId);
		local color = MIWOW_MINIMAP_BUTTON.COLOR_QUEUED;
		GameTooltip:AddLine(format(MIWOW_STR_PANEL_MINIMAP_QUEUED, game and game.name or MiWow_Panel.queue.gameId),
			color[1], color[2], color[3]);
	end
	GameTooltip:AddLine(MIWOW_STR_PANEL_MINIMAP_HINT, 0.8, 0.8, 0.8);
	GameTooltip:Show();
end

-- Borde verde mientras se busca partida (o se entra en una); tooltip al dia
function MiWowPanel_UpdateMinimapButton()
	local button = MiWowMinimapButton;
	if ( not button ) then
		return;
	end
	local busy = MiWow_Panel.queue ~= nil or (MiWowMatch_IsLoading and MiWowMatch_IsLoading());
	if ( busy ) then
		local color = MIWOW_MINIMAP_BUTTON.COLOR_QUEUED;
		button.border:SetVertexColor(color[1], color[2], color[3]);
	else
		button.border:SetVertexColor(1, 1, 1);
	end
	if ( GameTooltip:IsOwned(button) ) then
		MiWow_MinimapButtonTooltip(button);
	end
end

local function MiWow_CreateMinimapButton()
	local button = CreateFrame("Button", "MiWowMinimapButton", Minimap);
	button:SetSize(31, 31);
	button:SetFrameStrata("MEDIUM");
	button:SetFrameLevel(8);
	local angle = math.rad(MIWOW_MINIMAP_BUTTON.ANGLE);
	button:SetPoint("CENTER", Minimap, "CENTER",
		MIWOW_MINIMAP_BUTTON.RADIUS * math.cos(angle), MIWOW_MINIMAP_BUTTON.RADIUS * math.sin(angle));
	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD");

	local background = button:CreateTexture(nil, "BACKGROUND");
	background:SetSize(20, 20);
	background:SetPoint("TOPLEFT", button, "TOPLEFT", 7, -5);
	background:SetTexture("Interface\\Minimap\\UI-Minimap-Background");

	local icon = button:CreateTexture(nil, "ARTWORK");
	icon:SetSize(17, 17);
	icon:SetPoint("TOPLEFT", button, "TOPLEFT", 7, -6);
	icon:SetTexture(MIWOW_MINIMAP_BUTTON.ICON);
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
		MiWowPanel_Toggle();
	end);
	button:SetScript("OnEnter", MiWow_MinimapButtonTooltip);
	button:SetScript("OnLeave", function()
		GameTooltip:Hide();
	end);
end

-- Protocolo -------------------------------------------------------------------------------------

-- QUEUE_STATUS QUEUED <id> <segundos> <jugadores> | QUEUE_STATUS NONE
MiWow_RegisterHandler("QUEUE_STATUS", function(fields)
	if ( fields[1] == "QUEUED" ) then
		MiWow_Panel.queue = {
			gameId = fields[2],
			startTime = GetTime() - (tonumber(fields[3]) or 0),
			players = tonumber(fields[4]) or 1,
		};
	else
		MiWow_Panel.queue = nil;
	end
	MiWowPanel_Update();
end);

MiWow_RegisterListener("CONNECTED", MiWowPanel_Update);
-- El boton de buscar depende del grupo nativo (lider, tamano)
local groupFrame = CreateFrame("Frame");
groupFrame:RegisterEvent("PARTY_MEMBERS_CHANGED");
groupFrame:RegisterEvent("RAID_ROSTER_UPDATE");
groupFrame:RegisterEvent("PARTY_LEADER_CHANGED");
groupFrame:SetScript("OnEvent", function()
	if ( MiWowPanel:IsShown() ) then
		MiWowPanel_UpdateDetail();
	end
end);
MiWow_RegisterListener("GAMES", MiWowPanel_Update);
MiWow_CreatePanel();
MiWow_CreateMinimapButton();
