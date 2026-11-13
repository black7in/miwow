-- EventWow: pagina "Amigos" de la seccion social del panel (EventWowSocial.lua: pestanas Grupo / Amigos).
-- Usa la lista de amigos NATIVA (GetFriendInfo, AddFriend, RemoveFriend, ShowFriends; evento FRIENDLIST_UPDATE):
-- se guarda en BD por personaje y el core avisa en el chat cuando un amigo se conecta/desconecta.
-- Servidor: los jugadores del lobby son invisibles en el mapa pero cuentan como conectados para la lista
-- (EventWowLobby.cpp, OnPlayerNotVisibleGloballyFor).
--
--   [o] Nombre                 Ausente    <- al pasar el raton: [Invitar] [Quitar]; clic = susurrar
--   [o] Nombre             desconectado
--   [ Nombre del jugador      ] [Anadir]

EVENTWOW_FRIENDS = {
	ROW_HEIGHT = 24,
	MAX_ROWS = 20,
	COLOR_ONLINE = { 0.2, 0.9, 0.2 },
	COLOR_AFK = { 1, 0.82, 0 },
	COLOR_DND = { 1, 0.25, 0.25 },
	COLOR_OFFLINE = { 0.35, 0.35, 0.4 },
	COLOR_ROW_HOVER = { 1, 1, 1, 0.06 },
};

EVENTWOW_STR_FRIENDS_ADD = "Añadir";
EVENTWOW_STR_FRIENDS_ADD_PLACEHOLDER = "Nombre del jugador";
EVENTWOW_STR_FRIENDS_EMPTY = "Aún no tienes amigos. Añade a alguien por su nombre.";
EVENTWOW_STR_FRIENDS_AFK = "Ausente";
EVENTWOW_STR_FRIENDS_DND = "Ocupado";
EVENTWOW_STR_FRIENDS_OFFLINE = "desconectado";
EVENTWOW_STR_FRIENDS_INVITE = "Invitar";
EVENTWOW_STR_FRIENDS_REMOVE = "Quitar";
EVENTWOW_STR_FRIENDS_REMOVE_CONFIRM = "¿Quitar a %s de tus amigos?";
EVENTWOW_STR_FRIENDS_WHISPER_TOOLTIP = "Clic: susurrar";
EVENTWOW_STR_FRIENDS_NOTE = "Nota: %s";

EventWow_Friends = {
	offset = 0,
	visibleRows = 1,
	-- { name, connected, status ("" | CHAT_FLAG_AFK | CHAT_FLAG_DND), note }, conectados primero
	list = {},
};

StaticPopupDialogs["EVENTWOW_REMOVE_FRIEND"] = {
	text = EVENTWOW_STR_FRIENDS_REMOVE_CONFIRM,
	button1 = YES,
	button2 = NO,
	OnAccept = function(self, name)
		RemoveFriend(name);
	end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1,
};

local function EventWow_BuildList()
	local list = {};
	for i = 1, GetNumFriends() do
		local name, _, _, _, connected, status, note = GetFriendInfo(i);
		if ( name ) then
			tinsert(list, { name = name, connected = connected and true or false, status = status or "", note = note });
		end
	end
	table.sort(list, function(a, b)
		if ( a.connected ~= b.connected ) then
			return a.connected;
		end
		return a.name < b.name;
	end);
	return list;
end

-- Conectados, total
function EventWowFriends_GetCounts()
	local online = 0;
	for _, friend in ipairs(EventWow_Friends.list) do
		if ( friend.connected ) then
			online = online + 1;
		end
	end
	return online, #EventWow_Friends.list;
end

local function EventWow_IsInMyGroup(name)
	for i = 1, GetNumPartyMembers() do
		if ( UnitName("party"..i) == name ) then
			return true;
		end
	end
	return false;
end

-- Se le puede invitar al grupo desde la lista
local function EventWow_CanInvite(friend)
	if ( not friend.connected or EventWow_IsInMyGroup(friend.name) ) then
		return false;
	end
	if ( GetNumPartyMembers() == 0 ) then
		return true;
	end
	return IsPartyLeader() and GetNumPartyMembers() + 1 < EVENTWOW_GROUP.MAX_MEMBERS;
end

local function EventWow_StatusColor(friend)
	if ( not friend.connected ) then
		return EVENTWOW_FRIENDS.COLOR_OFFLINE;
	elseif ( friend.status == CHAT_FLAG_AFK ) then
		return EVENTWOW_FRIENDS.COLOR_AFK;
	elseif ( friend.status == CHAT_FLAG_DND ) then
		return EVENTWOW_FRIENDS.COLOR_DND;
	end
	return EVENTWOW_FRIENDS.COLOR_ONLINE;
end

local function EventWow_StatusText(friend)
	if ( not friend.connected ) then
		return EVENTWOW_STR_FRIENDS_OFFLINE;
	elseif ( friend.status == CHAT_FLAG_AFK ) then
		return EVENTWOW_STR_FRIENDS_AFK;
	elseif ( friend.status == CHAT_FLAG_DND ) then
		return EVENTWOW_STR_FRIENDS_DND;
	end
	return "";
end

function EventWowFriends_Update()
	EventWow_Friends.list = EventWow_BuildList();
	if ( EventWowSocial_UpdateTabs ) then
		EventWowSocial_UpdateTabs();
	end

	local frame = EventWowFriendsFrame;
	if ( not frame ) then
		return;
	end

	local list = EventWow_Friends.list;
	local visibleRows = EventWow_Friends.visibleRows;
	EventWow_Friends.offset = math.min(math.max(EventWow_Friends.offset, 0), math.max(0, #list - visibleRows));

	for i = 1, EVENTWOW_FRIENDS.MAX_ROWS do
		local row = _G["EventWowFriendRow"..i];
		local friend = (i <= visibleRows) and list[i + EventWow_Friends.offset];
		row.friend = friend;
		if ( friend ) then
			row.dot:SetTexture(unpack(EventWow_StatusColor(friend)));
			row.name:SetText(friend.name);
			if ( friend.connected ) then
				row.name:SetTextColor(1, 1, 1);
			else
				row.name:SetTextColor(0.5, 0.5, 0.5);
			end
			row.status:SetText(EventWow_StatusText(friend));
			row:Show();
			if ( row.hover ) then
				row:GetScript("OnEnter")(row);
			end
		else
			row:Hide();
		end
	end

	if ( #list == 0 ) then
		EventWowFriendsEmpty:Show();
	else
		EventWowFriendsEmpty:Hide();
	end
end

-- Construccion ----------------------------------------------------------------------------------

local function EventWow_CreateSmallButton(parent, text, width)
	local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate");
	button:SetSize(width, 18);
	button:SetText(text);
	button:SetNormalFontObject(GameFontNormalSmall);
	button:SetHighlightFontObject(GameFontHighlightSmall);
	button:SetDisabledFontObject(GameFontDisableSmall);
	return button;
end

local function EventWow_CreateRow(parent, index)
	local row = CreateFrame("Button", "EventWowFriendRow"..index, parent);
	row:SetHeight(EVENTWOW_FRIENDS.ROW_HEIGHT);
	row:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, -6 - (index - 1) * (EVENTWOW_FRIENDS.ROW_HEIGHT + 2));
	row:SetPoint("RIGHT", parent, "RIGHT", -8, 0);

	local hover = row:CreateTexture(nil, "BACKGROUND");
	hover:SetAllPoints(row);
	hover:SetTexture(unpack(EVENTWOW_FRIENDS.COLOR_ROW_HOVER));
	hover:Hide();

	-- Estado: cuadradito de color
	local dot = row:CreateTexture(nil, "ARTWORK");
	dot:SetSize(8, 8);
	dot:SetPoint("LEFT", row, "LEFT", 6, 0);
	row.dot = dot;

	local remove = EventWow_CreateSmallButton(row, EVENTWOW_STR_FRIENDS_REMOVE, 56);
	remove:SetPoint("RIGHT", row, "RIGHT", -2, 0);
	remove:SetScript("OnClick", function()
		if ( row.friend ) then
			StaticPopup_Show("EVENTWOW_REMOVE_FRIEND", row.friend.name, nil, row.friend.name);
		end
	end);
	remove:Hide();
	row.remove = remove;

	local invite = EventWow_CreateSmallButton(row, EVENTWOW_STR_FRIENDS_INVITE, 56);
	invite:SetPoint("RIGHT", remove, "LEFT", -2, 0);
	invite:SetScript("OnClick", function()
		if ( row.friend ) then
			InviteUnit(row.friend.name);
		end
	end);
	invite:Hide();
	row.invite = invite;

	local status = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall");
	status:SetPoint("RIGHT", row, "RIGHT", -6, 0);
	row.status = status;

	local name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight");
	name:SetPoint("LEFT", dot, "RIGHT", 8, 0);
	name:SetPoint("RIGHT", status, "LEFT", -6, 0);
	name:SetJustifyH("LEFT");
	row.name = name;

	-- Botones al pasar el raton (tambien sobre los propios botones)
	local function onEnter()
		row.hover = true;
		local friend = row.friend;
		if ( not friend ) then
			return;
		end
		hover:Show();
		status:Hide();
		remove:Show();
		if ( EventWow_CanInvite(friend) ) then
			invite:Show();
		else
			invite:Hide();
		end
		GameTooltip:SetOwner(row, "ANCHOR_TOPLEFT");
		GameTooltip:SetText(friend.name);
		if ( friend.connected ) then
			GameTooltip:AddLine(EVENTWOW_STR_FRIENDS_WHISPER_TOOLTIP, 1, 1, 1);
		end
		if ( friend.note and friend.note ~= "" ) then
			GameTooltip:AddLine(format(EVENTWOW_STR_FRIENDS_NOTE, friend.note), 0.7, 0.7, 0.7, true);
		end
		GameTooltip:Show();
	end
	local function onLeave()
		if ( row:IsMouseOver() ) then
			return;
		end
		row.hover = nil;
		hover:Hide();
		remove:Hide();
		invite:Hide();
		status:Show();
		GameTooltip:Hide();
	end
	row:SetScript("OnEnter", onEnter);
	row:SetScript("OnLeave", onLeave);
	remove:HookScript("OnLeave", onLeave);
	invite:HookScript("OnLeave", onLeave);

	-- Clic: susurrar (si esta conectado)
	row:SetScript("OnClick", function()
		local friend = row.friend;
		if ( friend and friend.connected and EventWowChat_OpenConversation ) then
			local _, key = EventWowChat_OpenConversation(friend.name);
			EventWowChat_SelectTab(key);
			EventWowChatEditBox:SetFocus();
		end
	end);

	row:Hide();
	return row;
end

-- Filas que caben segun el alto (sobre la caja de anadir)
local function EventWow_Layout(self)
	local height = self:GetHeight() or 0;
	local rows = math.floor((height - 6 - 40) / (EVENTWOW_FRIENDS.ROW_HEIGHT + 2));
	EventWow_Friends.visibleRows = math.max(1, math.min(EVENTWOW_FRIENDS.MAX_ROWS, rows));
	EventWowFriends_Update();
end

local function EventWow_SubmitAdd()
	local editBox = EventWowFriendsAddBox;
	local name = strtrim(editBox:GetText() or "");
	if ( name ~= "" ) then
		AddFriend(name);
	end
	editBox:SetText("");
	editBox:ClearFocus();
end

function EventWowFriends_Create(parent)
	local f = CreateFrame("Frame", "EventWowFriendsFrame", parent);

	for i = 1, EVENTWOW_FRIENDS.MAX_ROWS do
		EventWow_CreateRow(f, i);
	end

	local empty = f:CreateFontString("EventWowFriendsEmpty", "ARTWORK", "GameFontDisableSmall");
	empty:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -12);
	empty:SetPoint("RIGHT", f, "RIGHT", -14, 0);
	empty:SetJustifyH("LEFT");
	empty:SetText(EVENTWOW_STR_FRIENDS_EMPTY);

	local add = CreateFrame("Button", "EventWowFriendsAddButton", f, "UIPanelButtonTemplate");
	add:SetSize(72, 22);
	add:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 8);
	add:SetText(EVENTWOW_STR_FRIENDS_ADD);
	add:SetScript("OnClick", function()
		PlaySound("igMainMenuOptionCheckBoxOn");
		EventWow_SubmitAdd();
	end);
	add:Disable();

	local editBox = CreateFrame("EditBox", "EventWowFriendsAddBox", f, "InputBoxTemplate");
	editBox:SetHeight(22);
	editBox:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 8);
	editBox:SetPoint("RIGHT", add, "LEFT", -8, 0);
	editBox:SetAutoFocus(false);
	editBox:SetMaxLetters(12);  -- nombres de personaje

	local placeholder = editBox:CreateFontString(nil, "ARTWORK", "GameFontDisable");
	placeholder:SetPoint("LEFT", editBox, "LEFT", 2, 0);
	placeholder:SetText(EVENTWOW_STR_FRIENDS_ADD_PLACEHOLDER);
	local function updatePlaceholder(self)
		if ( self:HasFocus() or self:GetText() ~= "" ) then
			placeholder:Hide();
		else
			placeholder:Show();
		end
		if ( strtrim(self:GetText() or "") ~= "" ) then
			add:Enable();
		else
			add:Disable();
		end
	end
	editBox:SetScript("OnEditFocusGained", updatePlaceholder);
	editBox:SetScript("OnEditFocusLost", updatePlaceholder);
	editBox:SetScript("OnTextChanged", updatePlaceholder);
	editBox:SetScript("OnEnterPressed", EventWow_SubmitAdd);
	editBox:SetScript("OnEscapePressed", function(self)
		self:ClearFocus();
	end);

	f:EnableMouseWheel(true);
	f:SetScript("OnMouseWheel", function(self, delta)
		EventWow_Friends.offset = EventWow_Friends.offset - delta;
		EventWowFriends_Update();
	end);
	f:SetScript("OnSizeChanged", EventWow_Layout);
	-- Pide al servidor la lista actualizada al mostrarse (llega FRIENDLIST_UPDATE)
	f:SetScript("OnShow", function(self)
		ShowFriends();
		EventWow_Layout(self);
	end);
	return f;
end

-- Eventos ---------------------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame", "EventWowFriendsEventFrame");
eventFrame:RegisterEvent("FRIENDLIST_UPDATE");
eventFrame:RegisterEvent("PARTY_MEMBERS_CHANGED");
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD");
eventFrame:SetScript("OnEvent", function(self, event)
	if ( event == "PLAYER_ENTERING_WORLD" ) then
		ShowFriends();
	end
	EventWowFriends_Update();
end);
