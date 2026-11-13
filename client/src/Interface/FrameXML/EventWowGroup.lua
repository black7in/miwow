-- EventWow: pagina "Grupo" de la seccion social del panel (EventWowSocial.lua: pestanas Grupo / Amigos).
-- Usa los grupos NATIVOS (API de grupo del cliente: InviteUnit, UninviteUnit, PromoteToLeader, LeaveParty).
-- La invitacion recibida es el dialogo nativo (StaticPopup PARTY_INVITE). Alt+clic en un nombre del chat invita.
-- Reglas en el servidor: modules/mod-eventwow/src/EventWowGroups.cpp (max 5, nunca banda, no en partida);
-- la cola en grupo la lanza el lider desde el panel (EventWowMatchMgr).

EVENTWOW_GROUP = {
	MAX_MEMBERS = 5,   -- MAXGROUPSIZE del core
	ROW_HEIGHT = 24,
	LEADER_ICON = "|TInterface\\GroupFrame\\UI-Group-LeaderIcon:14:14:0:0|t",
	COLOR_ROW_HOVER = { 1, 1, 1, 0.06 },
};

EVENTWOW_STR_GROUP_YOU = "(tú)";
EVENTWOW_STR_GROUP_OFFLINE = "desconectado";
EVENTWOW_STR_GROUP_EMPTY = "Libre";
EVENTWOW_STR_GROUP_HINT = "Invita a otros jugadores para buscar partida juntos.";
EVENTWOW_STR_GROUP_INVITE = "Invitar";
EVENTWOW_STR_GROUP_INVITE_PLACEHOLDER = "Nombre del jugador";
EVENTWOW_STR_GROUP_LEAVE = "Salir del grupo";
EVENTWOW_STR_GROUP_PROMOTE = "Líder";
EVENTWOW_STR_GROUP_KICK = "Expulsar";
EVENTWOW_STR_GROUP_WHISPER_TOOLTIP = "Clic: susurrar";

-- Miembros en orden: tu primero, luego party1..4
-- { unit, name, online, leader, isPlayer }
local function EventWow_GetMembers()
	local members = {};
	local count = GetNumPartyMembers();
	tinsert(members, {
		unit = "player",
		name = UnitName("player"),
		online = true,
		leader = count > 0 and IsPartyLeader(),
		isPlayer = true,
	});
	for i = 1, count do
		local unit = "party"..i;
		tinsert(members, {
			unit = unit,
			name = UnitName(unit) or "?",
			online = UnitIsConnected(unit),
			leader = UnitIsPartyLeader(unit),
		});
	end
	return members;
end

function EventWowGroup_IsInGroup()
	return GetNumPartyMembers() > 0;
end

-- Puede buscar partida por el grupo (o va solo)
function EventWowGroup_IsLeaderOrSolo()
	return not EventWowGroup_IsInGroup() or IsPartyLeader();
end

function EventWowGroup_GetSize()
	return GetNumPartyMembers() + 1;
end

function EventWowGroup_Update()
	local frame = EventWowGroupFrame;
	if ( not frame ) then
		return;
	end

	local inGroup = EventWowGroup_IsInGroup();
	local canInvite = not inGroup or IsPartyLeader();
	local members = EventWow_GetMembers();
	local amLeader = inGroup and IsPartyLeader();

	if ( EventWowSocial_UpdateTabs ) then
		EventWowSocial_UpdateTabs();
	end

	for i = 1, EVENTWOW_GROUP.MAX_MEMBERS do
		local row = _G["EventWowGroupRow"..i];
		local member = members[i];
		row.member = member;
		row.promote:Hide();
		row.kick:Hide();
		if ( member ) then
			local text = member.name;
			if ( member.leader ) then
				text = EVENTWOW_GROUP.LEADER_ICON.." "..text;
			end
			if ( member.isPlayer ) then
				text = text.." |cff808080"..EVENTWOW_STR_GROUP_YOU.."|r";
			elseif ( not member.online ) then
				text = text.." |cff808080"..EVENTWOW_STR_GROUP_OFFLINE.."|r";
			end
			row.name:SetText(text);
			if ( member.online ) then
				row.name:SetTextColor(1, 1, 1);
			else
				row.name:SetTextColor(0.5, 0.5, 0.5);
			end
			row.canManage = amLeader and not member.isPlayer;
			row:Show();
		elseif ( inGroup ) then
			row.name:SetText(EVENTWOW_STR_GROUP_EMPTY);
			row.name:SetTextColor(0.35, 0.35, 0.4);
			row.canManage = false;
			row:Show();
		else
			row:Hide();
		end
		if ( row.hover ) then
			row:GetScript("OnEnter")(row);
		end
	end

	if ( inGroup ) then
		EventWowGroupHint:Hide();
		EventWowGroupLeaveButton:Show();
	else
		EventWowGroupHint:Show();
		EventWowGroupLeaveButton:Hide();
	end

	if ( canInvite and #members < EVENTWOW_GROUP.MAX_MEMBERS ) then
		EventWowGroupInviteBox:Show();
		EventWowGroupInviteButton:Show();
		if ( strtrim(EventWowGroupInviteBox:GetText() or "") ~= "" ) then
			EventWowGroupInviteButton:Enable();
		else
			EventWowGroupInviteButton:Disable();
		end
	else
		EventWowGroupInviteBox:Hide();
		EventWowGroupInviteButton:Hide();
	end

	-- El boton de buscar partida depende del grupo
	if ( EventWowPanel_UpdateDetail and EventWowPanelDetail ) then
		EventWowPanel_UpdateDetail();
	end
end

function EventWowGroup_Invite(name)
	name = strtrim(name or "");
	if ( name == "" ) then
		return;
	end
	InviteUnit(name);
end

local function EventWow_SubmitInvite()
	local editBox = EventWowGroupInviteBox;
	EventWowGroup_Invite(editBox:GetText());
	editBox:SetText("");
	editBox:ClearFocus();
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
	local row = CreateFrame("Button", "EventWowGroupRow"..index, parent);
	row:SetHeight(EVENTWOW_GROUP.ROW_HEIGHT);
	row:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, -6 - (index - 1) * (EVENTWOW_GROUP.ROW_HEIGHT + 2));
	row:SetPoint("RIGHT", parent, "RIGHT", -8, 0);

	local hover = row:CreateTexture(nil, "BACKGROUND");
	hover:SetAllPoints(row);
	hover:SetTexture(unpack(EVENTWOW_GROUP.COLOR_ROW_HOVER));
	hover:Hide();

	local kick = EventWow_CreateSmallButton(row, EVENTWOW_STR_GROUP_KICK, 64);
	kick:SetPoint("RIGHT", row, "RIGHT", -2, 0);
	kick:SetScript("OnClick", function()
		if ( row.member ) then
			UninviteUnit(row.member.name);
		end
	end);
	row.kick = kick;

	local promote = EventWow_CreateSmallButton(row, EVENTWOW_STR_GROUP_PROMOTE, 48);
	promote:SetPoint("RIGHT", kick, "LEFT", -2, 0);
	promote:SetScript("OnClick", function()
		if ( row.member ) then
			PromoteToLeader(row.member.unit);
		end
	end);
	row.promote = promote;

	local name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight");
	name:SetPoint("LEFT", row, "LEFT", 6, 0);
	name:SetPoint("RIGHT", row, "RIGHT", -6, 0);
	name:SetJustifyH("LEFT");
	row.name = name;

	-- Botones de lider al pasar el raton (tambien sobre los propios botones)
	local function onEnter()
		row.hover = true;
		local member = row.member;
		if ( member and not member.isPlayer ) then
			hover:Show();
			GameTooltip:SetOwner(row, "ANCHOR_TOPLEFT");
			GameTooltip:SetText(EVENTWOW_STR_GROUP_WHISPER_TOOLTIP);
		end
		if ( row.canManage ) then
			promote:Show();
			kick:Show();
		end
	end
	local function onLeave()
		if ( row:IsMouseOver() ) then
			return;
		end
		row.hover = nil;
		hover:Hide();
		promote:Hide();
		kick:Hide();
		GameTooltip:Hide();
	end
	row:SetScript("OnEnter", onEnter);
	row:SetScript("OnLeave", onLeave);
	kick:HookScript("OnLeave", onLeave);
	promote:HookScript("OnLeave", onLeave);

	-- Clic: susurrar
	row:SetScript("OnClick", function()
		local member = row.member;
		if ( member and not member.isPlayer and EventWowChat_OpenConversation ) then
			local _, key = EventWowChat_OpenConversation(member.name);
			EventWowChat_SelectTab(key);
			EventWowChatEditBox:SetFocus();
		end
	end);

	row:Hide();
	return row;
end

function EventWowGroup_Create(parent)
	-- Pagina de la seccion social (EventWowSocial.lua coloca el marco; titulo y contador van en su pestana)
	local f = CreateFrame("Frame", "EventWowGroupFrame", parent);

	for i = 1, EVENTWOW_GROUP.MAX_MEMBERS do
		EventWow_CreateRow(f, i);
	end

	local hint = f:CreateFontString("EventWowGroupHint", "ARTWORK", "GameFontDisableSmall");
	hint:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -38);
	hint:SetPoint("RIGHT", f, "RIGHT", -14, 0);
	hint:SetJustifyH("LEFT");
	hint:SetText(EVENTWOW_STR_GROUP_HINT);

	-- Abajo: salir del grupo, y encima invitar
	local leave = CreateFrame("Button", "EventWowGroupLeaveButton", f, "UIPanelButtonTemplate");
	leave:SetHeight(22);
	leave:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 8);
	leave:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 8);
	leave:SetText(EVENTWOW_STR_GROUP_LEAVE);
	leave:SetScript("OnClick", function()
		PlaySound("igMainMenuOptionCheckBoxOff");
		LeaveParty();
	end);

	local invite = CreateFrame("Button", "EventWowGroupInviteButton", f, "UIPanelButtonTemplate");
	invite:SetSize(72, 22);
	invite:SetPoint("BOTTOMRIGHT", leave, "TOPRIGHT", 0, 6);
	invite:SetText(EVENTWOW_STR_GROUP_INVITE);
	invite:SetScript("OnClick", function()
		PlaySound("igMainMenuOptionCheckBoxOn");
		EventWow_SubmitInvite();
	end);

	local editBox = CreateFrame("EditBox", "EventWowGroupInviteBox", f, "InputBoxTemplate");
	editBox:SetHeight(22);
	editBox:SetPoint("BOTTOMLEFT", leave, "TOPLEFT", 6, 6);
	editBox:SetPoint("RIGHT", invite, "LEFT", -8, 0);
	editBox:SetAutoFocus(false);
	editBox:SetMaxLetters(12);  -- nombres de personaje

	local placeholder = editBox:CreateFontString(nil, "ARTWORK", "GameFontDisable");
	placeholder:SetPoint("LEFT", editBox, "LEFT", 2, 0);
	placeholder:SetText(EVENTWOW_STR_GROUP_INVITE_PLACEHOLDER);
	local function updatePlaceholder(self)
		if ( self:HasFocus() or self:GetText() ~= "" ) then
			placeholder:Hide();
		else
			placeholder:Show();
		end
		if ( strtrim(self:GetText() or "") ~= "" ) then
			invite:Enable();
		else
			invite:Disable();
		end
	end
	editBox:SetScript("OnEditFocusGained", updatePlaceholder);
	editBox:SetScript("OnEditFocusLost", updatePlaceholder);
	editBox:SetScript("OnTextChanged", updatePlaceholder);
	editBox:SetScript("OnEnterPressed", EventWow_SubmitInvite);
	editBox:SetScript("OnEscapePressed", function(self)
		self:ClearFocus();
	end);

	-- Sin EventWowGroup_Update aqui: el panel se esta construyendo (y EventWowMatch.lua aun no ha cargado).
	-- Se actualiza al mostrarse y con los eventos de grupo.
	f:SetScript("OnShow", EventWowGroup_Update);
	return f;
end

-- Eventos ---------------------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame", "EventWowGroupEventFrame");
eventFrame:RegisterEvent("PARTY_MEMBERS_CHANGED");
eventFrame:RegisterEvent("PARTY_LEADER_CHANGED");
eventFrame:RegisterEvent("PARTY_MEMBER_ENABLE");
eventFrame:RegisterEvent("PARTY_MEMBER_DISABLE");
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD");
eventFrame:SetScript("OnEvent", EventWowGroup_Update);
