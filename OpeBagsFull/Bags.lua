local _, ns = ...

-- Reading the bags and deciding what can go: free slots, trash candidates
-- (lowest vendor value first) and which partial stacks can be combined.

local ItemClass = {
	Consumable = 0,
	Container = 1,
	Reagent = 5,
	Projectile = 6,
	Quiver = 11,
	Quest = 12,
	Key = 13,
}
ns.ItemClass = ItemClass

-- Never trashed unless they're on your junk list: bags, class reagents,
-- ammo and quivers, keys.
local PROTECTED_CLASSES = {
	[ItemClass.Container] = "bag",
	[ItemClass.Reagent] = "reagent",
	[ItemClass.Projectile] = "ammo",
	[ItemClass.Quiver] = "quiver",
	[ItemClass.Key] = "key",
}

local QUALITY_POOR, QUALITY_COMMON, QUALITY_UNCOMMON = 0, 1, 2

---------------------------------------------------------------------------
-- Bags
---------------------------------------------------------------------------

-- Backpack and equipped bags that take any item. Specialty bags (soul bags,
-- quivers, herb bags...) are left out: emptying them doesn't make room for loot.
function ns.GeneralBags()
	local bags = {}
	for bag = 0, NUM_BAG_SLOTS or 4 do
		local size = C_Container.GetContainerNumSlots(bag) or 0
		local _, family = C_Container.GetContainerNumFreeSlots(bag)
		if size > 0 and (family or 0) == 0 then
			bags[#bags + 1] = bag
		end
	end
	return bags
end

function ns.FreeSlots()
	local free = 0
	for _, bag in ipairs(ns.GeneralBags()) do
		free = free + (C_Container.GetContainerNumFreeSlots(bag) or 0)
	end
	return free
end

-- Everything in the general bags, with what we need to judge it. Items the
-- client hasn't loaded yet are requested and marked `pending`.
function ns.ScanItems()
	local items = {}
	for _, bag in ipairs(ns.GeneralBags()) do
		for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.itemID then
				local name, _, quality, _, _, _, _, maxStack, _, icon, sellPrice, classID = ns.GetItemInfo(info.itemID)
				local count = info.stackCount or 1
				local item = {
					bag = bag,
					slot = slot,
					itemID = info.itemID,
					link = info.hyperlink,
					name = name or info.itemName,
					icon = info.iconFileID or icon,
					count = count,
					quality = info.quality or quality,
					locked = info.isLocked,
					noValue = info.hasNoValue,
					classID = classID,
					maxStack = maxStack or 1,
					unitPrice = sellPrice or 0,
					value = (sellPrice or 0) * count,
					pending = name == nil,
				}
				if item.pending then
					ns.RequestItem(info.itemID)
				end
				local quest = C_Container.GetContainerItemQuestInfo and C_Container.GetContainerItemQuestInfo(bag, slot)
				item.quest = classID == ItemClass.Quest or (quest and (quest.isQuestItem or quest.questID)) and true or false
				items[#items + 1] = item
			end
		end
	end
	return items
end

---------------------------------------------------------------------------
-- What may go
---------------------------------------------------------------------------

-- With Stash or Trash installed: does this character (or a usable alt) have
-- a profession that uses the item?
function ns.UsedByProfessions(itemID)
	local sot = _G.StashOrTrash
	if not (sot and type(sot.BuildReport) == "function") then
		return false
	end
	local ok, report = pcall(sot.BuildReport, itemID)
	return ok and type(report) == "table" and ((report.mine and #report.mine > 0) or (report.alts and #report.alts > 0)) or false
end

-- Returns true, or false and the reason the item is kept. `junkOnly` limits
-- it to gray items and your junk list (what's safe to sell automatically).
function ns.IsTrashable(item, junkOnly)
	local db = ns.db
	if item.pending then
		return false, "still loading"
	end
	if db.keep[item.itemID] then
		return false, "on your keep list"
	end
	if item.quest then
		return false, "quest item"
	end
	if db.trash[item.itemID] then
		return true
	end
	if item.noValue or item.unitPrice <= 0 then
		return false, "can't be sold"
	end
	local quality = item.quality or QUALITY_COMMON
	if quality == QUALITY_POOR then
		return true
	end
	if junkOnly then
		return false, "not junk"
	end
	if quality == QUALITY_COMMON and not db.includeCommon then
		return false, "white item"
	elseif quality == QUALITY_UNCOMMON and not db.includeUncommon then
		return false, "green item"
	elseif quality > QUALITY_UNCOMMON then
		return false, "rare or better"
	end
	local protected = PROTECTED_CLASSES[item.classID]
	if protected then
		return false, protected
	end
	if db.keepConsumables and item.classID == ItemClass.Consumable then
		return false, "consumable"
	end
	if db.respectStashOrTrash and ns.UsedByProfessions(item.itemID) then
		return false, "used by your professions"
	end
	return true
end

local function ByValue(a, b)
	if a.value ~= b.value then
		return a.value < b.value
	end
	if (a.quality or 1) ~= (b.quality or 1) then
		return (a.quality or 1) < (b.quality or 1)
	end
	if a.bag ~= b.bag then
		return a.bag < b.bag
	end
	return a.slot < b.slot
end

-- Trashable items, cheapest stack first.
function ns.Candidates(items, junkOnly)
	local list = {}
	for _, item in ipairs(items or ns.ScanItems()) do
		if not item.locked and ns.IsTrashable(item, junkOnly) then
			list[#list + 1] = item
		end
	end
	table.sort(list, ByValue)
	return list
end

---------------------------------------------------------------------------
-- Combining stacks
---------------------------------------------------------------------------

-- Moves that top up the fullest partial stack of each item from the
-- smallest ones. Returns the moves and how many slots they empty.
function ns.PlanStacks(items)
	local groups = {}
	for _, item in ipairs(items or ns.ScanItems()) do
		if item.maxStack > 1 and item.count < item.maxStack and not item.locked and not item.pending then
			local group = groups[item.itemID]
			if not group then
				group = {}
				groups[item.itemID] = group
			end
			group[#group + 1] = { bag = item.bag, slot = item.slot, count = item.count, max = item.maxStack, itemID = item.itemID }
		end
	end

	local moves, freed = {}, 0
	local ids = {}
	for itemID, group in pairs(groups) do
		if #group > 1 then
			ids[#ids + 1] = itemID
		end
	end
	table.sort(ids)
	for _, itemID in ipairs(ids) do
		local stacks = groups[itemID]
		table.sort(stacks, function(a, b)
			if a.count ~= b.count then
				return a.count > b.count
			end
			if a.bag ~= b.bag then
				return a.bag < b.bag
			end
			return a.slot < b.slot
		end)
		local dst, src = 1, #stacks
		while dst < src do
			local to, from = stacks[dst], stacks[src]
			local room = to.max - to.count
			if room <= 0 then
				dst = dst + 1
			else
				local amount = math.min(room, from.count)
				moves[#moves + 1] = {
					itemID = itemID, amount = amount,
					fromBag = from.bag, fromSlot = from.slot, toBag = to.bag, toSlot = to.slot,
				}
				to.count = to.count + amount
				from.count = from.count - amount
				if from.count == 0 then
					freed = freed + 1
					src = src - 1
				end
			end
		end
	end
	return moves, freed
end

---------------------------------------------------------------------------
-- The plan
---------------------------------------------------------------------------

-- What "Make room" would do to reach `goal` free slots: combine stacks
-- first (free), then trash the cheapest items.
function ns.Plan(goal)
	goal = goal or ns.db.goal
	local items = ns.ScanItems()
	local free = ns.FreeSlots()
	local plan = { free = free, goal = goal, need = math.max(0, goal - free), trash = {}, lost = 0, moves = {}, stackFreed = 0 }
	if ns.db.combineStacks then
		plan.moves, plan.stackFreed = ns.PlanStacks(items)
	end
	local candidates = ns.Candidates(items)
	plan.available = #candidates
	local remaining = math.max(0, plan.need - plan.stackFreed)
	for i = 1, math.min(remaining, #candidates) do
		plan.trash[i] = candidates[i]
		plan.lost = plan.lost + candidates[i].value
	end
	plan.short = remaining - #plan.trash -- slots we can't free with the current rules
	return plan
end
