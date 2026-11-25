-- MiWow: aviso de subida de nivel y de habilidades nuevas estilo retail (franja en la parte de arriba, un aviso
-- detras de otro). Contraparte: MiWowAutoLearn.cpp (auto-aprendizaje).
--   PLAYER_LEVEL_UP (evento nativo)    -> "¡Has alcanzado el nivel X!"
--   SPELLS_LEARNED <n> <hechizo>...    -> "Nueva habilidad: [icono] nombre" por cada uno (hasta MAX_SPELLS, luego
--                                         "Y N más"). Llega justo despues del PLAYER_LEVEL_UP (el core manda la subida
--                                         de nivel antes del gancho), al aprender un talento o tras el login.
-- El chat nativo sigue diciendo "Has aprendido un nuevo hechizo: X" (no se toca).
--
--     ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~    linea dorada que se difumina en los lados
--                       ¡Has alcanzado el
--                          Nivel 25
--     ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- y despues, uno a uno:
--                       Nueva habilidad
--                  [icono]  Bola de Fuego
--                           Rango 5

MIWOW_STR_LEVELUP_REACHED = "¡Has alcanzado el";
MIWOW_STR_LEVELUP_LEVEL = "Nivel %d";
MIWOW_STR_LEVELUP_NEW_SPELL = "Nueva habilidad";
MIWOW_STR_LEVELUP_MORE = "Y %d más";
MIWOW_STR_LEVELUP_MORE_HINT = "Míralas en tu libro de hechizos";

MiWow_LevelUp = {
	MAX_SPELLS = 6,      -- habilidades que se muestran de una tanda; el resto, "Y N más"
	FADE_IN = 0.35,
	FADE_OUT = 0.5,
	HOLD_LEVEL = 2.5,
	HOLD_SPELL = 1.8,
	queue = {},          -- { kind = "level", level } | { kind = "spell", name, rank, icon } | { kind = "more", count }
	current = nil,       -- aviso en pantalla
	elapsed = 0,
};

local frame;

-- Textura blanca con degradado horizontal de transparencia (de "a0" a "a1")
local function MiWow_GradientTexture(parent, layer, r, g, b, a0, a1)
	local tex = parent:CreateTexture(nil, layer);
	tex:SetTexture("Interface\\Buttons\\WHITE8X8");
	tex:SetGradientAlpha("HORIZONTAL", r, g, b, a0, r, g, b, a1);
	return tex;
end

-- Franja: dos mitades que se difuminan hacia los lados
local function MiWow_Band(parent, layer, r, g, b, alpha, height, point, y)
	local left = MiWow_GradientTexture(parent, layer, r, g, b, 0, alpha);
	left:SetHeight(height);
	left:SetPoint(point.."LEFT", parent, point.."LEFT", 0, y);
	left:SetPoint(point.."RIGHT", parent, point, 0, y);
	local right = MiWow_GradientTexture(parent, layer, r, g, b, alpha, 0);
	right:SetHeight(height);
	right:SetPoint(point.."LEFT", parent, point, 0, y);
	right:SetPoint(point.."RIGHT", parent, point.."RIGHT", 0, y);
end

local function MiWow_CreateFrame()
	frame = CreateFrame("Frame", "MiWowLevelUpFrame", UIParent);
	frame:SetSize(440, 96);
	frame:SetPoint("TOP", UIParent, "TOP", 0, -110);
	frame:SetFrameStrata("HIGH");
	frame:Hide();

	-- Fondo oscuro y lineas doradas arriba y abajo
	local bgLeft = MiWow_GradientTexture(frame, "BACKGROUND", 0, 0, 0, 0, 0.75);
	bgLeft:SetPoint("TOPLEFT", frame, "TOPLEFT");
	bgLeft:SetPoint("BOTTOMRIGHT", frame, "BOTTOM");
	local bgRight = MiWow_GradientTexture(frame, "BACKGROUND", 0, 0, 0, 0.75, 0);
	bgRight:SetPoint("TOPLEFT", frame, "TOP");
	bgRight:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT");
	MiWow_Band(frame, "BORDER", 1, 0.82, 0, 0.9, 2, "TOP", 0);
	MiWow_Band(frame, "BORDER", 1, 0.82, 0, 0.9, 2, "BOTTOM", 0);

	local fontFile = GameFontNormalHuge:GetFont();

	-- Linea pequena de arriba ("¡Has alcanzado el" / "Nueva habilidad" / "Y N más")
	local header = frame:CreateFontString("MiWowLevelUpHeader", "ARTWORK", "GameFontNormalLarge");
	header:SetPoint("TOP", frame, "TOP", 0, -12);
	header:SetTextColor(1, 1, 1);

	-- "Nivel 25" grande
	local level = frame:CreateFontString("MiWowLevelUpLevel", "ARTWORK", "GameFontNormalHuge");
	level:SetFont(fontFile, 36, "OUTLINE");
	level:SetPoint("TOP", header, "BOTTOM", 0, -6);
	level:SetTextColor(1, 0.82, 0);

	-- Habilidad: icono + nombre + rango, centrados como bloque
	local spell = CreateFrame("Frame", "MiWowLevelUpSpell", frame);
	spell:SetSize(1, 44);
	spell:SetPoint("TOP", header, "BOTTOM", 0, -6);

	local icon = spell:CreateTexture("MiWowLevelUpSpellIcon", "ARTWORK");
	icon:SetSize(44, 44);
	icon:SetPoint("LEFT", spell, "LEFT", 0, 0);

	local name = spell:CreateFontString("MiWowLevelUpSpellName", "ARTWORK", "GameFontNormalHuge");
	name:SetFont(fontFile, 22, "OUTLINE");
	name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -2);
	name:SetTextColor(1, 0.82, 0);

	local rank = spell:CreateFontString("MiWowLevelUpSpellRank", "ARTWORK", "GameFontHighlight");
	rank:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -3);
	rank:SetTextColor(0.8, 0.8, 0.8);

	-- "Míralas en tu libro de hechizos"
	local hint = frame:CreateFontString("MiWowLevelUpHint", "ARTWORK", "GameFontHighlight");
	hint:SetPoint("TOP", header, "BOTTOM", 0, -12);

	frame:SetScript("OnUpdate", MiWowLevelUp_OnUpdate);
end

local function MiWow_ShowItem(item)
	MiWowLevelUpLevel:Hide();
	MiWowLevelUpSpell:Hide();
	MiWowLevelUpHint:Hide();

	if ( item.kind == "level" ) then
		MiWowLevelUpHeader:SetText(MIWOW_STR_LEVELUP_REACHED);
		MiWowLevelUpLevel:SetText(format(MIWOW_STR_LEVELUP_LEVEL, item.level));
		MiWowLevelUpLevel:Show();
	elseif ( item.kind == "spell" ) then
		MiWowLevelUpHeader:SetText(MIWOW_STR_LEVELUP_NEW_SPELL);
		MiWowLevelUpSpellIcon:SetTexture(item.icon or "Interface\\Icons\\INV_Misc_QuestionMark");
		MiWowLevelUpSpellName:SetText(item.name);
		MiWowLevelUpSpellRank:SetText(item.rank or "");
		-- Ancho del bloque = icono + hueco + texto mas largo, para centrarlo
		local textWidth = math.max(MiWowLevelUpSpellName:GetStringWidth(), MiWowLevelUpSpellRank:GetStringWidth());
		MiWowLevelUpSpell:SetWidth(44 + 10 + textWidth);
		MiWowLevelUpSpell:Show();
	else
		MiWowLevelUpHeader:SetText(format(MIWOW_STR_LEVELUP_MORE, item.count));
		MiWowLevelUpHint:SetText(MIWOW_STR_LEVELUP_MORE_HINT);
		MiWowLevelUpHint:Show();
	end

	MiWow_LevelUp.current = item;
	MiWow_LevelUp.elapsed = 0;
	frame:SetAlpha(0);
	frame:Show();
end

local function MiWow_Next()
	local item = table.remove(MiWow_LevelUp.queue, 1);
	if ( item ) then
		MiWow_ShowItem(item);
	else
		MiWow_LevelUp.current = nil;
		frame:Hide();
	end
end

function MiWowLevelUp_OnUpdate(self, delta)
	local data = MiWow_LevelUp;
	local item = data.current;
	if ( not item ) then
		MiWow_Next();
		return;
	end

	data.elapsed = data.elapsed + delta;
	local hold = (item.kind == "level") and data.HOLD_LEVEL or data.HOLD_SPELL;
	local t = data.elapsed;
	if ( t < data.FADE_IN ) then
		self:SetAlpha(t / data.FADE_IN);
	elseif ( t < data.FADE_IN + hold ) then
		self:SetAlpha(1);
	elseif ( t < data.FADE_IN + hold + data.FADE_OUT ) then
		self:SetAlpha(1 - (t - data.FADE_IN - hold) / data.FADE_OUT);
	else
		MiWow_Next();
	end
end

local function MiWow_Push(item)
	tinsert(MiWow_LevelUp.queue, item);
	if ( not MiWow_LevelUp.current ) then
		MiWow_Next();
	end
end

-- Protocolo -------------------------------------------------------------------------------------

-- SPELLS_LEARNED <n> <hechizo>...
MiWow_RegisterHandler("SPELLS_LEARNED", function(fields)
	local count = tonumber(fields[1]) or 0;

	-- Varios rangos del mismo hechizo en una tanda (login, varios niveles de golpe): solo el ultimo
	local items, byName = {}, {};
	for i = 2, count + 1 do
		local spellId = tonumber(fields[i]);
		local name, rank, icon = GetSpellInfo(spellId or 0);
		if ( name ) then
			local item = { kind = "spell", name = name, rank = rank, icon = icon };
			local index = byName[name];
			if ( index ) then
				items[index] = item;
			else
				tinsert(items, item);
				byName[name] = #items;
			end
		end
	end

	local max = MiWow_LevelUp.MAX_SPELLS;
	for i = 1, math.min(#items, max) do
		MiWow_Push(items[i]);
	end
	if ( #items > max ) then
		MiWow_Push({ kind = "more", count = #items - max });
	end
end);

MiWow_CreateFrame();

-- Evento nativo: la subida de nivel (sin habilidades nuevas tambien sale)
frame:RegisterEvent("PLAYER_LEVEL_UP");
frame:SetScript("OnEvent", function(self, event, level)
	if ( event == "PLAYER_LEVEL_UP" ) then
		MiWow_Push({ kind = "level", level = tonumber(level) or UnitLevel("player") });
	end
end);
