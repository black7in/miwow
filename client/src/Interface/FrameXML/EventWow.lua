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
-- Modo partida (MATCH_STATE del servidor, EventWowMatch.lua): sin portada ni panel, el mundo visible
-- y solo los marcos de EVENTWOW_MATCH_VISIBLE_FRAMES; las ventanas y acciones siguen bloqueadas.
-- De momento sin chat en partida.

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

-- De los anteriores, los que se ven durante una partida (las barras de accion llegaran con el "disfraz")
EVENTWOW_MATCH_VISIBLE_FRAMES = {
	PlayerFrame = true,
	TargetFrame = true,
	BuffFrame = true,
	CastingBarFrame = true,
};

-- Funciones globales (llamadas desde Bindings.xml / micro menu) que no hacen nada en el lobby ni en partida
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

EVENTWOW_STR_DEV_SHOW_PANEL = "Mostrar panel";
EVENTWOW_STR_DEV_ONLY = "Solo en modo dev (.gm on o .dev on).";

EventWow_UI = {
	-- "lobby" | "match" (nil antes de inicializar)
	mode = nil,
	-- Modo dev (.gm on o .dev on, lo avisa el servidor con DEV_MODE): permite ocultar el panel
	dev = false,
	-- Panel oculto: interfaz nativa sin restricciones (solo en modo dev; no toca ningun flag)
	panelHidden = false,
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

-- Interfaz nativa sin restricciones: modo dev + panel oculto
function EventWow_IsUnrestricted()
	return EventWow_UI.dev and EventWow_UI.panelHidden;
end

-- Ventanas y acciones bloqueadas (lobby y partida, salvo con el panel oculto en modo dev)
function EventWow_IsRestricted()
	return EventWow_UI.mode ~= nil and not EventWow_IsUnrestricted();
end

local function EventWow_WrapBlockedFunctions()
	for _, name in ipairs(EVENTWOW_LOBBY_BLOCKED_FUNCTIONS) do
		local original = _G[name];
		if ( original ) then
			_G[name] = function(...)
				if ( EventWow_IsRestricted() ) then
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
				if ( EventWow_IsRestricted() ) then
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

-- Aplica el modo actual: EventWow_UI.mode ("lobby" | "match") + panel oculto en modo dev
local function EventWow_ApplyMode()
	local mode, dev = EventWow_UI.mode, EventWow_IsUnrestricted();
	local lobby = mode == "lobby" and not dev;

	for _, name in ipairs(EVENTWOW_LOBBY_HIDDEN_FRAMES) do
		if ( dev or (mode == "match" and EVENTWOW_MATCH_VISIBLE_FRAMES[name]) ) then
			EventWow_RestoreFrame(name);
		else
			EventWow_HideFrame(name);
		end
	end

	if ( not dev ) then
		for _, name in ipairs(EVENTWOW_LOBBY_BLOCKED_PANELS) do
			if ( _G[name] ) then
				_G[name]:Hide();
			end
		end
		CloseAllBags();
	end

	if ( lobby ) then
		EventWowWorldCover:Show();
		EventWowPanel:Show();
	else
		EventWowWorldCover:Hide();
		EventWowPanel:Hide();
	end

	EventWowChat_SetNativeVisible(dev);
	if ( dev ) then
		EventWowDevButton:Show();
	else
		EventWowDevButton:Hide();
	end
end

-- mode: "lobby" (portada + panel) o "match" (mundo visible + HUD de EventWowMatch.lua)
function EventWow_SetMode(mode)
	if ( EventWow_UI.mode == mode ) then
		return;
	end
	EventWow_UI.mode = mode;
	EventWow_ApplyMode();
end

-- Compatibilidad
function EventWow_SetLobbyMode(enabled)
	EventWow_SetMode(enabled and "lobby" or "match");
end

-- Modo dev (DEV_MODE del servidor). Al salir de el, el panel vuelve siempre.
function EventWow_SetDevMode(enabled)
	enabled = enabled and true or false;
	if ( EventWow_UI.dev == enabled ) then
		return;
	end
	EventWow_UI.dev = enabled;
	if ( not enabled ) then
		EventWow_UI.panelHidden = false;
	end
	EventWow_ApplyMode();
	EventWow_FireListeners("DEV_MODE");
end

-- Ocultar / mostrar el panel (solo en modo dev; solo cliente)
function EventWow_SetPanelHidden(hidden)
	hidden = hidden and EventWow_UI.dev and true or false;
	if ( EventWow_UI.panelHidden == hidden ) then
		return;
	end
	EventWow_UI.panelHidden = hidden;
	EventWow_ApplyMode();
end

-- Boton flotante con el panel oculto para volver a mostrarlo
local function EventWow_CreateDevButton()
	local button = CreateFrame("Button", "EventWowDevButton", UIParent, "UIPanelButtonTemplate");
	button:SetSize(150, 22);
	button:SetPoint("TOP", UIParent, "TOP", 0, -2);
	button:SetFrameStrata("HIGH");
	button:SetText(EVENTWOW_STR_DEV_SHOW_PANEL);
	button:SetScript("OnClick", function()
		EventWow_SetPanelHidden(false);
	end);
	button:Hide();
end

-- DEV_MODE <0|1>: .gm on o .dev on
EventWow_RegisterHandler("DEV_MODE", function(fields)
	EventWow_SetDevMode(fields[1] == "1");
end);

-- /eventwow: ocultar / mostrar el panel (modo dev)
SLASH_EVENTWOW1 = "/eventwow";
SlashCmdList["EVENTWOW"] = function()
	if ( EventWow_UI.dev ) then
		EventWow_SetPanelHidden(not EventWow_UI.panelHidden);
	else
		DEFAULT_CHAT_FRAME:AddMessage(EVENTWOW_STR_DEV_ONLY, 1, 0.2, 0.2);
	end
end

EventWow_CreateWorldCover();
EventWow_CreateDevButton();
EventWow_WrapBlockedFunctions();
EventWow_SetupGameMenu();

-- Se empieza en el lobby; el servidor cambia de modo con MATCH_STATE (EventWowMatch.lua)
EventWow_SetMode("lobby");
