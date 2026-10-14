-- Ope! Bag's Full test suite. Runs on plain Lua 5.1 (the WoW client's version):
--   lua5.1 tests/run.lua            (from the repository root)
-- or, without a system Lua: python3 tests/run_tests.py

local ROOT = (arg and arg[1]) or "."
dofile(ROOT .. "/tests/wow_mock.lua")

local ADDON_DIR = ROOT .. "/OpeBagsFull"

---------------------------------------------------------------------------
-- Tiny test framework
---------------------------------------------------------------------------

local tests, failures = {}, {}
local function test(name, fn)
	tests[#tests + 1] = { name = name, fn = fn }
end

local function fmt(v)
	if type(v) == "string" then
		return string.format("%q", v)
	end
	return tostring(v)
end

local function eq(actual, expected, msg)
	if actual ~= expected then
		error((msg or "values differ") .. ": expected " .. fmt(expected) .. ", got " .. fmt(actual), 2)
	end
end

local function ok(value, msg)
	if not value then
		error(msg or "expected a truthy value", 2)
	end
end

local function contains(haystack, needle, msg)
	if not haystack:find(needle, 1, true) then
		error((msg or "text missing") .. ": " .. fmt(needle) .. " not in:\n" .. haystack, 2)
	end
end

local function lacks(haystack, needle, msg)
	if haystack:find(needle, 1, true) then
		error((msg or "unexpected text") .. ": " .. fmt(needle) .. " found in:\n" .. haystack, 2)
	end
end

---------------------------------------------------------------------------
-- Items & helpers
---------------------------------------------------------------------------

local FANG, WING, SWORD = 100, 101, 102 -- gray
local LINEN, JERKY, ARROW, FEATHER, BAG = 200, 201, 202, 203, 204 -- white
local RING, BLUE = 300, 400
local QUEST, GRAY_QUEST, HEARTH = 500, 501, 600
local FILLER, SHARD = 700, 800

local function DefineItems()
	Mock.DefineItem(FANG, { name = "Broken Fang", quality = 0, price = 3, maxStack = 10 })
	Mock.DefineItem(WING, { name = "Torn Wing", quality = 0, price = 12, maxStack = 10 })
	Mock.DefineItem(SWORD, { name = "Rusty Sword", quality = 0, price = 40, class = 2 })
	Mock.DefineItem(LINEN, { name = "Linen Cloth", quality = 1, price = 13, class = 7, maxStack = 20 })
	Mock.DefineItem(JERKY, { name = "Tough Jerky", quality = 1, price = 1, class = 0, maxStack = 20 })
	Mock.DefineItem(ARROW, { name = "Rough Arrow", quality = 1, price = 1, class = 6, maxStack = 200 })
	Mock.DefineItem(FEATHER, { name = "Light Feather", quality = 1, price = 2, class = 5, maxStack = 20 })
	Mock.DefineItem(BAG, { name = "Small Pouch", quality = 1, price = 5, class = 1 })
	Mock.DefineItem(RING, { name = "Jade Ring", quality = 2, price = 500, class = 4 })
	Mock.DefineItem(BLUE, { name = "Blue Blade", quality = 3, price = 2000, class = 2 })
	Mock.DefineItem(QUEST, { name = "Murloc Fin", quality = 1, price = 0, class = 12, quest = true })
	Mock.DefineItem(GRAY_QUEST, { name = "Grimy Note", quality = 0, price = 5, quest = true })
	Mock.DefineItem(HEARTH, { name = "Hearthstone", quality = 1, price = 0 })
	Mock.DefineItem(FILLER, { name = "Shiny Trinket", quality = 1, price = 50 })
	Mock.DefineItem(SHARD, { name = "Soul Shard", quality = 1, price = 0, maxStack = 1 })
end

-- Fresh client + addon. `before(state)` sets up bags before login.
local function Boot(opts)
	opts = opts or {}
	Mock.Reset()
	DefineItems()
	Mock.state.interface = opts.flavor == "era" and 11509 or 16001
	Mock.CreateBagFrames(opts.flavor ~= "era")
	_G.StashOrTrash = nil
	OpeBagsFullDB = opts.db
	Mock.SetBag(0, 16)
	if opts.before then
		opts.before(Mock.state)
	end
	local toc = opts.flavor == "era" and "OpeBagsFull_Vanilla" or "OpeBagsFull"
	local ns, files = Mock.LoadAddon(ADDON_DIR, "OpeBagsFull", toc)
	Mock.Fire("ADDON_LOADED", "OpeBagsFull")
	Mock.Fire("PLAYER_LOGIN")
	Mock.RunTimers()
	Mock.printed = {}
	return ns, files
end

local function IDs(list)
	local out = {}
	for i, item in ipairs(list) do
		out[i] = item.itemID .. "x" .. item.count
	end
	return table.concat(out, ",")
end

-- A full backpack with some junk in it.
local function FullBagsWithJunk(s)
	Mock.Put(0, 1, FANG, 5) -- 15c
	Mock.Put(0, 2, WING, 1) -- 12c
	Mock.Put(0, 3, SWORD, 1) -- 40c
	Mock.Put(0, 4, LINEN, 4) -- 52c, white
	Mock.Put(0, 5, HEARTH, 1)
	Mock.Fill(0, FILLER)
end

local function Settle()
	Mock.RunTimers(Mock.ServerTick)
end

---------------------------------------------------------------------------
-- Loading
---------------------------------------------------------------------------

test("addon loads every .toc file and registers settings, slash command and bindings", function()
	local ns, files = Boot()
	eq(#files, 5, "toc file count")
	ok(Mock.settings.registered, "settings category registered")
	eq(Mock.settings.registered.name, "Ope! Bag's Full")
	ok(SlashCmdList.OPEBAGSFULL, "slash command registered")
	eq(SLASH_OPEBAGSFULL1, "/ope")
	ok(type(OpeBagsFull_OnAddonCompartmentClick) == "function", "addon compartment handler")
	eq(_G.OpeBagsFull, ns, "namespace exposed")
	eq(OpeBagsFullDB.goal, 5, "defaults saved")
end)

test("Forever and Classic Era .toc files match except the interface version", function()
	local function Lines(name)
		local lines = {}
		for line in io.lines(ADDON_DIR .. "/" .. name .. ".toc") do
			lines[#lines + 1] = line
		end
		return lines
	end
	local forever, era = Lines("OpeBagsFull"), Lines("OpeBagsFull_Vanilla")
	eq(#era, #forever, "line count")
	for i = 1, #forever do
		if forever[i]:match("^## Interface:") then
			eq(forever[i], "## Interface: 16001")
			eq(era[i], "## Interface: 11509")
		else
			eq(era[i], forever[i], "toc line " .. i)
		end
	end
end)

test("every key binding calls a function the addon defines", function()
	Boot()
	local xml = io.open(ADDON_DIR .. "/Bindings.xml"):read("*a")
	local count = 0
	for name, body in xml:gmatch('<Binding name="([%w_]+)"[^>]*>%s*(.-)%s*</Binding>') do
		count = count + 1
		ok(_G["BINDING_NAME_" .. name], "binding label for " .. name)
		local fn = body:match("^([%w_]+)%(%)$")
		ok(fn and type(_G[fn]) == "function", "binding " .. name .. " calls a defined function: " .. body)
	end
	eq(count, 3, "bindings")
	ok(BINDING_HEADER_OPEBAGSFULL, "binding header")
end)

test("Classic Era loads its own .toc and works without the combined bag frame", function()
	local ns = Boot({ flavor = "era", before = FullBagsWithJunk })
	eq(ContainerFrameCombinedBags, nil)
	eq(ns.FreeSlots(), 0)
	eq(ns.Candidates()[1].itemID, WING)
end)

test("existing saved settings and lists are kept, missing ones filled in", function()
	local ns = Boot({ db = { goal = 9, keep = { [LINEN] = true }, includeCommon = "garbage" } })
	eq(ns.db.goal, 9)
	ok(ns.db.keep[LINEN], "keep list kept")
	eq(ns.db.includeCommon, false, "wrong type replaced by default")
	eq(ns.db.autoSellJunk, true, "missing setting filled in")
end)

---------------------------------------------------------------------------
-- Bags & candidates
---------------------------------------------------------------------------

test("free slots only count bags that take any item", function()
	local ns = Boot({
		before = function()
			Mock.SetBag(1, 10) -- general
			Mock.SetBag(2, 20, 4) -- soul bag
			Mock.Put(0, 1, FANG, 1)
			Mock.Put(2, 1, SHARD, 1)
		end,
	})
	eq(ns.FreeSlots(), 15 + 10)
	eq(#ns.GeneralBags(), 2)
end)

test("by default only gray items can go, cheapest whole stack first", function()
	local ns = Boot({ before = FullBagsWithJunk })
	-- Torn Wing (12c) < Broken Fang x5 (15c) < Rusty Sword (40c); Linen is white
	eq(IDs(ns.Candidates()), "101x1,100x5,102x1")
end)

test("items in specialty bags are never candidates", function()
	local ns = Boot({
		before = function()
			Mock.SetBag(1, 4, 4)
			Mock.Put(1, 1, FANG, 1)
			Mock.Put(0, 1, WING, 1)
		end,
	})
	eq(IDs(ns.Candidates()), "101x1")
end)

test("quest items, unsellable items and the keep list are never trashed", function()
	local ns = Boot({
		db = { keep = { [SWORD] = true }, includeCommon = true, includeUncommon = true },
		before = function()
			Mock.Put(0, 1, GRAY_QUEST, 1)
			Mock.Put(0, 2, QUEST, 1)
			Mock.Put(0, 3, HEARTH, 1)
			Mock.Put(0, 4, SWORD, 1)
			Mock.Put(0, 5, BLUE, 1)
		end,
	})
	eq(IDs(ns.Candidates()), "")
	local function Reason(bag, slot)
		local items = ns.ScanItems()
		for _, item in ipairs(items) do
			if item.bag == bag and item.slot == slot then
				return select(2, ns.IsTrashable(item))
			end
		end
	end
	eq(Reason(0, 1), "quest item")
	eq(Reason(0, 2), "quest item")
	eq(Reason(0, 3), "can't be sold")
	eq(Reason(0, 4), "on your keep list")
	eq(Reason(0, 5), "rare or better")
end)

test("white items: off by default; when on, bags, ammo, reagents and consumables are still kept", function()
	local function Setup()
		Mock.Put(0, 1, LINEN, 1)
		Mock.Put(0, 2, JERKY, 1)
		Mock.Put(0, 3, ARROW, 200)
		Mock.Put(0, 4, FEATHER, 1)
		Mock.Put(0, 5, BAG, 1)
		Mock.Put(0, 6, RING, 1)
	end
	local ns = Boot({ before = Setup })
	eq(IDs(ns.Candidates()), "")
	ns.db.includeCommon = true
	eq(IDs(ns.Candidates()), "200x1")
	ns.db.keepConsumables = false
	eq(IDs(ns.Candidates()), "201x1,200x1")
	ns.db.includeUncommon = true
	eq(IDs(ns.Candidates()), "201x1,200x1,300x1")
end)

test("the junk list makes any item count as junk; keep and junk are exclusive", function()
	local ns = Boot({ before = function()
		Mock.Put(0, 1, LINEN, 2)
	end })
	ns.SetListed("trash", LINEN, true)
	eq(IDs(ns.Candidates(nil, true)), "200x2", "junk list item is junk even with whites off")
	ns.SetListed("keep", LINEN, true)
	eq(ns.db.trash[LINEN], nil, "adding to keep removes from junk")
	eq(IDs(ns.Candidates()), "")
end)

test("with Stash or Trash, white materials your professions use are kept", function()
	local ns = Boot({
		db = { includeCommon = true },
		before = function()
			Mock.Put(0, 1, LINEN, 1)
			Mock.Put(0, 2, FANG, 1)
		end,
	})
	_G.StashOrTrash = {
		BuildReport = function(itemID)
			if itemID == LINEN then
				return { mine = { { name = "Tailoring" } }, alts = {}, others = {} }
			end
			return { mine = {}, alts = {}, others = {} }
		end,
	}
	eq(IDs(ns.Candidates()), "100x1")
	ns.db.respectStashOrTrash = false
	eq(IDs(ns.Candidates()), "100x1,200x1")
	ns.db.respectStashOrTrash = true
	_G.StashOrTrash.BuildReport = function()
		error("boom")
	end
	eq(IDs(ns.Candidates()), "100x1,200x1", "a failing Stash or Trash doesn't block anything")
end)

test("items the client hasn't loaded yet are skipped and requested", function()
	local ns = Boot({ before = function()
		Mock.Put(0, 1, FANG, 1)
		Mock.Put(0, 2, WING, 1)
	end })
	Mock.DefineItem(FANG, { name = "Broken Fang", quality = 0, price = 3, maxStack = 10, uncached = true })
	Mock.requested = 0
	eq(IDs(ns.Candidates()), "101x1")
	ok(Mock.requested > 0, "item data requested")
end)

---------------------------------------------------------------------------
-- Trashing
---------------------------------------------------------------------------

test("trash next deletes exactly one stack per click, cheapest first", function()
	local ns = Boot({ before = FullBagsWithJunk })
	Mock.Hardware(ns.TrashNext)
	eq(#Mock.deleted, 1)
	eq(Mock.deleted[1].id, WING)
	Mock.Hardware(ns.TrashNext)
	eq(Mock.deleted[2].id, FANG)
	eq(Mock.deleted[2].count, 5, "whole stack")
	eq(#Mock.blocked, 0, "never more than one delete per click")
	eq(ns.FreeSlots(), 2)
	contains(Mock.Output(), "Trashed |cff9d9d9d|Hitem:101")
	eq(ns.session.trashed, 2)
	eq(ns.session.lost, 27)
end)

test("nothing is ever deleted outside a click or key press", function()
	local ns = Boot({ before = FullBagsWithJunk })
	Mock.Fire("UI_ERROR_MESSAGE", 1, ERR_INV_FULL)
	Mock.Fire("BAG_UPDATE_DELAYED")
	Settle()
	eq(#Mock.deleted, 0)
	eq(#Mock.blocked, 0)
end)

test("trash next refuses while you're holding an item", function()
	local ns = Boot({ before = FullBagsWithJunk })
	C_Container.PickupContainerItem(0, 3) -- holding the sword
	Mock.Hardware(ns.TrashNext)
	eq(#Mock.deleted, 0)
	eq(select(2, GetCursorInfo()), SWORD, "cursor untouched")
	contains(Mock.Output(), "put it down first")
end)

test("if the wrong item lands on the cursor nothing is deleted", function()
	local ns = Boot({ before = FullBagsWithJunk })
	local real = C_Container.PickupContainerItem
	C_Container.PickupContainerItem = function()
		real(0, 3) -- something else gets picked up
	end
	Mock.Hardware(ns.TrashNext)
	C_Container.PickupContainerItem = real
	eq(#Mock.deleted, 0)
	eq(GetCursorInfo(), nil, "cursor cleared")
	contains(Mock.Output(), "nothing was deleted")
end)

test("trash next with nothing trashable says so", function()
	local ns = Boot({ before = function()
		Mock.Put(0, 1, LINEN, 1)
	end })
	Mock.Hardware(ns.TrashNext)
	eq(#Mock.deleted, 0)
	contains(Mock.Output(), "Nothing left that's safe to trash")
end)

---------------------------------------------------------------------------
-- Combining stacks & making room
---------------------------------------------------------------------------

test("stack plan tops up the fullest stack from the smallest ones", function()
	local ns = Boot({ before = function()
		Mock.Put(0, 1, LINEN, 15)
		Mock.Put(0, 2, LINEN, 10)
		Mock.Put(0, 3, LINEN, 8)
		Mock.Put(0, 4, LINEN, 20) -- full, untouched
		Mock.Put(0, 5, SWORD, 1) -- doesn't stack
	end })
	local moves, freed = ns.PlanStacks()
	eq(freed, 1)
	eq(#moves, 2)
	eq(moves[1].fromSlot, 3)
	eq(moves[1].toSlot, 1)
	eq(moves[1].amount, 5)
end)

test("combining stacks waits for the server between moves and keeps every item", function()
	local ns = Boot({ before = function()
		Mock.Put(0, 1, LINEN, 15)
		Mock.Put(0, 2, LINEN, 10)
		Mock.Put(0, 3, LINEN, 8)
		Mock.Put(0, 4, FANG, 3)
		Mock.Put(0, 5, FANG, 4)
	end })
	local before = ns.FreeSlots()
	Mock.Hardware(ns.CombineStacks)
	ok(ns.stacking, "running")
	Settle()
	eq(ns.stacking, nil, "finished")
	eq(Mock.CountItem(LINEN), 33)
	eq(Mock.CountItem(FANG), 7)
	eq(ns.FreeSlots(), before + 2)
	eq(#Mock.deleted, 0)
	contains(Mock.Output(), "Combined stacks: 2 slots freed.")
end)

test("combining stacks copes with bags changing underneath it", function()
	local ns = Boot({ before = function()
		Mock.Put(0, 1, LINEN, 15)
		Mock.Put(0, 2, LINEN, 10)
		Mock.Put(0, 3, LINEN, 8)
	end })
	Mock.Hardware(ns.CombineStacks)
	Mock.ServerTick()
	Mock.state.bags[0].slots[2] = nil -- e.g. sold or moved by hand
	Settle()
	eq(ns.stacking, nil)
	eq(Mock.CountItem(LINEN), 23)
	eq(GetCursorInfo(), nil)
end)

test("make room: combine first, then one trash per click until the goal is met", function()
	local ns = Boot({
		db = { goal = 3 },
		before = function()
			Mock.Put(0, 1, FANG, 1)
			Mock.Put(0, 2, FANG, 1) -- combines with slot 1: 2 fangs, 6c
			Mock.Put(0, 3, WING, 1) -- 12c
			Mock.Put(0, 4, SWORD, 1) -- 40c
			Mock.Fill(0, FILLER)
		end,
	})
	ns.ShowPanel()
	local action = OpeBagsFullPanelAction
	eq(action:GetText(), "Combine stacks (+1)")
	contains(OpeBagsFullPanel.info.text, "Combining stacks frees 1, then trash 2")

	action:Click()
	Settle()
	eq(ns.FreeSlots(), 1)
	eq(#Mock.deleted, 0, "combining deletes nothing")
	ns.Refresh(true)
	eq(action:GetText(), "Trash next (2 to go)")

	action:Click()
	eq(Mock.deleted[1].id, FANG)
	eq(Mock.deleted[1].count, 2, "the combined stack")
	ns.Refresh(true)
	eq(action:GetText(), "Trash next (1 to go)")
	action:Click()
	eq(Mock.deleted[2].id, WING)
	ns.Refresh(true)
	eq(ns.FreeSlots(), 3)
	eq(action:GetText(), "You have room")
	eq(action:IsEnabled(), false)
	eq(#Mock.blocked, 0)
	eq(Mock.CountItem(SWORD), 1, "only what the goal needed")
end)

test("make room explains when the rules don't allow enough", function()
	local ns = Boot({
		db = { goal = 3 },
		before = function()
			Mock.Put(0, 1, WING, 1)
			Mock.Put(0, 2, LINEN, 1)
			Mock.Fill(0, FILLER)
		end,
	})
	local plan = ns.Plan()
	eq(#plan.trash, 1)
	eq(plan.short, 2)
	ns.ShowPanel()
	contains(OpeBagsFullPanel.info.text, "2 more need white items allowed")
end)

---------------------------------------------------------------------------
-- Vendors
---------------------------------------------------------------------------

test("opening a vendor sells all junk, a few items per tick", function()
	local ns = Boot({
		db = { includeCommon = true, trash = { [JERKY] = true } },
		before = function()
			for slot = 1, 8 do
				Mock.Put(0, slot, FANG, 1)
			end
			Mock.Put(0, 9, LINEN, 1) -- white: allowed for trashing but never auto-sold
			Mock.Put(0, 10, JERKY, 1) -- on the junk list
		end,
	})
	Mock.OpenMerchant()
	Mock.RunTimers()
	eq(#Mock.sold, 9)
	eq(Mock.CountItem(LINEN), 1, "white items aren't sold automatically")
	eq(Mock.state.money, 8 * 3 + 1)
	contains(Mock.Output(), "Sold 9 items for 25")
	eq(#Mock.state.used, 0)
end)

test("selling stops the moment the vendor closes, so nothing gets used instead", function()
	local ns = Boot({ before = function()
		for slot = 1, 12 do
			Mock.Put(0, slot, FANG, 1)
		end
	end })
	ns.db.autoSellJunk = false
	Mock.OpenMerchant()
	Mock.RunTimers()
	ns.SellJunk() -- sells the first batch now, queues the rest
	Mock.CloseMerchant()
	Mock.RunTimers()
	eq(#Mock.sold, 6)
	eq(#Mock.state.used, 0, "no item was used away from the vendor")
end)

test("auto-sell can be turned off", function()
	local ns = Boot({ db = { autoSellJunk = false }, before = function()
		Mock.Put(0, 1, FANG, 1)
	end })
	Mock.OpenMerchant()
	Mock.RunTimers()
	eq(#Mock.sold, 0)
end)

test("at a vendor, trash next and make room sell instead of deleting", function()
	local ns = Boot({
		db = { autoSellJunk = false, goal = 2 },
		before = function()
			Mock.Put(0, 1, WING, 1)
			Mock.Put(0, 2, SWORD, 1)
			Mock.Fill(0, FILLER)
		end,
	})
	Mock.OpenMerchant()
	Mock.RunTimers()
	Mock.Hardware(ns.TrashNext)
	Mock.RunTimers()
	eq(#Mock.deleted, 0)
	eq(Mock.sold[1].id, WING)
	ns.ShowPanel()
	eq(OpeBagsFullPanelAction:GetText(), "Sell 1 item")
	OpeBagsFullPanelAction:Click()
	Mock.RunTimers()
	eq(#Mock.sold, 2)
	eq(#Mock.deleted, 0)
end)

---------------------------------------------------------------------------
-- Alerts
---------------------------------------------------------------------------

test("looting with full bags: alert names the cheapest item and opens the panel", function()
	local ns = Boot({ before = FullBagsWithJunk })
	Mock.state.bindings.OPEBAGSFULL_TRASHNEXT = "CTRL-T"
	Mock.Fire("UI_ERROR_MESSAGE", 3, ERR_INV_FULL)
	local out = Mock.Output()
	contains(out, "Ope! Bag's full!")
	contains(out, "Torn Wing")
	contains(out, "press CTRL-T")
	eq(#Mock.state.sounds, 1)
	ok(OpeBagsFullPanel:IsShown(), "panel opened")

	Mock.printed = {}
	Mock.state.time = Mock.state.time + 2
	Mock.Fire("UI_ERROR_MESSAGE", 3, ERR_INV_FULL)
	eq(Mock.Output(), "", "not repeated right away")
	Mock.state.time = Mock.state.time + 10
	Mock.Fire("UI_ERROR_MESSAGE", 3, ERR_INV_FULL)
	contains(Mock.Output(), "Ope! Bag's full!")
end)

test("the bag-full alert can be turned off and ignores other errors", function()
	local ns = Boot({ before = FullBagsWithJunk })
	Mock.Fire("UI_ERROR_MESSAGE", 3, "You are too far away.")
	Mock.state.secretValues[ERR_INV_FULL] = true
	Mock.Fire("UI_ERROR_MESSAGE", 3, ERR_INV_FULL)
	Mock.state.secretValues[ERR_INV_FULL] = nil
	ns.db.alertWhenFull = false
	Mock.Fire("UI_ERROR_MESSAGE", 3, ERR_INV_FULL)
	eq(Mock.Output(), "")
end)

test("warns once when free slots drop to the threshold", function()
	local ns = Boot({ before = function()
		Mock.SetBag(0, 4)
	end })
	Mock.Put(0, 1, FILLER, 1)
	Mock.Fire("BAG_UPDATE_DELAYED") -- 3 free
	eq(Mock.Output(), "")
	Mock.Put(0, 2, FILLER, 1)
	Mock.Fire("BAG_UPDATE_DELAYED") -- 2 free
	contains(Mock.Output(), "Only 2 bag slots left.")
	Mock.printed = {}
	Mock.Put(0, 3, FILLER, 1)
	Mock.Fire("BAG_UPDATE_DELAYED") -- 1 free: still below, no repeat
	eq(Mock.Output(), "")
end)

test("no low-space warning while bags load in right after login", function()
	Mock.Reset()
	DefineItems()
	Mock.CreateBagFrames(true)
	OpeBagsFullDB = nil
	Mock.SetBag(0, 4)
	Mock.LoadAddon(ADDON_DIR, "OpeBagsFull", "OpeBagsFull")
	Mock.Fire("ADDON_LOADED", "OpeBagsFull")
	Mock.Fire("PLAYER_LOGIN") -- ready timer not run yet
	Mock.Fill(0, FILLER)
	Mock.Fire("BAG_UPDATE_DELAYED")
	lacks(Mock.Output(), "bag slots left")
end)

---------------------------------------------------------------------------
-- Bag button, panel, slash commands
---------------------------------------------------------------------------

test("the Ope icon sits on the backpack window with the free slot count on it", function()
	local ns = Boot({ before = FullBagsWithJunk })
	local button = OpeBagsFullBagButton
	ContainerFrame3:SetID(0) -- whichever frame holds the backpack
	ContainerFrame3:Show()
	Mock.RunTimers()
	ok(button:IsShown(), "shown with the backpack")
	eq(button:GetParent(), ContainerFrame3)
	eq(button.Count:GetText(), 0)
	eq(button.Count.textColor[2], 0.25, "red when bags are nearly full")
	for slot = 1, 3 do
		Mock.state.bags[0].slots[slot] = nil
	end
	ns.Refresh(true)
	eq(button.Count:GetText(), 3)
	eq(button.Count.textColor[2], 1, "white with room to spare")

	ContainerFrame3:Hide()
	Mock.RunTimers()
	ok(not button:IsShown(), "hidden with the backpack")

	ContainerFrameCombinedBags:Show()
	Mock.RunTimers()
	eq(button:GetParent(), ContainerFrameCombinedBags, "combined bags on Forever")

	ns.db.showBagButton = false
	ns.AttachBagButton()
	ok(not button:IsShown(), "can be turned off")
end)

test("Ope button: click opens the panel, shift-click trashes one item", function()
	local ns = Boot({ before = FullBagsWithJunk })
	ns.CreateBagButton()
	OpeBagsFullBagButton:Click()
	ok(OpeBagsFullPanel:IsShown())
	Mock.state.shift = true
	OpeBagsFullBagButton:Click()
	Mock.state.shift = false
	eq(#Mock.deleted, 1)
	OpeBagsFullBagButton:Click("RightButton")
	ok(Mock.settings.opened, "right-click opens options")
end)

test("panel lists the cheapest items; Keep protects one", function()
	local ns = Boot({ before = FullBagsWithJunk })
	ns.ShowPanel()
	local rows = OpeBagsFullPanel.rows
	eq(rows[1].item.itemID, WING)
	ok(rows[1]:IsShown())
	ok(not rows[4]:IsShown(), "only 3 candidates")
	contains(rows[2].text.text, "x5")
	rows[1].keep:Click()
	ok(ns.db.keep[WING], "added to keep list")
	ns.Refresh(true)
	eq(rows[1].item.itemID, FANG)
	eq(#Mock.deleted, 0, "Keep never deletes")
end)

test("panel goal stepper stays within 1-40", function()
	local ns = Boot()
	ns.ShowPanel()
	ns.SetGoal(1)
	OpeBagsFullPanel.minus:Click()
	eq(ns.db.goal, 1)
	ns.SetGoal(40)
	OpeBagsFullPanel.plus:Click()
	eq(ns.db.goal, 40)
end)

test("slash commands", function()
	local ns = Boot({ before = FullBagsWithJunk })
	Mock.Slash("keep |cffffffff|Hitem:200::::::::|h[Linen Cloth]|h|r")
	ok(ns.db.keep[LINEN])
	Mock.Slash("junk 200")
	ok(ns.db.trash[LINEN] and not ns.db.keep[LINEN], "junk replaces keep")
	Mock.Slash("unjunk 200")
	eq(ns.db.trash[LINEN], nil)
	Mock.Slash("goal 7")
	eq(ns.db.goal, 7)
	Mock.Slash("trash")
	eq(#Mock.deleted, 1, "/ope trash deletes one item")
	Mock.Slash("status")
	contains(Mock.Output(), "This session: trashed 1")
	Mock.Slash("keep")
	contains(Mock.Output(), "Shift-click an item")
	Mock.printed = {}
	Mock.Slash("help")
	contains(Mock.Output(), "/ope trash")
	Mock.Slash("")
	ok(OpeBagsFullPanel:IsShown(), "/ope opens the panel")
	eq(#Mock.blocked, 0)
end)

test("settings panel covers every setting", function()
	local ns = Boot()
	local expected = 0
	for key, value in pairs(ns.defaults) do
		if type(value) ~= "table" then
			expected = expected + 1
			ok(Mock.settings.settings["OPEBAGSFULL_" .. key:upper()], "setting for " .. key)
		end
	end
	eq(Mock.settings.controls, expected)
end)

test("money is formatted with coin colors and empty units left out", function()
	local ns = Boot()
	eq(ns.FormatMoney(0), "0|cffeda55fc|r")
	eq(ns.FormatMoney(10203), "1|cffffd700g|r 2|cffc7c7cfs|r 3|cffeda55fc|r")
	eq(ns.FormatMoney(10000), "1|cffffd700g|r")
end)

---------------------------------------------------------------------------
-- Run
---------------------------------------------------------------------------

local passed = 0
for _, t in ipairs(tests) do
	local success, err = pcall(t.fn)
	if success then
		passed = passed + 1
		io.write("  ok   ", t.name, "\n")
	else
		failures[#failures + 1] = t.name
		io.write("  FAIL ", t.name, "\n       ", tostring(err), "\n")
	end
end
io.write(("\n%d passed, %d failed\n"):format(passed, #failures))
if #failures > 0 then
	error("tests failed", 0)
end
