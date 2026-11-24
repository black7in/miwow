-- MiWow: aspecto propio del HUD tactil del cliente web. La logica (zonas tactiles, joystick, arco, gestos) es la de
-- Last Havens, incrustada en el wasm; aqui solo se cambian texturas. Texturas: tools\touchui\gen_touchui.py.
-- - Anillo de todos los botones: lo cargan ellos de Interface\TouchUI\DragonUI\forever_circle_lh (el nuestro va en
--   el parche, junto con PadDisc).
-- - Fondo de huecos vacios y joystick: usaban Interface\Minimap\UI-Minimap-Background (no se puede sustituir el
--   archivo sin cambiar el minimapa) -> se cambia la textura en sus marcos.
-- - Botones fijos (saltar, boton inteligente, objetivo amigo, correr, montar, sentarse, ajustes, edicion, flechas del
--   vehiculo): pictogramas dorados propios sobre el disco, elegidos por el usuario (2026-11-22). Los iconos de
--   hechizos, objetos y monturas reales se quedan como estan.
-- En el cliente de PC no hace nada (no existe la CVar webTouch ni el HUD).

local DIR = "Interface\\TouchUI\\MiWow\\";
local DISC, WELL, KNOB = DIR .. "disc", DIR .. "well", DIR .. "knob";

-- Icono de WoW que ponen sus botones -> nuestro pictograma (tabla SMART y ThumbButton de 18_WebTouchSecure)
local MIWOW_TOUCH_GLYPHS = {
	["interface\\icons\\ability_heroicleap"] = "jump",
	["interface\\icons\\ability_hunter_snipershot"] = "s_target",
	["interface\\icons\\ability_steelmelee"] = "s_attack",
	["interface\\icons\\inv_misc_bag_08"] = "s_loot",
	["interface\\icons\\inv_misc_pelt_wolf_01"] = "s_skin",
	["interface\\gossipframe\\gossipgossipicon"] = "s_talk",
	["interface\\icons\\trade_herbalism"] = "s_herb",
	["interface\\icons\\trade_mining"] = "s_ore",
	["interface\\icons\\inv_box_02"] = "s_open",
	["interface\\icons\\inv_letter_15"] = "s_mail",
	["interface\\icons\\trade_fishing"] = "s_fish",
	["interface\\icons\\inv_misc_gear_01"] = "s_use",          -- tambien ajustes (setup y cajon)
	["interface\\vehicles\\ui-vehicles-button-exit-up"] = "s_leave",
	["interface\\icons\\spell_holy_heal"] = "u_friend",
	["interface\\icons\\ability_rogue_sprint"] = "u_run",      -- cajon, aviso del joystick y bola con correr automatico
	["interface\\icons\\ability_mount_ridinghorse"] = "u_mount", -- sin montura elegida (con montura: su icono real)
	["interface\\icons\\spell_nature_sleep"] = "u_sit",
	["interface\\icons\\inv_misc_wrench_01"] = "u_edit",
	["interface\\icons\\misc_arrowup"] = "u_up",
	["interface\\icons\\misc_arrowdown"] = "u_down",
};

local function MiWowTouch_IsWeb()
	return GetCVar("webTouch") == "1";
end

local function MiWowTouch_GlyphFor(path)
	return type(path) == "string" and MIWOW_TOUCH_GLYPHS[string.lower(path)] or nil;
end

local function MiWowTouch_IsDiscPath(path)
	return type(path) == "string" and string.find(string.lower(path), "ui%-minimap%-background") ~= nil;
end

-- Pictograma encima del fondo "tex" de "owner" (nil = quitarlo). El tamano sale del marco (sus botones: 36, fijado
-- por ellos), no de la textura (las texturas con SetAllPoints aun no tienen tamano al montarse).
local function MiWowTouch_SetGlyph(owner, tex, name)
	local glyph = owner.miwowGlyph;
	if ( not name ) then
		if ( glyph ) then
			glyph:Hide();
		end
		return;
	end
	tex:SetTexture(DISC);
	if ( not glyph ) then
		glyph = owner:CreateTexture(nil, "OVERLAY");
		owner.miwowGlyph = glyph;
		local size = (owner:GetWidth() or 36) * 0.72;
		glyph:SetWidth(size);
		glyph:SetHeight(size);
		glyph:SetPoint("CENTER", owner, "CENTER", 0, 0);
	end
	glyph:SetTexture(DIR .. name);
	glyph:Show();
end

-- Sus botones ponen el icono con SetPortraitToTexture (b:SetIcon, tambien al construirse: este archivo carga antes
-- que su HUD). Solo actua sobre sus botones (campo SetIcon) o marcos marcados con miwowSkin (bola del joystick).
local MiWowTouch_OrigPortrait = SetPortraitToTexture;
function SetPortraitToTexture(tex, path, ...)
	if ( type(tex) == "table" and tex.GetParent and MiWowTouch_IsWeb() ) then
		local owner = tex:GetParent();
		if ( owner and (owner.SetIcon or owner.miwowSkin) ) then
			local name = MiWowTouch_GlyphFor(path);
			MiWowTouch_SetGlyph(owner, tex, name);
			if ( name ) then
				return;
			end
		end
	end
	return MiWowTouch_OrigPortrait(tex, path, ...);
end

-- Fondo de minimapa -> nuestro disco, en todas las texturas de un marco y sus hijos
local function MiWowTouch_Sweep(frame)
	for _, region in ipairs({ frame:GetRegions() }) do
		if ( region:GetObjectType() == "Texture" and MiWowTouch_IsDiscPath(region:GetTexture()) ) then
			region:SetTexture(DISC);
		end
	end
	for _, child in ipairs({ frame:GetChildren() }) do
		MiWowTouch_Sweep(child);
	end
end

local function MiWowTouch_SkinStick(stick)
	if ( not stick ) then
		return;
	end
	for _, region in ipairs({ stick:GetRegions() }) do
		if ( region:GetObjectType() == "Texture" and MiWowTouch_IsDiscPath(region:GetTexture()) ) then
			region:SetTexture(WELL);    -- la base (la bola esta en un marco hijo)
		end
	end
	local fill = stick.knobFill;
	if ( not fill ) then
		return;
	end
	-- Con correr automatico ponen el icono de Carrera en la bola (-> disco + u_run, por SetPortraitToTexture);
	-- al quitarlo, el fondo del minimapa -> nuestra bola sin icono
	local knob = fill:GetParent();
	knob.miwowSkin = true;
	local busy = false;
	local function Fix(self, path)
		if ( not busy and MiWowTouch_IsDiscPath(path) ) then
			busy = true;
			self:SetTexture(KNOB);
			busy = false;
			MiWowTouch_SetGlyph(knob, self, nil);
		end
	end
	hooksecurefunc(fill, "SetTexture", Fix);
	Fix(fill, fill:GetTexture());
end

-- Boton inteligente: el estado "hablar" no pasa por SetPortraitToTexture (su SetIcon pone su propio glyph de
-- GossipFrame sobre el fondo del minimapa) -> se envuelve su SetIcon para cambiarlo por el nuestro.
local function MiWowTouch_SkinSmart(smart)
	if ( not smart or not smart.SetIcon or not smart.icon ) then
		return;
	end
	local orig = smart.SetIcon;
	smart.SetIcon = function(self, icon)
		orig(self, icon);
		local name = MiWowTouch_GlyphFor(icon);
		if ( name and self.glyph and self.glyph:IsShown() ) then
			self.glyph:Hide();
			MiWowTouch_SetGlyph(self, self.icon, name);
		end
	end;
	if ( LasthavensTouchSmartIcon ) then
		smart:SetIcon(LasthavensTouchSmartIcon() or "Interface\\Icons\\Ability_Hunter_SniperShot");
	end
end

-- Boton redondo propio (disco + pictograma + anillo) encima de un boton suyo o de Blizzard cuyo dibujo se oculta.
-- d = diametro; ox, oy = desplazamiento del centro (su arte de minimapa no esta centrado en el boton).
-- El anillo se dibuja sin SetTexCoord: la textura ocupa el 75 % del cuadro de ellos -> 58/36 * 0.75 = 1.208 d.
local function MiWowTouch_Overlay(frame, glyph, d, ox, oy)
	local o = frame.miwowOverlay;
	if ( not o ) then
		o = {};
		o.disc = frame:CreateTexture(nil, "BACKGROUND");
		o.disc:SetTexture(DISC);
		o.glyph = frame:CreateTexture(nil, "OVERLAY");
		o.ring = frame:CreateTexture(nil, "OVERLAY");
		o.ring:SetTexture("Interface\\TouchUI\\DragonUI\\forever_circle_lh");
		frame.miwowOverlay = o;
	end
	for tex, k in pairs({ [o.disc] = 1, [o.glyph] = 0.72, [o.ring] = 1.208 }) do
		tex:SetWidth(d * k);
		tex:SetHeight(d * k);
		tex:ClearAllPoints();
		tex:SetPoint("CENTER", frame, "CENTER", ox or 0, oy or 0);
	end
	o.glyph:SetTexture(DIR .. glyph);
	return o;
end

-- Como MiWowTouch_Overlay pero con un icono ORIGINAL de WoW recortado en circulo (SetPortraitToTexture; nuestro
-- envoltorio no lo toca: estos marcos no tienen SetIcon ni miwowSkin) dentro del anillo dorado. Pulsado = mas oscuro.
local function MiWowTouch_RoundIcon(frame, icon, d)
	local o = MiWowTouch_Overlay(frame, "u_menu", d);
	SetPortraitToTexture(o.glyph, icon);
	o.glyph:SetWidth(d * 0.9);
	o.glyph:SetHeight(d * 0.9);
	if ( frame:IsObjectType("Button") ) then
		frame:HookScript("OnMouseDown", function() o.glyph:SetVertexColor(0.65, 0.65, 0.65); end);
		frame:HookScript("OnMouseUp", function() o.glyph:SetVertexColor(1, 1, 1); end);
		frame:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD");
	end
	return o;
end

-- Oculta (alfa 0) las texturas propias de un marco salvo las que "keep" diga y las nuestras
local function MiWowTouch_HideArt(frame, keep)
	local o = frame.miwowOverlay;
	for _, region in ipairs({ frame:GetRegions() }) do
		if ( region:GetObjectType() == "Texture" and not (o and (region == o.disc or region == o.glyph or region == o.ring))
				and not (keep and keep(region)) ) then
			region:SetAlpha(0);
		end
	end
end

local function MiWowTouch_PathHas(region, text)
	local path = region:GetTexture();
	return type(path) == "string" and string.find(string.lower(path), text, 1, true) ~= nil;
end

-- Chat, frases rapidas y dictado: su arte es el de los botones del minimapa (centro desplazado 1 px)
local function MiWowTouch_SkinChatButtons(api)
	if ( api.chatButton ) then
		MiWowTouch_Overlay(api.chatButton, "s_talk", 26, 1, 1);
		MiWowTouch_HideArt(api.chatButton, function(r) return r == api.chatButton:GetHighlightTexture(); end);
	end
	if ( WebQuickChatToggle ) then
		MiWowTouch_Overlay(WebQuickChatToggle, "u_quick", 26, 1, 1);
		MiWowTouch_HideArt(WebQuickChatToggle, function(r) return r == WebQuickChatToggle:GetHighlightTexture(); end);
	end
	local voice = WebVoiceChatToggle;
	if ( voice ) then
		local o = MiWowTouch_Overlay(voice, "u_mic", 26, 1, 1);
		local waves;
		MiWowTouch_HideArt(voice, function(r)
			if ( MiWowTouch_PathHas(r, "voicechat-on") ) then
				waves = r;
			end
			return r == voice:GetHighlightTexture();
		end);
		-- Escuchando (su textura de ondas se muestra): microfono en rojo
		if ( waves ) then
			hooksecurefunc(waves, "Show", function() o.glyph:SetVertexColor(1, 0.35, 0.35); end);
			hooksecurefunc(waves, "Hide", function() o.glyph:SetVertexColor(1, 1, 1); end);
		end
	end
end

-- Asa del cajon (flecha de Blizzard) -> boton de menu. Su HandleArt vuelve a poner las flechas al abrir/cerrar.
local function MiWowTouch_SkinDrawerHandle()
	local handle = LasthavensTouchDrawer and LasthavensTouchDrawer.handle;
	if ( not handle ) then
		return;
	end
	MiWowTouch_Overlay(handle, "u_menu", 30);
	local function Hide(self)
		for _, tex in ipairs({ self:GetNormalTexture(), self:GetPushedTexture(), self:GetHighlightTexture() }) do
			if ( tex ) then
				tex:SetAlpha(0);
			end
		end
	end
	hooksecurefunc(handle, "SetNormalTexture", Hide);
	hooksecurefunc(handle, "SetPushedTexture", Hide);
	hooksecurefunc(handle, "SetHighlightTexture", Hide);
	Hide(handle);
end

-- Cajon: fondo oscuro con borde dorado; micro botones de Blizzard -> botones redondos dorados
local MIWOW_TOUCH_MICRO = {
	CharacterMicroButton = "m_char", SpellbookMicroButton = "m_book", TalentMicroButton = "m_star",
	AchievementMicroButton = "m_trophy", QuestLogMicroButton = "m_quest", SocialsMicroButton = "m_social",
	PVPMicroButton = "m_pvp", LFDMicroButton = "m_lfg", MainMenuMicroButton = "s_use", HelpMicroButton = "m_help",
};

local function MiWowTouch_SkinDrawer()
	-- Personaje: el retrato del micro boton se sale del circulo (y Blizzard le reajusta el alfa al pulsarlo) -> fuera
	if ( MicroButtonPortrait ) then
		MicroButtonPortrait:Hide();
	end
	local drawer = CharacterMicroButton and CharacterMicroButton:GetParent();
	if ( drawer and drawer ~= MainMenuBarArtFrame and drawer.SetBackdrop ) then
		drawer:SetBackdrop({
			bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 },
		});
		drawer:SetBackdropColor(0.09, 0.075, 0.06, 0.95);
		drawer:SetBackdropBorderColor(1, 0.84, 0.21, 0.85);
	end
	for name, glyph in pairs(MIWOW_TOUCH_MICRO) do
		local button = _G[name];
		if ( button ) then
			-- Micro boton 28x58: el dibujo va en la parte de abajo (encima, el hueco de la pestana)
			MiWowTouch_Overlay(button, glyph, 22, 0, -9);
			MiWowTouch_HideArt(button);
			for _, tex in ipairs({ button:GetNormalTexture(), button:GetPushedTexture(), button:GetDisabledTexture(),
					button:GetHighlightTexture() }) do
				if ( tex ) then
					tex:SetAlpha(0);
				end
			end
		end
	end
end

-- Desactivados (p. ej. Talentos antes de nivel 10): icono atenuado
local function MiWowTouch_UpdateMicro()
	for name in pairs(MIWOW_TOUCH_MICRO) do
		local button = _G[name];
		local o = button and button.miwowOverlay;
		if ( o ) then
			o.glyph:SetAlpha(button:IsEnabled() == 1 and 1 or 0.35);
		end
	end
end

-- Experiencia: su linea (3 px arriba a todo lo ancho, sin texto; su Update le vuelve a poner la altura) se oculta
-- (alfa 0) y va una barra propia abajo en el centro con "actual / siguiente nivel (%)" y lo que falta.
-- Descansada: tramo azul por delante. Oculta al nivel maximo (como la suya).
local MIWOW_TOUCH_XP_H = 13;

local function MiWowTouch_UpdateXpBar()
	local bar = MiWowTouchXpBar;
	if ( not bar ) then
		return;
	end
	local cur, top, rest = UnitXP("player"), UnitXPMax("player"), GetXPExhaustion() or 0;
	if ( UnitLevel("player") >= MAX_PLAYER_LEVEL or top <= 0 ) then
		bar:Hide();
		return;
	end
	bar:Show();
	bar:SetMinMaxValues(0, top);
	bar:SetValue(cur);
	bar.rested:SetMinMaxValues(0, top);
	bar.rested:SetValue(math.min(top, cur + rest));
	if ( GetRestState() == 1 ) then
		bar:SetStatusBarColor(0.0, 0.39, 0.88);
	else
		bar:SetStatusBarColor(0.58, 0.0, 0.55);
	end
	local text = string.format("Nivel %d  ·  %s / %s (%d %%)  ·  faltan %s", UnitLevel("player"),
		BreakUpLargeNumbers and BreakUpLargeNumbers(cur) or cur, BreakUpLargeNumbers and BreakUpLargeNumbers(top) or top,
		math.floor(cur / top * 100), BreakUpLargeNumbers and BreakUpLargeNumbers(top - cur) or (top - cur));
	if ( rest > 0 ) then
		text = text .. string.format("  ·  |cff66b3ffdescanso %s|r", BreakUpLargeNumbers and BreakUpLargeNumbers(rest) or rest);
	end
	bar.text:SetText(text);
end

local function MiWowTouch_MoveXpLine(hud)
	for _, child in ipairs({ hud:GetChildren() }) do
		if ( child.IsEventRegistered and child:IsEventRegistered("PLAYER_XP_UPDATE") and child:GetHeight() <= 4 ) then
			child:SetAlpha(0);
		end
	end
	if ( MiWowTouchXpBar ) then
		return;
	end
	local bar = CreateFrame("StatusBar", "MiWowTouchXpBar", UIParent);
	bar:SetFrameStrata("MEDIUM");
	bar:SetHeight(MIWOW_TOUCH_XP_H);
	bar:SetWidth(math.min(UIParent:GetWidth() * 0.46, 460));
	bar:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 4);
	bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar");
	bar:SetBackdrop({
		bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 8,
		insets = { left = -2, right = -2, top = -2, bottom = -2 },
	});
	bar:SetBackdropColor(0.03, 0.03, 0.05, 0.85);
	bar:SetBackdropBorderColor(1, 0.84, 0.21, 0.85);
	-- Descansada: otra barra debajo (misma caja), azul translucida
	local rested = CreateFrame("StatusBar", nil, bar);
	rested:SetAllPoints(bar);
	rested:SetFrameLevel(bar:GetFrameLevel());
	rested:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar");
	rested:SetStatusBarColor(0.0, 0.39, 0.88, 0.45);
	bar.rested = rested;
	bar:SetFrameLevel(rested:GetFrameLevel() + 1);
	local over = CreateFrame("Frame", nil, bar);
	over:SetAllPoints(bar);
	over:SetFrameLevel(bar:GetFrameLevel() + 2);
	local text = over:CreateFontString(nil, "OVERLAY", "TextStatusBarText");
	text:SetPoint("CENTER", bar, "CENTER", 0, 1);
	bar.text = text;
	for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_XP_UPDATE", "PLAYER_LEVEL_UP", "UPDATE_EXHAUSTION",
			"PLAYER_UPDATE_RESTING" }) do
		bar:RegisterEvent(event);
	end
	bar:SetScript("OnEvent", MiWowTouch_UpdateXpBar);
	MiWowTouch_UpdateXpBar();
end

-- Vista previa del chat (su LasthavensChatPreview, el chat que se ve con la ventana cerrada): de la esquina de abajo
-- -> centrada y por encima de la barra de experiencia. Se re-ancla cada vez que su PlaceChat la coloca (con mando no).
local MIWOW_TOUCH_CHAT_LIFT = 26;

local function MiWowTouch_CenterChatPreview(hud)
	local preview = hud.preview;
	if ( not preview or preview.miwowCentered ) then
		return;
	end
	preview.miwowCentered = true;
	local busy = false;
	local function Center(self, point, rel, relPoint, x, y)
		if ( busy or hud.pad or (point ~= "BOTTOMLEFT" and point ~= "BOTTOMRIGHT") ) then
			return;
		end
		busy = true;
		self:ClearAllPoints();
		self:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, (y or 0) + MIWOW_TOUCH_CHAT_LIFT);
		busy = false;
	end
	hooksecurefunc(preview, "SetPoint", Center);
	if ( preview:GetNumPoints() == 1 ) then
		Center(preview, preview:GetPoint(1));
	end
end

-- Boton "Menu" (retrato del jugador, LasthavensTouchMenuButton 52x52, retrato 36x36 en 8,-8): su anillo del
-- minimapa -> nuestro anillo dorado
local function MiWowTouch_SkinMenuButton()
	local menu = LasthavensTouchMenuButton;
	if ( not menu or menu.miwowRing ) then
		return;
	end
	for _, region in ipairs({ menu:GetRegions() }) do
		if ( region:GetObjectType() == "Texture" and MiWowTouch_PathHas(region, "minimap-trackingborder") ) then
			region:SetAlpha(0);
		end
	end
	local ring = menu:CreateTexture(nil, "OVERLAY");
	ring:SetTexture("Interface\\TouchUI\\DragonUI\\forever_circle_lh");
	ring:SetWidth(36 * 1.208);
	ring:SetHeight(36 * 1.208);
	ring:SetPoint("CENTER", menu, "TOPLEFT", 26, -26);
	menu.miwowRing = ring;
	MiWowTouch_CreateBagButton(menu);
end

-- Libro de hechizos: su "hud.setup" (engranaje junto al boton inteligente; al tocarlo pulsa SpellbookMicroButton) se
-- quita y va un boton con el icono del libro debajo de la mochila, junto al minimapa (decision del usuario 2026-11-24).
-- Su Place lo vuelve a mostrar en cada recolocacion -> hook a Show. Sus zonas tactiles miran IsVisible: oculto = sin zona.
function MiWowTouch_CreateSpellButton(hud)
	-- Sin la mochila (donde se ancla) se deja su engranaje: que el libro siga a mano
	if ( MiWowTouchSpellButton or not MiWowTouchBagButton ) then
		return;
	end
	local setup = hud and hud.setup;
	if ( setup and not setup.miwowHidden ) then
		setup.miwowHidden = true;
		hooksecurefunc(setup, "Show", function(self) self:Hide(); end);
		setup:Hide();
	end
	local button = CreateFrame("Button", "MiWowTouchSpellButton", UIParent);
	button:SetFrameStrata("MEDIUM");
	button:SetWidth(40);
	button:SetHeight(40);
	button:SetPoint("TOP", MiWowTouchBagButton, "BOTTOM", 0, -4);
	MiWowTouch_RoundIcon(button, "Interface\\Icons\\INV_Misc_Book_09", 34);
	button:SetScript("OnClick", function()
		ToggleSpellBook(BOOKTYPE_SPELL);
	end);
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT");
		GameTooltip:SetText(SPELLBOOK or "Libro de hechizos");
		GameTooltip:Show();
	end);
	button:SetScript("OnLeave", function() GameTooltip:Hide(); end);
end

-- Boton de bolsas fuera del menu (debajo del boton "Menu"): abre/cierra todas; numero = casillas libres.
-- Dibujo = el de la mochila original de Blizzard (MainMenuBarBackpackButton), decision del usuario 2026-11-24.
function MiWowTouch_CreateBagButton(menu)
	if ( MiWowTouchBagButton ) then
		return;
	end
	local button = CreateFrame("Button", "MiWowTouchBagButton", UIParent);
	button:SetFrameStrata("MEDIUM");
	button:SetWidth(40);
	button:SetHeight(40);
	button:SetPoint("TOP", menu, "TOPLEFT", 26, -64);
	MiWowTouch_RoundIcon(button, "Interface\\Buttons\\Button-Backpack-Up", 34);
	local free = button:CreateFontString(nil, "OVERLAY", "NumberFontNormal");
	free:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 2, -2);
	local function Count()
		local total = 0;
		for bag = 0, NUM_BAG_SLOTS do
			local slots, family = GetContainerNumFreeSlots(bag);
			if ( slots and (family == 0 or family == nil) ) then
				total = total + slots;
			end
		end
		free:SetText(total);
		if ( total == 0 ) then
			free:SetTextColor(1, 0.3, 0.3);
		else
			free:SetTextColor(1, 1, 1);
		end
	end
	button:RegisterEvent("BAG_UPDATE");
	button:RegisterEvent("PLAYER_ENTERING_WORLD");
	button:SetScript("OnEvent", Count);
	button:SetScript("OnClick", function()
		PlaySound("igBackPackOpen");
		OpenAllBags();
	end);
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT");
		GameTooltip:SetText("Bolsas");
		GameTooltip:Show();
	end);
	button:SetScript("OnLeave", function() GameTooltip:Hide(); end);
	Count();
end

-- --- Chat (su ventana grande LasthavensBigChat + chat nativo) ------------------------------------------------------

local PILL, PILL_EDGE = DIR .. "pill", DIR .. "pill_edge";

local MiWowTouch_FontOff = CreateFont("MiWowTouchPillFont");
MiWowTouch_FontOff:SetFontObject(GameFontNormalSmall);
MiWowTouch_FontOff:SetTextColor(0.84, 0.82, 0.79);
local MiWowTouch_FontOn = CreateFont("MiWowTouchPillFontOn");
MiWowTouch_FontOn:SetFontObject(GameFontNormalSmall);
MiWowTouch_FontOn:SetTextColor(0.1, 0.08, 0.03);

-- Pastilla (fondo + borde dorado) detras de un boton; top/bottom = margen vertical (pestanas: dibujo abajo)
local function MiWowTouch_Pill(frame, top, bottom)
	local p = frame.miwowPill;
	if ( not p ) then
		p = {};
		p.bg = frame:CreateTexture(nil, "BACKGROUND");
		p.bg:SetTexture(PILL);
		p.edge = frame:CreateTexture(nil, "BORDER");
		p.edge:SetTexture(PILL_EDGE);
		for _, tex in ipairs({ p.bg, p.edge }) do
			tex:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -(top or 0));
			tex:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, bottom or 0);
		end
		frame.miwowPill = p;
	end
	return p;
end

local function MiWowTouch_PillOn(frame, on)
	local p = frame.miwowPill;
	if ( not p ) then
		return;
	end
	if ( on ) then
		p.bg:SetVertexColor(1, 0.84, 0.21, 0.95);
		p.edge:SetVertexColor(1, 0.93, 0.55, 0.9);
	else
		p.bg:SetVertexColor(0.13, 0.11, 0.09, 0.9);
		p.edge:SetVertexColor(1, 0.84, 0.21, 0.45);
	end
end

-- Boton de Blizzard (UIPanelButtonTemplate) -> pastilla; on = dorada (accion principal / seleccionada)
local function MiWowTouch_StyleButton(button, on)
	if ( not button.miwowPill ) then
		MiWowTouch_Pill(button);
		for _, tex in ipairs({ button:GetNormalTexture(), button:GetPushedTexture(), button:GetDisabledTexture(),
				button:GetHighlightTexture() }) do
			if ( tex ) then
				tex:SetAlpha(0);
			end
		end
	end
	local font = on and MiWowTouch_FontOn or MiWowTouch_FontOff;
	button:SetNormalFontObject(font);
	button:SetHighlightFontObject(font);
	MiWowTouch_PillOn(button, on);
end

-- Boton redondo del chat de Blizzard: dibujo fuera, nuestro disco + pictograma
local function MiWowTouch_RoundButton(button, glyph, d)
	if ( not button or button.miwowOverlay ) then
		return;
	end
	MiWowTouch_Overlay(button, glyph, d or 24);
	MiWowTouch_HideArt(button);
	for _, tex in ipairs({ button:GetNormalTexture(), button:GetPushedTexture(), button:GetDisabledTexture(),
			button:GetHighlightTexture() }) do
		if ( tex ) then
			tex:SetAlpha(0);
		end
	end
end

-- Canales (sus botones LasthavensChatChannelN, se crean segun haga falta): el activo en dorado
local function MiWowTouch_StyleChannels(panel)
	local box = ChatFrame1EditBox;
	local kind, target = box:GetAttribute("stickyType"), box:GetAttribute("channelTarget");
	for _, button in ipairs(panel.channelButtons or {}) do
		local on = button.kind == kind and (button.kind ~= "CHANNEL" or tonumber(target) == button.target);
		MiWowTouch_StyleButton(button, on);
	end
	-- Sus textos en ingles
	local text = panel.type and panel.type:GetText();
	if ( text and string.find(text, ": type a message", 1, true) ) then
		panel.type:SetText((string.gsub(text, ": type a message", ": escribe un mensaje")));
	end
	if ( panel.send and panel.send:GetText() == "Send" ) then
		panel.send:SetText("Enviar");
	end
end

-- Pestanas del chat: pastilla abajo (su texto va 7 px por debajo del centro); seleccionada en dorado
local function MiWowTouch_StyleTab(tab, selected)
	if ( not tab ) then
		return;
	end
	if ( not tab.miwowPill ) then
		MiWowTouch_Pill(tab, 11, 1);
		for _, key in ipairs({ "leftTexture", "middleTexture", "rightTexture", "leftSelectedTexture",
				"middleSelectedTexture", "rightSelectedTexture", "leftHighlightTexture", "middleHighlightTexture",
				"rightHighlightTexture" }) do
			if ( tab[key] ) then
				tab[key]:SetAlpha(0);
			end
		end
	end
	if ( selected == nil ) then
		selected = tab.leftSelectedTexture and tab.leftSelectedTexture:IsShown();
	end
	MiWowTouch_PillOn(tab, selected);
	local text = tab:GetFontString();
	if ( text ) then
		if ( selected ) then
			text:SetTextColor(0.1, 0.08, 0.03);
		else
			text:SetTextColor(0.84, 0.82, 0.79);
		end
	end
end

local function MiWowTouch_StyleTabs()
	for i = 1, NUM_CHAT_WINDOWS do
		MiWowTouch_StyleTab(_G["ChatFrame" .. i .. "Tab"]);
	end
end

-- Caja de escribir: sus bordes de Blizzard fuera, fondo oscuro con borde dorado
local function MiWowTouch_StyleEditBox(box)
	if ( not box or box.miwowStyled ) then
		return;
	end
	box.miwowStyled = true;
	for _, region in ipairs({ box:GetRegions() }) do
		if ( region:GetObjectType() == "Texture" and MiWowTouch_PathHas(region, "chatinputborder") ) then
			region:SetAlpha(0);
		end
	end
	box:SetBackdrop({
		bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 14,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	});
	box:SetBackdropColor(0.055, 0.047, 0.04, 0.95);
	box:SetBackdropBorderColor(1, 0.84, 0.21, 0.7);
end

local function MiWowTouch_SkinBigChat(api)
	local panel = api.hud and api.hud.bigChat;
	if ( not panel or panel.miwowHooked ) then
		return;
	end
	panel.miwowHooked = true;

	local function Skin()
		-- Su marco de mapa (Slices) y el retrato de la carta se crean al abrirlo por primera vez
		if ( not panel.miwowArt ) then
			panel.miwowArt = true;
			for _, region in ipairs({ panel:GetRegions() }) do
				if ( region:GetObjectType() == "Texture" and region ~= panel.floor ) then
					region:SetAlpha(0);
				end
			end
			panel:SetBackdrop({
				bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
				edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
				tile = true, tileSize = 16, edgeSize = 16,
				insets = { left = 4, right = 4, top = 4, bottom = 4 },
			});
			panel:SetBackdropColor(0.09, 0.075, 0.06, 0.9);
			panel:SetBackdropBorderColor(1, 0.84, 0.21, 0.85);
			if ( panel.title ) then
				panel.title:SetTextColor(1, 0.84, 0.21);
			end
			if ( panel.close ) then
				MiWowTouch_RoundButton(panel.close, "u_close", 22);
			end
		end
		if ( panel.ring ) then
			panel.ring:Hide();
		end
		if ( panel.type ) then
			MiWowTouch_StyleButton(panel.type, false);
		end
		if ( panel.send ) then
			MiWowTouch_StyleButton(panel.send, true);
		end
		MiWowTouch_StyleChannels(panel);
		MiWowTouch_StyleTabs();
	end
	panel:HookScript("OnShow", Skin);
	if ( panel.channels ) then
		panel.channels:HookScript("OnEvent", function() MiWowTouch_StyleChannels(panel); end);
	end
	if ( type(api.hud.ChatChannels) == "function" ) then
		hooksecurefunc(api.hud, "ChatChannels", function() MiWowTouch_StyleChannels(panel); end);
	end
	hooksecurefunc("ChatEdit_UpdateHeader", function() MiWowTouch_StyleChannels(panel); end);
	if ( panel:IsShown() ) then
		Skin();
	end
end

local function MiWowTouch_SkinChat(api)
	MiWowTouch_SkinBigChat(api);
	MiWowTouch_StyleTabs();
	hooksecurefunc("FCFTab_UpdateColors", MiWowTouch_StyleTab);
	MiWowTouch_StyleEditBox(ChatFrame1EditBox);
	MiWowTouch_RoundButton(ChatFrameMenuButton, "s_talk");
	MiWowTouch_RoundButton(FriendsMicroButton, "m_social");
	MiWowTouch_RoundButton(ChatFrame1ButtonFrameUpButton, "u_up");
	MiWowTouch_RoundButton(ChatFrame1ButtonFrameDownButton, "u_down");
	MiWowTouch_RoundButton(ChatFrame1ButtonFrameBottomButton, "u_down");
	if ( ChatFrame1ButtonFrame ) then
		MiWowTouch_HideArt(ChatFrame1ButtonFrame);
	end
end

-- --- Bolsas (su ventana LasthavensBigBags) ---------------------------------------------------------------------------

local SLOT_TEX, SLOT_EDGE = DIR .. "slot", DIR .. "slot_edge";

-- Casilla (ContainerFrameItemButtonTemplate, 37x37 escalada): su fondo -> nuestra casilla, borde de calidad propio
local function MiWowTouch_StyleSlot(button)
	if ( button.miwowSlot ) then
		return;
	end
	button.miwowSlot = true;
	if ( button.empty ) then
		button.empty:SetTexture(SLOT_TEX);
		button.empty:SetTexCoord(0, 1, 0, 1);
		button.empty:SetVertexColor(1, 1, 1);
		button.empty:ClearAllPoints();
		button.empty:SetAllPoints();
	end
	local normal = button:GetNormalTexture();
	if ( normal ) then
		normal:SetAlpha(0);
	end
	local icon = _G[button:GetName() .. "IconTexture"];
	if ( icon ) then
		icon:ClearAllPoints();
		icon:SetPoint("TOPLEFT", 3, -3);
		icon:SetPoint("BOTTOMRIGHT", -3, 3);
		icon:SetTexCoord(0.08, 0.92, 0.08, 0.92);
	end
	-- Su brillo de calidad (borde de boton de accion, ADD, 66x66): ellos le ponen color y lo muestran/ocultan
	if ( button.glow ) then
		button.glow:SetTexture(SLOT_EDGE);
		button.glow:SetBlendMode("BLEND");
		button.glow:ClearAllPoints();
		button.glow:SetAllPoints();
	end
end

local function MiWowTouch_StyleBagSlots()
	for bag = 0, NUM_BAG_SLOTS do
		for slot = 1, 40 do
			local button = _G["LasthavensBigBags" .. bag .. "Item" .. slot];
			if ( button ) then
				MiWowTouch_StyleSlot(button);
			end
		end
	end
end

local function MiWowTouch_SkinBags()
	local grid = LasthavensBigBags;
	if ( not grid or grid.miwowSkinned or not grid.Update ) then
		return;
	end
	grid.miwowSkinned = true;

	-- Marco de bolsa de Blizzard, suelo de la hoja de personaje, retrato y tira del vendedor -> fuera
	for _, region in ipairs({ grid:GetRegions() }) do
		if ( region:GetObjectType() == "Texture" ) then
			region:SetAlpha(0);
		end
	end
	grid:SetBackdrop({
		bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	});
	grid:SetBackdropColor(0.09, 0.075, 0.06, 0.95);
	grid:SetBackdropBorderColor(1, 0.84, 0.21, 0.85);
	if ( grid.title ) then
		grid.title:SetFontObject(GameFontNormalLarge);
		grid.title:SetTextColor(1, 0.84, 0.21);
	end

	-- Emblema: la mochila original (donde estaba su retrato)
	local badge = CreateFrame("Frame", nil, grid);
	badge:SetWidth(36);
	badge:SetHeight(36);
	badge:SetPoint("TOPLEFT", grid, "TOPLEFT", 9, -7);
	MiWowTouch_RoundIcon(badge, "Interface\\Buttons\\Button-Backpack-Up", 36);

	for _, child in ipairs({ grid:GetChildren() }) do
		local normal = child.GetNormalTexture and child:GetNormalTexture();
		if ( normal and MiWowTouch_PathHas(normal, "minimizebutton") ) then
			MiWowTouch_RoundButton(child, "u_close", 22);
		end
	end

	-- Pie: caja del oro de vendedor -> pastilla
	if ( grid.moneyBox ) then
		MiWowTouch_HideArt(grid.moneyBox);
		MiWowTouch_Pill(grid.moneyBox);
		MiWowTouch_PillOn(grid.moneyBox, false);
	end

	-- Pestanas laterales de las bolsas (BigBagsUIBagNSlot): pestana del libro de hechizos -> casilla
	for i = 0, NUM_BAG_SLOTS - 1 do
		local bagButton = _G["BigBagsUIBag" .. i .. "Slot"];
		local icon = bagButton and _G[bagButton:GetName() .. "IconTexture"];
		if ( icon ) then
			MiWowTouch_HideArt(bagButton, function(r)
				return r == icon or r == bagButton:GetHighlightTexture() or r == bagButton:GetCheckedTexture()
					or not MiWowTouch_PathHas(r, "skilllinetab");
			end);
			local back = bagButton:CreateTexture(nil, "BACKGROUND");
			back:SetTexture(SLOT_TEX);
			back:SetPoint("TOPLEFT", icon, "TOPLEFT", -4, 4);
			back:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 4, -4);
			icon:SetTexCoord(0.08, 0.92, 0.08, 0.92);
		end
	end

	-- Menu de un objeto (usar, equipar, vender...): mismo dorado
	if ( LasthavensItemMenu ) then
		LasthavensItemMenu:SetBackdropBorderColor(1, 0.84, 0.21, 0.85);
	end

	hooksecurefunc(grid, "Update", MiWowTouch_StyleBagSlots);
	MiWowTouch_StyleBagSlots();
end

local MiWowTouch_Applied = false;

-- Su 18_WebTouchSecure crea el global LasthavensEditApi (hud, stick, jump...) y su 15_LasthavensPadParts lo recoge y lo
-- borra en seguida (comprobado en el navegador: nil ya al entrar al mundo). Se captura al crearse: __newindex de _G
-- solo salta con claves nuevas; despues se quita el metatable (o se restaura el que hubiera).
local MiWowTouch_Api, MiWowTouch_OldMeta;
do
	local old = getmetatable(_G);
	MiWowTouch_OldMeta = old;
	local oldNew = old and old.__newindex;
	local meta = {};
	if ( old ) then
		for k, v in pairs(old) do
			meta[k] = v;
		end
	end
	meta.__newindex = function(t, k, v)
		if ( oldNew ) then
			oldNew(t, k, v);
		else
			rawset(t, k, v);
		end
		if ( k == "LasthavensEditApi" and type(v) == "table" ) then
			MiWowTouch_Api = v;
			setmetatable(_G, old);
		end
	end;
	setmetatable(_G, meta);
end

local function MiWowTouch_Apply()
	local api = MiWowTouch_Api or LasthavensEditApi;
	if ( MiWowTouch_Applied or not api or not api.hud ) then
		return MiWowTouch_Applied;
	end
	MiWowTouch_Applied = true;
	MiWowTouch_Api = api;
	MiWowTouchSkin_State = "aplicado";
	MiWowTouch_SkinStick(api.stick);
	if ( api.jump and api.jump.icon ) then
		MiWowTouch_SetGlyph(api.jump, api.jump.icon, "jump");    -- por si se monto antes que este archivo
	end
	MiWowTouch_SkinSmart(api.smart);
	MiWowTouch_SkinChatButtons(api);
	MiWowTouch_SkinDrawerHandle();
	MiWowTouch_SkinDrawer();
	MiWowTouch_MoveXpLine(api.hud);
	MiWowTouch_CenterChatPreview(api.hud);
	MiWowTouch_SkinMenuButton();
	MiWowTouch_CreateSpellButton(api.hud);
	MiWowTouch_SkinChat(api);
	MiWowTouch_SkinBags();
	MiWowTouch_Sweep(api.hud);
	-- Huecos vacios del arco (botones de accion de Blizzard)
	hooksecurefunc("ActionButton_Update", function(button)
		local icon = button and button:GetName() and _G[button:GetName() .. "Icon"];
		if ( icon and MiWowTouch_IsDiscPath(icon:GetTexture()) ) then
			icon:SetTexture(DISC);
		end
	end);
	return true;
end

-- Su HUD se monta despues de FrameXML: se aplica en cuanto existe y luego se repasa cada segundo
-- (algunos botones vuelven a poner el fondo del minimapa al cambiar de estado)
local MiWowTouch_Frame = CreateFrame("Frame");
local MiWowTouch_Wait, MiWowTouch_Tick = 0, 0;
MiWowTouch_Frame:RegisterEvent("PLAYER_LOGIN");
MiWowTouch_Frame:SetScript("OnEvent", function(self)
	self:UnregisterAllEvents();
	if ( not MiWowTouch_IsWeb() ) then
		setmetatable(_G, MiWowTouch_OldMeta);
		MiWowTouchSkin_State = "sin webTouch";
		return;
	end
	MiWowTouchSkin_State = MiWowTouch_Api and "capturado" or "esperando";
	self:SetScript("OnUpdate", function(frame, elapsed)
		MiWowTouch_Tick = MiWowTouch_Tick + elapsed;
		if ( MiWowTouch_Tick < 1 ) then
			return;
		end
		MiWowTouch_Tick = 0;
		if ( not MiWowTouch_Apply() ) then
			MiWowTouch_Wait = MiWowTouch_Wait + 1;
			if ( MiWowTouch_Wait > 60 ) then
				frame:SetScript("OnUpdate", nil);
				setmetatable(_G, MiWowTouch_OldMeta);
				MiWowTouchSkin_State = "sin HUD (no se capturo LasthavensEditApi)";
			end
			return;
		end
		MiWowTouch_Sweep(MiWowTouch_Api.hud);
		MiWowTouch_UpdateMicro();
	end);
end);
