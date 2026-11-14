-- EventWow: fase de eleccion de personaje (MATCH_STATE PICKING). Contraparte: EventWowMatch::HandlePick.
--   MATCH_PICK <unico 0/1> <n> (<id> <nombre> <icono> <descripcion> <hechizos "id,id,..."> <vehiculo 0/1>) x n
--   MATCH_PICKS <n> (<nombre jugador> <id personaje, 0 = eligiendo>) x n
-- Responde PICK <id>. La eleccion es definitiva; al acabar el tiempo el servidor da uno al azar a quien no
-- haya elegido. Todo lo que se muestra llega del servidor (el cliente no conoce ningun personaje).
--
--          +----------------------------------------------------------+
--          |  ELIGE TU PERSONAJE                              0:25    |
--          |  [ico] [ico] [ico] [ico]     <nombre>                    |
--          |  nombre nombre ...           <descripcion>               |
--          |                              Habilidades: [1][2][3][4]   |
--          |                              [        Elegir        ]    |
--          |  Jugadores: Fulano - Mago   Mengano - eligiendo...       |
--          +----------------------------------------------------------+

EVENTWOW_PICK = {
	WIDTH = 660,
	HEIGHT = 330,
	CARD_SIZE = 56,
	CARD_WIDTH = 92,   -- icono + nombre debajo
	CARD_HEIGHT = 92,
	COLUMNS = 3,
	MAX_CARDS = 12,
	SPELL_SIZE = 32,
	MAX_SPELLS = 10,
};

EVENTWOW_STR_PICK_TITLE = "ELIGE TU PERSONAJE";
EVENTWOW_STR_PICK_BUTTON = "Elegir";
EVENTWOW_STR_PICK_DONE = "Elegido. Esperando al resto...";
EVENTWOW_STR_PICK_TAKEN_BY = "Elegido por %s";
EVENTWOW_STR_PICK_ABILITIES = "Habilidades:";
EVENTWOW_STR_PICK_VEHICLE = "Va en vehículo: sus habilidades son las del vehículo.";
EVENTWOW_STR_PICK_PLAYERS = "Jugadores:";
EVENTWOW_STR_PICK_CHOOSING = "|cff999999eligiendo...|r";
EVENTWOW_STR_PICK_RANDOM = "Si no eliges a tiempo, te tocará uno al azar.";

EventWow_Pick = {
	unique = true,
	characters = {},   -- { id, name, icon, description, spells = { id... }, vehicle }
	players = {},      -- { name, characterId }
	selected = nil,    -- id del personaje que se esta mirando
};

local cards = {};
local spellButtons = {};

local function EventWow_FindCharacter(id)
	for _, character in ipairs(EventWow_Pick.characters) do
		if ( character.id == id ) then
			return character;
		end
	end
	return nil;
end

-- Mi eleccion (0 = sin elegir) y quien tiene cada personaje
local function EventWow_PickState()
	local me = UnitName("player");
	local mine = 0;
	local owners = {};
	for _, entry in ipairs(EventWow_Pick.players) do
		if ( entry.characterId ~= 0 ) then
			if ( entry.name == me ) then
				mine = entry.characterId;
			else
				owners[entry.characterId] = entry.name;
			end
		end
	end
	return mine, owners;
end

function EventWowPick_Update()
	local frame = EventWowPickFrame;
	if ( EventWow_Match.state ~= "PICKING" or #EventWow_Pick.characters == 0 ) then
		frame:Hide();
		return;
	end

	local mine, owners = EventWow_PickState();
	if ( mine ~= 0 ) then
		EventWow_Pick.selected = mine;
	elseif ( not EventWow_FindCharacter(EventWow_Pick.selected) ) then
		EventWow_Pick.selected = EventWow_Pick.characters[1].id;
	end

	-- Tarjetas
	for i = 1, EVENTWOW_PICK.MAX_CARDS do
		local card = cards[i];
		local character = EventWow_Pick.characters[i];
		if ( character ) then
			card.characterId = character.id;
			card.icon:SetTexture(character.icon ~= "" and character.icon or "Interface\\Icons\\INV_Misc_QuestionMark");
			card.name:SetText(character.name);
			local taken = EventWow_Pick.unique and owners[character.id] ~= nil;
			card.icon:SetDesaturated(taken and 1 or nil);
			if ( character.id == mine ) then
				card.name:SetTextColor(0.2, 1, 0.2);
			elseif ( taken ) then
				card.name:SetTextColor(0.5, 0.5, 0.5);
			else
				card.name:SetTextColor(1, 0.82, 0);
			end
			if ( character.id == EventWow_Pick.selected ) then
				card.selected:Show();
			else
				card.selected:Hide();
			end
			card:Show();
		else
			card:Hide();
		end
	end

	-- Detalle
	local character = EventWow_FindCharacter(EventWow_Pick.selected);
	EventWowPickName:SetText(character.name);
	EventWowPickDescription:SetText(character.description);

	for i = 1, EVENTWOW_PICK.MAX_SPELLS do
		local button = spellButtons[i];
		local spellId = character.spells[i];
		if ( spellId ) then
			local _, _, icon = GetSpellInfo(spellId);
			button.spellId = spellId;
			button.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark");
			button:Show();
		else
			button:Hide();
		end
	end
	if ( #character.spells > 0 ) then
		EventWowPickAbilities:SetText(EVENTWOW_STR_PICK_ABILITIES);
	elseif ( character.vehicle ) then
		EventWowPickAbilities:SetText(EVENTWOW_STR_PICK_VEHICLE);
	else
		EventWowPickAbilities:SetText("");
	end

	local button = EventWowPickButton;
	if ( mine ~= 0 ) then
		button:SetText(EVENTWOW_STR_PICK_DONE);
		button:Disable();
	elseif ( EventWow_Pick.unique and owners[character.id] ) then
		button:SetText(format(EVENTWOW_STR_PICK_TAKEN_BY, owners[character.id]));
		button:Disable();
	else
		button:SetText(EVENTWOW_STR_PICK_BUTTON);
		button:Enable();
	end

	-- Jugadores
	local parts = {};
	for _, entry in ipairs(EventWow_Pick.players) do
		local picked = EventWow_FindCharacter(entry.characterId);
		local text = picked and ("|cffffffff"..picked.name.."|r") or EVENTWOW_STR_PICK_CHOOSING;
		tinsert(parts, entry.name.." - "..text);
	end
	EventWowPickPlayers:SetText(EVENTWOW_STR_PICK_PLAYERS.."  "..table.concat(parts, "    "));

	frame:Show();
end

local function EventWow_UpdateTimer()
	local endTime = EventWow_Match.endTime;
	local left = endTime and math.max(0, math.ceil(endTime - GetTime())) or 0;
	EventWowPickTimer:SetText(format("%d:%02d", math.floor(left / 60), left % 60));
end

-- Construccion ----------------------------------------------------------------------------------

local function EventWow_CreatePickFrame()
	local layout = EVENTWOW_PICK;
	local frame = CreateFrame("Frame", "EventWowPickFrame", UIParent);
	frame:SetSize(layout.WIDTH, layout.HEIGHT);
	frame:SetPoint("CENTER", UIParent, "CENTER", 0, 20);
	frame:SetFrameStrata("HIGH");
	frame:EnableMouse(true);
	frame:SetBackdrop(EVENTWOW_PANEL.BACKDROP);
	frame:SetBackdropColor(0.04, 0.05, 0.08, 0.92);
	frame:SetBackdropBorderColor(unpack(EVENTWOW_PANEL.COLOR_BORDER));
	frame:Hide();

	local title = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge");
	title:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -14);
	title:SetText(EVENTWOW_STR_PICK_TITLE);

	local timer = frame:CreateFontString("EventWowPickTimer", "ARTWORK", "GameFontHighlightLarge");
	timer:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -16, -14);

	-- Tarjetas (izquierda)
	local gridLeft = 16;
	local gridTop = -46;
	for i = 1, layout.MAX_CARDS do
		local card = CreateFrame("Button", "EventWowPickCard"..i, frame);
		card:SetSize(layout.CARD_WIDTH, layout.CARD_HEIGHT);
		local column = (i - 1) % layout.COLUMNS;
		local row = math.floor((i - 1) / layout.COLUMNS);
		card:SetPoint("TOPLEFT", frame, "TOPLEFT", gridLeft + column * layout.CARD_WIDTH, gridTop - row * layout.CARD_HEIGHT);

		local icon = card:CreateTexture(nil, "ARTWORK");
		icon:SetSize(layout.CARD_SIZE, layout.CARD_SIZE);
		icon:SetPoint("TOP", card, "TOP", 0, -2);
		card.icon = icon;

		local selected = card:CreateTexture(nil, "OVERLAY");
		selected:SetTexture("Interface\\Buttons\\CheckButtonHilight");
		selected:SetBlendMode("ADD");
		selected:SetAllPoints(icon);
		selected:Hide();
		card.selected = selected;

		local highlight = card:CreateTexture(nil, "HIGHLIGHT");
		highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square");
		highlight:SetBlendMode("ADD");
		highlight:SetAllPoints(icon);

		local name = card:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall");
		name:SetPoint("TOP", icon, "BOTTOM", 0, -3);
		name:SetWidth(layout.CARD_WIDTH - 4);
		name:SetHeight(26);
		name:SetJustifyV("TOP");
		card.name = name;

		card:SetScript("OnClick", function(self)
			EventWow_Pick.selected = self.characterId;
			EventWowPick_Update();
		end);
		card:SetScript("OnDoubleClick", function(self)
			EventWow_Pick.selected = self.characterId;
			EventWowPick_Update();
			if ( EventWowPickButton:IsEnabled() == 1 ) then
				EventWowPickButton:Click();
			end
		end);
		cards[i] = card;
	end

	-- Detalle (derecha)
	local detailLeft = gridLeft + layout.COLUMNS * layout.CARD_WIDTH + 16;

	local separator = frame:CreateTexture(nil, "ARTWORK");
	separator:SetTexture(1, 1, 1, 0.15);
	separator:SetWidth(1);
	separator:SetPoint("TOPLEFT", frame, "TOPLEFT", detailLeft - 8, gridTop);
	separator:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", detailLeft - 8, 44);

	local name = frame:CreateFontString("EventWowPickName", "ARTWORK", "GameFontNormalHuge");
	name:SetPoint("TOPLEFT", frame, "TOPLEFT", detailLeft, gridTop);
	name:SetPoint("RIGHT", frame, "RIGHT", -16, 0);
	name:SetJustifyH("LEFT");

	local description = frame:CreateFontString("EventWowPickDescription", "ARTWORK", "GameFontHighlight");
	description:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -10);
	description:SetPoint("RIGHT", frame, "RIGHT", -16, 0);
	description:SetHeight(60);
	description:SetJustifyH("LEFT");
	description:SetJustifyV("TOP");

	local abilities = frame:CreateFontString("EventWowPickAbilities", "ARTWORK", "GameFontNormal");
	abilities:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 0, -8);
	abilities:SetPoint("RIGHT", frame, "RIGHT", -16, 0);
	abilities:SetJustifyH("LEFT");

	for i = 1, layout.MAX_SPELLS do
		local button = CreateFrame("Button", "EventWowPickSpell"..i, frame);
		button:SetSize(layout.SPELL_SIZE, layout.SPELL_SIZE);
		button:SetPoint("TOPLEFT", abilities, "BOTTOMLEFT", (i - 1) * (layout.SPELL_SIZE + 6), -6);
		local icon = button:CreateTexture(nil, "ARTWORK");
		icon:SetAllPoints(button);
		button.icon = icon;
		local highlight = button:CreateTexture(nil, "HIGHLIGHT");
		highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square");
		highlight:SetBlendMode("ADD");
		highlight:SetAllPoints(button);
		-- Tooltip nativo del hechizo (no hace falta tenerlo aprendido)
		button:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
			GameTooltip:SetHyperlink("spell:"..self.spellId);
			GameTooltip:Show();
		end);
		button:SetScript("OnLeave", function()
			GameTooltip:Hide();
		end);
		button:Hide();
		spellButtons[i] = button;
	end

	local pick = CreateFrame("Button", "EventWowPickButton", frame, "UIPanelButtonTemplate");
	pick:SetSize(220, 28);
	pick:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 52);
	pick:SetScript("OnClick", function()
		local id = EventWow_Pick.selected;
		if ( id ) then
			EventWow_Send("PICK", id);
		end
	end);

	local hint = frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall");
	hint:SetPoint("RIGHT", pick, "LEFT", -10, 0);
	hint:SetPoint("LEFT", frame, "LEFT", detailLeft, 0);
	hint:SetJustifyH("LEFT");
	hint:SetText(EVENTWOW_STR_PICK_RANDOM);

	-- Jugadores (abajo)
	local players = frame:CreateFontString("EventWowPickPlayers", "ARTWORK", "GameFontHighlightSmall");
	players:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 16);
	players:SetPoint("RIGHT", frame, "RIGHT", -16, 0);
	players:SetJustifyH("LEFT");

	local elapsed = 0;
	frame:SetScript("OnUpdate", function(self, delta)
		elapsed = elapsed + delta;
		if ( elapsed >= 0.2 ) then
			elapsed = 0;
			EventWow_UpdateTimer();
		end
	end);
	frame:SetScript("OnShow", EventWow_UpdateTimer);
end

-- Protocolo -------------------------------------------------------------------------------------

-- MATCH_PICK <unico 0/1> <n> (<id> <nombre> <icono> <descripcion> <hechizos> <vehiculo 0/1>) x n
EventWow_RegisterHandler("MATCH_PICK", function(fields)
	local pick = EventWow_Pick;
	pick.unique = fields[1] == "1";
	pick.characters = {};
	local count = math.min(tonumber(fields[2]) or 0, EVENTWOW_PICK.MAX_CARDS);
	for i = 0, count - 1 do
		local base = 3 + i * 6;
		local spells = {};
		for spellId in string.gmatch(fields[base + 4] or "", "%d+") do
			tinsert(spells, tonumber(spellId));
		end
		tinsert(pick.characters, {
			id = tonumber(fields[base]) or 0,
			name = fields[base + 1] or "",
			icon = fields[base + 2] or "",
			description = fields[base + 3] or "",
			spells = spells,
			vehicle = fields[base + 5] == "1",
		});
	end
	pick.selected = nil;
	EventWowPick_Update();
end);

-- MATCH_PICKS <n> (<nombre jugador> <id personaje>) x n
EventWow_RegisterHandler("MATCH_PICKS", function(fields)
	local players = {};
	local count = tonumber(fields[1]) or 0;
	for i = 0, count - 1 do
		tinsert(players, { name = fields[2 + i * 2] or "", characterId = tonumber(fields[3 + i * 2]) or 0 });
	end
	EventWow_Pick.players = players;
	EventWowPick_Update();
end);

-- Al cambiar de estado (fin de la eleccion, fuera de la partida) se oculta
EventWow_RegisterListener("MATCH", function()
	if ( EventWow_Match.state ~= "PICKING" ) then
		EventWow_Pick.characters = {};
		EventWow_Pick.players = {};
		EventWow_Pick.selected = nil;
	end
	EventWowPick_Update();
end);

EventWow_CreatePickFrame();
