-- MiWow: temporadas de hermandad (servidor: modules/mod-miwow/src/guild, ver "Hermandad" en docs/protocolo.md).
-- Las cuatro superficies del diseno (mod-guild-season/doc/AIO_FRONTEND_INSTRUCTIONS.md), en una ventana con pestanas:
--   1 Tablon      misiones diarias y semanales. Se abre desde el objeto "Tablon de la hermandad": sustituye a la
--                 lista nativa del gossip y sus botones eligen las misiones del gossip (detalle y recompensas en la
--                 ventana de misiones nativa). Desde otro sitio solo se consulta.
--   2 Hermandad   puntos de temporada, ventajas, premios del podio, ranking interno y clasificacion.
--   3 Reputacion  rango personal, progreso y tramos.
--   4 Tienda      objetos de la temporada por rango. Se abre desde el intendente (comprar, GUILD_BUY: el servidor
--                 comprueba distancia, rango y oro); desde otro sitio solo se consulta.
-- Sin hermandad no se abre. Todo llega del servidor (GUILD_INFO); el cliente solo pinta. Cerrada en partida.

MIWOW_GUILD = {
	WIDTH = 720,
	HEIGHT = 560,
	TOP_BAR_HEIGHT = 36,
	TAB_HEIGHT = 26,
	BOARD_ROWS = 8,
	BOARD_ROW_HEIGHT = 38,
	PERK_ROWS = 15,
	PERK_ROW_HEIGHT = 22,
	MEMBER_ROWS = 10,
	RANKING_ROWS = 5,
	SHOP_ROWS = 12,
	SHOP_ROW_HEIGHT = 30,
	-- Tras GUILD_DIRTY, se espera un poco antes de pedir (el servidor admite una peticion por segundo)
	REFRESH_DELAY = 1.2,
	-- GUILD_BOARD_OPEN llega justo antes del gossip del tablon
	BOARD_OPEN_WINDOW = 3,
	COLOR_OK = "|cff33ff33",
	COLOR_LOCKED = "|cff888888",
	COLOR_BAD = "|cffff4444",
	COLOR_GOLD = "|cffffd100",
	COLOR_WHITE = "|cffffffff",
	TAB_ICON = "Interface\\Icons\\INV_Shirt_GuildTabard_01",
	ICON_CHECK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14|t",
	ICON_LOCK = "|TInterface\\LFGFrame\\UI-LFG-ICON-LOCK:14|t",
	ICON_STAR = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:16|t",
	ICON_UNKNOWN = "Interface\\Icons\\INV_Misc_QuestionMark",
};

MIWOW_STR_GUILD_TAB_TOOLTIP = "Temporada de la hermandad";
MIWOW_STR_GUILD_NO_GUILD = "No perteneces a ninguna hermandad.";
MIWOW_STR_GUILD_LOADING = "Cargando...";
MIWOW_STR_GUILD_TABS = { "Tablón", "Hermandad", "Reputación", "Tienda" };
MIWOW_STR_GUILD_TITLE_BOARD = "TABLÓN DE HERMANDAD";
MIWOW_STR_GUILD_TITLE_GUILD = "HERMANDAD: %s";
MIWOW_STR_GUILD_TITLE_REP = "TU REPUTACIÓN CON LA HERMANDAD";
MIWOW_STR_GUILD_TITLE_SHOP = "TIENDA DE HERMANDAD";
MIWOW_STR_GUILD_SEASON_DAY = "%s  ·  Día %d";
MIWOW_STR_GUILD_SEASON_LEFT = "%s  ·  acaba en %s";
MIWOW_STR_GUILD_PTH = "%s PTH";
MIWOW_STR_GUILD_REP = "%s Rep";
-- Tablon
MIWOW_STR_GUILD_DAILY = "MISIONES DIARIAS";
MIWOW_STR_GUILD_WEEKLY = "MISIONES SEMANALES";
MIWOW_STR_GUILD_RESET = "Reinicio: %s";
MIWOW_STR_GUILD_WEEKDAYS = { "domingo", "lunes", "martes", "miércoles", "jueves", "viernes", "sábado" };
MIWOW_STR_GUILD_KIND = { [0] = "Individual", [1] = "Grupal (%d)", [2] = "Banda (%d)" };
MIWOW_STR_GUILD_LEVEL = "Nv %d";
MIWOW_STR_GUILD_CLAIMED = MIWOW_GUILD.ICON_CHECK.." "..MIWOW_GUILD.COLOR_LOCKED.."RECLAMADA|r";
MIWOW_STR_GUILD_AVAILABLE = MIWOW_GUILD.COLOR_OK.."DISPONIBLE|r";
MIWOW_STR_GUILD_ACTION = { [0] = "Aceptar", [1] = "En curso", [2] = "Entregar", [3] = "Hecha", [4] = "Bloqueada" };
MIWOW_STR_GUILD_STATUS_TIP = {
	[0] = "Puedes aceptarla en el tablón.",
	[1] = "La tienes en curso.",
	[2] = "Lista para entregar en el tablón.",
	[3] = "Ya la has hecho (vuelve a salir con el reinicio).",
	[4] = "No se completó con el grupo que pedía: abandónala en el registro de misiones y vuelve a hacerla.",
};
MIWOW_STR_GUILD_TIP_INDIVIDUAL = "Individual: suma puntos a la hermandad en cada entrega.";
MIWOW_STR_GUILD_TIP_GROUP = "De grupo: hacen falta %d miembros de la hermandad en el grupo al completarla. Solo la primera entrega de la hermandad suma puntos; las demás, solo reputación.";
MIWOW_STR_GUILD_TIP_CLAIMED = "Tu hermandad ya la ha reclamado: solo da reputación.";
MIWOW_STR_GUILD_BOARD_EMPTY = "No hay misiones en el tablón.";
MIWOW_STR_GUILD_BOARD_AWAY = "Ve al tablón de la hermandad para aceptar y entregar misiones.";
MIWOW_STR_GUILD_BOARD_LEGEND = "La reputación es siempre para quien la entrega.";
-- Hermandad
MIWOW_STR_GUILD_POINTS = "Puntos de Temporada";
MIWOW_STR_GUILD_NEXT_PERK = "Próxima ventaja: %s (%s PTH)";
MIWOW_STR_GUILD_ALL_PERKS = "Todas las ventajas desbloqueadas";
MIWOW_STR_GUILD_NO_PERKS = "Sin ventajas esta temporada";
MIWOW_STR_GUILD_PERKS = "VENTAJAS";
MIWOW_STR_GUILD_PERK_ACTIVE = MIWOW_GUILD.ICON_CHECK.." "..MIWOW_GUILD.COLOR_OK.."Activa|r";
MIWOW_STR_GUILD_PRIZES = "PREMIOS TOP 3 ESTA TEMPORADA";
MIWOW_STR_GUILD_NO_PRIZES = "Sin premios esta temporada";
MIWOW_STR_GUILD_PRIZE_POSITION = "%d.º";
MIWOW_STR_GUILD_MEMBERS = "RANKING INTERNO";
MIWOW_STR_GUILD_CONTRIBUTION = "Tu contribución: %s PTH";
MIWOW_STR_GUILD_RANKING = "CLASIFICACIÓN DE HERMANDADES";
MIWOW_STR_GUILD_POSITION = "Tu hermandad: %d.º";
MIWOW_STR_GUILD_NO_POSITION = "Tu hermandad aún no tiene puntos";
MIWOW_STR_GUILD_EMPTY = "Nadie tiene puntos todavía.";
MIWOW_STR_GUILD_YOU = "Tú";
-- Reputacion
MIWOW_STR_GUILD_CURRENT_TIER = "Tramo actual:";
MIWOW_STR_GUILD_PROGRESS = "Progreso:  %s / %s";
MIWOW_STR_GUILD_TOWARDS = "hacia %s";
MIWOW_STR_GUILD_MAX_TIER = "Tramo máximo (%s de reputación)";
MIWOW_STR_GUILD_TIERS = "TRAMOS";
MIWOW_STR_GUILD_TIER_SHOP = "%d en la tienda";
MIWOW_STR_GUILD_SEASON_CONTRIBUTION = "Tu contribución esta temporada: %s PTH";
MIWOW_STR_GUILD_DAILY_CAP = "Hoy: %s / %s PTH";
MIWOW_STR_GUILD_REP_NOTE = "La reputación es permanente: no se pierde al cambiar de temporada (sí al dejar la hermandad).";
-- Tienda
MIWOW_STR_GUILD_MY_TIER = "Tu tramo: %s (%d)";
MIWOW_STR_GUILD_MY_MONEY = "Tu dinero: %s";
MIWOW_STR_GUILD_SHOP_AVAILABLE = "DISPONIBLES PARA TI";
MIWOW_STR_GUILD_SHOP_LOCKED = "REQUIEREN MAYOR REPUTACIÓN";
MIWOW_STR_GUILD_SHOP_FROM = "Desde: %s";
MIWOW_STR_GUILD_SHOP_BUY = "Comprar";
MIWOW_STR_GUILD_SHOP_EMPTY = "La tienda no tiene objetos esta temporada.";
MIWOW_STR_GUILD_SHOP_AWAY = "Habla con el intendente de la hermandad para comprar.";
MIWOW_STR_GUILD_SHOP_CONFIRM = "¿Comprar %s por %s?";

MiWow_Guild = {
	tab = 2,
	pending = nil,      -- segundos hasta pedir GUILD_INFO
	state = nil,
	ranks = {},
	perks = {},
	prizes = {},
	board = nil,
	ranking = nil,
	members = {},
	vendor = {},
	receivedAt = 0,     -- GetTime() de cuando llegaron los segundos (temporada, reinicios)
	boardOpenAt = nil,  -- GetTime() de GUILD_BOARD_OPEN (el gossip que llega detras es el del tablon)
	gossip = false,     -- el gossip del tablon esta abierto (botones del tablon activos)
	handoff = false,    -- se oculta la ventana para pasar a la de misiones nativa (sin cerrar el gossip)
	reopen = false,     -- volver al tablon al cerrar la ventana de misiones nativa
	shop = false,       -- abierta desde el intendente (botones de compra activos)
};

local function MiWowGuild_Number(value)
	-- 12345 -> "12.345"
	local text = tostring(math.floor(tonumber(value) or 0));
	local formatted = text:reverse():gsub("(%d%d%d)", "%1."):reverse();
	return (formatted:gsub("^%.", ""));
end

local function MiWowGuild_Remaining(seconds)
	return (tonumber(seconds) or 0) - (GetTime() - MiWow_Guild.receivedAt);
end

local function MiWowGuild_TimeLeft(seconds)
	seconds = MiWowGuild_Remaining(seconds);
	if ( seconds <= 0 ) then
		return "-";
	end
	if ( seconds < 60 ) then
		return SecondsToTime(seconds);
	end
	return SecondsToTime(seconds, true, false, 2);
end

-- Hora local del siguiente reinicio: "06:00" (diario) o "lunes 06:00" (semanal)
local function MiWowGuild_ResetTime(seconds, weekly)
	local remaining = MiWowGuild_Remaining(seconds);
	if ( remaining <= 0 ) then
		return "-";
	end
	local when = date("*t", time() + remaining);
	local text = format("%02d:%02d", when.hour, when.min);
	if ( weekly ) then
		text = (MIWOW_STR_GUILD_WEEKDAYS[when.wday] or "").." "..text;
	end
	return text;
end

local function MiWowGuild_Money(copper)
	copper = math.floor(tonumber(copper) or 0);
	local gold = math.floor(copper / 10000);
	local silver = math.floor((copper % 10000) / 100);
	local rest = copper % 100;
	local parts = {};
	if ( gold > 0 ) then
		tinsert(parts, format(GOLD_AMOUNT_TEXTURE, gold, 0, 0));
	end
	if ( silver > 0 ) then
		tinsert(parts, format(SILVER_AMOUNT_TEXTURE, silver, 0, 0));
	end
	if ( rest > 0 or #parts == 0 ) then
		tinsert(parts, format(COPPER_AMOUNT_TEXTURE, rest, 0, 0));
	end
	return table.concat(parts, " ");
end

local function MiWowGuild_RankName(rank)
	for _, info in ipairs(MiWow_Guild.ranks) do
		if ( info.rank == rank ) then
			return info.name;
		end
	end
	return tostring(rank);
end

-- Rango propio (numero); -1 sin datos
local function MiWowGuild_MyRank()
	local state = MiWow_Guild.state;
	if ( not state or not state.inGuild ) then
		return -1;
	end
	for _, info in ipairs(MiWow_Guild.ranks) do
		if ( info.name == state.rankName ) then
			return info.rank;
		end
	end
	return 0;
end

-- GetItemIcon no necesita el objeto en la cache; si no existiera, el de GetItemInfo (puede no estar aun)
local function MiWowGuild_ItemIcon(id)
	local icon = GetItemIcon and GetItemIcon(id);
	if ( not icon ) then
		icon = select(10, GetItemInfo(id));
	end
	return icon or MIWOW_GUILD.ICON_UNKNOWN;
end

local function MiWowGuild_ItemName(id, fallback)
	local name, _, quality = GetItemInfo(id);
	if ( name and quality and ITEM_QUALITY_COLORS[quality] ) then
		return ITEM_QUALITY_COLORS[quality].hex..name.."|r";
	end
	return MIWOW_GUILD.COLOR_WHITE..(fallback or name or ("#"..id)).."|r";
end

-- Indice de una mision en la lista del gossip (disponibles: 5 valores por mision; en curso: 4)
local function MiWowGuild_FindGossip(title, stride, ...)
	local index = 0;
	for i = 1, select("#", ...), stride do
		index = index + 1;
		if ( select(i, ...) == title ) then
			return index;
		end
	end
	return nil;
end

local function MiWowGuild_IsActiveStatus(status)
	return status == 1 or status == 2 or status == 4;
end

local function MiWowGuild_GossipIndex(quest)
	if ( not MiWow_Guild.gossip ) then
		return nil;
	end
	if ( MiWowGuild_IsActiveStatus(quest.status) ) then
		return MiWowGuild_FindGossip(quest.title, 4, GetGossipActiveQuests());
	end
	if ( quest.status == 0 ) then
		return MiWowGuild_FindGossip(quest.title, 5, GetGossipAvailableQuests());
	end
	return nil;
end

-- Peticion ---------------------------------------------------------------------------------------

function MiWowGuild_Request(delay)
	if ( not MiWow_Protocol.connected ) then
		return;
	end
	if ( delay ) then
		MiWow_Guild.pending = delay;
	else
		MiWow_Guild.pending = nil;
		MiWow_Send("GUILD_INFO");
	end
end

-- Construccion comun -----------------------------------------------------------------------------

local function MiWowGuild_Backdrop(frame, color)
	frame:SetBackdrop(MIWOW_PANEL.BACKDROP);
	frame:SetBackdropColor(unpack(color));
	frame:SetBackdropBorderColor(unpack(MIWOW_PANEL.COLOR_BORDER));
end

local function MiWowGuild_Text(parent, font, justify)
	local text = parent:CreateFontString(nil, "ARTWORK", font or "GameFontHighlight");
	text:SetJustifyH(justify or "LEFT");
	return text;
end

local function MiWowGuild_CreateBar(parent, width, height, r, g, b)
	local bar = CreateFrame("StatusBar", nil, parent);
	bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar");
	bar:SetStatusBarColor(r, g, b);
	bar:SetSize(width, height);
	local background = bar:CreateTexture(nil, "BACKGROUND");
	background:SetAllPoints(bar);
	background:SetTexture(0, 0, 0, 0.6);
	bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
	bar.text:SetPoint("CENTER", bar, "CENTER", 0, 0);
	return bar;
end

local function MiWowGuild_SetBar(bar, value, minValue, maxValue)
	if ( not maxValue or maxValue <= minValue ) then
		bar:SetMinMaxValues(0, 1);
		bar:SetValue(1);
		return;
	end
	bar:SetMinMaxValues(minValue, maxValue);
	bar:SetValue(math.min(math.max(value, minValue), maxValue));
end

local function MiWowGuild_SetTooltip(frame)
	frame:SetScript("OnEnter", function(self)
		if ( not self.tooltip ) then
			return;
		end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
		if ( self.tooltip.spell ) then
			GameTooltip:SetHyperlink("spell:"..self.tooltip.spell);
		elseif ( self.tooltip.item ) then
			GameTooltip:SetHyperlink("item:"..self.tooltip.item);
		else
			GameTooltip:SetText(self.tooltip.title or "", 1, 1, 1);
			for _, line in ipairs(self.tooltip.lines or {}) do
				GameTooltip:AddLine(line, 1, 0.82, 0, true);
			end
		end
		GameTooltip:Show();
	end);
	frame:SetScript("OnLeave", function()
		GameTooltip:Hide();
	end);
end

-- Cabecera de seccion: titulo a la izquierda, texto a la derecha, linea debajo
local function MiWowGuild_CreateHeader(parent)
	local header = CreateFrame("Frame", nil, parent);
	header:SetHeight(22);
	header.left = MiWowGuild_Text(header, "GameFontNormal");
	header.left:SetPoint("LEFT", header, "LEFT", 4, 0);
	header.right = MiWowGuild_Text(header, "GameFontHighlightSmall", "RIGHT");
	header.right:SetPoint("RIGHT", header, "RIGHT", -4, 0);
	local line = header:CreateTexture(nil, "ARTWORK");
	line:SetTexture(1, 0.82, 0, 0.25);
	line:SetHeight(1);
	line:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0);
	line:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0);
	return header;
end

-- Pestana 1: tablon ------------------------------------------------------------------------------

local function MiWowGuild_CreateBoardRow(parent)
	local row = CreateFrame("Frame", nil, parent);
	row:SetHeight(MIWOW_GUILD.BOARD_ROW_HEIGHT);
	row:EnableMouse(true);
	MiWowGuild_SetTooltip(row);

	row.icon = row:CreateTexture(nil, "ARTWORK");
	row.icon:SetSize(20, 20);
	row.icon:SetPoint("LEFT", row, "LEFT", 6, 0);

	row.button = CreateFrame("Button", nil, row, "UIPanelButtonTemplate");
	row.button:SetSize(96, 22);
	row.button:SetPoint("RIGHT", row, "RIGHT", -4, 0);
	row.button:SetScript("OnClick", function(self)
		MiWowGuild_BoardAction(self:GetParent());
	end);

	row.reward = MiWowGuild_Text(row, "GameFontHighlight", "RIGHT");
	row.reward:SetPoint("TOPRIGHT", row.button, "TOPLEFT", -12, 6);
	row.claim = MiWowGuild_Text(row, "GameFontHighlightSmall", "RIGHT");
	row.claim:SetPoint("TOPRIGHT", row.reward, "BOTTOMRIGHT", 0, -3);

	row.title = MiWowGuild_Text(row, "GameFontNormal");
	row.title:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, 6);
	row.title:SetPoint("RIGHT", row.reward, "LEFT", -8, 0);
	row.sub = MiWowGuild_Text(row, "GameFontHighlightSmall");
	row.sub:SetPoint("TOPLEFT", row.title, "BOTTOMLEFT", 0, -3);
	row:Hide();
	return row;
end

local function MiWowGuild_CreateBoardPage(content)
	local page = CreateFrame("Frame", "MiWowGuildBoardPage", content);
	page:SetAllPoints(content);
	page.headers = { MiWowGuild_CreateHeader(page), MiWowGuild_CreateHeader(page) };
	page.rows = {};
	for i = 1, MIWOW_GUILD.BOARD_ROWS do
		page.rows[i] = MiWowGuild_CreateBoardRow(page);
	end
	page.message = MiWowGuild_Text(page, "GameFontNormalLarge", "CENTER");
	page.message:SetPoint("CENTER", page, "CENTER", 0, 20);
	page.footer = MiWowGuild_Text(page, "GameFontNormalSmall");
	page.footer:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 12, 10);
	page.footer:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -12, 10);
	page:Hide();
end

local function MiWowGuild_FillBoardRow(row, quest)
	row.quest = quest;

	local icon;
	if ( quest.status == 2 ) then
		icon = "Interface\\GossipFrame\\ActiveQuestIcon";
	elseif ( quest.status == 1 or quest.status == 4 ) then
		icon = "Interface\\GossipFrame\\IncompleteQuestIcon";
	elseif ( quest.board == 0 ) then
		icon = "Interface\\GossipFrame\\DailyQuestIcon";
	else
		icon = "Interface\\GossipFrame\\AvailableQuestIcon";
	end
	row.icon:SetTexture(icon);
	row.icon:SetDesaturated(quest.status == 3);

	local color = (quest.status == 3) and MIWOW_GUILD.COLOR_LOCKED or "";
	row.title:SetText(color..quest.title..(color ~= "" and "|r" or ""));
	local level = (quest.level and quest.level > 0) and quest.level or UnitLevel("player");
	local kind = format(MIWOW_STR_GUILD_KIND[quest.kind] or MIWOW_STR_GUILD_KIND[0], quest.members);
	row.sub:SetText(kind.."  ·  "..format(MIWOW_STR_GUILD_LEVEL, level));
	row.reward:SetText(MIWOW_GUILD.COLOR_GOLD.."+"..format(MIWOW_STR_GUILD_PTH, MiWowGuild_Number(quest.points)).."|r   "..
		MIWOW_GUILD.COLOR_OK.."+"..format(MIWOW_STR_GUILD_REP, MiWowGuild_Number(quest.reputation)).."|r");
	row.claim:SetText(quest.claimed and MIWOW_STR_GUILD_CLAIMED or MIWOW_STR_GUILD_AVAILABLE);

	row.button:SetText(MIWOW_STR_GUILD_ACTION[quest.status] or "");
	if ( MiWowGuild_GossipIndex(quest) ) then
		row.button:Enable();
	else
		row.button:Disable();
	end

	local lines = { MIWOW_STR_GUILD_STATUS_TIP[quest.status] or "" };
	if ( quest.kind == 0 ) then
		tinsert(lines, MIWOW_STR_GUILD_TIP_INDIVIDUAL);
	else
		tinsert(lines, format(MIWOW_STR_GUILD_TIP_GROUP, quest.members));
	end
	if ( quest.claimed ) then
		tinsert(lines, MIWOW_STR_GUILD_TIP_CLAIMED);
	end
	row.tooltip = { title = quest.title, lines = lines };
end

local function MiWowGuild_UpdateBoard()
	local page = MiWowGuildBoardPage;
	local board = MiWow_Guild.board;
	for _, row in ipairs(page.rows) do
		row:Hide();
	end
	for _, header in ipairs(page.headers) do
		header:Hide();
	end

	if ( not board ) then
		page.message:SetText(MIWOW_STR_GUILD_LOADING);
		page.footer:SetText("");
		return;
	end
	page.message:SetText(#board.quests == 0 and MIWOW_STR_GUILD_BOARD_EMPTY or "");

	local y = -8;
	local used = 0;
	local sections = {
		{ board = 0, title = MIWOW_STR_GUILD_DAILY, reset = MiWowGuild_ResetTime(board.dailyLeft, false) },
		{ board = 1, title = MIWOW_STR_GUILD_WEEKLY, reset = MiWowGuild_ResetTime(board.weeklyLeft, true) },
	};
	for index, section in ipairs(sections) do
		local quests = {};
		for _, quest in ipairs(board.quests) do
			if ( quest.board == section.board ) then
				tinsert(quests, quest);
			end
		end
		if ( #quests > 0 ) then
			local header = page.headers[index];
			header:SetPoint("TOPLEFT", page, "TOPLEFT", 10, y);
			header:SetPoint("RIGHT", page, "RIGHT", -10, 0);
			header.left:SetText(section.title);
			header.right:SetText(format(MIWOW_STR_GUILD_RESET, section.reset));
			header:Show();
			y = y - 26;
			for _, quest in ipairs(quests) do
				if ( used < MIWOW_GUILD.BOARD_ROWS ) then
					used = used + 1;
					local row = page.rows[used];
					row:SetPoint("TOPLEFT", page, "TOPLEFT", 10, y);
					row:SetPoint("RIGHT", page, "RIGHT", -10, 0);
					MiWowGuild_FillBoardRow(row, quest);
					row:Show();
					y = y - MIWOW_GUILD.BOARD_ROW_HEIGHT - 2;
				end
			end
			y = y - 8;
		end
	end

	local footer = MIWOW_STR_GUILD_BOARD_LEGEND;
	if ( not MiWow_Guild.gossip ) then
		footer = MIWOW_STR_GUILD_BOARD_AWAY.."  "..footer;
	end
	page.footer:SetText(footer);
end

-- Boton de una mision: elige la mision en el gossip del tablon; la ventana de misiones nativa hace el resto
-- (detalle/aceptar, progreso, recompensas). Al cerrarla se vuelve al tablon.
function MiWowGuild_BoardAction(row)
	local quest = row.quest;
	local index = quest and MiWowGuild_GossipIndex(quest);
	if ( not index ) then
		return;
	end
	MiWow_Guild.handoff = true;
	MiWow_Guild.reopen = true;
	MiWowGuildFrame:Hide();
	MiWow_Guild.handoff = false;
	if ( MiWowGuild_IsActiveStatus(quest.status) ) then
		SelectGossipActiveQuest(index);
	else
		SelectGossipAvailableQuest(index);
	end
end

-- Pestana 2: hermandad ---------------------------------------------------------------------------

local function MiWowGuild_CreateLine(parent, height)
	local line = CreateFrame("Frame", nil, parent);
	line:SetHeight(height);
	line:EnableMouse(true);
	MiWowGuild_SetTooltip(line);
	line.left = MiWowGuild_Text(line, "GameFontHighlight");
	line.left:SetPoint("LEFT", line, "LEFT", 4, 0);
	line.right = MiWowGuild_Text(line, "GameFontNormal", "RIGHT");
	line.right:SetPoint("RIGHT", line, "RIGHT", -4, 0);
	return line;
end

local function MiWowGuild_CreateGuildPage(content)
	local page = CreateFrame("Frame", "MiWowGuildGuildPage", content);
	page:SetAllPoints(content);
	local leftWidth = 400;

	-- Puntos de temporada
	local pointsLabel = MiWowGuild_Text(page, "GameFontNormal");
	pointsLabel:SetPoint("TOPLEFT", page, "TOPLEFT", 14, -12);
	pointsLabel:SetText(MIWOW_STR_GUILD_POINTS);
	page.pointsBar = MiWowGuild_CreateBar(page, leftWidth - 20, 20, 0.85, 0.65, 0.1);
	page.pointsBar:SetPoint("TOPLEFT", pointsLabel, "BOTTOMLEFT", 0, -6);
	page.pointsBar.text:SetFontObject(GameFontHighlight);
	page.nextPerk = MiWowGuild_Text(page, "GameFontHighlightSmall");
	page.nextPerk:SetPoint("TOPLEFT", page.pointsBar, "BOTTOMLEFT", 0, -6);

	-- Ventajas
	page.perkHeader = MiWowGuild_CreateHeader(page);
	page.perkHeader:SetPoint("TOPLEFT", page, "TOPLEFT", 10, -84);
	page.perkHeader:SetWidth(leftWidth - 12);
	page.perkHeader.left:SetText(MIWOW_STR_GUILD_PERKS);
	page.perks = {};
	for i = 1, MIWOW_GUILD.PERK_ROWS do
		local line = MiWowGuild_CreateLine(page, MIWOW_GUILD.PERK_ROW_HEIGHT);
		line:SetPoint("TOPLEFT", page.perkHeader, "BOTTOMLEFT", 0, -4 - (i - 1) * MIWOW_GUILD.PERK_ROW_HEIGHT);
		line:SetWidth(leftWidth - 12);
		line.icon = line:CreateTexture(nil, "ARTWORK");
		line.icon:SetSize(MIWOW_GUILD.PERK_ROW_HEIGHT - 2, MIWOW_GUILD.PERK_ROW_HEIGHT - 2);
		line.icon:SetPoint("LEFT", line, "LEFT", 4, 0);
		line.left:SetPoint("LEFT", line.icon, "RIGHT", 8, 0);
		page.perks[i] = line;
	end

	-- Premios del podio (columna derecha, abajo)
	page.prizeHeader = MiWowGuild_CreateHeader(page);
	page.prizeHeader:SetPoint("TOPLEFT", page, "TOPLEFT", leftWidth + 16, -392);
	page.prizeHeader:SetPoint("RIGHT", page, "RIGHT", -10, 0);
	page.prizeHeader.left:SetText(MIWOW_STR_GUILD_PRIZES);
	page.prizes = {};
	for i = 1, 3 do
		local prize = CreateFrame("Button", nil, page);
		prize:SetSize(38, 38);
		prize:SetPoint("TOPLEFT", page.prizeHeader, "BOTTOMLEFT", 36 + (i - 1) * 90, -8);
		prize.icon = prize:CreateTexture(nil, "ARTWORK");
		prize.icon:SetAllPoints(prize);
		prize.count = prize:CreateFontString(nil, "OVERLAY", "NumberFontNormal");
		prize.count:SetPoint("BOTTOMRIGHT", prize, "BOTTOMRIGHT", -2, 2);
		prize.position = MiWowGuild_Text(page, "GameFontNormalLarge", "RIGHT");
		prize.position:SetPoint("RIGHT", prize, "LEFT", -6, 0);
		MiWowGuild_SetTooltip(prize);
		page.prizes[i] = prize;
	end
	page.noPrizes = MiWowGuild_Text(page, "GameFontHighlightSmall");
	page.noPrizes:SetPoint("TOPLEFT", page.prizeHeader, "BOTTOMLEFT", 4, -12);
	page.noPrizes:SetText(MIWOW_GUILD.COLOR_LOCKED..MIWOW_STR_GUILD_NO_PRIZES.."|r");

	-- Ranking interno
	local rightX = leftWidth + 16;
	page.memberHeader = MiWowGuild_CreateHeader(page);
	page.memberHeader:SetPoint("TOPLEFT", page, "TOPLEFT", rightX, -10);
	page.memberHeader:SetPoint("RIGHT", page, "RIGHT", -10, 0);
	page.memberHeader.left:SetText(MIWOW_STR_GUILD_MEMBERS);
	page.contribution = MiWowGuild_Text(page, "GameFontHighlightSmall");
	page.contribution:SetPoint("TOPLEFT", page.memberHeader, "BOTTOMLEFT", 4, -4);
	page.members = {};
	for i = 1, MIWOW_GUILD.MEMBER_ROWS do
		local line = MiWowGuild_CreateLine(page, 18);
		line:SetPoint("TOPLEFT", page.memberHeader, "BOTTOMLEFT", 0, -22 - (i - 1) * 18);
		line:SetPoint("RIGHT", page, "RIGHT", -10, 0);
		page.members[i] = line;
	end

	-- Clasificacion de hermandades
	page.rankingHeader = MiWowGuild_CreateHeader(page);
	page.rankingHeader:SetPoint("TOPLEFT", page, "TOPLEFT", rightX, -246);
	page.rankingHeader:SetPoint("RIGHT", page, "RIGHT", -10, 0);
	page.rankingHeader.left:SetText(MIWOW_STR_GUILD_RANKING);
	page.ranking = {};
	for i = 1, MIWOW_GUILD.RANKING_ROWS do
		local line = MiWowGuild_CreateLine(page, 18);
		line:SetPoint("TOPLEFT", page.rankingHeader, "BOTTOMLEFT", 0, -4 - (i - 1) * 18);
		line:SetPoint("RIGHT", page, "RIGHT", -10, 0);
		page.ranking[i] = line;
	end
	page.position = MiWowGuild_Text(page, "GameFontNormalSmall");
	page.position:SetPoint("TOPLEFT", page.rankingHeader, "BOTTOMLEFT", 4, -10 - MIWOW_GUILD.RANKING_ROWS * 18);
	page:Hide();
end

local function MiWowGuild_UpdateGuildPage()
	local page = MiWowGuildGuildPage;
	local state = MiWow_Guild.state;
	local points = state and state.points or 0;

	-- Barra hacia la siguiente ventaja (desde la ultima desbloqueada)
	local previous, nextPerk = 0, nil;
	for _, perk in ipairs(MiWow_Guild.perks) do
		if ( perk.unlocked and perk.points > previous ) then
			previous = perk.points;
		end
		if ( not perk.unlocked and (not nextPerk or perk.points < nextPerk.points) ) then
			nextPerk = perk;
		end
	end
	page.pointsBar.text:SetText(format(MIWOW_STR_GUILD_PTH, MiWowGuild_Number(points)));
	if ( #MiWow_Guild.perks == 0 ) then
		MiWowGuild_SetBar(page.pointsBar, 0, 0, 1);
		page.nextPerk:SetText(MIWOW_STR_GUILD_NO_PERKS);
	elseif ( nextPerk ) then
		MiWowGuild_SetBar(page.pointsBar, points, previous, nextPerk.points);
		local name = GetSpellInfo(nextPerk.spellId) or ("#"..nextPerk.spellId);
		page.nextPerk:SetText(format(MIWOW_STR_GUILD_NEXT_PERK, name, MiWowGuild_Number(nextPerk.points)));
	else
		MiWowGuild_SetBar(page.pointsBar, 1, 0, 0);
		page.nextPerk:SetText(MIWOW_STR_GUILD_ALL_PERKS);
	end

	-- Ventajas
	for i, line in ipairs(page.perks) do
		local perk = MiWow_Guild.perks[i];
		if ( perk ) then
			local name, _, icon = GetSpellInfo(perk.spellId);
			line.icon:SetTexture(icon or MIWOW_GUILD.ICON_UNKNOWN);
			line.icon:SetDesaturated(not perk.unlocked);
			local color = perk.unlocked and MIWOW_GUILD.COLOR_WHITE or MIWOW_GUILD.COLOR_LOCKED;
			line.left:SetText(color..(name or ("#"..perk.spellId)).."|r");
			line.right:SetText(perk.unlocked and MIWOW_STR_GUILD_PERK_ACTIVE or
				(MIWOW_GUILD.COLOR_LOCKED..format(MIWOW_STR_GUILD_PTH, MiWowGuild_Number(perk.points)).."|r"));
			line.tooltip = { spell = perk.spellId };
			line:Show();
		else
			line:Hide();
		end
	end

	-- Premios: el primer objeto de cada puesto del podio
	local any = false;
	for i, prize in ipairs(page.prizes) do
		local entry;
		for _, candidate in ipairs(MiWow_Guild.prizes) do
			if ( candidate.position == i ) then
				entry = candidate;
				break;
			end
		end
		if ( entry ) then
			any = true;
			prize.icon:SetTexture(MiWowGuild_ItemIcon(entry.item));
			prize.count:SetText(entry.count > 1 and entry.count or "");
			prize.position:SetText(format(MIWOW_STR_GUILD_PRIZE_POSITION, i));
			prize.tooltip = { item = entry.item };
			prize:Show();
			prize.position:Show();
		else
			prize:Hide();
			prize.position:Hide();
		end
	end
	if ( any ) then
		page.noPrizes:Hide();
	else
		page.noPrizes:Show();
	end

	-- Ranking interno
	page.contribution:SetText(format(MIWOW_STR_GUILD_CONTRIBUTION, MiWowGuild_Number(state and state.contribution or 0)));
	local me = UnitName("player");
	for i, line in ipairs(page.members) do
		local member = MiWow_Guild.members[i];
		if ( member ) then
			local mine = (member.name == me);
			local name = mine and (MIWOW_GUILD.COLOR_OK..MIWOW_STR_GUILD_YOU.."|r") or member.name;
			line.left:SetText(format("%d.  %s  %s%s|r", i, name, MIWOW_GUILD.COLOR_LOCKED, member.rankName));
			line.right:SetText(format(MIWOW_STR_GUILD_PTH, MiWowGuild_Number(member.contribution)));
			line:Show();
		elseif ( i == 1 ) then
			line.left:SetText(MIWOW_GUILD.COLOR_LOCKED..MIWOW_STR_GUILD_EMPTY.."|r");
			line.right:SetText("");
			line:Show();
		else
			line:Hide();
		end
	end

	-- Clasificacion
	local ranking = MiWow_Guild.ranking;
	local myGuild = GetGuildInfo("player");
	for i, line in ipairs(page.ranking) do
		local entry = ranking and ranking.guilds[i];
		if ( entry ) then
			local color = (entry.name == myGuild) and MIWOW_GUILD.COLOR_OK or MIWOW_GUILD.COLOR_WHITE;
			line.left:SetText(format("%d.  %s%s|r", i, color, entry.name));
			line.right:SetText(format(MIWOW_STR_GUILD_PTH, MiWowGuild_Number(entry.points)));
			line:Show();
		elseif ( i == 1 ) then
			line.left:SetText(MIWOW_GUILD.COLOR_LOCKED..MIWOW_STR_GUILD_EMPTY.."|r");
			line.right:SetText("");
			line:Show();
		else
			line:Hide();
		end
	end
	if ( ranking and ranking.position > 0 ) then
		page.position:SetText(format(MIWOW_STR_GUILD_POSITION, ranking.position));
	else
		page.position:SetText(MIWOW_STR_GUILD_NO_POSITION);
	end
end

-- Pestana 3: reputacion --------------------------------------------------------------------------

local function MiWowGuild_CreateRepPage(content)
	local page = CreateFrame("Frame", "MiWowGuildRepPage", content);
	page:SetAllPoints(content);

	local label = MiWowGuild_Text(page, "GameFontNormal");
	label:SetPoint("TOPLEFT", page, "TOPLEFT", 20, -24);
	label:SetText(MIWOW_STR_GUILD_CURRENT_TIER);
	page.stars = MiWowGuild_Text(page, "GameFontHighlight");
	page.stars:SetPoint("LEFT", label, "RIGHT", 12, 0);
	page.tier = MiWowGuild_Text(page, "GameFontNormalHuge");
	page.tier:SetTextColor(1, 1, 1);
	page.tier:SetPoint("LEFT", page.stars, "RIGHT", 10, 0);

	page.progress = MiWowGuild_Text(page, "GameFontHighlight");
	page.progress:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -26);
	page.bar = MiWowGuild_CreateBar(page, 480, 16, 0.2, 0.5, 1);
	page.bar:SetPoint("TOPLEFT", page.progress, "BOTTOMLEFT", 0, -8);
	page.towards = MiWowGuild_Text(page, "GameFontNormal");
	page.towards:SetPoint("LEFT", page.bar, "RIGHT", 12, 0);

	page.chain = MiWowGuild_Text(page, "GameFontHighlight");
	page.chain:SetPoint("TOPLEFT", page.bar, "BOTTOMLEFT", 0, -22);
	page.chain:SetWidth(MIWOW_GUILD.WIDTH - 60);

	page.tierHeader = MiWowGuild_CreateHeader(page);
	page.tierHeader:SetPoint("TOPLEFT", page, "TOPLEFT", 14, -200);
	page.tierHeader:SetPoint("RIGHT", page, "RIGHT", -14, 0);
	page.tierHeader.left:SetText(MIWOW_STR_GUILD_TIERS);
	page.tiers = {};
	for i = 1, 8 do
		local line = MiWowGuild_CreateLine(page, 22);
		line:SetPoint("TOPLEFT", page.tierHeader, "BOTTOMLEFT", 0, -4 - (i - 1) * 22);
		line:SetPoint("RIGHT", page, "RIGHT", -14, 0);
		line.middle = MiWowGuild_Text(line, "GameFontHighlightSmall");
		line.middle:SetPoint("LEFT", line, "LEFT", 260, 0);
		page.tiers[i] = line;
	end

	page.contribution = MiWowGuild_Text(page, "GameFontHighlight");
	page.contribution:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 20, 36);
	page.note = MiWowGuild_Text(page, "GameFontNormalSmall");
	page.note:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 20, 14);
	page.note:SetText(MIWOW_STR_GUILD_REP_NOTE);
	page:Hide();
end

local function MiWowGuild_UpdateRepPage()
	local page = MiWowGuildRepPage;
	local state = MiWow_Guild.state;
	if ( not state ) then
		return;
	end
	local myRank = MiWowGuild_MyRank();

	page.stars:SetText(myRank > 0 and strrep(MIWOW_GUILD.ICON_STAR, myRank) or "");
	page.tier:SetText(string.upper(state.rankName or ""));

	if ( state.nextRankName ~= "" ) then
		page.progress:SetText(format(MIWOW_STR_GUILD_PROGRESS, MiWowGuild_Number(state.reputation), MiWowGuild_Number(state.nextRankRep)));
		MiWowGuild_SetBar(page.bar, state.reputation, state.rankRep, state.nextRankRep);
		page.towards:SetText(format(MIWOW_STR_GUILD_TOWARDS, state.nextRankName));
	else
		page.progress:SetText(format(MIWOW_STR_GUILD_MAX_TIER, MiWowGuild_Number(state.reputation)));
		MiWowGuild_SetBar(page.bar, 1, 0, 0);
		page.towards:SetText("");
	end

	-- Recluta -> Iniciado -> ... : alcanzados en verde, el actual en dorado, el siguiente entre corchetes
	local parts = {};
	for _, rank in ipairs(MiWow_Guild.ranks) do
		local text;
		if ( rank.rank == myRank ) then
			text = MIWOW_GUILD.COLOR_GOLD..rank.name.."|r";
		elseif ( rank.rank < myRank ) then
			text = MIWOW_GUILD.COLOR_OK..rank.name.."|r";
		elseif ( rank.rank == myRank + 1 ) then
			text = MIWOW_GUILD.COLOR_WHITE.."["..rank.name.."]|r";
		else
			text = MIWOW_GUILD.COLOR_LOCKED..rank.name.."|r";
		end
		tinsert(parts, text);
	end
	page.chain:SetText(table.concat(parts, "  →  "));

	for i, line in ipairs(page.tiers) do
		local rank = MiWow_Guild.ranks[i];
		if ( rank ) then
			local shop = 0;
			for _, item in ipairs(MiWow_Guild.vendor) do
				if ( item.rank == rank.rank ) then
					shop = shop + 1;
				end
			end
			local color = (rank.rank == myRank) and MIWOW_GUILD.COLOR_GOLD or ((rank.rank < myRank) and MIWOW_GUILD.COLOR_OK or MIWOW_GUILD.COLOR_WHITE);
			line.left:SetText(color..rank.rank..".  "..rank.name.."|r");
			line.middle:SetText(shop > 0 and format(MIWOW_STR_GUILD_TIER_SHOP, shop) or "");
			line.right:SetText(format(MIWOW_STR_GUILD_REP, MiWowGuild_Number(rank.reputation)));
			line:Show();
		else
			line:Hide();
		end
	end

	local contribution = format(MIWOW_STR_GUILD_SEASON_CONTRIBUTION, MiWowGuild_Number(state.contribution));
	if ( state.dailyCap > 0 ) then
		contribution = contribution.."    "..format(MIWOW_STR_GUILD_DAILY_CAP, MiWowGuild_Number(state.dailyPoints), MiWowGuild_Number(state.dailyCap));
	end
	page.contribution:SetText(contribution);
end

-- Pestana 4: tienda ------------------------------------------------------------------------------

local function MiWowGuild_CreateShopRow(parent)
	local row = CreateFrame("Frame", nil, parent);
	row:SetHeight(MIWOW_GUILD.SHOP_ROW_HEIGHT);
	row:EnableMouse(true);
	MiWowGuild_SetTooltip(row);

	row.icon = row:CreateTexture(nil, "ARTWORK");
	row.icon:SetSize(26, 26);
	row.icon:SetPoint("LEFT", row, "LEFT", 4, 0);
	row.count = row:CreateFontString(nil, "OVERLAY", "NumberFontNormal");
	row.count:SetPoint("BOTTOMRIGHT", row.icon, "BOTTOMRIGHT", 0, 0);

	row.button = CreateFrame("Button", nil, row, "UIPanelButtonTemplate");
	row.button:SetSize(86, 22);
	row.button:SetPoint("RIGHT", row, "RIGHT", -4, 0);
	row.button:SetText(MIWOW_STR_GUILD_SHOP_BUY);
	row.button:SetScript("OnClick", function(self)
		local item = self:GetParent().item;
		if ( item ) then
			StaticPopup_Show("MIWOW_GUILD_BUY", MiWowGuild_ItemName(item.id, item.name), MiWowGuild_Money(item.price), item);
		end
	end);

	row.price = MiWowGuild_Text(row, "GameFontHighlight", "RIGHT");
	row.price:SetPoint("RIGHT", row.button, "LEFT", -12, 0);
	row.name = MiWowGuild_Text(row, "GameFontNormal");
	row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, 1);
	row.name:SetPoint("RIGHT", row.price, "LEFT", -8, 0);
	row.sub = MiWowGuild_Text(row, "GameFontHighlightSmall");
	row.sub:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2);
	row:Hide();
	return row;
end

local function MiWowGuild_CreateShopPage(content)
	local page = CreateFrame("Frame", "MiWowGuildShopPage", content);
	page:SetAllPoints(content);
	page.tier = MiWowGuild_Text(page, "GameFontNormal");
	page.tier:SetPoint("TOPLEFT", page, "TOPLEFT", 14, -12);
	page.money = MiWowGuild_Text(page, "GameFontHighlight", "RIGHT");
	page.money:SetPoint("TOPRIGHT", page, "TOPRIGHT", -14, -12);
	page.headers = { MiWowGuild_CreateHeader(page), MiWowGuild_CreateHeader(page) };
	page.headers[1].left:SetText(MIWOW_STR_GUILD_SHOP_AVAILABLE);
	page.headers[2].left:SetText(MIWOW_STR_GUILD_SHOP_LOCKED);
	page.rows = {};
	for i = 1, MIWOW_GUILD.SHOP_ROWS do
		page.rows[i] = MiWowGuild_CreateShopRow(page);
	end
	page.message = MiWowGuild_Text(page, "GameFontNormalLarge", "CENTER");
	page.message:SetPoint("CENTER", page, "CENTER", 0, 20);
	page.footer = MiWowGuild_Text(page, "GameFontNormalSmall");
	page.footer:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 12, 10);
	page.footer:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -12, 10);
	page:Hide();
end

local function MiWowGuild_FillShopRow(row, item, unlocked)
	row.item = item;
	row.icon:SetTexture(MiWowGuild_ItemIcon(item.id));
	row.icon:SetDesaturated(not unlocked);
	row.count:SetText(item.count > 1 and item.count or "");
	if ( unlocked ) then
		row.name:SetText(MiWowGuild_ItemName(item.id, item.name));
		row.sub:SetText(format(MIWOW_STR_GUILD_SHOP_FROM, MiWowGuild_RankName(item.rank)));
		row.price:SetText(MiWowGuild_Money(item.price));
		row.button:Show();
		if ( MiWow_Guild.shop and GetMoney() >= item.price ) then
			row.button:Enable();
		else
			row.button:Disable();
		end
	else
		row.name:SetText(MIWOW_GUILD.COLOR_LOCKED..(GetItemInfo(item.id) or item.name).."|r");
		row.sub:SetText(MIWOW_GUILD.ICON_LOCK.." "..MIWOW_GUILD.COLOR_BAD..MiWowGuild_RankName(item.rank).."|r");
		row.price:SetText(MIWOW_GUILD.COLOR_LOCKED..MiWowGuild_Money(item.price).."|r");
		row.button:Hide();
	end
	row.tooltip = { item = item.id };
end

local function MiWowGuild_UpdateShopPage()
	local page = MiWowGuildShopPage;
	local myRank = MiWowGuild_MyRank();
	page.tier:SetText(format(MIWOW_STR_GUILD_MY_TIER, MiWowGuild_RankName(math.max(myRank, 0)), math.max(myRank, 0)));
	page.money:SetText(format(MIWOW_STR_GUILD_MY_MONEY, MiWowGuild_Money(GetMoney())));
	for _, row in ipairs(page.rows) do
		row:Hide();
	end
	for _, header in ipairs(page.headers) do
		header:Hide();
	end
	page.message:SetText(#MiWow_Guild.vendor == 0 and MIWOW_STR_GUILD_SHOP_EMPTY or "");

	local groups = { {}, {} };
	for _, item in ipairs(MiWow_Guild.vendor) do
		tinsert(groups[(item.rank <= myRank) and 1 or 2], item);
	end

	local y = -34;
	local used = 0;
	for index, items in ipairs(groups) do
		if ( #items > 0 ) then
			local header = page.headers[index];
			header:SetPoint("TOPLEFT", page, "TOPLEFT", 10, y);
			header:SetPoint("RIGHT", page, "RIGHT", -10, 0);
			header:Show();
			y = y - 26;
			for _, item in ipairs(items) do
				if ( used < MIWOW_GUILD.SHOP_ROWS ) then
					used = used + 1;
					local row = page.rows[used];
					row:SetPoint("TOPLEFT", page, "TOPLEFT", 10, y);
					row:SetPoint("RIGHT", page, "RIGHT", -10, 0);
					MiWowGuild_FillShopRow(row, item, index == 1);
					row:Show();
					y = y - MIWOW_GUILD.SHOP_ROW_HEIGHT - 2;
				end
			end
			y = y - 8;
		end
	end
	page.footer:SetText(MiWow_Guild.shop and "" or MIWOW_STR_GUILD_SHOP_AWAY);
end

StaticPopupDialogs["MIWOW_GUILD_BUY"] = {
	text = MIWOW_STR_GUILD_SHOP_CONFIRM,
	button1 = YES,
	button2 = NO,
	OnAccept = function(self, item)
		if ( item ) then
			MiWow_Send("GUILD_BUY", item.id);
		end
	end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
};

-- Ventana ----------------------------------------------------------------------------------------

local MIWOW_GUILD_PAGES = { "MiWowGuildBoardPage", "MiWowGuildGuildPage", "MiWowGuildRepPage", "MiWowGuildShopPage" };

local function MiWowGuild_UpdateTopBar()
	local state = MiWow_Guild.state;
	local tab = MiWow_Guild.tab;
	local guildName = GetGuildInfo("player") or "";

	if ( tab == 1 ) then
		MiWowGuildFrameTitle:SetText(MIWOW_STR_GUILD_TITLE_BOARD);
	elseif ( tab == 2 ) then
		MiWowGuildFrameTitle:SetText(format(MIWOW_STR_GUILD_TITLE_GUILD, guildName));
	elseif ( tab == 3 ) then
		MiWowGuildFrameTitle:SetText(MIWOW_STR_GUILD_TITLE_REP);
	else
		MiWowGuildFrameTitle:SetText(MIWOW_STR_GUILD_TITLE_SHOP);
	end

	if ( not state ) then
		MiWowGuildFrameSeason:SetText(MIWOW_STR_GUILD_LOADING);
	elseif ( tab == 2 and state.secondsLeft > 0 ) then
		MiWowGuildFrameSeason:SetText(format(MIWOW_STR_GUILD_SEASON_LEFT, state.seasonName, MiWowGuild_TimeLeft(state.secondsLeft)));
	else
		local day = math.floor((state.sinceStart + (GetTime() - MiWow_Guild.receivedAt)) / 86400) + 1;
		MiWowGuildFrameSeason:SetText(format(MIWOW_STR_GUILD_SEASON_DAY, state.seasonName, day));
	end
end

function MiWowGuild_Update()
	if ( not MiWowGuildFrame or not MiWowGuildFrame:IsShown() ) then
		return;
	end
	MiWowGuild_UpdateTopBar();

	for i, name in ipairs(MIWOW_GUILD_PAGES) do
		local tab = _G["MiWowGuildTab"..i];
		if ( i == MiWow_Guild.tab ) then
			tab:LockHighlight();
			_G[name]:Show();
		else
			tab:UnlockHighlight();
			_G[name]:Hide();
		end
	end

	if ( not MiWow_Guild.state ) then
		MiWowGuildFrameLoading:Show();
		return;
	end
	MiWowGuildFrameLoading:Hide();

	if ( MiWow_Guild.tab == 1 ) then
		MiWowGuild_UpdateBoard();
	elseif ( MiWow_Guild.tab == 2 ) then
		MiWowGuild_UpdateGuildPage();
	elseif ( MiWow_Guild.tab == 3 ) then
		MiWowGuild_UpdateRepPage();
	else
		MiWowGuild_UpdateShopPage();
	end
end

function MiWowGuild_SelectTab(index)
	MiWow_Guild.tab = index;
	MiWowGuild_Update();
end

local function MiWowGuild_CreateTopBar(frame)
	local bar = CreateFrame("Frame", "MiWowGuildFrameTopBar", frame);
	bar:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -8);
	bar:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -8);
	bar:SetHeight(MIWOW_GUILD.TOP_BAR_HEIGHT);
	MiWowGuild_Backdrop(bar, MIWOW_PANEL.COLOR_SECTION);

	local title = bar:CreateFontString("MiWowGuildFrameTitle", "ARTWORK", "GameFontNormalLarge");
	title:SetPoint("LEFT", bar, "LEFT", 12, 0);

	local close = CreateFrame("Button", "MiWowGuildFrameCloseButton", bar, "UIPanelCloseButton");
	close:SetPoint("RIGHT", bar, "RIGHT", 2, 0);
	close:SetScript("OnClick", function()
		MiWowGuildFrame:Hide();
	end);

	local season = bar:CreateFontString("MiWowGuildFrameSeason", "ARTWORK", "GameFontHighlight");
	season:SetPoint("RIGHT", close, "LEFT", -6, 0);

	bar:EnableMouse(true);
	bar:RegisterForDrag("LeftButton");
	bar:SetScript("OnDragStart", function()
		MiWowGuildFrame:StartMoving();
	end);
	bar:SetScript("OnDragStop", function()
		MiWowGuildFrame:StopMovingOrSizing();
	end);
end

local function MiWowGuild_CreateContent(frame)
	local previous;
	for i, text in ipairs(MIWOW_STR_GUILD_TABS) do
		local tab = CreateFrame("Button", "MiWowGuildTab"..i, frame, "UIPanelButtonTemplate");
		tab:SetSize(130, MIWOW_GUILD.TAB_HEIGHT);
		if ( previous ) then
			tab:SetPoint("LEFT", previous, "RIGHT", 4, 0);
		else
			tab:SetPoint("TOPLEFT", MiWowGuildFrameTopBar, "BOTTOMLEFT", 0, -6);
		end
		tab:SetText(text);
		tab:SetScript("OnClick", function()
			PlaySound("igMainMenuOptionCheckBoxOn");
			MiWowGuild_SelectTab(i);
		end);
		previous = tab;
	end

	local content = CreateFrame("Frame", "MiWowGuildFrameContent", frame);
	content:SetPoint("TOPLEFT", MiWowGuildTab1, "BOTTOMLEFT", 0, -6);
	content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -8, 8);
	MiWowGuild_Backdrop(content, MIWOW_PANEL.COLOR_SECTION);

	local loading = content:CreateFontString("MiWowGuildFrameLoading", "ARTWORK", "GameFontNormalLarge");
	loading:SetPoint("CENTER", content, "CENTER", 0, 0);
	loading:SetText(MIWOW_STR_GUILD_LOADING);

	MiWowGuild_CreateBoardPage(content);
	MiWowGuild_CreateGuildPage(content);
	MiWowGuild_CreateRepPage(content);
	MiWowGuild_CreateShopPage(content);
end

local function MiWowGuild_CreateFrame()
	local frame = CreateFrame("Frame", "MiWowGuildFrame", UIParent);
	frame:SetSize(MIWOW_GUILD.WIDTH, MIWOW_GUILD.HEIGHT);
	frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0);
	frame:SetFrameStrata("MEDIUM");
	frame:SetToplevel(true);
	frame:EnableMouse(true);
	frame:SetMovable(true);
	frame:SetClampedToScreen(true);
	MiWowGuild_Backdrop(frame, MIWOW_PANEL.COLOR_PANEL);
	tinsert(UISpecialFrames, "MiWowGuildFrame");

	MiWowGuild_CreateTopBar(frame);
	MiWowGuild_CreateContent(frame);

	-- Peticion pendiente (GUILD_DIRTY) y cuentas atras
	local elapsed = 0;
	frame:SetScript("OnUpdate", function(self, delta)
		if ( MiWow_Guild.pending ) then
			MiWow_Guild.pending = MiWow_Guild.pending - delta;
			if ( MiWow_Guild.pending <= 0 ) then
				MiWowGuild_Request();
			end
		end
		elapsed = elapsed + delta;
		if ( elapsed >= 1 ) then
			elapsed = 0;
			MiWowGuild_UpdateTopBar();
		end
	end);
	frame:SetScript("OnShow", function()
		PlaySound("igCharacterInfoOpen");
		MiWowGuild_Update();
		MiWowGuild_Request();
	end);
	frame:SetScript("OnHide", function()
		PlaySound("igCharacterInfoClose");
		MiWow_Guild.pending = nil;
		MiWow_Guild.shop = false;
		StaticPopup_Hide("MIWOW_GUILD_BUY");
		-- Cerrar la ventana cierra el gossip del tablon, salvo al pasar a la ventana de misiones nativa
		if ( MiWow_Guild.gossip and not MiWow_Guild.handoff ) then
			MiWow_Guild.gossip = false;
			CloseGossip();
		end
	end);

	frame:RegisterEvent("QUEST_FINISHED");
	frame:RegisterEvent("PLAYER_GUILD_UPDATE");
	frame:RegisterEvent("PLAYER_MONEY");
	frame:SetScript("OnEvent", function(self, event)
		if ( event == "QUEST_FINISHED" ) then
			-- Vuelta al tablon tras aceptar/entregar en la ventana de misiones nativa: el servidor cierra el gossip,
			-- asi que se le pide otro (GUILD_BOARD_OPEN + gossip, como al hacer clic en el tablon)
			if ( MiWow_Guild.reopen ) then
				MiWow_Guild.reopen = false;
				MiWow_Send("GUILD_BOARD_REOPEN");
			end
		elseif ( event == "PLAYER_GUILD_UPDATE" ) then
			if ( not IsInGuild() ) then
				self:Hide();
			else
				MiWowGuild_Request(MIWOW_GUILD.REFRESH_DELAY);
			end
		elseif ( event == "PLAYER_MONEY" ) then
			if ( MiWow_Guild.tab == 4 ) then
				MiWowGuild_Update();
			end
		end
	end);
	frame:Hide();
end

-- Abre la ventana en una pestana (sin hermandad no se abre)
function MiWowGuild_Open(tab)
	if ( not IsInGuild() ) then
		UIErrorsFrame:AddMessage(MIWOW_STR_GUILD_NO_GUILD, 1, 0.2, 0.2, 1.0);
		return false;
	end
	if ( MiWow_UI and MiWow_UI.mode == "match" ) then
		UIErrorsFrame:AddMessage(MIWOW_STR_PANEL_IN_MATCH, 1, 0.2, 0.2, 1.0);
		return false;
	end
	MiWow_Guild.tab = tab or MiWow_Guild.tab;
	if ( MiWowGuildFrame:IsShown() ) then
		MiWowGuild_Update();
	else
		MiWowGuildFrame:Show();
	end
	return true;
end

function MiWowGuild_Toggle(tab)
	if ( MiWowGuildFrame:IsShown() ) then
		MiWowGuildFrame:Hide();
	else
		MiWowGuild_Open(tab or 2);
	end
end

-- Pestana lateral en la ventana de hermandad nativa (FriendsFrame -> GuildFrame), como las del libro de hechizos
local function MiWowGuild_CreateGuildFrameTab()
	local tab = CreateFrame("CheckButton", "MiWowGuildFrameTab", GuildFrame, "SpellBookSkillLineTabTemplate");
	tab:SetPoint("TOPLEFT", FriendsFrame, "TOPRIGHT", -32, -70);
	tab:SetNormalTexture(MIWOW_GUILD.TAB_ICON);
	tab:SetScript("OnClick", function(self)
		self:SetChecked(nil);
		MiWowGuild_Toggle(2);
	end);
	tab:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
		GameTooltip:SetText(MIWOW_STR_GUILD_TAB_TOOLTIP);
		GameTooltip:Show();
	end);
	tab:SetScript("OnLeave", function()
		GameTooltip:Hide();
	end);
	tab:Show();
end

-- Gossip del tablon: si llega justo despues de GUILD_BOARD_OPEN, se muestra el tablon en lugar de la lista nativa
-- (el gossip sigue abierto: sus misiones se eligen desde los botones del tablon). Cualquier otro gossip, nativo.
local function MiWowGuild_HookGossip()
	local original = GossipFrame:GetScript("OnEvent");
	GossipFrame:SetScript("OnEvent", function(self, event, ...)
		if ( event == "GOSSIP_SHOW" and MiWow_Guild.boardOpenAt and GetTime() - MiWow_Guild.boardOpenAt < MIWOW_GUILD.BOARD_OPEN_WINDOW ) then
			MiWow_Guild.boardOpenAt = nil;
			if ( GossipFrame:IsShown() ) then
				-- Otra ventana de gossip abierta: el tablon la sustituye (sin cerrar el gossip nuevo)
				local onHide = GossipFrame:GetScript("OnHide");
				GossipFrame:SetScript("OnHide", nil);
				HideUIPanel(GossipFrame);
				GossipFrame:SetScript("OnHide", onHide);
			end
			MiWow_Guild.gossip = true;
			if ( not MiWowGuild_Open(1) ) then
				MiWow_Guild.gossip = false;
				CloseGossip();
			end
			return;
		end
		if ( event == "GOSSIP_CLOSED" and MiWow_Guild.gossip ) then
			MiWow_Guild.gossip = false;
			MiWowGuild_Update();
		end
		original(self, event, ...);
	end);
end

-- Protocolo --------------------------------------------------------------------------------------

-- GUILD_STATE <en hermandad> <temporada> <nombre> <segundos> <puntos> <puesto> <siguiente ventaja> <reputacion>
--   <rango> <reputacion del rango> <siguiente rango> <su reputacion> <contribucion> <hoy> <limite diario>
--   <segundos desde el inicio>
MiWow_RegisterHandler("GUILD_STATE", function(fields)
	MiWow_Guild.receivedAt = GetTime();
	MiWow_Guild.state = {
		inGuild = fields[1] == "1",
		seasonId = tonumber(fields[2]) or 0,
		seasonName = fields[3] or "",
		secondsLeft = tonumber(fields[4]) or 0,
		points = tonumber(fields[5]) or 0,
		position = tonumber(fields[6]) or 0,
		nextPerk = tonumber(fields[7]) or 0,
		reputation = tonumber(fields[8]) or 0,
		rankName = fields[9] or "",
		rankRep = tonumber(fields[10]) or 0,
		nextRankName = fields[11] or "",
		nextRankRep = tonumber(fields[12]) or 0,
		contribution = tonumber(fields[13]) or 0,
		dailyPoints = tonumber(fields[14]) or 0,
		dailyCap = tonumber(fields[15]) or 0,
		sinceStart = tonumber(fields[16]) or 0,
	};
	MiWowGuild_Update();
end);

-- GUILD_RANKS <n> (<rango> <nombre> <reputacion>) x n
MiWow_RegisterHandler("GUILD_RANKS", function(fields)
	local ranks = {};
	for i = 1, tonumber(fields[1]) or 0 do
		local base = 1 + (i - 1) * 3;
		tinsert(ranks, { rank = tonumber(fields[base + 1]) or 0, name = fields[base + 2] or "", reputation = tonumber(fields[base + 3]) or 0 });
	end
	MiWow_Guild.ranks = ranks;
	MiWowGuild_Update();
end);

-- GUILD_PERKS <n> (<puntos> <hechizo> <desbloqueada>) x n
MiWow_RegisterHandler("GUILD_PERKS", function(fields)
	local perks = {};
	for i = 1, tonumber(fields[1]) or 0 do
		local base = 1 + (i - 1) * 3;
		tinsert(perks, { points = tonumber(fields[base + 1]) or 0, spellId = tonumber(fields[base + 2]) or 0, unlocked = fields[base + 3] == "1" });
	end
	MiWow_Guild.perks = perks;
	MiWowGuild_Update();
end);

-- GUILD_PRIZES <n> (<puesto> <objeto> <cantidad>) x n
MiWow_RegisterHandler("GUILD_PRIZES", function(fields)
	local prizes = {};
	for i = 1, tonumber(fields[1]) or 0 do
		local base = 1 + (i - 1) * 3;
		tinsert(prizes, { position = tonumber(fields[base + 1]) or 0, item = tonumber(fields[base + 2]) or 0, count = tonumber(fields[base + 3]) or 1 });
	end
	MiWow_Guild.prizes = prizes;
	MiWowGuild_Update();
end);

-- GUILD_BOARD <segundos diaria> <segundos semanal> <n> (<mision> <tablon> <titulo> <puntos> <reputacion> <miembros>
--   <reclamada> <estado> <nivel> <tipo>) x n
MiWow_RegisterHandler("GUILD_BOARD", function(fields)
	local board = { dailyLeft = tonumber(fields[1]) or 0, weeklyLeft = tonumber(fields[2]) or 0, quests = {} };
	for i = 1, tonumber(fields[3]) or 0 do
		local base = 3 + (i - 1) * 10;
		tinsert(board.quests, {
			id = tonumber(fields[base + 1]),
			board = tonumber(fields[base + 2]) or 0,
			title = fields[base + 3] or "",
			points = tonumber(fields[base + 4]) or 0,
			reputation = tonumber(fields[base + 5]) or 0,
			members = tonumber(fields[base + 6]) or 0,
			claimed = fields[base + 7] == "1",
			status = tonumber(fields[base + 8]) or 0,
			level = tonumber(fields[base + 9]) or -1,
			kind = tonumber(fields[base + 10]) or 0,
		});
	end
	MiWow_Guild.board = board;
	MiWowGuild_Update();
end);

-- GUILD_RANKING <puesto propio> <n> (<hermandad> <puntos>) x n
MiWow_RegisterHandler("GUILD_RANKING", function(fields)
	local ranking = { position = tonumber(fields[1]) or 0, guilds = {} };
	for i = 1, tonumber(fields[2]) or 0 do
		local base = 2 + (i - 1) * 2;
		tinsert(ranking.guilds, { name = fields[base + 1] or "", points = tonumber(fields[base + 2]) or 0 });
	end
	MiWow_Guild.ranking = ranking;
	MiWowGuild_Update();
end);

-- GUILD_MEMBERS <n> (<personaje> <contribucion> <rango>) x n
MiWow_RegisterHandler("GUILD_MEMBERS", function(fields)
	local members = {};
	for i = 1, tonumber(fields[1]) or 0 do
		local base = 1 + (i - 1) * 3;
		tinsert(members, { name = fields[base + 1] or "", contribution = tonumber(fields[base + 2]) or 0, rankName = fields[base + 3] or "" });
	end
	MiWow_Guild.members = members;
	MiWowGuild_Update();
end);

-- GUILD_VENDOR <n> (<objeto> <nombre> <rango> <precio> <cantidad>) x n
MiWow_RegisterHandler("GUILD_VENDOR", function(fields)
	local vendor = {};
	for i = 1, tonumber(fields[1]) or 0 do
		local base = 1 + (i - 1) * 5;
		tinsert(vendor, {
			id = tonumber(fields[base + 1]) or 0,
			name = fields[base + 2] or "",
			rank = tonumber(fields[base + 3]) or 0,
			price = tonumber(fields[base + 4]) or 0,
			count = tonumber(fields[base + 5]) or 1,
		});
	end
	MiWow_Guild.vendor = vendor;
	MiWowGuild_Update();
end);

-- GUILD_DIRTY: algo cambio (puntos, tablon, temporada, compra...). Solo se pide si la ventana esta abierta.
MiWow_RegisterHandler("GUILD_DIRTY", function()
	if ( MiWowGuildFrame:IsShown() ) then
		MiWowGuild_Request(MIWOW_GUILD.REFRESH_DELAY);
	end
end);

-- GUILD_BOARD_OPEN: el gossip que llega detras es el del tablon
MiWow_RegisterHandler("GUILD_BOARD_OPEN", function()
	MiWow_Guild.boardOpenAt = GetTime();
end);

-- GUILD_SHOP_OPEN: desde el intendente (compras activas mientras siga abierta)
MiWow_RegisterHandler("GUILD_SHOP_OPEN", function()
	if ( MiWowGuild_Open(4) ) then
		MiWow_Guild.shop = true;
		MiWowGuild_Update();
	end
end);

SLASH_MIWOWGUILD1 = "/temporada";
SlashCmdList["MIWOWGUILD"] = function()
	MiWowGuild_Toggle(2);
end

MiWowGuild_CreateFrame();
MiWowGuild_CreateGuildFrameTab();
MiWowGuild_HookGossip();
