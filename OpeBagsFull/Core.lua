local addonName, ns = ...

-- Ope, Bag's Full: frees bag space by combining stacks and getting rid of the
-- lowest-value junk first. Shared helpers, saved variables and events.

_G.OpeBagsFull = ns
ns.addonName = addonName
ns.TITLE = "Ope, Bag's Full"
ns.ICON = "Interface\\Icons\\INV_Misc_Bag_10"

ns.defaults = {
	goal = 5, -- free bag slots "Make room" aims for
	includeCommon = false, -- white items
	includeUncommon = false, -- green items
	keepConsumables = true, -- food, drink, potions, bandages... (only matters for white+)
	respectStashOrTrash = true, -- keep white+ items your professions use (needs Stash or Trash)
	combineStacks = true,
	autoSellJunk = true,
	alertWhenFull = true,
	lowSpaceWarning = 2, -- warn when this many free slots or fewer are left (0 = off)
	showBagButton = true,
	keep = {}, -- itemID -> true: never trash
	trash = {}, -- itemID -> true: always counts as junk
}

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

function ns.Print(...)
	print("|cffff9933Ope|r:", ...)
end

-- C_Item on both clients; the old global as a fallback.
function ns.GetItemInfo(item)
	local fn = (C_Item and C_Item.GetItemInfo) or GetItemInfo
	if fn then
		return fn(item)
	end
end

function ns.RequestItem(itemID)
	if C_Item and C_Item.RequestLoadItemDataByID then
		C_Item.RequestLoadItemDataByID(itemID)
	end
end

-- "1g 2s 3c" with coin colors; empty denominations are left out.
function ns.FormatMoney(copper)
	copper = math.floor(copper or 0)
	local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
	local parts = {}
	if g > 0 then
		parts[#parts + 1] = g .. "|cffffd700g|r"
	end
	if s > 0 then
		parts[#parts + 1] = s .. "|cffc7c7cfs|r"
	end
	if c > 0 or #parts == 0 then
		parts[#parts + 1] = c .. "|cffeda55fc|r"
	end
	return table.concat(parts, " ")
end

local function CopyDefaults(dst, src)
	for k, v in pairs(src) do
		if type(v) == "table" then
			if type(dst[k]) ~= "table" then
				dst[k] = {}
			end
			CopyDefaults(dst[k], v)
		elseif dst[k] == nil or type(dst[k]) ~= type(v) then
			dst[k] = v
		end
	end
end

local function InitDB()
	if type(OpeBagsFullDB) ~= "table" then
		OpeBagsFullDB = {}
	end
	CopyDefaults(OpeBagsFullDB, ns.defaults)
	ns.db = OpeBagsFullDB
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local frame = CreateFrame("Frame")
local handlers = {}

-- Registering an event a client doesn't have throws; skip those quietly.
function ns.RegisterEvent(event, fn)
	if not handlers[event] then
		if not pcall(frame.RegisterEvent, frame, event) then
			return false
		end
		handlers[event] = {}
	end
	table.insert(handlers[event], fn)
	return true
end

frame:SetScript("OnEvent", function(_, event, ...)
	for _, fn in ipairs(handlers[event] or {}) do
		fn(event, ...)
	end
end)

ns.RegisterEvent("ADDON_LOADED", function(_, name)
	if name ~= addonName then
		return
	end
	InitDB()
	if ns.OnInitialize then
		ns.OnInitialize()
	end
end)

ns.RegisterEvent("PLAYER_LOGIN", function()
	if ns.OnLogin then
		ns.OnLogin()
	end
end)
