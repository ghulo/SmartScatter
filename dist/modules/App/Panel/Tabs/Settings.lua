--[[
	Smart Scatter — Settings tab: the plugin's own settings, the same in every area. Look and text size, the
	viewport overlay, game-ready output and the tour; shortcuts under More options.
	Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]

return function(App)
	local G, saveG, P, SANS, SANS_B = App.G, App.saveG, App.P, App.SANS, App.SANS_B
	local box, label, para, hlist = App.box, App.label, App.para, App.hlist
	local hintOn, switchRow, button, buttonRow, commit = App.hintOn, App.switchRow, App.button, App.buttonRow, App.commit

	local function buildLook(b)
		local swatches = App.chipGrid(b, 5, 32, 88)
		for _, a in App.ACCENTS do
			App.chip(swatches, a.name, function()
				return G.accent == a.name
			end, function()
				if G.accent ~= a.name then
					G.accent = a.name
					saveG()
					task.defer(App.applyTheme) -- after this click finishes (the tab it's on is rebuilt)
				end
			end, Color3.fromHex(a.dark))
		end
		App.explain(b, "The accent the whole plugin wears: buttons, glow, the brush, painted ground and paths.")
		label("Text size", 13, P.text, SANS, { Parent = b })
		App.segmented({ "Small", "Normal", "Large" }, function()
			return App.TEXT_SIZES[G.textScale] or "Normal"
		end, function(v)
			for scale, name in App.TEXT_SIZES do
				if name == v then
					G.textScale = scale
				end
			end
			saveG()
			task.defer(App.rebuildAll) -- after this click finishes (the tab it's on is rebuilt)
		end).Parent =
			b
	end

	local function buildViewport(b)
		switchRow("Show overlay", function()
			return G.overlay
		end, function(v)
			G.overlay = v
		end, function()
			saveG()
			App.rebuildOverlay()
			App.drawSpline()
		end, "Shows the painted area coloured by the surface under it, and the path.").Parent =
			b
		switchRow(
			"Focus when a tool is on",
			function()
				return G.focus
			end,
			function(v)
				G.focus = v
			end,
			function()
				saveG()
				if App.refreshFocus then
					App.refreshFocus()
				end
			end,
			"While a tool is on, the world loses a little colour so the tool stands out, and the viewport's top left says what the tool is doing and on what, like Blender's."
		).Parent =
			b
		switchRow(
			"Tools in the viewport",
			function()
				return G.toolbar
			end,
			function(v)
				G.toolbar = v
			end,
			saveG,
			"A strip of tool buttons down the viewport's left edge, and a bar along its top with the settings of the tool in use, like Blender's. The panel keeps everything too."
		).Parent =
			b
		switchRow("Brush grid", function()
			return G.grid
		end, function(v)
			G.grid = v
		end, function()
			saveG()
			if App.clearGrid then
				App.clearGrid()
			end
		end, "A grid on the ground round the brush, on the area's cells: it shows what a stroke fills. Like Blender's floor grid.").Parent =
			b
		switchRow("History timeline", function()
			return G.history
		end, function(v)
			G.history = v
		end, function()
			saveG()
			task.defer(App.rebuildAll)
		end, "A tick for every step Smart Scatter takes, over the bottom bar: click one to go back (or forward) to it.").Parent =
			b
	end

	local function buildOutput(b)
		local function outSwitch(text, key, hint)
			switchRow(text, function()
				return G[key]
			end, function(v)
				G[key] = v
			end, function()
				saveG()
				commit()
			end, hint).Parent =
				b
		end
		outSwitch("Walk through plants", "walk", "Flowers and bushes get no collision, so players never snag on them.")
		outSwitch("No shadows on small stuff", "shadows", "Flowers and tiny parts skip shadows. Big win on lower-end devices.")
		outSwitch("Flowers ignore clicks", "query", "Flowers won't block raycasts, clicks, tools or weapons.")
		outSwitch(
			"Streaming chunks",
			"chunks",
			"Groups output into 128-stud models that stream in and out together, with low-detail stand-ins far away."
		)
		outSwitch(
			"Live previews as boxes",
			"liveBoxes",
			"With Live on, changes show as a see-through box per copy: quick, even on big areas. Generate places the real models. Off: Live places the real models every time."
		)
		box({ Size = UDim2.new(1, 0, 0, 4), Parent = b })
		App.ui.perf = para("", { Parent = b })
		App.refreshPerf()
	end

	local function buildShortcuts(b)
		App.explain(b, "Click a key to change it, then press the new one (Esc keeps the old). A key already in use swaps over.")
		local group
		for _, a in App.KEYMAP do
			if a.group ~= group then
				group = a.group
				label(group, 12, P.dim, SANS_B, { Size = UDim2.new(1, 0, 0, 24), Parent = b })
			end
			local row = box({ Size = UDim2.new(1, 0, 0, 32), Parent = b })
			label(a.label, 13, P.text, SANS, { Size = UDim2.new(1, -96, 1, 0), Parent = row })
			local key = button(App.keyText(a.id), nil, nil, {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, 0, 0.5, 0),
				AutomaticSize = Enum.AutomaticSize.None,
				Size = UDim2.fromOffset(84, 26),
				Font = SANS_B,
				Parent = row,
			})
			local lit = App.glow(key, 8, 0.8)
			key.MouseButton1Click:Connect(function()
				if App.capturingKey then
					return
				end
				App.capturingKey = true
				key.Text = "Press a key"
				lit:pulse(true)
				App.captureKey(key, function(k)
					App.capturingKey = false
					if not k then
						key.Text = App.keyText(a.id)
						lit:pulse(false)
						return
					end
					local moved = App.bindKey(a.id, k)
					local studio = App.STUDIO_KEYS[k]
					App.status(
						(
							moved
								and string.format("%s is now %s. %s moved to %s.", a.label, App.keyText(a.id), moved.label, App.keyText(moved.id))
							or string.format("%s is now %s.", a.label, App.keyText(a.id))
						) .. (studio and string.format(" Careful: in Studio %s also %s.", App.keyText(a.id), studio) or ""),
						studio and "error" or nil
					)
					App.rebuildAll() -- every hint that names a key shows the new one
				end)
			end)
		end
		local fixed = label(
			"Fixed: Shift erases while painting and raises a path point while dragging; Ctrl+Z undoes; a quick right-click closes a polygon or deletes a path point.",
			12,
			P.faint,
			SANS,
			{ Parent = b }
		)
		fixed.TextWrapped, fixed.AutomaticSize, fixed.Size = true, Enum.AutomaticSize.Y, UDim2.new(1, 0, 0, 0)
		box({ Size = UDim2.new(1, 0, 0, 4), Parent = b })
		button("Reset all shortcuts", "ghost", function()
			App.resetKeys()
			App.status("Shortcuts are back to their defaults.")
			App.rebuildAll()
		end, { Parent = buttonRow(b) })
	end

	local function buildAbout(b)
		hintOn(
			button("Replay the tour", nil, function()
				App.startTour()
			end, { Parent = buttonRow(b) }),
			"A three-minute walk through everything: what it's for, areas, paths, objects and their rules, placing and finishing."
		)
		local about = box({ Size = UDim2.new(1, 0, 0, 40), Parent = b }, { hlist(10) })
		App.new("ImageLabel", { Image = App.LOGO.mark, BackgroundTransparency = 1, Size = UDim2.fromOffset(32, 32), Parent = about })
		local words = App.col({ Size = UDim2.new(1, -42, 0, 0), Parent = about }, { App.vlist(0) })
		label("Smart Scatter  " .. tostring(App.ctx.version or "dev"), 13, P.text, SANS_B, { Size = UDim2.new(1, 0, 0, 18), Parent = words })
		label("made by Ghulo", 12, P.faint, SANS, { Size = UDim2.new(1, 0, 0, 16), Parent = words })
	end

	App.buildSettingsTab = function(page)
		local cs = App.cards(page, "settings")
		cs.add({
			id = "look",
			title = "Look",
			sub = "Accent colour and text size",
			keys = "theme accent colour color text size font",
			build = buildLook,
		})
		cs.add({ id = "viewport", title = "Viewport", sub = "What's drawn over the 3D view", keys = "overlay", build = buildViewport })
		cs.add({
			id = "output",
			title = "Game-ready output",
			keys = "collision walk shadows clicks raycast streaming chunks live preview boxes ghost performance parts",
			build = buildOutput,
		})
		cs.add({
			id = "about",
			title = "Tour and about",
			sub = "A walk through everything, and the version",
			keys = "tour help version",
			build = buildAbout,
		})
		cs.add({
			id = "shortcuts",
			title = "Shortcuts",
			sub = "Every key, and changing them",
			keys = "keys keyboard keybind hotkey",
			more = true,
			build = buildShortcuts,
		})
	end
end
