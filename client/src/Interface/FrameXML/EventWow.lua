-- EventWow: interfaz dentro del mundo.
-- Archivo propio, cargado el ultimo en FrameXML.toc (todos los marcos y funciones de Blizzard ya existen).
-- Al ser FrameXML (no un addon) su codigo es seguro: puede reparentar marcos protegidos y envolver
-- funciones globales sin propagar taint.
--
-- Modo lobby ("limbo" invisible): el jugador no ve su personaje ni la zona, solo el panel.
--  - Una portada a pantalla completa tapa el mundo y bloquea el raton sobre el (camara, clics).
--  - Barras, marcos de unidad, minimapa, buffs, seguimiento de misiones... se ocultan reparentandolos
--    a un marco oculto (reversible: el codigo de Blizzard puede hacer Show() sin que se vean).
--  - Los atajos de teclado que abren ventanas (hechizos, talentos, bolsas, mapa...) o usan acciones
--    no hacen nada.
--  - Menu de Esc sin "Macros". "Desconectar" vuelve al login (lo gestiona GlueXML/CharacterSelect.lua).
-- Mas adelante el servidor cambiara de modo (minijuego) por el protocolo de addon messages.

EVENTWOW_UI_CONFIG = {
	-- Mismo fondo que las pantallas de Glue (GlueXML/CharacterSelect.lua EVENTWOW_CONFIG)
	BACKGROUND = "Interface\\Glues\\LoadingScreens\\LoadScreenNorthrendWide",
	BACKGROUND_TEXCOORD = { 0, 1, 0, 1 },
	BACKGROUND_SHADE = 0.45,
};

-- Marcos ocultos en el lobby (los hijos van con su padre: MainMenuBar incluye bolsas, micro menu,
-- barra de XP/reputacion, barras de forma/mascota/posesion)
EVENTWOW_LOBBY_HIDDEN_FRAMES = {
	"MainMenuBar",
	"MultiBarBottomLeft",
	"MultiBarBottomRight",
	"MultiBarLeft",
	"MultiBarRight",
	"VehicleMenuBar",
	"PlayerFrame",
	"TargetFrame",
	"FocusFrame",
	"PartyMemberFrame1",
	"PartyMemberFrame2",
	"PartyMemberFrame3",
	"PartyMemberFrame4",
	"MinimapCluster",
	"BuffFrame",
	"TemporaryEnchantFrame",
	"WatchFrame",
	"DurabilityFrame",
	"CastingBarFrame",
};

-- Funciones globales (llamadas desde Bindings.xml / micro menu) que no hacen nada en el lobby
EVENTWOW_LOBBY_BLOCKED_FUNCTIONS = {
	-- Ventanas
	"ToggleBackpack",
	"OpenAllBags",
	"ToggleKeyRing",
	"ToggleBag",
	"ToggleSpellBook",
	"ToggleGlyphFrame",
	"ToggleTalentFrame",
	"ToggleCharacter",
	"TogglePVPFrame",
	"ToggleFriendsFrame",
	"ToggleLFDParentFrame",
	"ToggleLFRParentFrame",
	"ToggleAchievementFrame",
	"ToggleCalendar",
	"ToggleMinimap",
	"ToggleBattlefieldMinimap",
	"ToggleWorldStateScoreFrame",
	-- Acciones (las barras ocultas seguirian respondiendo a sus teclas)
	"ActionButtonDown",
	"ActionButtonUp",
	"MultiActionButtonDown",
	"MultiActionButtonUp",
	"PetActionButtonDown",
	"PetActionButtonUp",
	"ShapeshiftBar_ChangeForm",
};

-- Ventanas que se abren con ToggleFrame(frame) directamente (Bindings.xml): se cierran al mostrarse
EVENTWOW_LOBBY_BLOCKED_PANELS = {
	"QuestLogFrame",
	"WorldMapFrame",
};

EventWow_UI = {
	lobby = false,
	savedParents = {},
};

local hiddenParent = CreateFrame("Frame", "EventWowHiddenParent", UIParent);
hiddenParent:Hide();

local function EventWow_HideFrame(name)
	local frame = _G[name];
	if ( not frame or EventWow_UI.savedParents[name] ) then
		return;
	end
	EventWow_UI.savedParents[name] = { parent = frame:GetParent(), level = frame:GetFrameLevel() };
	frame:SetParent(hiddenParent);
end

local function EventWow_RestoreFrame(name)
	local saved = EventWow_UI.savedParents[name];
	if ( not saved ) then
		return;
	end
	local frame = _G[name];
	frame:SetParent(saved.parent);
	frame:SetFrameLevel(saved.level);
	EventWow_UI.savedParents[name] = nil;
end

local function EventWow_CreateWorldCover()
	-- Hijo de WorldFrame (no de UIParent): sigue tapando el mundo aunque se oculte la UI (Alt+Z)
	local f = CreateFrame("Frame", "EventWowWorldCover", WorldFrame);
	f:SetAllPoints(WorldFrame);
	f:SetFrameStrata("BACKGROUND");
	f:SetFrameLevel(0);
	f:EnableMouse(true);
	f:EnableMouseWheel(true);
	f:SetScript("OnMouseWheel", function() end);

	-- Negro de base (por si la imagen no carga o no cubre todo)
	local base = f:CreateTexture("EventWowWorldCoverBase", "BACKGROUND");
	base:SetAllPoints(f);
	base:SetTexture(0, 0, 0, 1);

	local image = f:CreateTexture("EventWowWorldCoverImage", "BORDER");
	image:SetAllPoints(f);
	if ( image:SetTexture(EVENTWOW_UI_CONFIG.BACKGROUND) ) then
		image:SetTexCoord(unpack(EVENTWOW_UI_CONFIG.BACKGROUND_TEXCOORD));
	else
		image:Hide();
	end

	local shade = f:CreateTexture("EventWowWorldCoverShade", "ARTWORK");
	shade:SetAllPoints(f);
	shade:SetTexture(0, 0, 0, EVENTWOW_UI_CONFIG.BACKGROUND_SHADE);

	f:Hide();
	return f;
end

local function EventWow_WrapBlockedFunctions()
	for _, name in ipairs(EVENTWOW_LOBBY_BLOCKED_FUNCTIONS) do
		local original = _G[name];
		if ( original ) then
			_G[name] = function(...)
				if ( EventWow_UI.lobby ) then
					return;
				end
				return original(...);
			end
		end
	end

	for _, name in ipairs(EVENTWOW_LOBBY_BLOCKED_PANELS) do
		local frame = _G[name];
		if ( frame ) then
			frame:HookScript("OnShow", function(self)
				if ( EventWow_UI.lobby ) then
					self:Hide();
				end
			end);
		end
	end
end

local function EventWow_SetupGameMenu()
	-- Sin "Macros": "Desconectar" sube a su hueco
	GameMenuButtonMacros:Hide();
	GameMenuButtonLogout:SetPoint("TOP", GameMenuButtonKeybindings, "BOTTOM", 0, -1);
	GameMenuButtonRatings:SetPoint("TOP", GameMenuButtonKeybindings, "BOTTOM", 0, -1);
	GameMenuFrame:SetHeight(GameMenuFrame:GetHeight() - GameMenuButtonMacros:GetHeight() - 1);
end

function EventWow_SetLobbyMode(enabled)
	enabled = enabled and true or false;
	if ( EventWow_UI.lobby == enabled ) then
		return;
	end
	EventWow_UI.lobby = enabled;

	for _, name in ipairs(EVENTWOW_LOBBY_HIDDEN_FRAMES) do
		if ( enabled ) then
			EventWow_HideFrame(name);
		else
			EventWow_RestoreFrame(name);
		end
	end

	if ( enabled ) then
		for _, name in ipairs(EVENTWOW_LOBBY_BLOCKED_PANELS) do
			if ( _G[name] ) then
				_G[name]:Hide();
			end
		end
		CloseAllBags();
		EventWowWorldCover:Show();
	else
		EventWowWorldCover:Hide();
	end
end

EventWow_CreateWorldCover();
EventWow_WrapBlockedFunctions();
EventWow_SetupGameMenu();

-- De momento siempre en el lobby (no hay minijuegos todavia)
EventWow_SetLobbyMode(true);
