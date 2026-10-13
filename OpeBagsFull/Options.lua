local _, ns = ...

---------------------------------------------------------------------------
-- Settings panel (Esc > Options > AddOns > Ope, Bag's Full)
---------------------------------------------------------------------------

local function SectionHeader(layout, text)
	if layout and CreateSettingsListSectionHeaderInitializer then
		layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text))
	end
end

function ns.CreateSettings()
	if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterAddOnSetting) then
		return
	end
	local db = ns.db
	local category, layout = Settings.RegisterVerticalLayoutCategory(ns.TITLE)

	local function Register(key, varType, name)
		local setting = Settings.RegisterAddOnSetting(category, "OPEBAGSFULL_" .. key:upper(), key, db,
			varType, name, ns.defaults[key])
		if setting and setting.SetValueChangedCallback then
			setting:SetValueChangedCallback(function()
				ns.Refresh()
			end)
		end
		return setting
	end
	local function Checkbox(key, name, tooltip)
		Settings.CreateCheckbox(category, Register(key, Settings.VarType.Boolean, name), tooltip)
	end
	local function Slider(key, name, min, max, tooltip)
		local options = Settings.CreateSliderOptions(min, max, 1)
		if MinimalSliderWithSteppersMixin then
			options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right)
		end
		Settings.CreateSlider(category, Register(key, Settings.VarType.Number, name), options, tooltip)
	end

	SectionHeader(layout, "What can go")
	Checkbox("includeCommon", "Include white items",
		"Gray items always count as junk. Turn this on to also let white (common) items go, cheapest first. Bags, ammo, keys, class reagents and quest items are always kept.")
	Checkbox("includeUncommon", "Include green items",
		"Also let green (uncommon) items go, cheapest first. Careful: this includes Bind on Equip gear that could sell on the auction house.")
	Checkbox("keepConsumables", "Keep food, drink and potions",
		"When white or green items are allowed, never trash consumables like food, water, potions, bandages and scrolls.")
	Checkbox("respectStashOrTrash", "Keep crafting materials (Stash or Trash)",
		"If you also use the Stash or Trash addon: never trash white or green items that your professions, or your alts', can use.")

	SectionHeader(layout, "Making room")
	Slider("goal", "Free slots to aim for", 1, 20,
		"How many free bag slots Make room works toward. Also adjustable with + and - in the panel.")
	Checkbox("combineStacks", "Combine stacks first",
		"Before trashing anything, merge partial stacks of the same item (free bag space, nothing lost).")

	SectionHeader(layout, "Vendors and alerts")
	Checkbox("autoSellJunk", "Sell junk at vendors automatically",
		"When you open a vendor, sell all gray items and anything on your junk list. You can buy them back from the vendor's Buyback tab.")
	Checkbox("alertWhenFull", "Alert when bags are full",
		"When you try to loot with full bags, play a sound, name the cheapest item to trash and open the Make room panel.")
	Slider("lowSpaceWarning", "Warn when this many slots are left", 0, 10,
		"Print a warning when your free bag slots drop to this number. 0 turns it off.")
	Checkbox("showBagButton", "Show the Ope icon on your backpack",
		"Adds a bag icon beside the default backpack window showing your free slots. Click it to make room, Shift-click to trash the cheapest item.")

	Settings.RegisterAddOnCategory(category)
	ns.settingsCategory = category
end

function ns.OpenSettings()
	if ns.settingsCategory and Settings and Settings.OpenToCategory then
		Settings.OpenToCategory(ns.settingsCategory:GetID())
	else
		ns.Print("The settings panel is not available on this client. Use /ope help.")
	end
end

-- Addon compartment (the minimap drop-down), declared in the .toc.
function OpeBagsFull_OnAddonCompartmentClick()
	ns.TogglePanel()
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------

local function ListNames(list)
	local names = {}
	for itemID in pairs(list) do
		names[#names + 1] = ns.ItemName(itemID)
	end
	table.sort(names)
	return #names > 0 and table.concat(names, ", ") or "empty"
end

local function ListCommand(list, value, rest, done)
	local itemID = ns.ItemIDFrom(rest)
	if not itemID then
		ns.Print("Shift-click an item into the command, e.g. /ope " .. (value and "" or "un") .. list .. " [Linen Cloth]")
		return
	end
	ns.SetListed(list == "junk" and "trash" or list, itemID, value)
	ns.Print(ns.ItemName(itemID) .. " " .. done .. ".")
end

local HELP = {
	"/ope - show the Make room panel",
	"/ope trash - trash the cheapest item (one per use; works in a macro)",
	"/ope room - combine stacks, then trash the next item toward your goal",
	"/ope goal <n> - free slots to aim for",
	"/ope stack - combine partial stacks",
	"/ope sell - sell junk (at a vendor)",
	"/ope keep <item> / unkeep <item> - never trash an item",
	"/ope junk <item> / unjunk <item> - always treat an item as junk",
	"/ope lists - show your keep and junk lists",
	"/ope options - settings",
}

local function Status()
	local plan = ns.Plan()
	ns.Print(("%d free slots, goal %d. %d item%s can go."):format(plan.free, plan.goal, plan.available,
		plan.available == 1 and "" or "s"))
	local next = ns.Candidates()[1]
	if next then
		ns.Print("Cheapest: " .. ns.ItemLabel(next) .. " (" .. ns.FormatMoney(next.value) .. ")")
	end
	if ns.session.trashed > 0 or ns.session.sold > 0 then
		ns.Print(("This session: trashed %d (%s), sold %d (%s)."):format(ns.session.trashed,
			ns.FormatMoney(ns.session.lost), ns.session.sold, ns.FormatMoney(ns.session.earned)))
	end
end

SLASH_OPEBAGSFULL1 = "/ope"
SLASH_OPEBAGSFULL2 = "/opebagsfull"
SlashCmdList.OPEBAGSFULL = function(msg)
	msg = msg or ""
	local cmd, rest = msg:match("^%s*(%S*)%s*(.-)%s*$")
	cmd = (cmd or ""):lower()
	if cmd == "" then
		ns.TogglePanel()
	elseif cmd == "trash" or cmd == "next" then
		ns.TrashNext()
	elseif cmd == "room" or cmd == "make" then
		ns.MakeRoom()
	elseif cmd == "goal" then
		if tonumber(rest) then
			ns.SetGoal(rest)
		end
		ns.Print("Goal: " .. ns.db.goal .. " free slots.")
	elseif cmd == "stack" or cmd == "stacks" then
		if #ns.PlanStacks() == 0 then
			ns.Print("No partial stacks to combine.")
		else
			ns.CombineStacks()
		end
	elseif cmd == "sell" then
		if ns.AtMerchant() then
			ns.SellJunk()
		else
			ns.Print("Open a vendor first.")
		end
	elseif cmd == "keep" then
		ListCommand("keep", true, rest, "will never be trashed")
	elseif cmd == "unkeep" then
		ListCommand("keep", false, rest, "removed from your keep list")
	elseif cmd == "junk" then
		ListCommand("junk", true, rest, "will always count as junk")
	elseif cmd == "unjunk" then
		ListCommand("junk", false, rest, "removed from your junk list")
	elseif cmd == "lists" or cmd == "list" then
		ns.Print("Keep: " .. ListNames(ns.db.keep))
		ns.Print("Junk: " .. ListNames(ns.db.trash))
	elseif cmd == "options" or cmd == "config" or cmd == "settings" then
		ns.OpenSettings()
	elseif cmd == "status" then
		Status()
	else
		for _, line in ipairs(HELP) do
			ns.Print(line)
		end
	end
end

function ns.OnInitialize()
	ns.CreateSettings()
end
