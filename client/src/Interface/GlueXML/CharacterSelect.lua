CHARACTER_SELECT_ROTATION_START_X = nil;
CHARACTER_SELECT_INITIAL_FACING = nil;

CHARACTER_ROTATION_CONSTANT = 0.6;

MAX_CHARACTERS_DISPLAYED = 10;
MAX_CHARACTERS_PER_REALM = 10;


function CharacterSelect_OnLoad(self)
	self:SetSequence(0);
	self:SetCamera(0);

	self.createIndex = 0;
	self.selectedIndex = 0;
	self.selectLast = 0;
	self.currentModel = nil;
	self:RegisterEvent("ADDON_LIST_UPDATE");
	self:RegisterEvent("CHARACTER_LIST_UPDATE");
	self:RegisterEvent("UPDATE_SELECTED_CHARACTER");
	self:RegisterEvent("SELECT_LAST_CHARACTER");
	self:RegisterEvent("SELECT_FIRST_CHARACTER");
	self:RegisterEvent("SUGGEST_REALM");
	self:RegisterEvent("FORCE_RENAME_CHARACTER");

	-- CharacterSelect:SetModel("Interface\\Glues\\Models\\UI_Orc\\UI_Orc.m2");

	-- local fogInfo = CharModelFogInfo["ORC"];
	-- CharacterSelect:SetFogColor(fogInfo.r, fogInfo.g, fogInfo.b);
	-- CharacterSelect:SetFogNear(0);
	-- CharacterSelect:SetFogFar(fogInfo.far);

	SetCharSelectModelFrame("CharacterSelect");

	-- Color edit box backdrops
	local backdropColor = DEFAULT_TOOLTIP_COLOR;
	CharacterSelectCharacterFrame:SetBackdropBorderColor(backdropColor[1], backdropColor[2], backdropColor[3]);
	CharacterSelectCharacterFrame:SetBackdropColor(backdropColor[4], backdropColor[5], backdropColor[6], 0.85);

	EventWow_CharSelect_OnLoad(self); -- EventWow
end

function CharacterSelect_OnShow()
	-- request account data times from the server (so we know if we should refresh keybindings, etc...)
	ReadyForAccountDataTimes()
	EventWow_CharSelect_OnShow(); -- EventWow

	local CurrentModel = CharacterSelect.currentModel;

	if ( CurrentModel ) then
		PlayGlueAmbience(GlueAmbienceTracks[strupper(CurrentModel)], 4.0);
	end

	UpdateAddonButton();

	local serverName, isPVP, isRP = GetServerName();
	local connected = IsConnectedToServer();
	local serverType = "";
	if ( serverName ) then
		if( not connected ) then
			serverName = serverName.."\n("..SERVER_DOWN..")";
		end
		if ( isPVP ) then
			if ( isRP ) then
				serverType = RPPVP_PARENTHESES;
			else
				serverType = PVP_PARENTHESES;
			end
		elseif ( isRP ) then
			serverType = RP_PARENTHESES;
		end
		CharSelectRealmName:SetText(serverName.." "..serverType);
		CharSelectRealmName:Show();
	else
		CharSelectRealmName:Hide();
	end

	if ( connected ) then
		GetCharacterListUpdate();
	else
		UpdateCharacterList();
	end

	-- Gameroom billing stuff (For Korea and China only)
	if ( SHOW_GAMEROOM_BILLING_FRAME ) then
		local paymentPlan, hasFallBackBillingMethod, isGameRoom = GetBillingPlan();
		if ( paymentPlan == 0 ) then
			-- No payment plan
			GameRoomBillingFrame:Hide();
			CharacterSelectRealmSplitButton:ClearAllPoints();
			CharacterSelectRealmSplitButton:SetPoint("TOP", CharacterSelectLogo, "BOTTOM", 0, -5);
		else
			local billingTimeLeft = GetBillingTimeRemaining();
			-- Set default text for the payment plan
			local billingText = _G["BILLING_TEXT"..paymentPlan];
			if ( paymentPlan == 1 ) then
				-- Recurring account
				billingTimeLeft = ceil(billingTimeLeft/(60 * 24));
				if ( billingTimeLeft == 1 ) then
					billingText = BILLING_TIME_LEFT_LAST_DAY;
				end
			elseif ( paymentPlan == 2 ) then
				-- Free account
				if ( billingTimeLeft < (24 * 60) ) then
					billingText = format(BILLING_FREE_TIME_EXPIRE, billingTimeLeft.." "..MINUTES_ABBR);
				end				
			elseif ( paymentPlan == 3 ) then
				-- Fixed but not recurring
				if ( isGameRoom == 1 ) then
					if ( billingTimeLeft <= 30 ) then
						billingText = BILLING_GAMEROOM_EXPIRE;
					else
						billingText = format(BILLING_FIXED_IGR, MinutesToTime(billingTimeLeft, 1));
					end
				else
					-- personal fixed plan
					if ( billingTimeLeft < (24 * 60) ) then
						billingText = BILLING_FIXED_LASTDAY;
					else
						billingText = format(billingText, MinutesToTime(billingTimeLeft));
					end	
				end
			elseif ( paymentPlan == 4 ) then
				-- Usage plan
				if ( isGameRoom == 1 ) then
					-- game room usage plan
					if ( billingTimeLeft <= 600 ) then
						billingText = BILLING_GAMEROOM_EXPIRE;
					else
						billingText = BILLING_IGR_USAGE;
					end
				else
					-- personal usage plan
					if ( billingTimeLeft <= 30 ) then
						billingText = BILLING_TIME_LEFT_30_MINS;
					else
						billingText = format(billingText, billingTimeLeft);
					end
				end
			end
			-- If fallback payment method add a note that says so
			if ( hasFallBackBillingMethod == 1 ) then
				billingText = billingText.."\n\n"..BILLING_HAS_FALLBACK_PAYMENT;
			end
			GameRoomBillingFrameText:SetText(billingText);
			GameRoomBillingFrame:SetHeight(GameRoomBillingFrameText:GetHeight() + 26);
			GameRoomBillingFrame:Show();
			CharacterSelectRealmSplitButton:ClearAllPoints();
			CharacterSelectRealmSplitButton:SetPoint("TOP", GameRoomBillingFrame, "BOTTOM", 0, -10);
		end
	end
	
	if( IsTrialAccount() ) then
		CharacterSelectUpgradeAccountButton:Show();
	else
		CharacterSelectUpgradeAccountButton:Hide();
	end

	-- fadein the character select ui
	GlueFrameFadeIn(CharacterSelectUI, CHARACTER_SELECT_FADE_IN)

	RealmSplitCurrentChoice:Hide();
	RequestRealmSplitInfo();

	--Clear out the addons selected item
	GlueDropDownMenu_SetSelectedValue(AddonCharacterDropDown, ALL);
end

function CharacterSelect_OnHide()
	CharacterDeleteDialog:Hide();
	CharacterRenameDialog:Hide();
	if ( DeclensionFrame ) then
		DeclensionFrame:Hide();
	end
	SERVER_SPLIT_STATE_PENDING = -1;
end

function CharacterSelect_OnUpdate(elapsed)
	EventWow_CharSelect_OnUpdate(elapsed); -- EventWow
	if ( SERVER_SPLIT_STATE_PENDING > 0 ) then
		CharacterSelectRealmSplitButton:Show();

		if ( SERVER_SPLIT_CLIENT_STATE > 0 ) then
			RealmSplit_SetChoiceText();
			RealmSplitPending:SetPoint("TOP", RealmSplitCurrentChoice, "BOTTOM", 0, -10);
		else
			RealmSplitPending:SetPoint("TOP", CharacterSelectRealmSplitButton, "BOTTOM", 0, 0);
			RealmSplitCurrentChoice:Hide();
		end

		if ( SERVER_SPLIT_STATE_PENDING > 1 ) then
			CharacterSelectRealmSplitButton:Disable();
			CharacterSelectRealmSplitButtonGlow:Hide();
			RealmSplitPending:SetText( SERVER_SPLIT_PENDING );
		else
			CharacterSelectRealmSplitButton:Enable();
			CharacterSelectRealmSplitButtonGlow:Show();
			local datetext = SERVER_SPLIT_CHOOSE_BY.."\n"..SERVER_SPLIT_DATE;
			RealmSplitPending:SetText( datetext );
		end

		if ( SERVER_SPLIT_SHOW_DIALOG and not GlueDialog:IsShown() ) then
			SERVER_SPLIT_SHOW_DIALOG = false;
			local dialogString = format(SERVER_SPLIT,SERVER_SPLIT_DATE);
			if ( SERVER_SPLIT_CLIENT_STATE > 0 ) then
				local serverChoice = RealmSplit_GetFormatedChoice(SERVER_SPLIT_REALM_CHOICE);
				local stringWithDate = format(SERVER_SPLIT,SERVER_SPLIT_DATE);
				dialogString = stringWithDate.."\n\n"..serverChoice;
				GlueDialog_Show("SERVER_SPLIT_WITH_CHOICE", dialogString);
			else
				GlueDialog_Show("SERVER_SPLIT", dialogString);
			end
		end
	else
		CharacterSelectRealmSplitButton:Hide();
	end

	-- Account Msg stuff
	if ( (ACCOUNT_MSG_NUM_AVAILABLE > 0) and not GlueDialog:IsShown() ) then
		if ( ACCOUNT_MSG_HEADERS_LOADED ) then
			if ( ACCOUNT_MSG_BODY_LOADED ) then
				local dialogString = AccountMsg_GetHeaderSubject( ACCOUNT_MSG_CURRENT_INDEX ).."\n\n"..AccountMsg_GetBody();
				GlueDialog_Show("ACCOUNT_MSG", dialogString);
			end
		end
	end
end

function CharacterSelect_OnKeyDown(self,key)
	if ( key == "ESCAPE" ) then
		CharacterSelect_Exit();
	elseif ( key == "ENTER" ) then
		CharacterSelect_EnterWorld();
	elseif ( key == "PRINTSCREEN" ) then
		Screenshot();
	elseif ( key == "UP" or key == "LEFT" ) then
		local numChars = GetNumCharacters();
		if ( numChars > 1 ) then
			if ( self.selectedIndex > 1 ) then
				CharacterSelect_SelectCharacter(self.selectedIndex - 1);
			else
				CharacterSelect_SelectCharacter(numChars);
			end
		end
	elseif ( arg1 == "DOWN" or arg1 == "RIGHT" ) then
		local numChars = GetNumCharacters();
		if ( numChars > 1 ) then
			if ( self.selectedIndex < GetNumCharacters() ) then
				CharacterSelect_SelectCharacter(self.selectedIndex + 1);
			else
				CharacterSelect_SelectCharacter(1);
			end
		end
	end
end

function CharacterSelect_OnEvent(self, event, ...)
	if ( event == "ADDON_LIST_UPDATE" ) then
		UpdateAddonButton();
	elseif ( event == "CHARACTER_LIST_UPDATE" ) then
		UpdateCharacterList();
		CharSelectCharacterName:SetText(GetCharacterInfo(self.selectedIndex));
		EventWow_OnCharacterListUpdate(); -- EventWow
	elseif ( event == "UPDATE_SELECTED_CHARACTER" ) then
		local index = ...;
		if ( index == 0 ) then
			CharSelectCharacterName:SetText("");
		else
			CharSelectCharacterName:SetText(GetCharacterInfo(index));
			self.selectedIndex = index;
		end
		UpdateCharacterSelection(self);
	elseif ( event == "SELECT_LAST_CHARACTER" ) then
		self.selectLast = 1;
	elseif ( event == "SELECT_FIRST_CHARACTER" ) then
		CharacterSelect_SelectCharacter(1, 1);
	elseif ( event == "SUGGEST_REALM" ) then
		local category, id = ...;
		local name = GetRealmInfo(category, id);
		if ( name ) then
			SetGlueScreen("charselect");
			ChangeRealm(category, id);
		else
			if ( RealmList:IsShown() ) then
				RealmListUpdate();
			else
				RealmList:Show();
			end
		end
	elseif ( event == "FORCE_RENAME_CHARACTER" ) then
		local message = ...;
		CharacterRenameDialog:Show();
		CharacterRenameText1:SetText(_G[message]);
	end
end

function CharacterSelect_UpdateModel(self)
	UpdateSelectionCustomizationScene();
	self:AdvanceTime();
end

function UpdateCharacterSelection(self)
	for i=1, MAX_CHARACTERS_DISPLAYED, 1 do
		_G["CharSelectCharacterButton"..i]:UnlockHighlight();
	end

	local index = self.selectedIndex;
	if ( (index > 0) and (index <= MAX_CHARACTERS_DISPLAYED) )then
		_G["CharSelectCharacterButton"..index]:LockHighlight();
	end
end

function UpdateCharacterList()
	local numChars = GetNumCharacters();
	local index = 1;
	local coords;
	for i=1, numChars, 1 do
		local name, race, class, level, zone, sex, ghost, PCC, PRC, PFC = GetCharacterInfo(i);
		local button = _G["CharSelectCharacterButton"..index];
		if ( not name ) then
			button:SetText("ERROR - Tell Jeremy");
		else
			if ( not zone ) then
				zone = "";
			end
			_G["CharSelectCharacterButton"..index.."ButtonTextName"]:SetText(name);
			if( ghost ) then
				_G["CharSelectCharacterButton"..index.."ButtonTextInfo"]:SetFormattedText(CHARACTER_SELECT_INFO_GHOST, level, class);
			else
				_G["CharSelectCharacterButton"..index.."ButtonTextInfo"]:SetFormattedText(CHARACTER_SELECT_INFO, level, class);
			end
			_G["CharSelectCharacterButton"..index.."ButtonTextLocation"]:SetText(zone);
		end
		button:Show();

		-- setup paid service buttons
		_G["CharSelectCharacterCustomize"..index]:Hide();
		_G["CharSelectRaceChange"..index]:Hide();
		_G["CharSelectFactionChange"..index]:Hide();
		if ( PFC ) then
			_G["CharSelectFactionChange"..index]:Show();
		elseif ( PRC ) then
			_G["CharSelectRaceChange"..index]:Show();
		elseif ( PCC ) then
			_G["CharSelectCharacterCustomize"..index]:Show();
		end

		index = index + 1;
		if ( index > MAX_CHARACTERS_DISPLAYED ) then
			break;
		end
	end

	if ( numChars == 0 ) then
		CharacterSelectDeleteButton:Disable();
		CharSelectEnterWorldButton:Disable();
	else
		CharacterSelectDeleteButton:Enable();
		CharSelectEnterWorldButton:Enable();
	end

	CharacterSelect.createIndex = 0;
	CharSelectCreateCharacterButton:Hide();	
	
	local connected = IsConnectedToServer();
	for i=index, MAX_CHARACTERS_DISPLAYED, 1 do
		local button = _G["CharSelectCharacterButton"..index];
		if ( (CharacterSelect.createIndex == 0) and (numChars < MAX_CHARACTERS_PER_REALM) ) then
			CharacterSelect.createIndex = index;
			if ( connected ) then
				--If can create characters position and show the create button
				CharSelectCreateCharacterButton:SetID(index);
				--CharSelectCreateCharacterButton:SetPoint("TOP", button, "TOP", 0, -5);
				CharSelectCreateCharacterButton:Show();	
			end
		end
		_G["CharSelectCharacterCustomize"..index]:Hide();
		_G["CharSelectFactionChange"..index]:Hide();
		_G["CharSelectRaceChange"..index]:Hide();
		button:Hide();
		index = index + 1;
	end

	if ( numChars == 0 ) then
		CharacterSelect.selectedIndex = 0;
		CharacterSelect_SelectCharacter(CharacterSelect.selectedIndex, 1);
		return;
	end

	if ( CharacterSelect.selectLast == 1 ) then
		CharacterSelect.selectLast = 0;
		CharacterSelect_SelectCharacter(numChars, 1);
		return;
	end

	if ( (CharacterSelect.selectedIndex == 0) or (CharacterSelect.selectedIndex > numChars) ) then
		CharacterSelect.selectedIndex = 1;
	end
	CharacterSelect_SelectCharacter(CharacterSelect.selectedIndex, 1);
end

function CharacterSelectButton_OnClick(self)
	local id = self:GetID();
	if ( id ~= CharacterSelect.selectedIndex ) then
		CharacterSelect_SelectCharacter(id);
	end
end

function CharacterSelectButton_OnDoubleClick(self)
	local id = self:GetID();
	if ( id ~= CharacterSelect.selectedIndex ) then
		CharacterSelect_SelectCharacter(id);
	end
	CharacterSelect_EnterWorld();
end

function CharacterSelect_TabResize(self)
	local buttonMiddle = _G[self:GetName().."Middle"];
	local buttonMiddleDisabled = _G[self:GetName().."MiddleDisabled"];
	local width = self:GetTextWidth() - 8;
	local leftWidth = _G[self:GetName().."Left"]:GetWidth();
	buttonMiddle:SetWidth(width);
	buttonMiddleDisabled:SetWidth(width);
	self:SetWidth(width + (2 * leftWidth));
end

function CharacterSelect_SelectCharacter(id, noCreate)
	if ( id == CharacterSelect.createIndex ) then
		if ( not noCreate ) then
			PlaySound("gsCharacterSelectionCreateNew");
			SetGlueScreen("charcreate");
		end
	else
		CharacterSelect.currentModel = GetSelectBackgroundModel(id);
		SetBackgroundModel(CharacterSelect,CharacterSelect.currentModel);

		SelectCharacter(id);
	end
end

function CharacterDeleteDialog_OnShow()
	local name, race, class, level = GetCharacterInfo(CharacterSelect.selectedIndex);
	CharacterDeleteText1:SetFormattedText(CONFIRM_CHAR_DELETE, name, level, class);
	CharacterDeleteBackground:SetHeight(16 + CharacterDeleteText1:GetHeight() + CharacterDeleteText2:GetHeight() + 23 + CharacterDeleteEditBox:GetHeight() + 8 + CharacterDeleteButton1:GetHeight() + 16);
	CharacterDeleteButton1:Disable();
end

function CharacterSelect_EnterWorld()
	PlaySound("gsCharacterSelectionEnterWorld");
	StopGlueAmbience();
	EnterWorld();
end

function CharacterSelect_Exit()
	PlaySound("gsCharacterSelectionExit");
	DisconnectFromServer();
	SetGlueScreen("login");
end

function CharacterSelect_AccountOptions()
	PlaySound("gsCharacterSelectionAcctOptions");
end

function CharacterSelect_TechSupport()
	PlaySound("gsCharacterSelectionAcctOptions");
	LaunchURL(TECH_SUPPORT_URL);
end

function CharacterSelect_Delete()
	PlaySound("gsCharacterSelectionDelCharacter");
	if ( CharacterSelect.selectedIndex > 0 ) then
		CharacterDeleteDialog:Show();
	end
end

function CharacterSelect_ChangeRealm()
	PlaySound("gsCharacterSelectionDelCharacter");
	RequestRealmList(1);
end

function CharacterSelectFrame_OnMouseDown(button)
	if ( button == "LeftButton" ) then
		CHARACTER_SELECT_ROTATION_START_X = GetCursorPosition();
		CHARACTER_SELECT_INITIAL_FACING = GetCharacterSelectFacing();
	end
end

function CharacterSelectFrame_OnMouseUp(button)
	if ( button == "LeftButton" ) then
		CHARACTER_SELECT_ROTATION_START_X = nil
	end
end

function CharacterSelectFrame_OnUpdate()
	if ( CHARACTER_SELECT_ROTATION_START_X ) then
		local x = GetCursorPosition();
		local diff = (x - CHARACTER_SELECT_ROTATION_START_X) * CHARACTER_ROTATION_CONSTANT;
		CHARACTER_SELECT_ROTATION_START_X = GetCursorPosition();
		SetCharacterSelectFacing(GetCharacterSelectFacing() + diff);
	end
end

function CharacterSelectRotateRight_OnUpdate(self)
	if ( self:GetButtonState() == "PUSHED" ) then
		SetCharacterSelectFacing(GetCharacterSelectFacing() + CHARACTER_FACING_INCREMENT);
	end
end

function CharacterSelectRotateLeft_OnUpdate(self)
	if ( self:GetButtonState() == "PUSHED" ) then
		SetCharacterSelectFacing(GetCharacterSelectFacing() - CHARACTER_FACING_INCREMENT);
	end
end

function CharacterSelect_ManageAccount()
	PlaySound("gsCharacterSelectionAcctOptions");
	LaunchURL(AUTH_NO_TIME_URL);
end

function RealmSplit_GetFormatedChoice(formatText)
	if ( SERVER_SPLIT_CLIENT_STATE == 1 ) then
		realmChoice = SERVER_SPLIT_SERVER_ONE;
	else
		realmChoice = SERVER_SPLIT_SERVER_TWO;
	end
	return format(formatText, realmChoice);
end

function RealmSplit_SetChoiceText()
	RealmSplitCurrentChoice:SetText( RealmSplit_GetFormatedChoice(SERVER_SPLIT_CURRENT_CHOICE) );
	RealmSplitCurrentChoice:Show();
end

function CharacterSelect_PaidServiceOnClick(self, button, down, service)
	PAID_SERVICE_CHARACTER_ID = self:GetID();
	PAID_SERVICE_TYPE = service;
	PlaySound("gsCharacterSelectionCreateNew");
	SetGlueScreen("charcreate");
end

function CharacterSelect_DeathKnightSwap(self)
	if ( CharacterSelect.currentModel == "DEATHKNIGHT" ) then
		if (self.currentModel ~= "DEATHKNIGHT") then
			self.currentModel = "DEATHKNIGHT";
			self:SetNormalTexture("Interface\\Glues\\Common\\Glue-Panel-Button-Up-Blue");
			self:SetPushedTexture("Interface\\Glues\\Common\\Glue-Panel-Button-Down-Blue");
			self:SetHighlightTexture("Interface\\Glues\\Common\\Glue-Panel-Button-Highlight-Blue");
		end
	else
		if (self.currentModel == "DEATHKNIGHT") then
			self.currentModel = nil;
			self:SetNormalTexture("Interface\\Glues\\Common\\Glue-Panel-Button-Up");
			self:SetPushedTexture("Interface\\Glues\\Common\\Glue-Panel-Button-Down");
			self:SetHighlightTexture("Interface\\Glues\\Common\\Glue-Panel-Button-Highlight");
		end
	end
end


-- =====================================================================
-- EventWow: flujo automatico de seleccion de personaje
--   0 personajes -> pantalla de nombre (charcreate)
--   1 personaje  -> EnterWorld automatico
--   volver del mundo -> desconectar y volver al login
-- =====================================================================

EVENTWOW_CONFIG = {
	RACE = "HUMAN",          -- fileString de GetAvailableRaces (HUMAN, ORC, DWARF, NIGHTELF, SCOURGE, TAUREN, GNOME, TROLL, BLOODELF, DRAENEI)
	CLASS = "WARRIOR",       -- fileString de GetAvailableClasses (WARRIOR, PALADIN, HUNTER, ROGUE, PRIEST, DEATHKNIGHT, SHAMAN, MAGE, WARLOCK, DRUID)
	SEX = SEX_MALE,          -- SEX_MALE / SEX_FEMALE (el modelo nunca se ve; en los minijuegos se cambia)
	AUTO_ACTION_DELAY = 0.2, -- segundos antes de ejecutar la accion automatica

	-- Fondo de las pantallas de nombre y "Conectando..." (tapa la escena 3D)
	BACKGROUND = "Interface\\Glues\\LoadingScreens\\LoadScreenNorthrendWide",
	BACKGROUND_TEXCOORD = { 0, 1, 0, 1 }, -- left, right, top, bottom (recortar si la imagen trae relleno)
	BACKGROUND_SHADE = 0.45,              -- opacidad del velo negro encima (0 = nada, 1 = negro)
};

EVENTWOW_STR_CONNECTING = "Conectando...";
EVENTWOW_STR_ENTERING = "Entrando...";
EVENTWOW_STR_CREATING = "Creando...";

-- true solo entre "pulsar Login" y "EnterWorld". El cliente recarga el Lua de Glue al
-- volver del mundo, asi que tras un logout vale nil -> se vuelve al login en vez de re-entrar.
-- OJO: cualquier login automatico futuro (launcher, etc.) debe ponerlo a true.
EventWow_LoginPending = nil;

EventWow_CharSelect = { pendingAction = nil, timer = 0 };

function EventWow_ReturnToLogin()
	DisconnectFromServer();
	SetGlueScreen("login");
end

function EventWow_SetPending(action)
	EventWow_CharSelect.pendingAction = action;
	EventWow_CharSelect.timer = EVENTWOW_CONFIG.AUTO_ACTION_DELAY;
end

-- Frame opaco a pantalla completa que tapa la escena 3D (personaje y fondo)
-- Se pone al nivel del padre para quedar por debajo de los demas hijos.
function EventWow_CreateCover(name, parent)
	local f = CreateFrame("Frame", name, parent);
	f:SetAllPoints(parent);
	f:SetFrameLevel(parent:GetFrameLevel());

	-- Negro de base (por si la imagen no carga o no cubre todo)
	local base = f:CreateTexture(name.."Base", "BACKGROUND");
	base:SetAllPoints(f);
	base:SetTexture(0, 0, 0, 1);

	local image = f:CreateTexture(name.."Image", "BORDER");
	image:SetAllPoints(f);
	if ( image:SetTexture(EVENTWOW_CONFIG.BACKGROUND) ) then
		image:SetTexCoord(unpack(EVENTWOW_CONFIG.BACKGROUND_TEXCOORD));
	else
		image:Hide();
	end

	local shade = f:CreateTexture(name.."Shade", "ARTWORK");
	shade:SetAllPoints(f);
	shade:SetTexture(0, 0, 0, EVENTWOW_CONFIG.BACKGROUND_SHADE);
	return f;
end

function EventWow_CharSelect_OnLoad(self)
	local f = EventWow_CreateCover("EventWowCharSelectStatus", self);
	f:SetFrameLevel(self:GetFrameLevel() + 1);
	local text = f:CreateFontString("EventWowCharSelectStatusText", "OVERLAY", "GlueFontNormalHuge");
	text:SetPoint("CENTER", f, "CENTER", 0, 0);
	text:SetText(EVENTWOW_STR_CONNECTING);
end

function EventWow_CharSelect_OnShow()
	CharacterSelectUI:Hide();
	EventWowCharSelectStatusText:SetText(EVENTWOW_STR_CONNECTING);
	EventWow_CharSelect.pendingAction = nil;

	if ( not EventWow_LoginPending ) then
		-- No venimos de pulsar Login (p.ej. logout desde el mundo): ir al login
		EventWow_SetPending("login");
	end
end

function EventWow_OnCharacterListUpdate()
	if ( not IsConnectedToServer() ) then
		return;
	end
	if ( EventWow_CharSelect.pendingAction == "login" ) then
		return;
	end
	if ( GetNumCharacters() == 0 ) then
		EventWow_SetPending("create");
	else
		EventWow_SetPending("enter");
	end
end

function EventWow_CharSelect_OnUpdate(elapsed)
	local state = EventWow_CharSelect;
	if ( not state.pendingAction ) then
		return;
	end
	state.timer = state.timer - elapsed;
	if ( state.timer > 0 ) then
		return;
	end

	local action = state.pendingAction;
	state.pendingAction = nil;

	if ( action == "create" ) then
		SetGlueScreen("charcreate");
	elseif ( action == "enter" ) then
		if ( CharacterSelect.selectedIndex == 0 ) then
			CharacterSelect_SelectCharacter(1, 1);
		end
		EventWow_LoginPending = nil;
		EventWowCharSelectStatusText:SetText(EVENTWOW_STR_ENTERING);
		CharacterSelect_EnterWorld();
	elseif ( action == "login" ) then
		EventWow_ReturnToLogin();
	end
end

-- Marcar que el siguiente charselect viene de un login (AccountLogin.lua se carga antes que este archivo)
local EventWow_Orig_AccountLogin_Login = AccountLogin_Login;
function AccountLogin_Login()
	EventWow_LoginPending = true;
	EventWow_Orig_AccountLogin_Login();
end

-- ---------------------------------------------------------------------
-- EventWow: sustituir los dialogos de estado del motor por nuestro texto.
-- Si el motor actualiza el dialogo con otro texto (p.ej. un error),
-- se muestra el dialogo real para no ocultar el problema.
-- (GlueDialog.lua se carga antes que este archivo)
-- ---------------------------------------------------------------------
EVENTWOW_STATUS_REPLACE = {
	[CHAR_LIST_RETRIEVING] = EVENTWOW_STR_CONNECTING,
	[CHAR_LIST_RETRIEVED] = EVENTWOW_STR_CONNECTING,
	[CHAR_LOGIN_IN_PROGRESS] = EVENTWOW_STR_ENTERING,
	[CHAR_CREATE_IN_PROGRESS] = EVENTWOW_STR_CREATING,
	[CHAR_CREATE_SUCCESS] = EVENTWOW_STR_ENTERING,
};

EventWow_SuppressedDialog = nil; -- "which" del dialogo suprimido, o nil

-- Escribe el estado en la etiqueta de la pantalla que este visible
-- (EventWowCharCreateStatusText se crea en CharacterCreate.lua)
function EventWow_SetStatus(text)
	EventWowCharSelectStatusText:SetText(text);
	if ( EventWowCharCreateStatusText ) then
		EventWowCharCreateStatusText:SetText(text);
	end
end

local EventWow_Orig_GlueDialog_OnEvent = GlueDialog_OnEvent;
function GlueDialog_OnEvent(self, event, arg1, arg2, arg3)
	if ( event == "OPEN_STATUS_DIALOG" ) then
		local replacement = arg2 and EVENTWOW_STATUS_REPLACE[arg2];
		if ( replacement ) then
			EventWow_SuppressedDialog = arg1;
			EventWow_SetStatus(replacement);
			return;
		end
		EventWow_SuppressedDialog = nil;
	elseif ( event == "UPDATE_STATUS_DIALOG" and EventWow_SuppressedDialog ) then
		local replacement = arg1 and EVENTWOW_STATUS_REPLACE[arg1];
		if ( replacement ) then
			EventWow_SetStatus(replacement);
			return;
		end
		-- Mensaje distinto (error): mostrar el dialogo real
		local which = EventWow_SuppressedDialog;
		EventWow_SuppressedDialog = nil;
		if ( EventWowCharCreateStatusText ) then
			EventWowCharCreateStatusText:SetText("");
		end
		GlueDialog_Show(which, arg1);
	elseif ( event == "CLOSE_STATUS_DIALOG" ) then
		EventWow_SuppressedDialog = nil;
	end
	EventWow_Orig_GlueDialog_OnEvent(self, event, arg1, arg2, arg3);
end
