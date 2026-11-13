-- EventWow: barra de habilidades del personaje de minijuego ("disfraz", EventWowDisguise.cpp).
-- La barra nativa no se usa (se guarda en character_action): esta es propia y solo vive en la partida.
--   MATCH_CHARACTER <id> <nombre> <icono> <hechizo>...   disfrazado: una casilla por hechizo, en orden
--   MATCH_CHARACTER 0                                    sin disfraz: barra oculta
--
-- Los hechizos son temporales pero estan aprendidos, asi que icono, tiempo de reutilizacion, coste y alcance
-- salen del propio cliente (GetSpellInfo, GetSpellCooldown, IsUsableSpell, IsSpellInRange).
-- Botones seguros (SecureActionButtonTemplate, type "spell" con el ID -> CastSpellByID): lanzar hechizos es
-- una accion protegida.
-- Teclas 1..0 por override bindings (las acciones nativas siguen bloqueadas en EventWow.lua).
-- Los botones seguros no se pueden cambiar en combate: si llega un cambio en combate se aplica al salir.
--
--                  Piromano goblin
--          [ 1 ] [ 2 ] [ 3 ]                EventWowAbilityBar (abajo, centrado)

EVENTWOW_ABILITY_BAR = {
	BUTTON_SIZE = 40,  -- ActionButtonTemplate mide 36; se escala
	SPACING = 8,
	BOTTOM_OFFSET = 70,
	KEYS = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "0" },
};

-- Personaje actual (nil = sin disfraz): { id, name, icon, spells = { id, ... } }
EventWow_Character = nil;

local bar;
local buttons = {};
local pendingUpdate = false;

-- "Nombre(Rango N)": CastSpellByName necesita el rango si el hechizo lo tiene
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
	button:SetScript("OnEnter", function(self)
		if ( self.spellId ) then
			GameTooltip_SetDefaultAnchor(GameTooltip, self);
			GameTooltip:SetHyperlink("spell:"..self.spellId);
		end
	end);
	button:SetScript("OnLeave", function()
		GameTooltip:Hide();
	end);

	button.icon = _G[name.."Icon"];
	button.cooldown = _G[name.."Cooldown"];
	button.hotkey = _G[name.."HotKey"];
	_G[name.."Count"]:SetText("");
	_G[name.."Name"]:SetText("");

	local key = EVENTWOW_ABILITY_BAR.KEYS[index];
	button.key = key;
	button.hotkey:SetText(key or "");

	buttons[index] = button;
	return button;
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
		local spell = EventWow_SpellString(spellId);
		if ( spell and index <= #EVENTWOW_ABILITY_BAR.KEYS ) then
			count = count + 1;
			local button = EventWow_GetButton(count);
			button.spellId = spellId;
			button.spell = spell;
			-- Lanza por ID (CastSpellByID); el nombre con rango es para las consultas de estado
			button:SetAttribute("spell", spellId);
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
		button.spellId = nil;
		button.spell = nil;
		button:SetAttribute("spell", nil);
		button:Hide();
	end

	if ( count == 0 ) then
		bar:Hide();
		return;
	end

	-- Coordenadas de los botones en su propia escala
	local scale = EVENTWOW_ABILITY_BAR.BUTTON_SIZE / 36;
	local size, spacing = EVENTWOW_ABILITY_BAR.BUTTON_SIZE, EVENTWOW_ABILITY_BAR.SPACING;
	local width = count * size + (count - 1) * spacing;
	bar:SetWidth(width);
	for index = 1, count do
		local button = buttons[index];
		button:ClearAllPoints();
		button:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", ((index - 1) * (size + spacing)) / scale, 0);
	end

	EventWowAbilityBarName:SetText(character.name or "");
	bar:Show();
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

local function EventWow_CreateAbilityBar()
	bar = CreateFrame("Frame", "EventWowAbilityBar", UIParent);
	bar:SetSize(EVENTWOW_ABILITY_BAR.BUTTON_SIZE, EVENTWOW_ABILITY_BAR.BUTTON_SIZE);
	bar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, EVENTWOW_ABILITY_BAR.BOTTOM_OFFSET);
	bar:SetFrameStrata("MEDIUM");
	bar:Hide();

	local name = bar:CreateFontString("EventWowAbilityBarName", "ARTWORK", "GameFontNormal");
	name:SetPoint("BOTTOM", bar, "TOP", 0, 6);

	local elapsed = 0;
	bar:SetScript("OnUpdate", function(self, delta)
		elapsed = elapsed + delta;
		if ( elapsed >= 0.1 ) then
			elapsed = 0;
			EventWow_UpdateButtons();
		end
	end);

	bar:RegisterEvent("PLAYER_REGEN_ENABLED");
	bar:SetScript("OnEvent", function()
		if ( pendingUpdate ) then
			EventWow_ApplyCharacter();
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
