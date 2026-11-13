-- EventWow: seccion social del panel (abajo a la derecha, junto al chat) con pestanas:
--   [Grupo (n/5)] -> EventWowGroup.lua      [Amigos (conectados/total)] -> EventWowFriends.lua
-- Al entrar en un grupo se pasa sola a la pestana Grupo.

EVENTWOW_SOCIAL = {
	WIDTH = 270,
	TAB_HEIGHT = 24,
	COLOR_TAB = { 0.07, 0.08, 0.11, 0.85 },
	COLOR_TAB_HOVER = { 0.12, 0.13, 0.17, 0.95 },
	COLOR_TAB_ACTIVE = { 0.17, 0.18, 0.24, 1 },
	COLOR_TAB_LINE = { 0.35, 0.35, 0.4, 0.8 },
	COLOR_ACCENT = { 1, 0.82, 0, 1 },
};

EVENTWOW_STR_SOCIAL_GROUP = "Grupo";
EVENTWOW_STR_SOCIAL_GROUP_COUNT = "Grupo (%d/%d)";
EVENTWOW_STR_SOCIAL_FRIENDS = "Amigos";
EVENTWOW_STR_SOCIAL_FRIENDS_COUNT = "Amigos (%d/%d)";

EventWow_Social = {
	-- "group" | "friends"
	activeTab = "group",
	inGroup = false,
	tabs = {},
};

local function EventWow_SetColor(texture, color)
	texture:SetTexture(color[1], color[2], color[3], color[4]);
end

local function EventWow_PaintTab(tab)
	if ( EventWow_Social.activeTab == tab.key ) then
		EventWow_SetColor(tab.bg, EVENTWOW_SOCIAL.COLOR_TAB_ACTIVE);
		tab.accent:Show();
		tab.label:SetTextColor(1, 1, 1);
	else
		EventWow_SetColor(tab.bg, tab.hover and EVENTWOW_SOCIAL.COLOR_TAB_HOVER or EVENTWOW_SOCIAL.COLOR_TAB);
		tab.accent:Hide();
		if ( tab.hover ) then
			tab.label:SetTextColor(0.9, 0.9, 0.9);
		else
			tab.label:SetTextColor(0.6, 0.6, 0.65);
		end
	end
end

function EventWowSocial_UpdateTabs()
	local group, friends = EventWow_Social.tabs.group, EventWow_Social.tabs.friends;
	if ( not group ) then
		return;
	end

	local partySize = GetNumPartyMembers();
	if ( partySize > 0 ) then
		group.label:SetText(format(EVENTWOW_STR_SOCIAL_GROUP_COUNT, partySize + 1, EVENTWOW_GROUP.MAX_MEMBERS));
	else
		group.label:SetText(EVENTWOW_STR_SOCIAL_GROUP);
	end

	local online, total = EventWowFriends_GetCounts();
	if ( total > 0 ) then
		friends.label:SetText(format(EVENTWOW_STR_SOCIAL_FRIENDS_COUNT, online, total));
	else
		friends.label:SetText(EVENTWOW_STR_SOCIAL_FRIENDS);
	end

	EventWow_PaintTab(group);
	EventWow_PaintTab(friends);
end

function EventWowSocial_SelectTab(key)
	EventWow_Social.activeTab = key;
	if ( key == "friends" ) then
		EventWowGroupFrame:Hide();
		EventWowFriendsFrame:Show();
	else
		EventWowFriendsFrame:Hide();
		EventWowGroupFrame:Show();
	end
	EventWowSocial_UpdateTabs();
end

local function EventWow_CreateTab(parent, key)
	local tab = CreateFrame("Button", nil, parent);
	tab.key = key;
	tab:SetHeight(EVENTWOW_SOCIAL.TAB_HEIGHT);

	tab.bg = tab:CreateTexture(nil, "BACKGROUND");
	tab.bg:SetAllPoints(tab);

	tab.accent = tab:CreateTexture(nil, "ARTWORK");
	tab.accent:SetHeight(2);
	tab.accent:SetPoint("TOPLEFT", tab, "TOPLEFT", 0, 0);
	tab.accent:SetPoint("TOPRIGHT", tab, "TOPRIGHT", 0, 0);
	EventWow_SetColor(tab.accent, EVENTWOW_SOCIAL.COLOR_ACCENT);

	tab.label = tab:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall");
	tab.label:SetPoint("LEFT", tab, "LEFT", 4, 0);
	tab.label:SetPoint("RIGHT", tab, "RIGHT", -4, 0);

	tab:SetScript("OnEnter", function(self)
		self.hover = true;
		EventWow_PaintTab(self);
	end);
	tab:SetScript("OnLeave", function(self)
		self.hover = nil;
		EventWow_PaintTab(self);
	end);
	tab:SetScript("OnClick", function(self)
		PlaySound("igMainMenuOptionCheckBoxOn");
		EventWowSocial_SelectTab(self.key);
	end);

	EventWow_Social.tabs[key] = tab;
	return tab;
end

function EventWowSocial_Create(parent)
	local f = CreateFrame("Frame", "EventWowSocialFrame", parent);
	f:SetWidth(EVENTWOW_SOCIAL.WIDTH);

	-- Linea bajo las pestanas (las pestanas se apoyan en ella, mitad y mitad)
	local line = f:CreateTexture("EventWowSocialTabLine", "ARTWORK");
	line:SetHeight(1);
	line:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -6 - EVENTWOW_SOCIAL.TAB_HEIGHT);
	line:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6 - EVENTWOW_SOCIAL.TAB_HEIGHT);
	EventWow_SetColor(line, EVENTWOW_SOCIAL.COLOR_TAB_LINE);

	local tabWidth = math.floor((EVENTWOW_SOCIAL.WIDTH - 12 - 2) / 2);
	local group = EventWow_CreateTab(f, "group");
	group:SetWidth(tabWidth);
	group:SetPoint("BOTTOMLEFT", line, "TOPLEFT", 0, 0);
	local friends = EventWow_CreateTab(f, "friends");
	friends:SetWidth(tabWidth);
	friends:SetPoint("BOTTOMRIGHT", line, "TOPRIGHT", 0, 0);

	-- Paginas: debajo de la linea
	for _, page in ipairs({ EventWowGroup_Create(f), EventWowFriends_Create(f) }) do
		page:SetPoint("TOPLEFT", line, "BOTTOMLEFT", -6, 0);
		page:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0);
	end

	EventWowSocial_SelectTab(EventWow_Social.activeTab);
	return f;
end

-- Al entrar en un grupo: pestana Grupo
local eventFrame = CreateFrame("Frame", "EventWowSocialEventFrame");
eventFrame:RegisterEvent("PARTY_MEMBERS_CHANGED");
eventFrame:SetScript("OnEvent", function()
	local inGroup = GetNumPartyMembers() > 0;
	if ( inGroup and not EventWow_Social.inGroup and EventWowSocialFrame ) then
		EventWowSocial_SelectTab("group");
	end
	EventWow_Social.inGroup = inGroup;
	EventWowSocial_UpdateTabs();
end);
