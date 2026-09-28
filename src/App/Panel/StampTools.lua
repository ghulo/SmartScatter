--[[
	Smart Scatter — StampTools: the Stamp card (Brush tab), for putting single models down by hand anywhere, no area
	needed (Viewport/Stamp does the stamping). Before stamping: stamp what's selected in the Explorer, or one of the
	area's objects. While stamping: which model, its turn and size, standing along the surface, a random one after
	each stamp, and its keys. The object's own Stamp button (Panel/HandTools) starts the same tool.
	Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]

return function(App)
	local G, saveG, P = App.G, App.saveG, App.P
	local col, vlist, para = App.col, App.vlist, App.para
	local slider, switchRow, button, buttonRow, hintOn, chip, chipGrid =
		App.slider, App.switchRow, App.button, App.buttonRow, App.hintOn, App.chip, App.chipGrid
	local key = App.keyText

	-- the stamp's settings while it's on: which model, turn, size, how it stands, random, keys
	local function controls(parent, rebuild)
		local st = App.stamp
		if #st.models > 1 then
			local grid = chipGrid(parent, 3, 28, 104)
			for i, inst in st.models do
				chip(grid, inst.Name, function()
					return st.vi == i
				end, function()
					App.setStamp(nil, nil, i)
					rebuild()
				end)
			end
		end
		slider("Turn", 0, 359, function()
			return math.floor(math.deg(st.yaw) + 0.5) % 360
		end, function(v)
			App.setStamp(v)
		end, "%d°", 1, nil, nil, "Which way it faces. Drag in the viewport to aim it, or " .. key("turn") .. " to turn it in 15° steps.", 0).Parent =
			parent
		slider("Size", 0.1, 5, function()
			return st.k
		end, function(v)
			App.setStamp(nil, v)
		end, "%.2f×", 0.05, nil, nil, "1× is the model's own size. " .. key("shrink") .. " and " .. key("grow") .. " in the viewport.", 1).Parent =
			parent
		switchRow("Stand along the surface", function()
			return G.stampAlign
		end, function(v)
			G.stampAlign = v
		end, saveG, "On: it leans with slopes and can go on walls. Off: it stands upright, settled on the lowest ground under it.").Parent =
			parent
		switchRow("A random one after each stamp", function()
			return G.stampRandom
		end, function(v)
			G.stampRandom = v
		end, saveG, "After each stamp the next gets a random turn, a size a little either side of the one set, and a random model of these.").Parent =
			parent
		local acts = buttonRow(parent)
		hintOn(
			button("Random now", nil, App.rollStamp, { Parent = acts }),
			"A random turn, size and model for the next stamp (" .. key("shuffle") .. " in the viewport)."
		)
		button("Stop stamping", nil, function()
			App.setMode("Off")
		end, { Parent = acts })
		App.keyChips(parent, {
			{ key("turn"), "turn" },
			{ "Shift", "turn freely" },
			{ key("shrink") .. " " .. key("grow"), "size" },
			{ key("model"), "model" },
			{ key("shuffle"), "random" },
			{ key("cancel"), "stop" },
		})
	end
	App.stampControls = controls

	-- every view of the stamp, rebuilt when it changes (keys, the bar, a random roll): [name] = rebuild
	App.stampViews = {}
	App.refreshStamp = function()
		for _, f in App.stampViews do
			f()
		end
	end

	App.buildStampCard = function(b)
		local box = col({ Parent = b }, { vlist(6) })
		local function build()
			for _, c in box:GetChildren() do
				if c:IsA("GuiObject") then
					c:Destroy()
				end
			end
			if App.mode == "Stamp" then
				local inst = App.stamp.models[App.stamp.vi]
				local head = para(
					string.format(
						"Stamping %s. Click the ground to put it down, press and drag to turn it. Stamps go in Workspace › Stamps.",
						inst and inst.Name or "?"
					),
					{ Parent = box }
				)
				head.TextColor3 = P.text
				controls(box, build)
				return
			end
			App.explain(
				box,
				"One model, exactly where you click, anywhere on the ground: no area needed. Select a model (or a folder of them) in the Explorer, then:"
			)
			local go = App.primaryButton("Stamp selected models", function()
				App.startStamp()
			end)
			go.Parent = buttonRow(box)
			hintOn(go, "The selected models float under the mouse; click to put one down. Pick up where you left off with no selection.")
			local a = App.area
			if a and #a.layers > 0 then -- or one of the area's own objects (all its models)
				App.label("Or one of this area's objects", 12, P.dim, App.SANS_B, { Size = UDim2.new(1, 0, 0, 20), Parent = box })
				local grid = chipGrid(box, 3, 28, 104)
				for _, l in a.layers do
					chip(grid, l.inst.Name, nil, function()
						App.startStamp(l)
					end)
				end
			end
		end
		build()
		App.stampViews.card = function()
			if box.Parent then
				build()
			end
		end
	end
end
