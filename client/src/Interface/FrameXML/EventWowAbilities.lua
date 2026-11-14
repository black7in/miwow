-- EventWow: barra de habilidades del personaje de minijuego ("disfraz", EventWowDisguise.cpp).
-- La barra nativa no se usa (se guarda en character_action): esta es propia y solo vive en la partida.
--   MATCH_CHARACTER <id> <nombre> <icono> <hechizo>...   disfrazado: una casilla por hechizo, en orden
--   MATCH_CHARACTER 0                                    sin disfraz: barra oculta
--
-- Progresion (EventWowProgress.cpp, docs/heroes.md): nivel, puntos y rango de cada habilidad.
--   MATCH_ABILITIES <nivel> <max> <puntos> <atrib> <atrib max> <atrib mejorable> <stats atrib "clave:valor,...">
--                   <n> (<rango> <rango max ahora> <rango total> <mejorable> <hechizo actual> <hechizo siguiente>) x n
--   MATCH_ABILITIES 0   sin progresion: todo aprendido, sin "+"
--   "+" -> UPGRADE <casilla 0..n-1 | attr>
--
-- Los hechizos son temporales pero estan aprendidos, asi que icono, tiempo de reutilizacion, coste y alcance
-- salen del propio cliente (GetSpellInfo, GetSpellCooldown, IsUsableSpell, IsSpellInRange).
-- Botones seguros (SecureActionButtonTemplate, type "spell"): lanzar hechizos es una accion protegida. Se lanza por
-- NOMBRE sin rango (CastSpellByName = el rango mas alto aprendido): subir de rango en combate no necesita tocar el
-- boton seguro. Un hechizo de heroe no debe llamarse igual que uno del druida contenedor.
-- Teclas 1..0 por override bindings (las acciones nativas siguen bloqueadas en EventWow.lua).
-- Los botones seguros no se pueden cambiar en combate: si llega un cambio de personaje en combate se aplica al salir.
-- Los "+", el boton de atributos y la barra de XP no son seguros: cambian tambien en combate.
--
--          Arthas, caballero de la Muerte - Nivel 5 - 1 punto          [Atrib]+
--          [============ XP ============================================]
--          [ 1 ]+ [ 2 ]+ [ 3 ]  [ 4 ]  [ 5 ]  [ 6 ]                 EventWowAbilityBar (abajo, centrado)

EVENTWOW_ABILITY_BAR = {
	BUTTON_SIZE = 40,  -- ActionButtonTemplate mide 36; se escala
	SPACING = 8,
	BOTTOM_OFFSET = 24,  -- alineada con EventWowStats.lua (izquierda) y EventWowInventory.lua (derecha)
	KEYS = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "0" },
	XP_HEIGHT = 6,
	XP_GAP = 5,          -- entre los botones y la barra de XP
	PLUS_SIZE = 18,
	ATTRIBUTE_SIZE = 24,
	ATTRIBUTE_ICON = "Interface\\Icons\\Spell_Holy_WordFortitude",
};

EVENTWOW_STR_ABILITY_LEVEL = "Nivel %d";
EVENTWOW_STR_ABILITY_POINT = "|cff00ff001 punto|r";
EVENTWOW_STR_ABILITY_POINTS = "|cff00ff00%d puntos|r";
EVENTWOW_STR_ABILITY_NOT_LEARNED = "Sin aprender";
EVENTWOW_STR_ABILITY_RANK = "Rango %d de %d";
EVENTWOW_STR_ABILITY_UPGRADE = "Mejorar: rango %d de %d";
EVENTWOW_STR_ABILITY_LEARN = "Aprender";
EVENTWOW_STR_ABILITY_ATTRIBUTES = "Atributos";
EVENTWOW_STR_ABILITY_ATTRIBUTES_PER_POINT = "Por cada punto:";
EVENTWOW_STR_ABILITY_ATTRIBUTES_TOTAL = "Total (%d/%d):";
EVENTWOW_STR_ABILITY_ATTRIBUTES_LOCKED = "Desde el nivel 2.";
EVENTWOW_STR_ABILITY_XP = "Experiencia: %d / %d";
EVENTWOW_STR_ABILITY_MAX_LEVEL = "Nivel máximo";

-- Nombres de las claves de EventWowStats (servidor) para el tooltip de atributos
EVENTWOW_STAT_NAMES = {
	str = "Fuerza", agi = "Agilidad", sta = "Aguante", int = "Intelecto", spi = "Espíritu",
	health = "Vida", mana = "Maná", armor = "Armadura", ap = "Poder de ataque", rap = "Poder de ataque a distancia",
	sp = "Poder con hechizos", crit = "Índice de golpe crítico", haste = "Índice de celeridad",
	hit = "Índice de golpe", expertise = "Índice de pericia", dodge = "Índice de esquivar",
	parry = "Índice de parada", block = "Índice de bloqueo", resilience = "Temple",
	armorpen = "Penetración de armadura", spellpen = "Penetración de hechizos", mp5 = "Maná cada 5 s",
	hp5 = "Vida cada 5 s",
};

-- Personaje actual (nil = sin disfraz): { id, name, icon, spells = { id, ... } }
EventWow_Character = nil;
-- Progresion actual (nil = sin progresion): ver EventWow_ParseProgress
EventWow_Progress = nil;

local bar;
local buttons = {};
local pendingUpdate = false;
local attributeButton, xpBar;

-- "Nombre(Rango N)": las consultas de estado por nombre necesitan el rango si el hechizo lo tiene
local function EventWow_SpellString(spellId)
	local name, rank = GetSpellInfo(spellId);
	if ( not name ) then
		return nil;
	end
	if ( rank and rank ~= "" ) then
		return name.."("..rank..")";
	end
	return name;
end

-- Estado de progresion de una casilla (indice de la ficha), nil sin progresion
local function EventWow_GetSlotProgress(slot)
	return EventWow_Progress and EventWow_Progress.slots[slot];
end

local function EventWow_CreatePlusButton(name, onClick, onEnter)
	local size = EVENTWOW_ABILITY_BAR.PLUS_SIZE;
	local plus = CreateFrame("Button", name, bar);
	plus:SetSize(size, size);
	plus:SetFrameLevel(bar:GetFrameLevel() + 10);
	plus:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-Up");
	plus:SetPushedTexture("Interface\\Buttons\\UI-PlusButton-Down");
	plus:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD");
	plus:SetScript("OnClick", onClick);
	plus:SetScript("OnEnter", onEnter);
	plus:SetScript("OnLeave", function()
		GameTooltip:Hide();
	end);
	plus:Hide();
	return plus;
end

local function EventWow_ShowAbilityTooltip(button)
	local slot = button.slot and EventWow_GetSlotProgress(button.slot);
	local spellId = slot and (slot.current ~= 0 and slot.current or button.firstSpellId) or button.spellId;
	if ( not spellId ) then
		return;
	end
	GameTooltip_SetDefaultAnchor(GameTooltip, button);
	GameTooltip:SetHyperlink("spell:"..spellId);
	if ( slot ) then
		if ( slot.rank == 0 ) then
			GameTooltip:AddLine(EVENTWOW_STR_ABILITY_NOT_LEARNED, 1, 0.1, 0.1);
		else
			GameTooltip:AddLine(format(EVENTWOW_STR_ABILITY_RANK, slot.rank, slot.total), 0.6, 0.6, 0.6);
		end
		GameTooltip:Show();
	end
end

local function EventWow_GetButton(index)
	local button = buttons[index];
	if ( button ) then
		return button;
	end

	local name = "EventWowAbilityButton"..index;
	button = CreateFrame("CheckButton", name, bar, "SecureActionButtonTemplate, ActionButtonTemplate");
	button:SetScale(EVENTWOW_ABILITY_BAR.BUTTON_SIZE / 36);
	button:RegisterForClicks("AnyUp");
	button:SetAttribute("type", "spell");
	button:SetScript("PostClick", function(self)
		self:SetChecked(false);
	end);
	button:SetScript("OnEnter", EventWow_ShowAbilityTooltip);
	button:SetScript("OnLeave", function()
		GameTooltip:Hide();
	end);

	button.icon = _G[name.."Icon"];
	button.cooldown = _G[name.."Cooldown"];
	button.hotkey = _G[name.."HotKey"];
	-- El texto de cantidad muestra el rango ("2/4")
	button.rankText = _G[name.."Count"];
	button.rankText:SetText("");
	_G[name.."Name"]:SetText("");

	local key = EVENTWOW_ABILITY_BAR.KEYS[index];
	button.key = key;
	button.hotkey:SetText(key or "");

	-- "+" en la esquina superior derecha (no seguro: hijo de la barra, no del boton)
	button.plus = EventWow_CreatePlusButton(name.."Plus", function()
		if ( button.slot ) then
			EventWow_Send("UPGRADE", button.slot - 1);
		end
	end, function(self)
		local slot = button.slot and EventWow_GetSlotProgress(button.slot);
		if ( not slot or slot.next == 0 ) then
			return;
		end
		GameTooltip:SetOwner(self, "ANCHOR_TOP");
		GameTooltip:SetHyperlink("spell:"..slot.next);
		GameTooltip:AddLine(slot.rank == 0 and EVENTWOW_STR_ABILITY_LEARN
			or format(EVENTWOW_STR_ABILITY_UPGRADE, slot.rank + 1, slot.total), 0, 1, 0);
		GameTooltip:Show();
	end);

	buttons[index] = button;
	return button;
end

-- Estado del boton de una casilla segun la progresion (no seguro: tambien en combate)
local function EventWow_UpdateButtonProgress(button)
	local slot = button.slot and EventWow_GetSlotProgress(button.slot);
	if ( not slot ) then
		button.spell = EventWow_SpellString(button.spellId);
		button.icon:SetDesaturated(nil);
		button.rankText:SetText("");
		button.plus:Hide();
		return;
	end

	if ( slot.rank == 0 ) then
		button.spell = nil;
		button.icon:SetDesaturated(1);
		button.icon:SetVertexColor(0.5, 0.5, 0.5);
		CooldownFrame_SetTimer(button.cooldown, 0, 0, 0);
	else
		button.spell = EventWow_SpellString(slot.current);
		button.icon:SetDesaturated(nil);
	end
	button.rankText:SetText(slot.total > 1 and slot.rank.."/"..slot.total or "");
	if ( slot.canUp ) then
		button.plus:Show();
	else
		button.plus:Hide();
	end
end

local function EventWow_UpdateXpBar()
	local progress = EventWow_Progress;
	if ( not progress or not bar:IsShown() ) then
		xpBar:Hide();
		return;
	end
	if ( progress.level >= progress.maxLevel ) then
		xpBar:SetMinMaxValues(0, 1);
		xpBar:SetValue(1);
	else
		xpBar:SetMinMaxValues(0, max(UnitXPMax("player"), 1));
		xpBar:SetValue(UnitXP("player"));
	end
	xpBar:Show();
end

-- Nombre, nivel, puntos, "+", atributos y XP (no seguro: tambien en combate)
local function EventWow_UpdateProgress()
	local character, progress = EventWow_Character, EventWow_Progress;
	for _, button in ipairs(buttons) do
		if ( button:IsShown() ) then
			EventWow_UpdateButtonProgress(button);
		else
			button.plus:Hide();
		end
	end

	local text = character and character.name or "";
	if ( progress ) then
		text = text.." - "..format(EVENTWOW_STR_ABILITY_LEVEL, progress.level);
		if ( progress.points > 0 ) then
			text = text.." - "..(progress.points == 1 and EVENTWOW_STR_ABILITY_POINT
				or format(EVENTWOW_STR_ABILITY_POINTS, progress.points));
		end
	end
	EventWowAbilityBarName:SetText(text);

	if ( progress and progress.attrMax > 0 and bar:IsShown() ) then
		attributeButton.count:SetText(progress.attr.."/"..progress.attrMax);
		attributeButton.icon:SetDesaturated(progress.attr == 0 and 1 or nil);
		attributeButton:Show();
		if ( progress.attrUp ) then
			attributeButton.plus:Show();
		else
			attributeButton.plus:Hide();
		end
	else
		attributeButton:Hide();
		attributeButton.plus:Hide();
	end

	EventWow_UpdateXpBar();
end

-- Disposicion y bindings segun EventWow_Character (fuera de combate)
local function EventWow_ApplyCharacter()
	if ( InCombatLockdown() ) then
		pendingUpdate = true;
		return;
	end
	pendingUpdate = false;

	ClearOverrideBindings(bar);
	local character = EventWow_Character;
	local spells = character and character.spells or {};
	local count = 0;

	for index, spellId in ipairs(spells) do
		local spellName = GetSpellInfo(spellId);
		if ( spellName and count < #EVENTWOW_ABILITY_BAR.KEYS ) then
			count = count + 1;
			local button = EventWow_GetButton(count);
			button.slot = index;
			button.spellId = spellId;
			button.firstSpellId = spellId;
			-- Por nombre sin rango: el rango mas alto aprendido (ver cabecera)
			button:SetAttribute("spell", spellName);
			button.icon:SetTexture(select(3, GetSpellInfo(spellId)));
			button.icon:SetVertexColor(1, 1, 1);
			button:SetChecked(false);
			button:Show();
			if ( button.key ) then
				SetOverrideBindingClick(bar, true, button.key, button:GetName());
			end
		end
	end

	for index = count + 1, #buttons do
		local button = buttons[index];
		button.slot = nil;
		button.spellId = nil;
		button.firstSpellId = nil;
		button.spell = nil;
		button:SetAttribute("spell", nil);
		button:Hide();
		button.plus:Hide();
	end

	if ( count == 0 ) then
		bar:Hide();
		EventWow_UpdateProgress();
		return;
	end

	-- Coordenadas de los botones en su propia escala
	local scale = EVENTWOW_ABILITY_BAR.BUTTON_SIZE / 36;
	local size, spacing = EVENTWOW_ABILITY_BAR.BUTTON_SIZE, EVENTWOW_ABILITY_BAR.SPACING;
	local width = count * size + (count - 1) * spacing;
	bar:SetWidth(width);
	for index = 1, count do
		local button = buttons[index];
		local x = (index - 1) * (size + spacing);
		button:ClearAllPoints();
		button:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", x / scale, 0);
		button.plus:ClearAllPoints();
		button.plus:SetPoint("CENTER", bar, "BOTTOMLEFT", x + size - 3, size - 3);
	end

	bar:Show();
	EventWow_UpdateProgress();
end

-- Tiempo de reutilizacion, coste y alcance (cada 0.1 s mientras la barra se ve)
local function EventWow_UpdateButtons()
	for _, button in ipairs(buttons) do
		if ( button:IsShown() and button.spell ) then
			local start, duration, enable = GetSpellCooldown(button.spell);
			if ( start ) then
				CooldownFrame_SetTimer(button.cooldown, start, duration, enable);
			end

			local usable, noMana = IsUsableSpell(button.spell);
			if ( usable ) then
				button.icon:SetVertexColor(1, 1, 1);
			elseif ( noMana ) then
				button.icon:SetVertexColor(0.5, 0.5, 1);
			else
				button.icon:SetVertexColor(0.4, 0.4, 0.4);
			end

			if ( IsSpellInRange(button.spell, "target") == 0 ) then
				button.hotkey:SetVertexColor(1, 0.1, 0.1);
			else
				button.hotkey:SetVertexColor(0.6, 0.6, 0.6);
			end
		end
	end
end

local function EventWow_ShowAttributeTooltip(self)
	local progress = EventWow_Progress;
	if ( not progress ) then
		return;
	end
	GameTooltip:SetOwner(self, "ANCHOR_TOP");
	GameTooltip:AddLine(EVENTWOW_STR_ABILITY_ATTRIBUTES, 1, 1, 1);
	GameTooltip:AddLine(EVENTWOW_STR_ABILITY_ATTRIBUTES_PER_POINT, 1, 0.82, 0);
	for _, stat in ipairs(progress.attrStats) do
		GameTooltip:AddLine("+"..stat.value.." "..(EVENTWOW_STAT_NAMES[stat.key] or stat.key), 0, 1, 0);
	end
	if ( progress.attr > 0 ) then
		GameTooltip:AddLine(" ");
		GameTooltip:AddLine(format(EVENTWOW_STR_ABILITY_ATTRIBUTES_TOTAL, progress.attr, progress.attrMax), 1, 0.82, 0);
		for _, stat in ipairs(progress.attrStats) do
			GameTooltip:AddLine("+"..(stat.value * progress.attr).." "..(EVENTWOW_STAT_NAMES[stat.key] or stat.key), 1, 1, 1);
		end
	end
	if ( progress.level < 2 ) then
		GameTooltip:AddLine(EVENTWOW_STR_ABILITY_ATTRIBUTES_LOCKED, 0.6, 0.6, 0.6);
	end
	GameTooltip:Show();
end

local function EventWow_CreateAbilityBar()
	local config = EVENTWOW_ABILITY_BAR;
	bar = CreateFrame("Frame", "EventWowAbilityBar", UIParent);
	bar:SetSize(config.BUTTON_SIZE, config.BUTTON_SIZE);
	bar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, config.BOTTOM_OFFSET);
	bar:SetFrameStrata("MEDIUM");
	bar:Hide();

	-- Barra de XP (nivel real del personaje: UnitXP / UnitXPMax)
	xpBar = CreateFrame("StatusBar", "EventWowAbilityXpBar", bar);
	xpBar:SetHeight(config.XP_HEIGHT);
	xpBar:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", 0, config.XP_GAP);
	xpBar:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", 0, config.XP_GAP);
	xpBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar");
	xpBar:SetStatusBarColor(0.58, 0.0, 0.55);
	local background = xpBar:CreateTexture(nil, "BACKGROUND");
	background:SetAllPoints();
	background:SetTexture(0, 0, 0, 0.6);
	xpBar:EnableMouse(true);
	xpBar:SetScript("OnEnter", function(self)
		local progress = EventWow_Progress;
		GameTooltip:SetOwner(self, "ANCHOR_TOP");
		if ( progress and progress.level >= progress.maxLevel ) then
			GameTooltip:SetText(EVENTWOW_STR_ABILITY_MAX_LEVEL);
		else
			GameTooltip:SetText(format(EVENTWOW_STR_ABILITY_XP, UnitXP("player"), UnitXPMax("player")));
		end
		GameTooltip:Show();
	end);
	xpBar:SetScript("OnLeave", function()
		GameTooltip:Hide();
	end);
	xpBar:Hide();

	local nameOffset = config.XP_GAP + config.XP_HEIGHT + 4;
	local name = bar:CreateFontString("EventWowAbilityBarName", "ARTWORK", "GameFontNormal");
	name:SetPoint("BOTTOM", bar, "TOP", 0, nameOffset);

	-- Atributos: encima del extremo derecho, a la altura del nombre
	attributeButton = CreateFrame("Button", "EventWowAbilityAttributeButton", bar);
	attributeButton:SetSize(config.ATTRIBUTE_SIZE, config.ATTRIBUTE_SIZE);
	attributeButton:SetPoint("BOTTOMRIGHT", bar, "TOPRIGHT", 0, nameOffset - 4);
	attributeButton.icon = attributeButton:CreateTexture(nil, "ARTWORK");
	attributeButton.icon:SetAllPoints();
	attributeButton.icon:SetTexture(config.ATTRIBUTE_ICON);
	attributeButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD");
	attributeButton.count = attributeButton:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall");
	attributeButton.count:SetPoint("RIGHT", attributeButton, "LEFT", -3, 0);
	attributeButton:SetScript("OnEnter", EventWow_ShowAttributeTooltip);
	attributeButton:SetScript("OnLeave", function()
		GameTooltip:Hide();
	end);
	attributeButton:Hide();
	attributeButton.plus = EventWow_CreatePlusButton("EventWowAbilityAttributePlus", function()
		EventWow_Send("UPGRADE", "attr");
	end, EventWow_ShowAttributeTooltip);
	attributeButton.plus:SetPoint("CENTER", attributeButton, "TOPRIGHT", -3, -3);

	local elapsed = 0;
	bar:SetScript("OnUpdate", function(self, delta)
		elapsed = elapsed + delta;
		if ( elapsed >= 0.1 ) then
			elapsed = 0;
			EventWow_UpdateButtons();
		end
	end);

	bar:RegisterEvent("PLAYER_REGEN_ENABLED");
	bar:RegisterEvent("PLAYER_XP_UPDATE");
	bar:RegisterEvent("PLAYER_LEVEL_UP");
	bar:SetScript("OnEvent", function(self, event)
		if ( event == "PLAYER_REGEN_ENABLED" ) then
			if ( pendingUpdate ) then
				EventWow_ApplyCharacter();
			end
		else
			EventWow_UpdateXpBar();
		end
	end);
end

-- MATCH_CHARACTER <id> <nombre> <icono> <hechizo>... | MATCH_CHARACTER 0
EventWow_RegisterHandler("MATCH_CHARACTER", function(fields)
	local id = tonumber(fields[1]) or 0;
	if ( id == 0 ) then
		EventWow_Character = nil;
	else
		local spells = {};
		for i = 4, #fields do
			local spellId = tonumber(fields[i]);
			if ( spellId ) then
				tinsert(spells, spellId);
			end
		end
		EventWow_Character = { id = id, name = fields[2], icon = fields[3], spells = spells };
	end
	EventWow_ApplyCharacter();
	EventWow_FireListeners("CHARACTER");
end);

-- MATCH_ABILITIES (ver cabecera) -> { level, maxLevel, points, attr, attrMax, attrUp, attrStats = { {key, value} },
-- slots = { {rank, maxNow, total, canUp, current, next} } } o nil
local function EventWow_ParseProgress(fields)
	local level = tonumber(fields[1]) or 0;
	if ( level == 0 ) then
		return nil;
	end

	local progress = {
		level = level,
		maxLevel = tonumber(fields[2]) or 0,
		points = tonumber(fields[3]) or 0,
		attr = tonumber(fields[4]) or 0,
		attrMax = tonumber(fields[5]) or 0,
		attrUp = fields[6] == "1",
		attrStats = {},
		slots = {},
	};
	for key, value in gmatch(fields[7] or "", "([%w_]+):(%-?%d+)") do
		tinsert(progress.attrStats, { key = key, value = tonumber(value) });
	end

	local count = tonumber(fields[8]) or 0;
	for i = 1, count do
		local base = 8 + (i - 1) * 6;
		progress.slots[i] = {
			rank = tonumber(fields[base + 1]) or 0,
			maxNow = tonumber(fields[base + 2]) or 0,
			total = tonumber(fields[base + 3]) or 1,
			canUp = fields[base + 4] == "1",
			current = tonumber(fields[base + 5]) or 0,
			next = tonumber(fields[base + 6]) or 0,
		};
	end
	return progress;
end

EventWow_RegisterHandler("MATCH_ABILITIES", function(fields)
	EventWow_Progress = EventWow_ParseProgress(fields);
	EventWow_UpdateProgress();
end);

-- "Has aprendido un nuevo hechizo" / "Has olvidado..." (los manda el motor como CHAT_MSG_SYSTEM): el disfraz
-- aprende y olvida sus hechizos en cada partida y el jugador nunca aprende otros, asi que se ocultan siempre
-- (salvo en modo dev con el panel oculto). Llegan antes que MATCH_CHARACTER: no se puede filtrar por disfraz.
EVENTWOW_HIDDEN_SYSTEM_MESSAGES = { "ERR_LEARN_SPELL_S", "ERR_LEARN_ABILITY_S", "ERR_SPELL_UNLEARNED_S" };

local function EventWow_SetupSpellMessageFilter()
	local patterns = {};
	for _, name in ipairs(EVENTWOW_HIDDEN_SYSTEM_MESSAGES) do
		local text = _G[name];
		if ( text ) then
			-- Formato -> patron: escapar los caracteres magicos y %s -> (.+)
			text = gsub(text, "([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1");
			text = gsub(text, "%%s", "(.+)");
			tinsert(patterns, "^"..text.."$");
		end
	end

	ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", function(self, event, message)
		if ( EventWow_IsUnrestricted() or not message ) then
			return false;
		end
		for _, pattern in ipairs(patterns) do
			if ( strfind(message, pattern) ) then
				return true;
			end
		end
		return false;
	end);
end

EventWow_CreateAbilityBar();
EventWow_SetupSpellMessageFilter();
