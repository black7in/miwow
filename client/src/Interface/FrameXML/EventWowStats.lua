-- EventWow: panel de stats compacto y fijo (estilo Dota) del personaje de minijuego.
-- A la izquierda de la barra de habilidades (EventWowAbilities.lua). Solo en partida y disfrazado (no en vehiculo:
-- ahi los stats son los de la criatura). Al pasar el raton: todos los stats.
-- Todo sale de la API nativa del cliente (UnitStat, UnitAttackPower...): lo que el servidor suma (EventWowStats,
-- objetos de las casillas, libros) ya llega en los campos del personaje. Sin protocolo.
--
--   FUE  120    P. at.    300
--   AGI   80    P. hech.  450
--   AGU  200    Crít.    12,5%
--   INT  150    Celer.    4,2%
--   ESP   60    Armad.   1200

EVENTWOW_STATS_FRAME = {
	ROW_HEIGHT = 18,
	PADDING = 8,
	COLUMN_WIDTH = 92,
	GAP = 16,          -- separacion con la barra de habilidades
	UPDATE_INTERVAL = 0.25,
};

EVENTWOW_STR_STATS_PRIMARY = { "FUE", "AGI", "AGU", "INT", "ESP" };
EVENTWOW_STR_STATS_DERIVED = { "P. at.", "P. hech.", "Crít.", "Celer.", "Armad." };
EVENTWOW_STR_STATS_TOOLTIP_TITLE = "Estadísticas";
EVENTWOW_STR_STATS_DETAIL = {
	STRENGTH = "Fuerza",
	AGILITY = "Agilidad",
	STAMINA = "Aguante",
	INTELLECT = "Intelecto",
	SPIRIT = "Espíritu",
	HEALTH = "Vida máxima",
	POWER = "Poder máximo",
	ATTACK_POWER = "Poder de ataque",
	ATTACK_SPEED = "Velocidad de ataque",
	SPELL_POWER = "Poder con hechizos",
	HEALING = "Sanación",
	MELEE_CRIT = "Crítico cuerpo a cuerpo",
	SPELL_CRIT = "Crítico con hechizos",
	HASTE = "Celeridad",
	HIT = "Golpe",
	EXPERTISE = "Pericia",
	ARMOR = "Armadura",
	DODGE = "Esquiva",
	PARRY = "Parada",
	BLOCK = "Bloqueo",
	RESILIENCE = "Temple",
	ARMOR_PEN = "Penetración de armadura",
	SPELL_PEN = "Penetración de hechizos",
	MP5 = "Maná cada 5 s",
};

local frame;
local primaryValues = {};
local derivedValues = {};

-- Un solo valor (gsub devuelve tambien el numero de cambios)
local function EventWow_Percent(value)
	local text = gsub(format("%.1f%%", value or 0), "%.", ",");
	return text;
end

-- Maximo de las escuelas magicas (2 sagrado .. 7 arcano)
local function EventWow_MaxSchool(func)
	local best = 0;
	for school = 2, 7 do
		best = max(best, func(school) or 0);
	end
	return best;
end

local function EventWow_SpellPower()
	return EventWow_MaxSchool(GetSpellBonusDamage);
end

local function EventWow_SpellCrit()
	return EventWow_MaxSchool(GetSpellCritChance);
end

local function EventWow_AttackPower()
	local base, positive, negative = UnitAttackPower("player");
	return (base or 0) + (positive or 0) + (negative or 0);
end

local function EventWow_Haste()
	return max(GetCombatRatingBonus(CR_HASTE_MELEE) or 0, GetCombatRatingBonus(CR_HASTE_SPELL) or 0);
end

local function EventWow_SetValue(fontString, text, buffed, debuffed)
	fontString:SetText(text);
	if ( debuffed ) then
		fontString:SetTextColor(1, 0.25, 0.25);
	elseif ( buffed ) then
		fontString:SetTextColor(0.25, 1, 0.25);
	else
		fontString:SetTextColor(1, 1, 1);
	end
end

function EventWowStats_Update()
	for i = 1, 5 do
		local _, stat, positive, negative = UnitStat("player", i);
		EventWow_SetValue(primaryValues[i], stat or 0, (positive or 0) > 0, (negative or 0) < 0);
	end

	local _, armor = UnitArmor("player");
	EventWow_SetValue(derivedValues[1], EventWow_AttackPower());
	EventWow_SetValue(derivedValues[2], EventWow_SpellPower());
	EventWow_SetValue(derivedValues[3], EventWow_Percent(max(GetCritChance() or 0, EventWow_SpellCrit())));
	EventWow_SetValue(derivedValues[4], EventWow_Percent(EventWow_Haste()));
	EventWow_SetValue(derivedValues[5], armor or 0);
end

local function EventWow_ShowTooltip(self)
	local text = EVENTWOW_STR_STATS_DETAIL;
	GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT");
	GameTooltip:AddLine(EVENTWOW_STR_STATS_TOOLTIP_TITLE, 1, 1, 1);

	local function add(label, value)
		GameTooltip:AddDoubleLine(label, value, 1, 0.82, 0, 1, 1, 1);
	end

	local names = { text.STRENGTH, text.AGILITY, text.STAMINA, text.INTELLECT, text.SPIRIT };
	for i = 1, 5 do
		local _, stat = UnitStat("player", i);
		add(names[i], stat or 0);
	end

	GameTooltip:AddLine(" ");
	add(text.HEALTH, UnitHealthMax("player"));
	add(text.POWER, UnitPowerMax("player"));
	local _, casting = GetManaRegen();
	add(text.MP5, floor((casting or 0) * 5));

	GameTooltip:AddLine(" ");
	local mainSpeed = UnitAttackSpeed("player");
	add(text.ATTACK_POWER, EventWow_AttackPower());
	add(text.ATTACK_SPEED, mainSpeed and gsub(format("%.2f s", mainSpeed), "%.", ",") or "-");
	add(text.SPELL_POWER, EventWow_SpellPower());
	add(text.HEALING, GetSpellBonusHealing() or 0);
	add(text.MELEE_CRIT, EventWow_Percent(GetCritChance()));
	add(text.SPELL_CRIT, EventWow_Percent(EventWow_SpellCrit()));
	add(text.HASTE, EventWow_Percent(EventWow_Haste()));
	add(text.HIT, EventWow_Percent(max(GetCombatRatingBonus(CR_HIT_MELEE) or 0, GetCombatRatingBonus(CR_HIT_SPELL) or 0)));
	add(text.EXPERTISE, GetExpertise() or 0);
	add(text.ARMOR_PEN, EventWow_Percent(GetArmorPenetration()));
	add(text.SPELL_PEN, GetSpellPenetration() or 0);

	GameTooltip:AddLine(" ");
	local _, armor = UnitArmor("player");
	add(text.ARMOR, armor or 0);
	add(text.DODGE, EventWow_Percent(GetDodgeChance()));
	add(text.PARRY, EventWow_Percent(GetParryChance()));
	add(text.BLOCK, EventWow_Percent(GetBlockChance()));
	add(text.RESILIENCE, GetCombatRating(CR_CRIT_TAKEN_MELEE) or 0);

	GameTooltip:Show();
end

-- Visible en partida, disfrazado y fuera de vehiculo
function EventWowStats_UpdateVisibility()
	if ( EventWowMatch_IsActive() and EventWow_Character and not UnitHasVehicleUI("player") ) then
		if ( not frame:IsShown() ) then
			frame:Show();
			EventWowStats_Update();
		end
	else
		frame:Hide();
	end
end

local function EventWow_CreateStatsFrame()
	local config = EVENTWOW_STATS_FRAME;
	frame = CreateFrame("Frame", "EventWowStatsFrame", UIParent);
	frame:SetSize(config.COLUMN_WIDTH * 2 + config.PADDING * 2, config.ROW_HEIGHT * 5 + config.PADDING * 2);
	frame:SetPoint("BOTTOMRIGHT", EventWowAbilityBar, "BOTTOMLEFT", -config.GAP, -config.PADDING);
	frame:SetFrameStrata("MEDIUM");
	frame:SetBackdrop(EVENTWOW_PANEL.BACKDROP);
	frame:SetBackdropColor(unpack(EVENTWOW_PANEL.COLOR_SECTION));
	frame:SetBackdropBorderColor(unpack(EVENTWOW_PANEL.COLOR_BORDER));
	frame:EnableMouse(true);
	frame:SetScript("OnEnter", EventWow_ShowTooltip);
	frame:SetScript("OnLeave", function()
		GameTooltip:Hide();
	end);
	frame:Hide();

	local function column(labels, values, x)
		for i, label in ipairs(labels) do
			local y = -config.PADDING - (i - 1) * config.ROW_HEIGHT;
			local name = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall");
			name:SetPoint("TOPLEFT", frame, "TOPLEFT", x, y);
			name:SetHeight(config.ROW_HEIGHT);
			name:SetText(label);

			local value = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall");
			value:SetPoint("TOPRIGHT", frame, "TOPLEFT", x + config.COLUMN_WIDTH - 10, y);
			value:SetHeight(config.ROW_HEIGHT);
			value:SetJustifyH("RIGHT");
			values[i] = value;
		end
	end
	column(EVENTWOW_STR_STATS_PRIMARY, primaryValues, config.PADDING);
	column(EVENTWOW_STR_STATS_DERIVED, derivedValues, config.PADDING + config.COLUMN_WIDTH);

	local elapsed = 0;
	frame:SetScript("OnUpdate", function(self, delta)
		elapsed = elapsed + delta;
		if ( elapsed >= config.UPDATE_INTERVAL ) then
			elapsed = 0;
			EventWowStats_Update();
			if ( GameTooltip:IsOwned(self) ) then
				EventWow_ShowTooltip(self);
			end
		end
	end);

	frame:RegisterEvent("UNIT_ENTERED_VEHICLE");
	frame:RegisterEvent("UNIT_EXITED_VEHICLE");
	frame:SetScript("OnEvent", function(self, event, unit)
		if ( unit == "player" ) then
			EventWowStats_UpdateVisibility();
		end
	end);
end

EventWow_CreateStatsFrame();
EventWow_RegisterListener("MATCH", EventWowStats_UpdateVisibility);
EventWow_RegisterListener("CHARACTER", EventWowStats_UpdateVisibility);
