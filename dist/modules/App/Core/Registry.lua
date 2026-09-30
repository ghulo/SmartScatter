--[[
	Smart Scatter — Registry: what the plugin is made of, as plain lists the panel and the viewport read. A feature
	registers its pieces here, and the outliner, the properties, the tool strip and the search menu show them; none of
	those knows the features by name. Adding a tool is one module that registers what it brings.
	  kind  a thing the outliner lists (Zone, Path, Clear, Stamps…):
	        { kind, icon, title, order, list = fn() -> { thing }, count = fn(thing) -> number?,
	          menu = fn(thing) -> { { text, run, danger? } }?, thumb = fn(thing) -> the model its row pictures?,
	          reorder = true when its rows can be put in any order (kept on each thing's folder, SS_Order) }
	  tab   a page of the properties for some kinds of thing:
	        { id, icon, title, order, kinds = { [kind] = true } | "all", when = fn(thing, active) -> bool?,
	          build = fn(page) }
	  tool  a button of the viewport's tool strip (and the panel's tool row where the strip can't show):
	        { id, group, order, icon, name, key? (a keymap id), danger?, when = fn() -> bool?, on = fn() -> bool,
	          click = fn() }
	  action  a line of the search menu: { id, name, group, icon?, words?, key?, when = fn() -> bool?, run = fn() }
	Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]

return function(App)
	local kinds, tabs, tools, actions = {}, {}, {}, {}

	local function byOrder(list)
		table.sort(list, function(a, b)
			if (a.order or 0) ~= (b.order or 0) then
				return (a.order or 0) < (b.order or 0)
			end
			return a.id < b.id
		end)
	end
	-- (a spec registered again under its id replaces the first: a module reloaded, or a tab rebuilt)
	local function put(list, spec)
		for i, s in list do
			if s.id == spec.id then
				list[i] = spec
				byOrder(list)
				return spec
			end
		end
		table.insert(list, spec)
		byOrder(list)
		return spec
	end

	App.registerKind = function(spec)
		spec.id = spec.kind
		return put(kinds, spec)
	end
	App.registerTab = function(spec)
		return put(tabs, spec)
	end
	App.registerTool = function(spec)
		return put(tools, spec)
	end
	App.registerAction = function(spec)
		return put(actions, spec)
	end
	-- the registered actions that apply now (the search menu adds them to its own)
	App.registeredActions = function()
		local out = {}
		for _, a in actions do
			if a.when == nil or a.when() ~= false then
				table.insert(out, a)
			end
		end
		return out
	end

	-- the thing kinds, in the outliner's order (App.kinds is the map scan's: Panel/MapTools)
	App.thingKinds = function()
		return kinds
	end
	App.kindSpec = function(kind)
		for _, k in kinds do
			if k.kind == kind then
				return k
			end
		end
		return nil
	end

	-- the tabs for a selection (nil: nothing selected), in order: the ones for its kind or for every kind, less the
	-- ones whose `when` says not now
	App.tabsFor = function(thing, active)
		local out = {}
		for _, t in tabs do
			local forKind = t.kinds == "all" or (thing ~= nil and t.kinds[thing.kind] == true)
			if forKind and (t.when == nil or t.when(thing, active) ~= false) then
				table.insert(out, t)
			end
		end
		return out
	end
	App.tabById = function(id)
		for _, t in tabs do
			if t.id == id then
				return t
			end
		end
		return nil
	end

	-- the tool strip's groups, in order (a tool's group places it; an unknown group goes last)
	App.TOOL_GROUPS = { "Select", "Ground", "Object", "Stamp", "Path", "Remove", "Search" }
	-- the tools that apply now, grouped: { { group, tools = { spec } } } in the strip's order
	App.toolGroups = function()
		local rank = {}
		for i, g in App.TOOL_GROUPS do
			rank[g] = i
		end
		local groups, byName = {}, {}
		for _, t in tools do
			if t.when == nil or t.when() ~= false then
				local g = byName[t.group]
				if not g then
					g = { group = t.group, tools = {} }
					byName[t.group] = g
					table.insert(groups, g)
				end
				table.insert(g.tools, t)
			end
		end
		table.sort(groups, function(a, b)
			return (rank[a.group] or 99) < (rank[b.group] or 99)
		end)
		return groups
	end
end
