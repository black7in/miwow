-- EventWow: inventario de partida estilo Dota/Warcraft III (servidor: EventWowInventory.cpp).
-- Casillas = las N primeras ranuras de la mochila nativa (contenedor 0, ranuras 1..N; N = inventorySlots del juego,
-- catalogo GAMES). Los objetos no se equipan: llevarlos ya da sus efectos (lo aplica el servidor).
-- A la derecha de la barra de habilidades; oro debajo. Las bolsas nativas siguen bloqueadas en partida (EventWow.lua).
--   Clic (izquierdo o derecho): usar el objeto si tiene "Uso:"; con el vendedor abierto, venderlo.
--   Arrastrar: mover/intercambiar entre casillas, soltar en el vendedor (vender) o en el suelo (destruir).
-- Usa la API nativa de contenedores directamente, como los botones de las bolsas originales (codigo de FrameXML).
--
--   [1] [2] [3]
--   [4] [5] [6]
--     350 oro

EVENTWOW_INVENTORY_FRAME = {
	COLUMNS = 3,
	BUTTON_SIZE = 37,  -- ItemButtonTemplate
	SPACING = 4,
	PADDING = 8,
	MONEY_HEIGHT = 18,
	GAP = 16,          -- separacion con la barra de habilidades
	EMPTY_TEXTURE = "Interface\\PaperDoll\\UI-Backpack-EmptySlot",
};

local frame;
local buttons = {};
local slots = 0;

local function EventWow_UpdateButton(button)
	local texture, count, locked = GetContainerItemInfo(0, button.slot);
	SetItemButtonTexture(button, texture);
	SetItemButtonCount(button, count);
	SetItemButtonDesaturated(button, locked);

	if ( texture ) then
		local start, duration, enable = GetContainerItemCooldown(0, button.slot);
		CooldownFrame_SetTimer(button.cooldown, start, duration, enable);
	else
		button.cooldown:Hide();
	end

	if ( GameTooltip:IsOwned(button) ) then
		button:GetScript("OnEnter")(button);
	end
end

local function EventWow_UpdateMoney()
	local money = GetMoney();
	if ( GetCoinTextureString ) then
		EventWowInventoryMoney:SetText(GetCoinTextureString(money));
	else
		EventWowInventoryMoney:SetText(GetCoinText(money, " "));
	end
end

function EventWowInventory_Update()
	for index = 1, slots do
		EventWow_UpdateButton(buttons[index]);
	end
	EventWow_UpdateMoney();
end

local function EventWow_OnClick(self)
	if ( CursorHasItem() ) then
		PickupContainerItem(0, self.slot);
		return;
	end

	local link = GetContainerItemLink(0, self.slot);
	if ( not link ) then
		return;
	end
	if ( IsModifiedClick("CHATLINK") ) then
		ChatEdit_InsertLink(link);
		return;
	end
	-- Sin "Uso:" no hay nada que hacer (equipar esta desactivado en partida), salvo vender
	if ( MerchantFrame:IsShown() or GetItemSpell(link) ) then
		UseContainerItem(0, self.slot);
	end
end

local function EventWow_GetButton(index)
	local button = buttons[index];
	if ( button ) then
		return button;
	end

	local name = "EventWowInventoryButton"..index;
	button = CreateFrame("Button", name, frame, "ItemButtonTemplate");
	button.slot = index;
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp");
	button:RegisterForDrag("LeftButton");

	local background = button:CreateTexture(nil, "BACKGROUND");
	background:SetAllPoints(button);
	background:SetTexture(EVENTWOW_INVENTORY_FRAME.EMPTY_TEXTURE);

	button.cooldown = CreateFrame("Cooldown", name.."Cooldown", button, "CooldownFrameTemplate");
	button.cooldown:SetAllPoints(_G[name.."IconTexture"]);

	button:SetScript("OnClick", EventWow_OnClick);
	button:SetScript("OnDragStart", function(self)
		PickupContainerItem(0, self.slot);
	end);
	button:SetScript("OnReceiveDrag", function(self)
		PickupContainerItem(0, self.slot);
	end);
	button:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOPRIGHT");
		if ( GameTooltip:SetBagItem(0, self.slot) ) then
			GameTooltip:Show();
		else
			GameTooltip:Hide();
		end
	end);
	button:SetScript("OnLeave", function()
		GameTooltip:Hide();
		ResetCursor();
	end);

	buttons[index] = button;
	return button;
end

-- Casillas del juego actual (0 = sin inventario: oculto)
local function EventWow_Layout(count)
	local config = EVENTWOW_INVENTORY_FRAME;
	slots = count;
	for index = 1, count do
		local button = EventWow_GetButton(index);
		local column = (index - 1) % config.COLUMNS;
		local row = floor((index - 1) / config.COLUMNS);
		button:ClearAllPoints();
		button:SetPoint("TOPLEFT", frame, "TOPLEFT", config.PADDING + column * (config.BUTTON_SIZE + config.SPACING),
			-config.PADDING - row * (config.BUTTON_SIZE + config.SPACING));
		button:Show();
	end
	for index = count + 1, #buttons do
		buttons[index]:Hide();
	end

	local columns = min(count, config.COLUMNS);
	local rows = ceil(count / config.COLUMNS);
	frame:SetWidth(config.PADDING * 2 + columns * config.BUTTON_SIZE + max(columns - 1, 0) * config.SPACING);
	frame:SetHeight(config.PADDING * 2 + rows * config.BUTTON_SIZE + max(rows - 1, 0) * config.SPACING
		+ config.MONEY_HEIGHT);
end

-- Visible en partida si el juego tiene casillas
function EventWowInventory_UpdateVisibility()
	local game = EventWowMatch_IsActive() and EventWowMatch_GetGame();
	local count = game and min(game.inventorySlots or 0, 16) or 0;
	if ( count == 0 ) then
		frame:Hide();
		return;
	end

	if ( count ~= slots ) then
		EventWow_Layout(count);
	end
	frame:Show();
	EventWowInventory_Update();
end

local function EventWow_CreateInventoryFrame()
	local config = EVENTWOW_INVENTORY_FRAME;
	frame = CreateFrame("Frame", "EventWowInventoryFrame", UIParent);
	frame:SetPoint("BOTTOMLEFT", EventWowAbilityBar, "BOTTOMRIGHT", config.GAP, -config.PADDING);
	frame:SetFrameStrata("MEDIUM");
	frame:SetBackdrop(EVENTWOW_PANEL.BACKDROP);
	frame:SetBackdropColor(unpack(EVENTWOW_PANEL.COLOR_SECTION));
	frame:SetBackdropBorderColor(unpack(EVENTWOW_PANEL.COLOR_BORDER));
	frame:EnableMouse(true);
	frame:Hide();

	local money = frame:CreateFontString("EventWowInventoryMoney", "ARTWORK", "GameFontHighlightSmall");
	money:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -config.PADDING, config.PADDING - 2);
	money:SetHeight(config.MONEY_HEIGHT);
	money:SetJustifyH("RIGHT");

	frame:RegisterEvent("BAG_UPDATE");
	frame:RegisterEvent("BAG_UPDATE_COOLDOWN");
	frame:RegisterEvent("ITEM_LOCK_CHANGED");
	frame:RegisterEvent("PLAYER_MONEY");
	frame:RegisterEvent("MERCHANT_SHOW");
	frame:RegisterEvent("MERCHANT_CLOSED");
	frame:SetScript("OnEvent", function(self, event, bag)
		if ( not self:IsShown() ) then
			return;
		end
		if ( event == "BAG_UPDATE" and bag ~= 0 ) then
			return;
		end
		EventWowInventory_Update();
	end);
end

EventWow_CreateInventoryFrame();
EventWow_RegisterListener("MATCH", EventWowInventory_UpdateVisibility);
EventWow_RegisterListener("GAMES", EventWowInventory_UpdateVisibility);
