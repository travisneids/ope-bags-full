local _, ns = ...

-- Doing it: trash one item per click, sell at vendors, combine stacks.
--
-- Blizzard only lets an addon delete ONE item per hardware event (a click or
-- key press), so TrashNext must be called straight from a click, key binding
-- or slash command, and only ever deletes a single stack.

ns.session = { trashed = 0, lost = 0, sold = 0, earned = 0 }

local function ItemLabel(item)
	local label = item.link or item.name or ("item " .. item.itemID)
	if item.count > 1 then
		label = label .. " x" .. item.count
	end
	return label
end
ns.ItemLabel = ItemLabel

local function SlotHolds(bag, slot, itemID)
	local info = C_Container.GetContainerItemInfo(bag, slot)
	return info and info.itemID == itemID and info or nil
end

local function CursorBusy()
	return (CursorHasItem and CursorHasItem()) or (GetCursorInfo and GetCursorInfo() ~= nil)
end

---------------------------------------------------------------------------
-- Trash (one stack per click)
---------------------------------------------------------------------------

-- Deletes the cheapest trashable stack. At a vendor it sells it instead.
-- Returns the item it got rid of.
function ns.TrashNext()
	if CursorBusy() then
		ns.Print("You're holding something - put it down first.")
		return
	end
	local item = ns.Candidates()[1]
	if not item then
		ns.Print("Nothing left that's safe to trash with your current settings.")
		return
	end
	if ns.AtMerchant() then
		ns.SellItems({ item })
		return item
	end
	C_Container.PickupContainerItem(item.bag, item.slot)
	local kind, cursorID = GetCursorInfo()
	if kind ~= "item" or cursorID ~= item.itemID then
		-- Something else ended up on the cursor; put it back, delete nothing.
		ClearCursor()
		ns.Print("Couldn't pick up " .. ItemLabel(item) .. ", nothing was deleted.")
		return
	end
	DeleteCursorItem()
	ns.session.trashed = ns.session.trashed + 1
	ns.session.lost = ns.session.lost + item.value
	ns.Print("Trashed " .. ItemLabel(item) .. " (" .. ns.FormatMoney(item.value) .. ").")
	if ns.Refresh then
		ns.Refresh()
	end
	return item
end

-- The panel's main button: combine stacks if that helps, otherwise trash
-- (or sell) the next planned item.
function ns.MakeRoom()
	local plan = ns.Plan()
	-- At a vendor: sell the junk (and whatever else the goal needs) instead.
	if ns.AtMerchant() then
		local list = ns.SellList(plan.need > 0 and plan or nil)
		if #list > 0 then
			ns.SellItems(list)
			return
		end
	end
	if plan.need <= 0 then
		ns.Print(("You have %d free slots - that's your goal of %d."):format(plan.free, plan.goal))
		return
	end
	if #plan.moves > 0 and plan.stackFreed > 0 and not ns.stacking then
		ns.CombineStacks()
		return
	end
	if #plan.trash == 0 then
		ns.Print("Nothing left that's safe to trash with your current settings. Allow white items in /ope options, or add items with /ope junk <item>.")
		return
	end
	return ns.TrashNext()
end

---------------------------------------------------------------------------
-- Selling
---------------------------------------------------------------------------

function ns.AtMerchant()
	return ns.merchantOpen and (not MerchantFrame or MerchantFrame:IsShown()) or false
end

-- Everything that's junk, plus whatever else the plan wants gone.
function ns.SellList(plan)
	local list, seen = {}, {}
	for _, item in ipairs(ns.Candidates(nil, true)) do
		list[#list + 1] = item
		seen[item.bag .. ":" .. item.slot] = true
	end
	for _, item in ipairs(plan and plan.trash or {}) do
		if not seen[item.bag .. ":" .. item.slot] then
			list[#list + 1] = item
		end
	end
	return list
end

local SELL_PER_TICK, SELL_INTERVAL = 6, 0.2
local sellQueue, sellTotals

local function FinishSelling()
	if sellTotals and sellTotals.count > 0 then
		ns.Print(("Sold %d item%s for %s."):format(sellTotals.count, sellTotals.count == 1 and "" or "s",
			ns.FormatMoney(sellTotals.value)))
	end
	sellQueue, sellTotals = nil, nil
	if ns.Refresh then
		ns.Refresh()
	end
end

local function SellTick()
	if not sellQueue then
		return
	end
	local sold = 0
	while sold < SELL_PER_TICK and #sellQueue > 0 do
		-- UseContainerItem away from a vendor would USE or equip the item.
		if not ns.AtMerchant() then
			sellQueue = {}
			break
		end
		local item = table.remove(sellQueue, 1)
		local info = SlotHolds(item.bag, item.slot, item.itemID)
		if info and not info.isLocked then
			C_Container.UseContainerItem(item.bag, item.slot)
			sellTotals.count = sellTotals.count + 1
			sellTotals.value = sellTotals.value + item.value
			ns.session.sold = ns.session.sold + 1
			ns.session.earned = ns.session.earned + item.value
			sold = sold + 1
		end
	end
	if #sellQueue > 0 then
		C_Timer.After(SELL_INTERVAL, SellTick)
	else
		FinishSelling()
	end
end

function ns.SellItems(items)
	if not ns.AtMerchant() or #items == 0 then
		return
	end
	if sellQueue then
		for _, item in ipairs(items) do
			sellQueue[#sellQueue + 1] = item
		end
		return
	end
	sellQueue, sellTotals = {}, { count = 0, value = 0 }
	for i, item in ipairs(items) do
		sellQueue[i] = item
	end
	SellTick()
end

function ns.SellJunk()
	ns.SellItems(ns.Candidates(nil, true))
end

---------------------------------------------------------------------------
-- Combining stacks (no deleting, so it can run on a timer)
---------------------------------------------------------------------------

local STACK_INTERVAL, STACK_TIMEOUT, STACK_MAX_MOVES = 0.1, 3, 200

function ns.CombineStacks()
	if ns.stacking then
		return
	end
	if CursorBusy() then
		ns.Print("You're holding something - put it down first.")
		return
	end
	local moves = ns.PlanStacks()
	if #moves == 0 then
		return
	end
	local startFree = ns.FreeSlots()
	local job = { moves = moves, index = 1, done = 0, waitingSince = nil }
	ns.stacking = job

	local function Finish(message)
		ns.stacking = nil
		if CursorBusy() then
			ClearCursor()
		end
		local gained = ns.FreeSlots() - startFree
		ns.Print(message or ("Combined stacks: %d slot%s freed."):format(gained, gained == 1 and "" or "s"))
		if ns.Refresh then
			ns.Refresh()
		end
	end

	local function Step()
		if ns.stacking ~= job then
			return
		end
		local move = job.moves[job.index]
		if not move then
			return Finish()
		end
		local from = SlotHolds(move.fromBag, move.fromSlot, move.itemID)
		local to = SlotHolds(move.toBag, move.toSlot, move.itemID)
		if (from and from.isLocked) or (to and to.isLocked) or CursorBusy() then
			-- The server hasn't finished the last move yet.
			job.waitingSince = job.waitingSince or GetTime()
			if GetTime() - job.waitingSince > STACK_TIMEOUT then
				return Finish("Combining stacks timed out; try again.")
			end
			return C_Timer.After(STACK_INTERVAL, Step)
		end
		job.waitingSince = nil
		if not (from and to) or (from.stackCount or 0) < move.amount then
			-- Bags changed under us (looting, another addon); start over.
			job.moves, job.index = ns.PlanStacks(), 1
		else
			if move.amount >= (from.stackCount or 0) then
				C_Container.PickupContainerItem(move.fromBag, move.fromSlot)
			else
				C_Container.SplitContainerItem(move.fromBag, move.fromSlot, move.amount)
			end
			C_Container.PickupContainerItem(move.toBag, move.toSlot)
			job.index = job.index + 1
			job.done = job.done + 1
			if job.done >= STACK_MAX_MOVES then
				return Finish()
			end
		end
		C_Timer.After(STACK_INTERVAL, Step)
	end

	Step()
end

---------------------------------------------------------------------------
-- Keep / junk lists
---------------------------------------------------------------------------

function ns.ItemIDFrom(text)
	if type(text) == "number" then
		return text
	end
	text = text or ""
	return tonumber(text:match("item:(%d+)")) or tonumber(text:match("^%s*(%d+)%s*$"))
end

local function ItemName(itemID)
	local name, link = ns.GetItemInfo(itemID)
	return link or name or ("item " .. itemID)
end
ns.ItemName = ItemName

-- list is "keep" or "trash"; the two are exclusive.
function ns.SetListed(list, itemID, value)
	local other = list == "keep" and "trash" or "keep"
	ns.db[list][itemID] = value and true or nil
	if value then
		ns.db[other][itemID] = nil
	end
	if ns.Refresh then
		ns.Refresh()
	end
end
