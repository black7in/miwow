-- MiWow: interfaz dentro del mundo (servidor tradicional + eventos).
-- Archivo propio, cargado el ultimo en FrameXML.toc (todos los marcos y funciones de Blizzard ya existen).
-- Al ser FrameXML (no un addon) su codigo es seguro: puede reparentar marcos protegidos y envolver
-- funciones globales sin propagar taint.
--
-- Modo "world" (fuera de los eventos): la interfaz nativa queda INTACTA. El panel de eventos (MiWowPanel.lua) es
-- una ventana que se abre y cierra con el boton del minimapa, /miwow o Esc.
-- Modo "match" (MATCH_STATE del servidor, MiWowMatch.lua): mundo + HUD de la partida; de la interfaz nativa solo
-- se ven los marcos de MIWOW_MATCH_VISIBLE_FRAMES y el chat; ventanas, bolsas y barras de accion nativas
-- bloqueadas (cada juego da lo suyo: p. ej. la barra de la moto). Al salir todo vuelve a su sitio (los marcos se reparentan, no se destruyen).
-- Modo dev (.gm on o .dev on): en partida, "/miwow dev" o el boton de arriba quitan las restricciones (solo cliente,
-- no toca ningun flag).

-- Marcos ocultos en partida (los hijos van con su padre: MainMenuBar incluye bolsas, micro menu,
-- barra de XP/reputacion, barras de forma/mascota/posesion)
MIWOW_MATCH_HIDDEN_FRAMES = {
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
MIWOW_MINIMAP_HIDDEN_BUTTONS = {
	"MiniMapTracking",
	"GameTimeFrame",
	"MiniMapMailFrame",
	"MiniMapLFGFrame",
	"MiniMapBattlefieldFrame",
	"MiniMapWorldMapButton",
	"MiniMapVoiceChatFrame",
	"MiniMapInstanceDifficulty",
	"MiWowMinimapButton",
};

-- De MIWOW_MATCH_HIDDEN_FRAMES, los que se ven durante una partida
MIWOW_MATCH_VISIBLE_FRAMES = {
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
MIWOW_MATCH_BLOCKED_FUNCTIONS = {
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
MIWOW_MATCH_BLOCKED_PANELS = {
	"QuestLogFrame",
	"WorldMapFrame",
};

MIWOW_STR_DEV_NATIVE_ON = "Interfaz nativa";
MIWOW_STR_DEV_NATIVE_OFF = "Interfaz de partida";
MIWOW_STR_DEV_ONLY = "Solo en modo dev (.gm on o .dev on).";

MiWow_UI = {
	-- "world" | "match"
	mode = "world",
	-- Modo dev (.gm on o .dev on, lo avisa el servidor con DEV_MODE)
	dev = false,
	-- En partida y en modo dev: interfaz nativa sin restricciones (solo cliente; no toca ningun flag)
	native = false,
	savedParents = {},
};

local hiddenParent = CreateFrame("Frame", "MiWowHiddenParent", UIParent);
hiddenParent:Hide();

local function MiWow_HideFrame(name)
	local frame = _G[name];
	if ( not frame or MiWow_UI.savedParents[name] ) then
		return;
	end
	MiWow_UI.savedParents[name] = { parent = frame:GetParent(), level = frame:GetFrameLevel() };
	frame:SetParent(hiddenParent);
end

local function MiWow_RestoreFrame(name)
	local saved = MiWow_UI.savedParents[name];
	if ( not saved ) then
		return;
	end
	local frame = _G[name];
	frame:SetParent(saved.parent);
	frame:SetFrameLevel(saved.level);
	MiWow_UI.savedParents[name] = nil;
end

-- Interfaz nativa sin restricciones en partida: modo dev + "Interfaz nativa"
function MiWow_IsUnrestricted()
	return MiWow_UI.dev and MiWow_UI.native;
end

-- Ventanas y acciones nativas bloqueadas: solo en partida (salvo modo dev con la interfaz nativa)
function MiWow_IsRestricted()
	return MiWow_UI.mode == "match" and not MiWow_IsUnrestricted();
end

-- Teclas 1-6 en vehiculo: ActionButtonDown/Up(id) pulsan VehicleMenuBarActionButton<id> si la barra se ve
MIWOW_VEHICLE_ACTION_FUNCTIONS = {
	ActionButtonDown = true,
	ActionButtonUp = true,
};

local function MiWow_IsVehicleAction(name, id)
	return MIWOW_VEHICLE_ACTION_FUNCTIONS[name] and MiWow_UI.mode == "match" and VehicleMenuBar:IsVisible()
		and type(id) == "number" and id <= VEHICLE_MAX_ACTIONBUTTONS;
end

local function MiWow_WrapBlockedFunctions()
	for _, name in ipairs(MIWOW_MATCH_BLOCKED_FUNCTIONS) do
		local original = _G[name];
		if ( original ) then
			local functionName = name;
			_G[name] = function(...)
				if ( MiWow_IsRestricted() and not MiWow_IsVehicleAction(functionName, ...) ) then
					return;
				end
				return original(...);
			end
		end
	end

	-- En partida el servidor vuelve a subir al vehiculo a quien se baja (MiWowDisguise): sin boton de bajarse
	VehicleMenuBarLeaveButton:HookScript("OnShow", function(self)
		if ( MiWow_IsRestricted() ) then
			self:Hide();
		end
	end);

	for _, name in ipairs(MIWOW_MATCH_BLOCKED_PANELS) do
		local frame = _G[name];
		if ( frame ) then
			frame:HookScript("OnShow", function(self)
				if ( MiWow_IsRestricted() ) then
					self:Hide();
				end
			end);
		end
	end
end

-- Barra de mascota nativa (PetActionBarFrame, hija de MainMenuBar): en partida MainMenuBar esta oculta, asi que
-- se cuelga de un marco propio centrado abajo (mascotas e invocaciones controlables).
-- La barra se coloca sola en TOPLEFT de su padre + (PETACTIONBAR_XPOS, PETACTIONBAR_YPOS).
MIWOW_PET_BAR = {
	WIDTH = 509,  -- tamano de PetActionBarFrame (PetActionBarFrame.xml)
	HEIGHT = 43,
	BOTTOM = 104, -- borde inferior de la barra, desde abajo de la pantalla
};

local function MiWow_AnchorPetBarHolder()
	local holder = MiWowPetBarHolder;
	holder:ClearAllPoints();
	holder:SetPoint("BOTTOMLEFT", UIParent, "BOTTOM",
		-MIWOW_PET_BAR.WIDTH / 2 - PETACTIONBAR_XPOS,
		MIWOW_PET_BAR.BOTTOM + MIWOW_PET_BAR.HEIGHT - PETACTIONBAR_YPOS);
end

local function MiWow_CreatePetBarHolder()
	local holder = CreateFrame("Frame", "MiWowPetBarHolder", UIParent);
	holder:SetSize(1, 1);
	MiWow_AnchorPetBarHolder();
	-- PETACTIONBAR_XPOS cambia con las formas/barras: se recoloca
	hooksecurefunc("PetActionBar_UpdatePositionValues", MiWow_AnchorPetBarHolder);
end

local function MiWow_ApplyPetBar(match)
	-- Contiene botones seguros: no se puede reparentar en combate (el modo cambia fuera de combate)
	if ( InCombatLockdown() ) then
		return;
	end
	local parent = match and MiWowPetBarHolder or MainMenuBar;
	if ( PetActionBarFrame:GetParent() ~= parent ) then
		PetActionBarFrame:SetParent(parent);
		PetActionBarFrame:ClearAllPoints();
		PetActionBarFrame:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", PETACTIONBAR_XPOS, PETACTIONBAR_YPOS);
	end
end

-- Aplica el modo actual: MiWow_UI.mode ("world" | "match") + interfaz nativa en modo dev
local function MiWow_ApplyMode()
	local match = MiWow_UI.mode == "match";
	local restricted = MiWow_IsRestricted();

	for _, name in ipairs(MIWOW_MATCH_HIDDEN_FRAMES) do
		if ( restricted and not MIWOW_MATCH_VISIBLE_FRAMES[name] ) then
			MiWow_HideFrame(name);
		else
			MiWow_RestoreFrame(name);
		end
	end

	for _, name in ipairs(MIWOW_MINIMAP_HIDDEN_BUTTONS) do
		if ( restricted ) then
			MiWow_HideFrame(name);
		else
			MiWow_RestoreFrame(name);
		end
	end

	if ( restricted ) then
		for _, name in ipairs(MIWOW_MATCH_BLOCKED_PANELS) do
			if ( _G[name] ) then
				_G[name]:Hide();
			end
		end
		CloseAllBags();
	end

	-- El panel de eventos no se usa dentro de una partida
	if ( match ) then
		MiWowPanel:Hide();
	end

	MiWow_ApplyPetBar(restricted);

	if ( match and MiWow_UI.dev ) then
		MiWowDevButton:SetText(MiWow_UI.native and MIWOW_STR_DEV_NATIVE_OFF or MIWOW_STR_DEV_NATIVE_ON);
		MiWowDevButton:Show();
	else
		MiWowDevButton:Hide();
	end
end

-- mode: "world" (interfaz nativa) o "match" (HUD de MiWowMatch.lua)
function MiWow_SetMode(mode)
	if ( MiWow_UI.mode == mode ) then
		return;
	end
	MiWow_UI.mode = mode;
	MiWow_ApplyMode();
end

-- Modo dev (DEV_MODE del servidor). Al salir de el vuelven las restricciones de partida.
function MiWow_SetDevMode(enabled)
	enabled = enabled and true or false;
	if ( MiWow_UI.dev == enabled ) then
		return;
	end
	MiWow_UI.dev = enabled;
	if ( not enabled ) then
		MiWow_UI.native = false;
	end
	MiWow_ApplyMode();
	MiWow_FireListeners("DEV_MODE");
end

-- Interfaz nativa sin restricciones en partida (solo en modo dev; solo cliente)
function MiWow_SetNativeUI(native)
	native = native and MiWow_UI.dev and true or false;
	if ( MiWow_UI.native == native ) then
		return;
	end
	MiWow_UI.native = native;
	MiWow_ApplyMode();
end

-- Boton flotante en partida (modo dev): interfaz nativa <-> interfaz de partida
local function MiWow_CreateDevButton()
	local button = CreateFrame("Button", "MiWowDevButton", UIParent, "UIPanelButtonTemplate");
	button:SetSize(150, 22);
	button:SetPoint("TOP", UIParent, "TOP", 0, -2);
	button:SetFrameStrata("HIGH");
	button:SetScript("OnClick", function()
		MiWow_SetNativeUI(not MiWow_UI.native);
	end);
	button:Hide();
end

-- DEV_MODE <0|1>: .gm on o .dev on
MiWow_RegisterHandler("DEV_MODE", function(fields)
	MiWow_SetDevMode(fields[1] == "1");
end);

-- /miwow: abrir / cerrar el panel de eventos | /miwow dev: interfaz nativa en partida (modo dev)
SLASH_MIWOW1 = "/miwow";
SLASH_MIWOW2 = "/eventos";
SlashCmdList["MIWOW"] = function(msg)
	msg = string.lower(strtrim(msg or ""));
	if ( msg == "dev" ) then
		if ( MiWow_UI.dev ) then
			MiWow_SetNativeUI(not MiWow_UI.native);
		else
			DEFAULT_CHAT_FRAME:AddMessage(MIWOW_STR_DEV_ONLY, 1, 0.2, 0.2);
		end
		return;
	end
	MiWowPanel_Toggle();
end

MiWow_CreateDevButton();
MiWow_CreatePetBarHolder();
MiWow_WrapBlockedFunctions();
