local ADDON = ...

local TOTT = CreateFrame("Frame", "TakeOutTheTrashCore")
_G.TakeOutTheTrash = TOTT

local Container          = C_Container
local GetNumSlots        = (Container and Container.GetContainerNumSlots)      or _G.GetContainerNumSlots
local GetSlotItemInfo    = (Container and Container.GetContainerItemInfo)      or _G.GetContainerItemInfo
local GetSlotLink        = (Container and Container.GetContainerItemLink)      or _G.GetContainerItemLink
local PickupSlot         = (Container and Container.PickupContainerItem)       or _G.PickupContainerItem
local GetSlotQuestInfo   = (Container and Container.GetContainerItemQuestInfo) or _G.GetContainerItemQuestInfo
local GetItemInfo        = (C_Item and C_Item.GetItemInfo)                     or _G.GetItemInfo
local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant)              or _G.GetItemInfoInstant
local DeleteCursorItem   = _G.DeleteCursorItem or (C_Item and C_Item.DeleteCursorItem)

local POOR              = 0
local CLASS_TRADEGOODS  = 7
local CLASS_QUEST       = 12
local LAST_BAG          = NUM_BAG_SLOTS or 4
local TOOLTIP_EXTRA     = 12
local GRAY              = "|cff9d9d9d"
local PREFIX            = "|cffffd100Take out the Trash|r: "

local BLACKLIST = {
}

local DEFAULTS = {
	skipped   = {},
	blacklist = {},
	pos       = nil,
	hidden    = false,
	unlocked  = false,
	strict    = false,
}

local function Print(msg, ...)
	if select("#", ...) > 0 then msg = msg:format(...) end
	DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. msg)
end

local function Money(copper)
	copper = tonumber(copper) or 0
	if copper <= 0 then return GRAY .. "no value|r" end
	if GetCoinTextureString then return GetCoinTextureString(copper) end
	local g = math.floor(copper / 10000)
	local s = math.floor((copper % 10000) / 100)
	local c = copper % 100
	local out = ""
	if g > 0 then out = out .. g .. "g " end
	if g > 0 or s > 0 then out = out .. s .. "s " end
	return out .. c .. "c"
end

local function SlotInfo(bag, slot)
	if not GetSlotItemInfo then return nil end
	local a, b, c, d, e, f, g, h, i, j, k = GetSlotItemInfo(bag, slot)
	if type(a) == "table" then return a end
	if a == nil then return nil end
	return {
		iconFileID = a, stackCount = b, isLocked   = c, quality  = d,
		isReadable = e, hasLoot    = f, hyperlink  = g, isFiltered = h,
		hasNoValue = i, itemID     = j, isBound    = k,
	}
end

local questStartCache = {}
local function StartsQuest(bag, slot, itemID)
	if not ITEM_STARTS_QUEST then return false end
	if itemID and questStartCache[itemID] ~= nil then return questStartCache[itemID] end

	local found

	if C_TooltipInfo and C_TooltipInfo.GetBagItem then
		local data = C_TooltipInfo.GetBagItem(bag, slot)
		if data then
			if TooltipUtil and TooltipUtil.SurfaceArgs then TooltipUtil.SurfaceArgs(data) end
			found = false
			for _, line in ipairs(data.lines or {}) do
				if TooltipUtil and TooltipUtil.SurfaceArgs then TooltipUtil.SurfaceArgs(line) end
				local text = line.leftText
				if text and text:find(ITEM_STARTS_QUEST, 1, true) then
					found = true
					break
				end
			end
		end
	else
		local tip = TOTT.scanTip
		tip:SetOwner(UIParent, "ANCHOR_NONE")
		tip:ClearLines()
		if pcall(tip.SetBagItem, tip, bag, slot) and tip:NumLines() > 0 then
			found = false
			for n = 1, tip:NumLines() do
				local fs = _G["TakeOutTheTrashScanTooltipTextLeft" .. n]
				local text = fs and fs:GetText()
				if text and text:find(ITEM_STARTS_QUEST, 1, true) then
					found = true
					break
				end
			end
		end
		tip:Hide()
	end

	if found ~= nil and itemID then questStartCache[itemID] = found end
	return found
end

local function IsFlaggedQuestItem(bag, slot)
	if not GetSlotQuestInfo then return false end
	local a, b = GetSlotQuestInfo(bag, slot)
	if type(a) == "table" then
		return (a.isQuestItem or a.questID) and true or false
	end
	return (a or b) and true or false
end

local BLOCKING_FRAMES = {
	"MerchantFrame", "MailFrame", "TradeFrame", "BankFrame", "AuctionFrame",
	"AuctionHouseFrame", "GuildBankFrame", "VoidStorageFrame", "ItemSocketingFrame",
}

local function BlockingFrame()
	for _, name in ipairs(BLOCKING_FRAMES) do
		local f = _G[name]
		if f and f.IsShown and f:IsShown() then return name end
	end
	return nil
end

function TOTT:RejectReason(bag, slot, info)
	local db = TakeOutTheTrashDB

	if info.quality ~= POOR then return "not poor (gray) quality" end
	if info.isLocked          then return "slot is locked" end
	if info.hasLoot           then return "container still holds loot" end

	local itemID = info.itemID
	if not itemID            then return "item ID unavailable" end
	if BLACKLIST[itemID]     then return "on the built-in safe list" end
	if db.blacklist[itemID]  then return "on your blacklist" end
	if db.skipped[itemID]    then return "skipped by you" end

	local link = info.hyperlink or (GetSlotLink and GetSlotLink(bag, slot))
	if not link then return "item link unavailable" end

	local name, _, quality, _, _, _, _, _, _, _, sellPrice,
	      classID, _, _, _, _, isReagent = GetItemInfo(link)

	if not name then
		self.pendingItemData = true
		return "item data not cached yet"
	end
	if quality ~= POOR          then return "not poor (gray) quality" end
	if classID == CLASS_QUEST   then return "quest item" end
	if isReagent                then return "flagged as a crafting reagent" end
	if db.strict and classID == CLASS_TRADEGOODS then return "trade good (strict mode)" end
	if IsFlaggedQuestItem(bag, slot) then return "flagged as a quest item" end

	local starts = StartsQuest(bag, slot, itemID)
	if starts == nil  then return "tooltip could not be read" end
	if starts         then return "begins a quest" end

	return nil, {
		bag   = bag,
		slot  = slot,
		itemID = itemID,
		name  = name,
		link  = link,
		texture = info.iconFileID,
		count = info.stackCount or 1,
		unit  = sellPrice or 0,
		value = (sellPrice or 0) * (info.stackCount or 1),
	}
end

function TOTT:ScanBags(collectRejects)
	local list, rejects = {}, collectRejects and {} or nil
	self.pendingItemData = false
	local unreadable = 0

	for bag = 0, LAST_BAG do
		local numSlots = (GetNumSlots and GetNumSlots(bag)) or 0
		for slot = 1, numSlots do
			local info = SlotInfo(bag, slot)
			if info then
				local reason, item = self:RejectReason(bag, slot, info)
				if item then
					list[#list + 1] = item
				else
					if reason == "tooltip could not be read" then unreadable = unreadable + 1 end
					if rejects and info.quality == POOR then
						rejects[#rejects + 1] = {
							bag = bag, slot = slot, itemID = info.itemID,
							link = info.hyperlink, reason = reason,
						}
					end
				end
			end
		end
	end

	table.sort(list, function(a, b)
		if a.value ~= b.value then return a.value < b.value end
		if a.name  ~= b.name  then return (a.name or "") < (b.name or "") end
		if a.bag   ~= b.bag   then return a.bag < b.bag end
		return a.slot < b.slot
	end)

	self.items = list

	if unreadable >= 5 and not self.warnedUnreadable then
		self.warnedUnreadable = true
		Print("|cffff8080%d gray items were skipped because their tooltip could not be read.|r Run /tott debug for details.", unreadable)
	end

	return list, rejects
end

function TOTT:Skip(itemID, name)
	if not itemID then return end
	TakeOutTheTrashDB.skipped[itemID] = name or tostring(itemID)
	Print("Skipping %s%s|r from now on. (/tott unskip to undo)", GRAY, name or itemID)
	self:Refresh()
end

function TOTT:Destroy(item)
	local blocker = BlockingFrame()
	if blocker then
		Print("|cffff8080Not while %s is open.|r", blocker)
		return
	end

	if GetCursorInfo() then
		Print("|cffff8080Your cursor is already holding something. Clear it first.|r")
		return
	end

	local info = SlotInfo(item.bag, item.slot)
	if not info or info.itemID ~= item.itemID or info.quality ~= POOR or info.isLocked then
		Print("|cffff8080Bags changed since that was listed. Try again.|r")
		self:Refresh()
		return
	end

	ClearCursor()
	PickupSlot(item.bag, item.slot)

	local cursorType, cursorItemID = GetCursorInfo()
	if cursorType ~= "item" or cursorItemID ~= item.itemID then
		ClearCursor()
		Print("|cffff8080Could not pick up %s -- nothing was deleted.|r", item.name)
		self:Refresh()
		return
	end

	DeleteCursorItem()
	ClearCursor()
	Print("Destroyed %s%d x %s|r (%s)", GRAY, item.count, item.name, Money(item.value))

	if C_Timer then C_Timer.After(0.2, function() TOTT:Refresh() end) end
end

function TOTT:HandleClick(mouseButton)
	local button = mouseButton or (GetMouseButtonClicked and GetMouseButtonClicked()) or self.lastButton
	local shift  = IsShiftKeyDown()

	self:ScanBags()
	local top = self.items and self.items[1]

	if button == "RightButton" then
		if top then self:Skip(top.itemID, top.name) end
		return
	end

	if button == "LeftButton" then
		if not shift then return end
		if not top then
			Print("Nothing eligible to delete.")
			return
		end
		self:Destroy(top)
	end
end

function TOTT:FillTooltip(tt)
	tt:ClearLines()
	tt:AddLine("Take out the Trash", 1, 1, 1)

	local items = self.items
	if not items or #items == 0 then
		tt:AddLine(self.pendingItemData and "Loading item data..." or "No items found for deletion", 1, 0.4, 0.4)
	else
		local top = items[1]
		tt:AddLine("Shift click to destroy:", 0.9, 0.9, 0.9)
		tt:AddDoubleLine(("%s%d %s|r"):format(GRAY, top.count, top.name), Money(top.value), 1, 1, 1, 1, 1, 1)
		tt:AddLine("Right click to skip this item", 0.6, 0.6, 0.6)

		if #items > 1 then
			tt:AddLine(" ")
			tt:AddLine("More deletable items:", 0.8, 0.8, 0.8)
			local shown = math.min(#items, TOOLTIP_EXTRA + 1)
			for i = 2, shown do
				local it = items[i]
				tt:AddDoubleLine(("%s%d %s|r"):format(GRAY, it.count, it.name), Money(it.value))
			end
			if #items > shown then
				tt:AddLine(("...and %d more"):format(#items - shown), 0.6, 0.6, 0.6)
			end
		end
	end

	tt:AddLine(" ")
	tt:AddLine("Ctrl+drag to move   /tott for options", 0.4, 0.6, 1)
end

function TOTT:CreateButton()
	local b = CreateFrame("Button", "TakeOutTheTrashButton", UIParent)
	self.button = b

	b:SetSize(36, 36)
	b:SetMovable(true)
	b:EnableMouse(true)
	b:SetClampedToScreen(true)
	b:RegisterForDrag("LeftButton")
	b:RegisterForClicks("AnyUp")
	b:SetFrameStrata("MEDIUM")

	b:SetScript("OnClick", function(_, mouseButton)
		TOTT:HandleClick(mouseButton)
	end)

	local border = b:CreateTexture(nil, "BACKGROUND")
	border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
	border:SetPoint("CENTER", 0, -1)
	border:SetSize(36 * 1.8, 36 * 1.8)

	local icon = b:CreateTexture(nil, "ARTWORK")
	icon:SetPoint("TOPLEFT", 2, -2)
	icon:SetPoint("BOTTOMRIGHT", -2, 2)
	icon:SetTexture("Interface\\PaperDollInfoFrame\\UI-GearManager-LeaveItem-Transparent")
	b.icon = icon

	b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	b:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")

	local count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	count:SetPoint("BOTTOMRIGHT", -2, 2)
	b.count = count

	b:SetScript("OnDragStart", function(self)
		if not (IsControlKeyDown() or TakeOutTheTrashDB.unlocked) then return end
		self:StartMoving()
		self.isMoving = true
	end)

	b:SetScript("OnDragStop", function(self)
		if not self.isMoving then return end
		self.isMoving = nil
		self:StopMovingOrSizing()
		local point, _, _, x, y = self:GetPoint()
		TakeOutTheTrashDB.pos = { point = point, x = x, y = y }
	end)

	b:SetScript("PreClick", function(self, mouseButton)
		TOTT.lastButton = mouseButton
	end)

	b:SetScript("OnEnter", function(self)
		TOTT:ScanBags()
		TOTT:UpdateButton()
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		TOTT:FillTooltip(GameTooltip)
		GameTooltip:Show()
	end)

	b:SetScript("OnLeave", function() GameTooltip:Hide() end)

	self:RestorePosition()
end

function TOTT:RestorePosition()
	local b = self.button
	if not b then return end
	b:ClearAllPoints()
	local pos = TakeOutTheTrashDB.pos
	if pos then
		b:SetPoint(pos.point or "CENTER", UIParent, pos.point or "CENTER", pos.x or 0, pos.y or 0)
	else
		b:SetPoint("CENTER", UIParent, "CENTER", 0, -120)
	end
end

function TOTT:UpdateButton()
	local b = self.button
	if not b then return end

	if TakeOutTheTrashDB.hidden then
		b:Hide()
		return
	end
	b:Show()

	local n = self.items and #self.items or 0
	b.count:SetText(n > 0 and n or "")
	b.icon:SetDesaturated(n == 0)
	b.icon:SetAlpha(n == 0 and 0.45 or 1)
end

function TOTT:Refresh()
	self:ScanBags()
	self:UpdateButton()
	if self.button and self.button:IsShown() and GameTooltip:IsOwned(self.button) then
		self:FillTooltip(GameTooltip)
		GameTooltip:Show()
	end
end

local function ResolveItemID(arg)
	if not arg or arg == "" then return nil end
	local id = tonumber(arg)
	if id then return id end
	if GetItemInfoInstant then
		local itemID = GetItemInfoInstant(arg)
		if itemID then return itemID end
	end
	return tonumber(arg:match("item:(%d+)"))
end

local function Usage()
	Print("commands:")
	local lines = {
		"|cffffff00/tott|r ................ toggle the button",
		"|cffffff00/tott lock|r / |cffffff00unlock|r . require Ctrl to drag (default) or not",
		"|cffffff00/tott reset|r .......... move the button back to centre screen",
		"|cffffff00/tott list|r ........... show everything currently eligible",
		"|cffffff00/tott skips|r .......... show your skipped items",
		"|cffffff00/tott unskip <id or link>|r  un-skip one item",
		"|cffffff00/tott unskip all|r ..... clear the whole skip list",
		"|cffffff00/tott blacklist <id or link>|r  never offer this item, ever",
		"|cffffff00/tott strict|r ......... also exclude gray Trade Goods",
		"|cffffff00/tott debug|r .......... explain why each gray item was excluded",
	}
	for _, l in ipairs(lines) do DEFAULT_CHAT_FRAME:AddMessage("   " .. l) end
end

local function SlashHandler(msg)
	local db = TakeOutTheTrashDB
	msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
	local cmd, rest = msg:match("^(%S*)%s*(.*)$")
	cmd = (cmd or ""):lower()

	if cmd == "" then
		db.hidden = not db.hidden
		TOTT:Refresh()
		Print(db.hidden and "Button hidden. /tott to show it again." or "Button shown.")

	elseif cmd == "show" then
		db.hidden = false; TOTT:Refresh(); Print("Button shown.")

	elseif cmd == "hide" then
		db.hidden = true; TOTT:Refresh(); Print("Button hidden.")

	elseif cmd == "lock" then
		db.unlocked = false; Print("Button locked. Ctrl+drag to move it.")

	elseif cmd == "unlock" then
		db.unlocked = true; Print("Button unlocked. Plain drag moves it.")

	elseif cmd == "reset" then
		db.pos = nil; TOTT:RestorePosition(); Print("Button position reset.")

	elseif cmd == "strict" then
		db.strict = not db.strict
		TOTT:Refresh()
		Print("Strict mode %s. Gray Trade Goods are %s.",
			db.strict and "|cff00ff00ON|r" or "|cffff8080OFF|r",
			db.strict and "excluded" or "included")

	elseif cmd == "list" then
		local items = TOTT:ScanBags()
		if #items == 0 then Print("Nothing eligible.") return end
		Print("%d eligible item(s), cheapest first:", #items)
		for i, it in ipairs(items) do
			DEFAULT_CHAT_FRAME:AddMessage(("   %d. %s x%d  -  %s"):format(i, it.link, it.count, Money(it.value)))
		end

	elseif cmd == "skips" then
		local n = 0
		for id, name in pairs(db.skipped) do
			n = n + 1
			DEFAULT_CHAT_FRAME:AddMessage(("   %s%s|r (%d)"):format(GRAY, name, id))
		end
		Print(n == 0 and "No skipped items." or ("%d skipped item(s) above."):format(n))

	elseif cmd == "unskip" then
		if rest:lower() == "all" then
			wipe(db.skipped); TOTT:Refresh(); Print("Skip list cleared.")
		else
			local id = ResolveItemID(rest)
			if id and db.skipped[id] then
				Print("No longer skipping %s%s|r.", GRAY, db.skipped[id])
				db.skipped[id] = nil
				TOTT:Refresh()
			else
				Print("Not in the skip list. Usage: /tott unskip <itemID or item link>, or /tott unskip all")
			end
		end

	elseif cmd == "blacklist" then
		if rest:lower() == "all" then
			wipe(db.blacklist); TOTT:Refresh(); Print("Blacklist cleared.")
		else
			local id = ResolveItemID(rest)
			if not id then Print("Usage: /tott blacklist <itemID or item link>, or /tott blacklist all to clear") return end
			local name = GetItemInfo(id) or tostring(id)
			db.blacklist[id] = name
			TOTT:Refresh()
			Print("Blacklisted %s%s|r -- it will never be offered.", GRAY, name)
		end

	elseif cmd == "debug" then
		local items, rejects = TOTT:ScanBags(true)
		Print("%d eligible, %d gray item(s) excluded:", #items, #rejects)
		for _, r in ipairs(rejects) do
			DEFAULT_CHAT_FRAME:AddMessage(("   [%d:%d] %s -- |cffff8080%s|r")
				:format(r.bag, r.slot, r.link or ("itemID " .. tostring(r.itemID)), r.reason or "?"))
		end

	else
		Usage()
	end
end

TOTT.scanTip = CreateFrame("GameTooltip", "TakeOutTheTrashScanTooltip", nil, "GameTooltipTemplate")
TOTT.scanTip:SetOwner(UIParent, "ANCHOR_NONE")

TOTT:RegisterEvent("ADDON_LOADED")
TOTT:RegisterEvent("PLAYER_LOGIN")
TOTT:RegisterEvent("BAG_UPDATE_DELAYED")
TOTT:RegisterEvent("GET_ITEM_INFO_RECEIVED")

TOTT:RegisterEvent("ADDON_ACTION_BLOCKED")
TOTT:RegisterEvent("ADDON_ACTION_FORBIDDEN")

TOTT:SetScript("OnEvent", function(self, event, arg1, arg2)
	if event == "ADDON_LOADED" and arg1 == ADDON then
		TakeOutTheTrashDB = TakeOutTheTrashDB or {}
		for k, v in pairs(DEFAULTS) do
			if TakeOutTheTrashDB[k] == nil then
				TakeOutTheTrashDB[k] = (type(v) == "table") and {} or v
			end
		end

	elseif event == "PLAYER_LOGIN" then
		self:CreateButton()
		self:Refresh()

	elseif event == "BAG_UPDATE_DELAYED" then
		self:Refresh()

	elseif event == "GET_ITEM_INFO_RECEIVED" then
		if self.pendingItemData then self:Refresh() end

	elseif event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
		if arg1 == ADDON then
			Print("|cffff8080The client blocked %s (%s).|r Please report this.",
				tostring(arg2 or "a protected call"), event)
		end
	end
end)

SLASH_TAKEOUTTHETRASH1 = "/tott"
SLASH_TAKEOUTTHETRASH2 = "/takeoutthetrash"
SlashCmdList["TAKEOUTTHETRASH"] = SlashHandler
