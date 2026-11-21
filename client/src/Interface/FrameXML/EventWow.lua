-- EventWow: interfaz dentro del mundo (servidor tradicional + eventos).
-- Archivo propio, cargado el ultimo en FrameXML.toc (todos los marcos y funciones de Blizzard ya existen).
-- Al ser FrameXML (no un addon) su codigo es seguro: puede reparentar marcos protegidos y envolver
-- funciones globales sin propagar taint.
--
-- Modo "world" (fuera de los eventos): la interfaz nativa queda INTACTA. El panel de eventos (EventWowPanel.lua) es
-- una ventana que se abre y cierra con el boton del minimapa, /eventwow o Esc.
-- Modo "match" (MATCH_STATE del servidor, EventWowMatch.lua): mundo + HUD de la partida; de la interfaz nativa solo
-- se ven los marcos de EVENTWOW_MATCH_VISIBLE_FRAMES y el chat; ventanas, bolsas y barras de accion nativas
-- bloqueadas (cada juego da lo suyo: p. ej. la barra de la moto). Al salir todo vuelve a su sitio (los marcos se reparentan, no se destruyen).
-- Modo dev (.gm on o .dev on): en partida, "/eventwow dev" o el boton de arriba quitan las restricciones (solo cliente,
-- no toca ningun flag).

-- Marcos ocultos en partida (los hijos van con su padre: MainMenuBar incluye bolsas, micro menu,
-- barra de XP/reputacion, barras de forma/mascota/posesion)
EVENTWOW_MATCH_HIDDEN_FRAMES = {
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

-- Botones del minimapa ocultos en partida (se reparentan porque algunos se muestran solos: correo, cola de BG/mazmorra).
-- Se dejan el zoom y el nombre de zona.
EVENTWOW_MINIMAP_HIDDEN_BUTTONS = {
	"MiniMapTracking",
	"GameTimeFrame",
	"MiniMapMailFrame",
	"MiniMapLFGFrame",
	"MiniMapBattlefieldFrame",
	"MiniMapWorldMapButton",
	"MiniMapVoiceChatFrame",
	"MiniMapInstanceDifficulty",
	"EventWowMinimapButton",
};

-- De EVENTWOW_MATCH_HIDDEN_FRAMES, los que se ven durante una partida
EVENTWOW_MATCH_VISIBLE_FRAMES = {
	PlayerFrame = true,
	TargetFrame = true,
	BuffFrame = true,
	CastingBarFrame = true,
	-- Minimapa y nombre de la zona (mapas propios: AreaTable + minimapas de tools/mapgen); sin sus botones
	MinimapCluster = true,
	-- Barra nativa de vehiculo (juegos con vehiculo; el motor la muestra solo al montar). Sin boton de bajarse.
	VehicleMenuBar = true,
	-- Marcos de grupo nativos (solo se ven con grupo)
	PartyMemberFrame1 = true,
	PartyMemberFrame2 = true,
	PartyMemberFrame3 = true,
	PartyMemberFrame4 = true,
};

-- Funciones globales (llamadas desde Bindings.xml / micro menu) que no hacen nada en partida
EVENTWOW_MATCH_BLOCKED_FUNCTIONS = {
	-- Ventanas (tambien las bolsas; OpenBackpack lo llama la ventana del vendedor)
	"ToggleBackpack",
	"OpenBackpack",
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

-- Ventanas que se abren con ToggleFrame(frame) directamente (Bindings.xml): en partida se cierran al mostrarse
EVENTWOW_MATCH_BLOCKED_PANELS = {
	"QuestLogFrame",
	"WorldMapFrame",
};

EVENTWOW_STR_DEV_NATIVE_ON = "Interfaz nativa";
EVENTWOW_STR_DEV_NATIVE_OFF = "Interfaz de partida";
EVENTWOW_STR_DEV_ONLY = "Solo en modo dev (.gm on o .dev on).";

EventWow_UI = {
	-- "world" | "match"
	mode = "world",
	-- Modo dev (.gm on o .dev on, lo avisa el servidor con DEV_MODE)
	dev = false,
	-- En partida y en modo dev: interfaz nativa sin restricciones (solo cliente; no toca ningun flag)
	native = false,
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

-- Interfaz nativa sin restricciones en partida: modo dev + "Interfaz nativa"
function EventWow_IsUnrestricted()
	return EventWow_UI.dev and EventWow_UI.native;
end

-- Ventanas y acciones nativas bloqueadas: solo en partida (salvo modo dev con la interfaz nativa)
function EventWow_IsRestricted()
	return EventWow_UI.mode == "match" and not EventWow_IsUnrestricted();
end

-- Teclas 1-6 en vehiculo: ActionButtonDown/Up(id) pulsan VehicleMenuBarActionButton<id> si la barra se ve
EVENTWOW_VEHICLE_ACTION_FUNCTIONS = {
	ActionButtonDown = true,
	ActionButtonUp = true,
};

local function EventWow_IsVehicleAction(name, id)
	return EVENTWOW_VEHICLE_ACTION_FUNCTIONS[name] and EventWow_UI.mode == "match" and VehicleMenuBar:IsVisible()
		and type(id) == "number" and id <= VEHICLE_MAX_ACTIONBUTTONS;
end

local function EventWow_WrapBlockedFunctions()
	for _, name in ipairs(EVENTWOW_MATCH_BLOCKED_FUNCTIONS) do
		local original = _G[name];
		if ( original ) then
			local functionName = name;
			_G[name] = function(...)
				if ( EventWow_IsRestricted() and not EventWow_IsVehicleAction(functionName, ...) ) then
					return;
				end
				return original(...);
			end
		end
	end

	-- En partida el servidor vuelve a subir al vehiculo a quien se baja (EventWowDisguise): sin boton de bajarse
	VehicleMenuBarLeaveButton:HookScript("OnShow", function(self)
		if ( EventWow_IsRestricted() ) then
			self:Hide();
		end
	end);

	for _, name in ipairs(EVENTWOW_MATCH_BLOCKED_PANELS) do
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

-- Barra de mascota nativa (PetActionBarFrame, hija de MainMenuBar): en partida MainMenuBar esta oculta, asi que
-- se cuelga de un marco propio centrado abajo (mascotas e invocaciones controlables).
-- La barra se coloca sola en TOPLEFT de su padre + (PETACTIONBAR_XPOS, PETACTIONBAR_YPOS).
EVENTWOW_PET_BAR = {
	WIDTH = 509,  -- tamano de PetActionBarFrame (PetActionBarFrame.xml)
	HEIGHT = 43,
	BOTTOM = 104, -- borde inferior de la barra, desde abajo de la pantalla
};

local function EventWow_AnchorPetBarHolder()
	local holder = EventWowPetBarHolder;
	holder:ClearAllPoints();
	holder:SetPoint("BOTTOMLEFT", UIParent, "BOTTOM",
		-EVENTWOW_PET_BAR.WIDTH / 2 - PETACTIONBAR_XPOS,
		EVENTWOW_PET_BAR.BOTTOM + EVENTWOW_PET_BAR.HEIGHT - PETACTIONBAR_YPOS);
end

local function EventWow_CreatePetBarHolder()
	local holder = CreateFrame("Frame", "EventWowPetBarHolder", UIParent);
	holder:SetSize(1, 1);
	EventWow_AnchorPetBarHolder();
	-- PETACTIONBAR_XPOS cambia con las formas/barras: se recoloca
	hooksecurefunc("PetActionBar_UpdatePositionValues", EventWow_AnchorPetBarHolder);
end

local function EventWow_ApplyPetBar(match)
	-- Contiene botones seguros: no se puede reparentar en combate (el modo cambia fuera de combate)
	if ( InCombatLockdown() ) then
		return;
	end
	local parent = match and EventWowPetBarHolder or MainMenuBar;
	if ( PetActionBarFrame:GetParent() ~= parent ) then
		PetActionBarFrame:SetParent(parent);
		PetActionBarFrame:ClearAllPoints();
		PetActionBarFrame:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", PETACTIONBAR_XPOS, PETACTIONBAR_YPOS);
	end
end

-- Aplica el modo actual: EventWow_UI.mode ("world" | "match") + interfaz nativa en modo dev
local function EventWow_ApplyMode()
	local match = EventWow_UI.mode == "match";
	local restricted = EventWow_IsRestricted();

	for _, name in ipairs(EVENTWOW_MATCH_HIDDEN_FRAMES) do
		if ( restricted and not EVENTWOW_MATCH_VISIBLE_FRAMES[name] ) then
			EventWow_HideFrame(name);
		else
			EventWow_RestoreFrame(name);
		end
	end

	for _, name in ipairs(EVENTWOW_MINIMAP_HIDDEN_BUTTONS) do
		if ( restricted ) then
			EventWow_HideFrame(name);
		else
			EventWow_RestoreFrame(name);
		end
	end

	if ( restricted ) then
		for _, name in ipairs(EVENTWOW_MATCH_BLOCKED_PANELS) do
			if ( _G[name] ) then
				_G[name]:Hide();
			end
		end
		CloseAllBags();
	end

	-- El panel de eventos no se usa dentro de una partida
	if ( match ) then
		EventWowPanel:Hide();
	end

	EventWow_ApplyPetBar(restricted);

	if ( match and EventWow_UI.dev ) then
		EventWowDevButton:SetText(EventWow_UI.native and EVENTWOW_STR_DEV_NATIVE_OFF or EVENTWOW_STR_DEV_NATIVE_ON);
		EventWowDevButton:Show();
	else
		EventWowDevButton:Hide();
	end
end

-- mode: "world" (interfaz nativa) o "match" (HUD de EventWowMatch.lua)
function EventWow_SetMode(mode)
	if ( EventWow_UI.mode == mode ) then
		return;
	end
	EventWow_UI.mode = mode;
	EventWow_ApplyMode();
end

-- Modo dev (DEV_MODE del servidor). Al salir de el vuelven las restricciones de partida.
function EventWow_SetDevMode(enabled)
	enabled = enabled and true or false;
	if ( EventWow_UI.dev == enabled ) then
		return;
	end
	EventWow_UI.dev = enabled;
	if ( not enabled ) then
		EventWow_UI.native = false;
	end
	EventWow_ApplyMode();
	EventWow_FireListeners("DEV_MODE");
end

-- Interfaz nativa sin restricciones en partida (solo en modo dev; solo cliente)
function EventWow_SetNativeUI(native)
	native = native and EventWow_UI.dev and true or false;
	if ( EventWow_UI.native == native ) then
		return;
	end
	EventWow_UI.native = native;
	EventWow_ApplyMode();
end

-- Boton flotante en partida (modo dev): interfaz nativa <-> interfaz de partida
local function EventWow_CreateDevButton()
	local button = CreateFrame("Button", "EventWowDevButton", UIParent, "UIPanelButtonTemplate");
	button:SetSize(150, 22);
	button:SetPoint("TOP", UIParent, "TOP", 0, -2);
	button:SetFrameStrata("HIGH");
	button:SetScript("OnClick", function()
		EventWow_SetNativeUI(not EventWow_UI.native);
	end);
	button:Hide();
end

-- DEV_MODE <0|1>: .gm on o .dev on
EventWow_RegisterHandler("DEV_MODE", function(fields)
	EventWow_SetDevMode(fields[1] == "1");
end);

-- /eventwow: abrir / cerrar el panel de eventos | /eventwow dev: interfaz nativa en partida (modo dev)
SLASH_EVENTWOW1 = "/eventwow";
SLASH_EVENTWOW2 = "/eventos";
SlashCmdList["EVENTWOW"] = function(msg)
	msg = string.lower(strtrim(msg or ""));
	if ( msg == "dev" ) then
		if ( EventWow_UI.dev ) then
			EventWow_SetNativeUI(not EventWow_UI.native);
		else
			DEFAULT_CHAT_FRAME:AddMessage(EVENTWOW_STR_DEV_ONLY, 1, 0.2, 0.2);
		end
		return;
	end
	EventWowPanel_Toggle();
end

EventWow_CreateDevButton();
EventWow_CreatePetBarHolder();
EventWow_WrapBlockedFunctions();
