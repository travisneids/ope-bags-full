-- Minimal WoW client mock for Ope, Bag's Full: bags, the cursor, a vendor,
-- frames, settings and timers. It enforces Blizzard's rule that
-- DeleteCursorItem needs a hardware event and deletes only one item per event.

Mock = {}

local state, items
local ITEM_DB = {}

function Mock.Reset()
	state = {
		time = 1000,
		interface = 16001,
		bags = {}, -- [bag] = { size, family, slots = { [slot] = { id, count, locked } } }
		cursor = nil, -- { bag, slot, id, count, split = bool }
		merchantShown = false,
		money = 0,
		hardware = nil, -- { deletes = n } while a click/key press is being handled
		pendingUnlocks = {},
		secretValues = {},
		shift = false,
		bindings = {},
		sounds = {},
		used = {}, -- items "used" away from a vendor (should never happen)
	}
	Mock.state = state
	Mock.printed = {}
	Mock.timers = {}
	Mock.frames = {}
	Mock.events = {}
	Mock.deleted = {}
	Mock.sold = {}
	Mock.settings = { categories = {}, settings = {}, controls = 0 }
	Mock.blocked = {}
	items = ITEM_DB
end

-- Items -------------------------------------------------------------------------

-- Mock.DefineItem(id, { name, quality, price, class, maxStack, quest })
function Mock.DefineItem(id, def)
	def.maxStack = def.maxStack or 1
	def.class = def.class or 15
	ITEM_DB[id] = def
end

local function Link(id)
	local def = ITEM_DB[id]
	return ("|cff9d9d9d|Hitem:%d::::::::|h[%s]|h|r"):format(id, def and def.name or "?")
end

-- Bags --------------------------------------------------------------------------

function Mock.SetBag(bag, size, family)
	state.bags[bag] = { size = size, family = family or 0, slots = {} }
end

function Mock.Put(bag, slot, id, count)
	assert(ITEM_DB[id], "undefined item " .. id)
	state.bags[bag].slots[slot] = { id = id, count = count or 1 }
end

function Mock.Get(bag, slot)
	local b = state.bags[bag]
	return b and b.slots[slot]
end

-- Fill every empty slot of a bag with a unique-per-slot filler item.
function Mock.Fill(bag, id)
	local b = state.bags[bag]
	for slot = 1, b.size do
		if not b.slots[slot] then
			b.slots[slot] = { id = id, count = 1 }
		end
	end
end

function Mock.CountItem(id)
	local n = 0
	for _, b in pairs(state.bags) do
		for _, s in pairs(b.slots) do
			if s.id == id then
				n = n + s.count
			end
		end
	end
	return n
end

-- Server round-trip: items moved this frame unlock.
function Mock.ServerTick()
	if #state.pendingUnlocks == 0 then
		return
	end
	for _, s in ipairs(state.pendingUnlocks) do
		s.locked = nil
	end
	state.pendingUnlocks = {}
	Mock.Fire("ITEM_LOCK_CHANGED")
	Mock.Fire("BAG_UPDATE_DELAYED")
end

local function Lock(s)
	s.locked = true
	state.pendingUnlocks[#state.pendingUnlocks + 1] = s
end

C_Container = {}
function C_Container.GetContainerNumSlots(bag)
	local b = state.bags[bag]
	return b and b.size or 0
end
function C_Container.GetContainerNumFreeSlots(bag)
	local b = state.bags[bag]
	if not b then
		return 0, 0
	end
	local free = 0
	for slot = 1, b.size do
		if not b.slots[slot] then
			free = free + 1
		end
	end
	return free, b.family
end
function C_Container.GetContainerItemInfo(bag, slot)
	local s = Mock.Get(bag, slot)
	if not s then
		return nil
	end
	local def = ITEM_DB[s.id]
	return {
		itemID = s.id, stackCount = s.count, isLocked = s.locked and true or false, quality = def.quality,
		hyperlink = Link(s.id), iconFileID = 1000 + s.id, hasNoValue = (def.price or 0) == 0,
		itemName = def.name, isBound = false,
	}
end
function C_Container.GetContainerItemQuestInfo(bag, slot)
	local s = Mock.Get(bag, slot)
	local def = s and ITEM_DB[s.id]
	return { isQuestItem = def and def.quest or false, questID = nil, isActive = false }
end

function C_Container.PickupContainerItem(bag, slot)
	local s = Mock.Get(bag, slot)
	local cur = state.cursor
	if not cur then
		if s and not s.locked then
			state.cursor = { bag = bag, slot = slot, id = s.id, count = s.count }
			Lock(s)
		end
		return
	end
	-- dropping what's on the cursor
	local src = Mock.Get(cur.bag, cur.slot)
	if bag == cur.bag and slot == cur.slot then
		state.cursor = nil
		return
	end
	if not s then
		state.bags[bag].slots[slot] = { id = cur.id, count = cur.count }
		src.count = src.count - cur.count
	elseif s.id == cur.id then
		local max = ITEM_DB[s.id].maxStack
		local moved = math.min(max - s.count, cur.count)
		s.count = s.count + moved
		src.count = src.count - moved
		Lock(s)
	else
		error("mock: swapping different items is not simulated")
	end
	if src.count <= 0 then
		state.bags[cur.bag].slots[cur.slot] = nil
	end
	state.cursor = nil
end
function C_Container.SplitContainerItem(bag, slot, amount)
	local s = Mock.Get(bag, slot)
	assert(s and not s.locked and amount > 0 and amount <= s.count, "bad split")
	assert(not state.cursor, "split with a full cursor")
	state.cursor = { bag = bag, slot = slot, id = s.id, count = amount, split = true }
	Lock(s)
end
function C_Container.UseContainerItem(bag, slot)
	local s = Mock.Get(bag, slot)
	if not s then
		return
	end
	if not state.merchantShown then
		state.used[#state.used + 1] = s.id
		return
	end
	local def = ITEM_DB[s.id]
	state.money = state.money + (def.price or 0) * s.count
	Mock.sold[#Mock.sold + 1] = { id = s.id, count = s.count }
	state.bags[bag].slots[slot] = nil
end

function GetCursorInfo()
	if state.cursor then
		return "item", state.cursor.id, Link(state.cursor.id)
	end
end
function CursorHasItem()
	return state.cursor ~= nil
end
function ClearCursor()
	if state.cursor then
		local s = Mock.Get(state.cursor.bag, state.cursor.slot)
		if s then
			s.locked = nil
		end
	end
	state.cursor = nil
end
function DeleteCursorItem()
	if not state.hardware then
		Mock.blocked[#Mock.blocked + 1] = "DeleteCursorItem without a hardware event"
		return
	end
	if state.hardware.deletes >= 1 then
		Mock.blocked[#Mock.blocked + 1] = "second DeleteCursorItem in one hardware event"
		return
	end
	state.hardware.deletes = state.hardware.deletes + 1
	local cur = state.cursor
	if not cur then
		return
	end
	local s = Mock.Get(cur.bag, cur.slot)
	s.count = s.count - cur.count
	if s.count <= 0 then
		state.bags[cur.bag].slots[cur.slot] = nil
	end
	Mock.deleted[#Mock.deleted + 1] = { id = cur.id, count = cur.count }
	state.cursor = nil
end

-- Runs fn as if from a mouse click / key press.
function Mock.Hardware(fn, ...)
	state.hardware = { deletes = 0 }
	local ok, err = pcall(fn, ...)
	state.hardware = nil
	if not ok then
		error(err, 0)
	end
end

C_Item = {}
function C_Item.GetItemInfo(id)
	local def = ITEM_DB[id]
	if not def or def.uncached then
		return nil
	end
	return def.name, Link(id), def.quality, 1, 1, "", "", def.maxStack, "", 1000 + id, def.price or 0, def.class
end
function C_Item.RequestLoadItemDataByID(id)
	Mock.requested = (Mock.requested or 0) + 1
end

-- Lua / WoW global helpers ---------------------------------------------------------

function wipe(t)
	for k in pairs(t) do
		t[k] = nil
	end
	return t
end
function GetTime()
	return state.time
end
function GetBuildInfo()
	return "1.0.0", "1", "Jan 1 2026", state.interface
end
function issecretvalue(value)
	return state.secretValues[value] == true
end
function IsShiftKeyDown()
	return state.shift
end
function GetBindingKey(name)
	return state.bindings[name]
end
function PlaySound(id)
	state.sounds[#state.sounds + 1] = id
end
SOUNDKIT = { RAID_WARNING = 8959 }
ERR_INV_FULL = "Inventory is full."
NUM_BAG_SLOTS = 4
NUM_CONTAINER_FRAMES = 13
UISpecialFrames = {}

print = function(...)
	local parts = {}
	for i = 1, select("#", ...) do
		parts[#parts + 1] = tostring((select(i, ...)))
	end
	Mock.printed[#Mock.printed + 1] = table.concat(parts, " ")
end

function Mock.Output()
	return table.concat(Mock.printed, "\n")
end

-- Frames & events -------------------------------------------------------------------

local KNOWN_EVENTS = {
	ADDON_LOADED = true, PLAYER_LOGIN = true, UI_ERROR_MESSAGE = true, BAG_UPDATE_DELAYED = true,
	ITEM_LOCK_CHANGED = true, MERCHANT_SHOW = true, MERCHANT_CLOSED = true,
}

-- A permissive widget: remembers the calls tests care about, ignores the rest.
local Widget = {}
Widget.__index = function(self, key)
	local method = rawget(Widget, key)
	if method then
		return method
	end
	if type(key) == "string" and key:match("^Create") then
		return function()
			return Mock.NewWidget()
		end
	end
	return function() end
end
function Widget:RegisterEvent(event)
	if not KNOWN_EVENTS[event] then
		error("Attempt to register unknown event \"" .. event .. "\"")
	end
	self.events[event] = true
end
function Widget:UnregisterEvent(event)
	self.events[event] = nil
end
function Widget:SetScript(name, fn)
	self.scripts[name] = fn
end
function Widget:GetScript(name)
	return self.scripts[name]
end
function Widget:HookScript(name, fn)
	local old = self.scripts[name]
	self.scripts[name] = function(...)
		if old then
			old(...)
		end
		fn(...)
	end
end
function Widget:Show()
	if not self.shown then
		self.shown = true
		if self.scripts.OnShow then
			self.scripts.OnShow(self)
		end
	end
end
function Widget:Hide()
	if self.shown then
		self.shown = false
		if self.scripts.OnHide then
			self.scripts.OnHide(self)
		end
	end
end
function Widget:SetShown(shown)
	if shown then
		self:Show()
	else
		self:Hide()
	end
end
function Widget:IsShown()
	return self.shown
end
function Widget:SetText(text)
	self.text = text
end
function Widget:GetText()
	return self.text
end
function Widget:SetTextColor(r, g, b)
	self.textColor = { r, g, b }
end
function Widget:SetEnabled(enabled)
	self.enabled = enabled and true or false
end
function Widget:IsEnabled()
	return self.enabled ~= false
end
function Widget:SetID(id)
	self.id = id
end
function Widget:GetID()
	return self.id or 0
end
function Widget:SetParent(parent)
	self.parent = parent
end
function Widget:GetParent()
	return self.parent
end
function Widget:GetName()
	return self.name
end
function Widget:GetFrameLevel()
	return 1
end
function Widget:SetAlpha(alpha)
	self.alpha = alpha
end
function Widget:GetPoint()
	return "CENTER", nil, "CENTER", 0, 0
end
function Widget:Click(button)
	Mock.Hardware(function()
		if self.enabled ~= false and self.scripts.OnClick then
			self.scripts.OnClick(self, button or "LeftButton")
		end
	end)
end

function Mock.NewWidget(name)
	local w = setmetatable({ events = {}, scripts = {}, shown = false, name = name }, Widget)
	if name then
		_G[name] = w
	end
	return w
end

function CreateFrame(_, name)
	local frame = Mock.NewWidget(name)
	Mock.frames[#Mock.frames + 1] = frame
	return frame
end

function Mock.Fire(event, ...)
	for _, frame in ipairs(Mock.frames) do
		if frame.events[event] and frame.scripts.OnEvent then
			frame.scripts.OnEvent(frame, event, ...)
		end
	end
end

UIParent = Mock.NewWidget("UIParent")
GameTooltip = Mock.NewWidget("GameTooltip")

-- Blizzard's bag windows
function Mock.CreateBagFrames(combined)
	for i = 1, 13 do
		Mock.NewWidget("ContainerFrame" .. i)
	end
	ContainerFrameCombinedBags = combined and Mock.NewWidget("ContainerFrameCombinedBags") or nil
end

-- Vendor
MerchantFrame = nil
function Mock.OpenMerchant()
	state.merchantShown = true
	MerchantFrame = MerchantFrame or Mock.NewWidget("MerchantFrame")
	MerchantFrame:Show()
	Mock.Fire("MERCHANT_SHOW")
end
function Mock.CloseMerchant()
	state.merchantShown = false
	if MerchantFrame then
		MerchantFrame:Hide()
	end
	Mock.Fire("MERCHANT_CLOSED")
end

-- Timers ----------------------------------------------------------------------------

C_Timer = {}
function C_Timer.After(delay, fn)
	Mock.timers[#Mock.timers + 1] = { delay = delay, fn = fn }
end

-- Runs queued timers (and the ones they queue). `tick` runs between rounds,
-- e.g. Mock.ServerTick to let item locks clear.
function Mock.RunTimers(tick)
	local guard = 0
	while #Mock.timers > 0 do
		local batch = Mock.timers
		Mock.timers = {}
		for _, timer in ipairs(batch) do
			state.time = state.time + timer.delay
			timer.fn()
		end
		if tick then
			tick()
		end
		guard = guard + 1
		assert(guard < 500, "timer loop")
	end
end

-- Settings ----------------------------------------------------------------------------

Settings = { VarType = { Boolean = "boolean", String = "string", Number = "number" } }

local function NewCategory(name, parent)
	local category = { name = name, parent = parent, id = #Mock.settings.categories + 1 }
	function category:GetID()
		return self.id
	end
	Mock.settings.categories[#Mock.settings.categories + 1] = category
	local layout = { initializers = {} }
	function layout:AddInitializer(init)
		self.initializers[#self.initializers + 1] = init
	end
	return category, layout
end
function Settings.RegisterVerticalLayoutCategory(name)
	return NewCategory(name)
end
function Settings.RegisterAddOnSetting(category, variable, key, tbl, varType, name, default)
	assert(type(tbl) == "table", "variableTbl must be a table")
	assert(Mock.settings.settings[variable] == nil, "duplicate setting variable " .. variable)
	if tbl[key] == nil then
		tbl[key] = default
	end
	assert(type(tbl[key]) == varType, ("setting %s has type %s, expected %s"):format(variable, type(tbl[key]), varType))
	local setting = { variable = variable, key = key, tbl = tbl, name = name, category = category }
	function setting:SetValueChangedCallback(fn)
		self.onChange = fn
	end
	Mock.settings.settings[variable] = setting
	return setting
end
local function Control()
	Mock.settings.controls = Mock.settings.controls + 1
	return {}
end
Settings.CreateCheckbox = Control
Settings.CreateSlider = Control
function Settings.CreateSliderOptions(min, max, step)
	return { min = min, max = max, step = step, SetLabelFormatter = function() end }
end
function Settings.RegisterAddOnCategory(category)
	Mock.settings.registered = category
end
function Settings.OpenToCategory(id)
	Mock.settings.opened = id
end
function CreateSettingsListSectionHeaderInitializer(text)
	return { header = text }
end
MinimalSliderWithSteppersMixin = { Label = { Right = 1 } }

SlashCmdList = {}

-- Typing a slash command counts as a key press.
function Mock.Slash(msg)
	Mock.Hardware(SlashCmdList.OPEBAGSFULL, msg)
end

-- Loading -------------------------------------------------------------------------------

function Mock.LoadAddon(root, addonName, tocName)
	local ns = {}
	local files = {}
	for line in io.lines(root .. "/" .. (tocName or addonName) .. ".toc") do
		line = line:gsub("\r", "")
		if line ~= "" and not line:match("^#") then
			files[#files + 1] = line:gsub("\\", "/")
		end
	end
	for _, file in ipairs(files) do
		local chunk, err = loadfile(root .. "/" .. file)
		if not chunk then
			error("failed to compile " .. file .. ": " .. tostring(err))
		end
		chunk(addonName, ns)
	end
	return ns, files
end

Mock.Reset()
