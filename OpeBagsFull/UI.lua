local _, ns = ...

-- The "Make room" panel, the button on the backpack, and the alerts.

local ROWS, ROW_HEIGHT = 8, 22
local panel, bagButton

---------------------------------------------------------------------------
-- Panel
---------------------------------------------------------------------------

local function ShowItemTooltip(row)
	local item = row.item
	if not item then
		return
	end
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	GameTooltip:SetBagItem(item.bag, item.slot)
	GameTooltip:Show()
end

local function HideTooltip()
	GameTooltip:Hide()
end

local function CreateRow(parent, index)
	local row = CreateFrame("Button", nil, parent)
	row:SetSize(288, ROW_HEIGHT - 2)
	row:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, -88 - (index - 1) * ROW_HEIGHT)

	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(18, 18)
	row.icon:SetPoint("LEFT", 0, 0)

	row.keep = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
	row.keep:SetSize(46, 18)
	row.keep:SetPoint("RIGHT", 0, 0)
	row.keep:SetText("Keep")
	row.keep:SetScript("OnClick", function()
		if row.item then
			ns.SetListed("keep", row.item.itemID, true)
			ns.Print(ns.ItemName(row.item.itemID) .. " added to your keep list (/ope unkeep to undo).")
		end
	end)
	row.keep:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText("Never trash or sell this item")
		GameTooltip:Show()
	end)
	row.keep:SetScript("OnLeave", HideTooltip)

	row.value = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.value:SetPoint("RIGHT", row.keep, "LEFT", -6, 0)
	row.value:SetJustifyH("RIGHT")

	row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
	row.text:SetPoint("RIGHT", row.value, "LEFT", -6, 0)
	row.text:SetJustifyH("LEFT")
	row.text:SetWordWrap(false)

	row:SetScript("OnEnter", ShowItemTooltip)
	row:SetScript("OnLeave", HideTooltip)
	row:Hide()
	return row
end

local function SavePosition(self)
	self:StopMovingOrSizing()
	local point, _, relativePoint, x, y = self:GetPoint()
	ns.db.panelPoint = { point, relativePoint, x, y }
end

function ns.CreatePanel()
	if panel then
		return panel
	end
	panel = CreateFrame("Frame", "OpeBagsFullPanel", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	panel:SetSize(320, 140 + ROWS * ROW_HEIGHT)
	local p = ns.db.panelPoint
	if type(p) == "table" and p[1] then
		panel:SetPoint(p[1], UIParent, p[2], p[3], p[4])
	else
		panel:SetPoint("RIGHT", UIParent, "RIGHT", -280, 40)
	end
	panel:SetFrameStrata("DIALOG")
	panel:SetToplevel(true)
	panel:SetClampedToScreen(true)
	panel:SetMovable(true)
	panel:EnableMouse(true)
	panel:RegisterForDrag("LeftButton")
	panel:SetScript("OnDragStart", panel.StartMoving)
	panel:SetScript("OnDragStop", SavePosition)
	if panel.SetBackdrop then
		panel:SetBackdrop({
			bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
			tile = true, tileSize = 32, edgeSize = 32,
			insets = { left = 11, right = 12, top = 12, bottom = 11 },
		})
	end
	panel:Hide()
	if UISpecialFrames then
		table.insert(UISpecialFrames, "OpeBagsFullPanel") -- Esc closes it
	end

	panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	panel.title:SetPoint("TOP", 0, -18)
	panel.title:SetText(ns.TITLE)

	local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", -6, -6)

	panel.status = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	panel.status:SetPoint("TOPLEFT", 20, -46)
	panel.status:SetJustifyH("LEFT")

	-- goal stepper: [-] 5 [+]
	panel.plus = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	panel.plus:SetSize(22, 20)
	panel.plus:SetPoint("TOPRIGHT", -20, -42)
	panel.plus:SetText("+")
	panel.goal = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	panel.goal:SetPoint("RIGHT", panel.plus, "LEFT", -6, 0)
	panel.minus = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	panel.minus:SetSize(22, 20)
	panel.minus:SetPoint("RIGHT", panel.goal, "LEFT", -6, 0)
	panel.minus:SetText("-")
	panel.goalLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	panel.goalLabel:SetPoint("RIGHT", panel.minus, "LEFT", -6, 0)
	panel.goalLabel:SetText("Goal")
	panel.plus:SetScript("OnClick", function()
		ns.SetGoal(ns.db.goal + 1)
	end)
	panel.minus:SetScript("OnClick", function()
		ns.SetGoal(ns.db.goal - 1)
	end)

	panel.info = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	panel.info:SetPoint("TOPLEFT", 20, -68)
	panel.info:SetWidth(280)
	panel.info:SetJustifyH("LEFT")

	panel.rows = {}
	for i = 1, ROWS do
		panel.rows[i] = CreateRow(panel, i)
	end
	panel.empty = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	panel.empty:SetPoint("TOP", 0, -100)
	panel.empty:SetWidth(270)

	panel.options = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	panel.options:SetSize(80, 26)
	panel.options:SetPoint("BOTTOMLEFT", 18, 18)
	panel.options:SetText("Options")
	panel.options:SetScript("OnClick", function()
		ns.OpenSettings()
	end)

	panel.action = CreateFrame("Button", "OpeBagsFullPanelAction", panel, "UIPanelButtonTemplate")
	panel.action:SetSize(196, 26)
	panel.action:SetPoint("BOTTOMRIGHT", -18, 18)
	panel.action:SetScript("OnClick", function()
		ns.MakeRoom()
	end)

	panel:SetScript("OnShow", function()
		ns.Refresh(true)
	end)
	return panel
end

-- What the main button says and whether it does anything right now.
function ns.ActionLabel(plan)
	if ns.stacking then
		return "Combining stacks...", false
	end
	if ns.AtMerchant() then
		local n = #ns.SellList(plan.need > 0 and plan or nil)
		if n > 0 then
			return ("Sell %d item%s"):format(n, n == 1 and "" or "s"), true
		end
	end
	if plan.need <= 0 then
		return "You have room", false
	end
	if #plan.moves > 0 and plan.stackFreed > 0 then
		return ("Combine stacks (+%d)"):format(plan.stackFreed), true
	end
	if #plan.trash > 0 then
		return ("Trash next (%d to go)"):format(#plan.trash), true
	end
	return "Nothing safe to trash", false
end

local function PlanSummary(plan)
	local parts = {}
	if plan.need <= 0 then
		return "Next to go when you need room:"
	end
	if plan.stackFreed > 0 then
		parts[#parts + 1] = ("combining stacks frees %d"):format(plan.stackFreed)
	end
	if #plan.trash > 0 then
		parts[#parts + 1] = ("trash %d (%s of vendor value)"):format(#plan.trash, ns.FormatMoney(plan.lost))
	end
	if plan.short > 0 then
		parts[#parts + 1] = ("%d more need white items allowed"):format(plan.short)
	end
	local text = table.concat(parts, ", then ")
	return text:sub(1, 1):upper() .. text:sub(2) .. "."
end

function ns.UpdatePanel()
	if not (panel and panel:IsShown()) then
		return
	end
	local plan = ns.Plan()
	local color = plan.need > 0 and "|cffff6060" or "|cff60ff60"
	panel.status:SetText(("Free slots: %s%d|r"):format(color, plan.free))
	panel.goal:SetText(plan.goal)
	panel.info:SetText(PlanSummary(plan))

	local candidates = ns.Candidates()
	for i, row in ipairs(panel.rows) do
		local item = candidates[i]
		row.item = item
		if item then
			row.icon:SetTexture(item.icon)
			row.text:SetText(ns.ItemLabel(item))
			row.value:SetText(ns.FormatMoney(item.value))
			-- items beyond what the goal needs are only a preview
			row:SetAlpha((plan.need > 0 and i > #plan.trash) and 0.45 or 1)
			row:Show()
		else
			row:Hide()
		end
	end
	if #candidates == 0 then
		panel.empty:SetText("No junk in your bags. To let white items go too, turn them on in Options.")
		panel.empty:Show()
	else
		panel.empty:Hide()
	end

	local label, enabled = ns.ActionLabel(plan)
	panel.action:SetText(label)
	panel.action:SetEnabled(enabled)
end

function ns.TogglePanel()
	ns.CreatePanel()
	panel:SetShown(not panel:IsShown())
end

function ns.ShowPanel()
	ns.CreatePanel()
	panel:Show()
	ns.UpdatePanel()
end

function ns.SetGoal(goal)
	ns.db.goal = math.max(1, math.min(40, math.floor(tonumber(goal) or ns.defaults.goal)))
	ns.Refresh(true)
end

---------------------------------------------------------------------------
-- Button on the backpack
---------------------------------------------------------------------------

local function BagButtonTooltip(self)
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:SetText(ns.TITLE)
	GameTooltip:AddLine(("%d free bag slots"):format(ns.FreeSlots()), 1, 1, 1)
	GameTooltip:AddLine("Click: make room", 0.8, 0.8, 0.8)
	GameTooltip:AddLine("Shift-click: trash the cheapest item", 0.8, 0.8, 0.8)
	GameTooltip:AddLine("Right-click: options", 0.8, 0.8, 0.8)
	GameTooltip:Show()
end

local BAG_BUTTON_SIZE = 32

function ns.CreateBagButton()
	if bagButton then
		return bagButton
	end
	-- An action-button-style icon with the free slot count on it, like a
	-- stack count.
	bagButton = CreateFrame("Button", "OpeBagsFullBagButton", UIParent)
	bagButton:SetSize(BAG_BUTTON_SIZE, BAG_BUTTON_SIZE)
	local icon = bagButton:CreateTexture(nil, "BACKGROUND")
	icon:SetAllPoints()
	icon:SetTexture(ns.ICON)
	icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	bagButton.Icon = icon
	-- The border art is 64px for a 36px button.
	local border = bagButton:CreateTexture(nil, "ARTWORK")
	border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
	border:SetSize(BAG_BUTTON_SIZE * 64 / 36, BAG_BUTTON_SIZE * 64 / 36)
	border:SetPoint("CENTER")
	bagButton:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
	bagButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	local count = bagButton:CreateFontString(nil, "OVERLAY", "NumberFontNormalLarge")
	count:SetPoint("BOTTOMRIGHT", -1, 2)
	count:SetJustifyH("RIGHT")
	bagButton.Count = count

	bagButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	bagButton:SetScript("OnClick", function(_, button)
		if button == "RightButton" then
			ns.OpenSettings()
		elseif IsShiftKeyDown() then
			ns.TrashNext()
		else
			ns.TogglePanel()
		end
	end)
	bagButton:SetScript("OnEnter", BagButtonTooltip)
	bagButton:SetScript("OnLeave", HideTooltip)
	bagButton:Hide()
	return bagButton
end

-- The default UI's backpack window: the combined bag on Forever (when turned
-- on), otherwise whichever ContainerFrame holds bag 0.
local function FindBackpackFrame()
	local combined = _G.ContainerFrameCombinedBags
	if combined and combined:IsShown() then
		return combined
	end
	for i = 1, NUM_CONTAINER_FRAMES or 13 do
		local frame = _G["ContainerFrame" .. i]
		if frame and frame:IsShown() and frame:GetID() == 0 then
			return frame
		end
	end
end

function ns.AttachBagButton()
	local button = ns.CreateBagButton()
	local target = ns.db.showBagButton and FindBackpackFrame()
	if target then
		button:SetParent(target)
		button:ClearAllPoints()
		button:SetPoint("TOPRIGHT", target, "TOPLEFT", -4, -40)
		button:SetFrameLevel(target:GetFrameLevel() + 5)
		ns.UpdateBagButton()
		button:Show()
	else
		button:Hide()
		button:SetParent(UIParent)
	end
end

function ns.UpdateBagButton()
	if bagButton then
		local free = ns.FreeSlots()
		bagButton.Count:SetText(free)
		if free <= math.max(ns.db.lowSpaceWarning, 0) then
			bagButton.Count:SetTextColor(1, 0.25, 0.25)
		else
			bagButton.Count:SetTextColor(1, 1, 1)
		end
	end
end

local function HookBagFrames()
	local function Reattach()
		C_Timer.After(0, ns.AttachBagButton)
	end
	local frames = { _G.ContainerFrameCombinedBags }
	for i = 1, NUM_CONTAINER_FRAMES or 13 do
		frames[#frames + 1] = _G["ContainerFrame" .. i]
	end
	for _, frame in pairs(frames) do
		if frame and frame.HookScript then
			frame:HookScript("OnShow", Reattach)
			frame:HookScript("OnHide", Reattach)
		end
	end
end

---------------------------------------------------------------------------
-- Refreshing
---------------------------------------------------------------------------

local refreshQueued = false
function ns.Refresh(now)
	if now then
		refreshQueued = false
		ns.UpdatePanel()
		ns.UpdateBagButton()
		return
	end
	if not refreshQueued then
		refreshQueued = true
		C_Timer.After(0.1, function()
			if refreshQueued then
				ns.Refresh(true)
			end
		end)
	end
end

---------------------------------------------------------------------------
-- Alerts
---------------------------------------------------------------------------

local ALERT_COOLDOWN = 8
local lastAlert, lastFree = -math.huge, nil

local function KeyHint()
	local key = GetBindingKey and GetBindingKey("OPEBAGSFULL_TRASHNEXT")
	if key then
		return "press " .. key .. " to trash the cheapest item"
	end
	return "shift-click Ope on your backpack to trash the cheapest item"
end

function ns.OnBagFull()
	if not ns.db.alertWhenFull or GetTime() - lastAlert < ALERT_COOLDOWN then
		return
	end
	lastAlert = GetTime()
	local next = ns.Candidates()[1]
	if next then
		ns.Print("Ope, bag's full! Cheapest to go: " .. ns.ItemLabel(next) .. " (" .. ns.FormatMoney(next.value) .. ") - " .. KeyHint() .. ".")
	else
		ns.Print("Ope, bag's full! Nothing is safe to trash with your settings; see /ope.")
	end
	if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then
		PlaySound(SOUNDKIT.RAID_WARNING)
	end
	ns.ShowPanel()
end

local function CheckLowSpace()
	local free = ns.FreeSlots()
	local threshold = ns.db.lowSpaceWarning
	if ns.ready and threshold > 0 and free <= threshold and lastFree and lastFree > threshold then
		ns.Print(("Only %d bag slot%s left."):format(free, free == 1 and "" or "s"))
	end
	lastFree = free
end

---------------------------------------------------------------------------
-- Events & entry points
---------------------------------------------------------------------------

ns.RegisterEvent("UI_ERROR_MESSAGE", function(_, _, message)
	if issecretvalue and issecretvalue(message) then
		return
	end
	if message and message == ERR_INV_FULL then
		ns.OnBagFull()
	end
end)

ns.RegisterEvent("BAG_UPDATE_DELAYED", function()
	CheckLowSpace()
	ns.Refresh()
end)
ns.RegisterEvent("ITEM_LOCK_CHANGED", function()
	ns.Refresh()
end)

ns.RegisterEvent("MERCHANT_SHOW", function()
	ns.merchantOpen = true
	-- let the merchant window finish opening first
	C_Timer.After(0.3, function()
		if ns.db.autoSellJunk and ns.AtMerchant() then
			ns.SellJunk()
		end
		ns.Refresh()
	end)
end)
ns.RegisterEvent("MERCHANT_CLOSED", function()
	ns.merchantOpen = false
	ns.Refresh()
end)

function ns.OnLogin()
	ns.CreateBagButton()
	HookBagFrames()
	lastFree = ns.FreeSlots()
	-- bags fill in over the first seconds after login; don't warn about that
	C_Timer.After(5, function()
		ns.ready = true
		lastFree = ns.FreeSlots()
	end)
end

-- Key bindings (Bindings.xml). Key presses count as hardware events.
BINDING_HEADER_OPEBAGSFULL = ns.TITLE
BINDING_NAME_OPEBAGSFULL_TRASHNEXT = "Trash the cheapest item"
BINDING_NAME_OPEBAGSFULL_MAKEROOM = "Make room (combine, then trash)"
BINDING_NAME_OPEBAGSFULL_TOGGLE = "Show/hide the Make room panel"

function OpeBagsFull_TrashNext()
	ns.TrashNext()
end
function OpeBagsFull_MakeRoom()
	ns.MakeRoom()
end
function OpeBagsFull_TogglePanel()
	ns.TogglePanel()
end
