--[[
	Smart Scatter — Focus: while a tool of the plugin is on in the viewport (painting, erasing, drawing the path,
	brushing one object, removing copies), the world steps back a little, so the tool stands out, the way Blender's
	edit mode and local view feel: the scene fades toward grey and dims (a colour correction on the camera, never
	saved with the place), a faint frame in the accent runs round the viewport, and quiet text in its top-left corner
	says the mode and what it's working on, Blender style. Red while it takes things away. Settings › Viewport can
	turn it off.
	Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]

return function(App)
	local G, P, tween, MED, FAST = App.G, App.P, App.tween, App.MED, App.FAST
	local new, box, corner, label = App.new, App.box, App.corner, App.label
	local SANS_M, SANS_B = App.SANS_M, App.SANS_B
	local LAYER_MODES = App.LAYER_MODES

	local LOOK = { Saturation = -0.35, Brightness = -0.05, Contrast = -0.06 } -- how far the world steps back
	local cc -- the camera's colour correction while focused
	local gui, group, frame, glowLine, dot, title, detail, keyRow -- the frame and the corner text, over the viewport

	-- what the tool is doing now: the mode, what it works on, and whether it takes things away
	local function describe()
		local m = App.mode
		local shift = App.shiftHeld and App.shiftHeld()
		local area = App.area and App.area.folder.Name or nil
		local function on(...)
			local bits = {}
			for _, b in { ... } do
				if b then
					table.insert(bits, b)
				end
			end
			return table.concat(bits, "  ·  ")
		end
		if m == "Paint" or m == "Erase" then
			local erase = (m == "Erase") ~= (shift == true)
			return erase and "Erasing ground" or "Painting ground", on(G.tool, area), erase
		elseif m == "Spline" and App.shapeTool then
			return "Placing a " .. string.lower(App.shapeTool),
				on(App.shapeTool == "Rectangle" and "corner to corner" or "drag from the centre", area),
				false
		elseif m == "Spline" then
			return "Drawing the path", on(area), false
		elseif m == "Remove" then
			return "Removing copies", on("click one to take it out", area), true
		elseif LAYER_MODES[m] then
			local act = shift and App.LAYER_OPPOSITE[m] or m
			local name = App.paintLayer and App.paintLayer.inst.Name or "object"
			return App.LAYER_LABEL[act] .. " · one object", on(name, area), act == "None" or act == "Less"
		end
		return nil, nil, false
	end

	local function build()
		gui = new("ScreenGui", {
			Name = "SmartScatterFocus",
			Archivable = false,
			IgnoreGuiInset = true,
			DisplayOrder = 50,
			ResetOnSpawn = false,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		})
		group = new("CanvasGroup", { BackgroundTransparency = 1, GroupTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = gui })
		-- the frame: a crisp line and a soft glow just inside it
		frame = box({ Size = UDim2.fromScale(1, 1), Parent = group })
		local line = App.stroke(P.accent)
		line.Thickness, line.Transparency = 2, 0.55
		line.Parent = frame
		local inner = box({ Position = UDim2.fromOffset(2, 2), Size = UDim2.new(1, -4, 1, -4), Parent = group })
		glowLine = App.stroke(P.accent)
		glowLine.Thickness, glowLine.Transparency = 6, 0.9
		glowLine.Parent = inner
		-- the corner text, Blender style: small, white, outlined so it reads on any sky; the mode, then what it's on
		local cornerText =
			box({ Position = UDim2.fromOffset(16, 12), Size = UDim2.fromOffset(0, 0), AutomaticSize = Enum.AutomaticSize.XY, Parent = group })
		dot = box({
			BackgroundTransparency = 0,
			BackgroundColor3 = P.accent,
			Position = UDim2.fromOffset(0, 6),
			Size = UDim2.fromOffset(7, 7),
			Parent = cornerText,
		}, { corner(4) })
		local lines = box(
			{ Position = UDim2.fromOffset(14, 0), Size = UDim2.fromOffset(0, 0), AutomaticSize = Enum.AutomaticSize.XY, Parent = cornerText },
			{
				new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 1) }),
			}
		)
		title = label(
			"",
			14,
			Color3.new(1, 1, 1),
			SANS_B,
			{ Size = UDim2.fromOffset(0, 18), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 1, Parent = lines }
		)
		detail = label(
			"",
			12,
			Color3.fromRGB(215, 215, 215),
			SANS_M,
			{ Size = UDim2.fromOffset(0, 16), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 2, Parent = lines }
		)
		-- under it, while painting: the overlay's colours and what they mean
		keyRow = box({ Size = UDim2.fromOffset(0, 18), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 3, Parent = lines }, {
			new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 10),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		})
		for _, t in { title, detail } do
			t.TextStrokeColor3, t.TextStrokeTransparency = Color3.new(0, 0, 0), 0.55
			t.TextTruncate = Enum.TextTruncate.None
		end
		pcall(function()
			gui.Parent = game:GetService("CoreGui")
		end)
	end

	local shown = false
	-- takes the focus on or off, and keeps its label and colour in step with the tool (called whenever the mode,
	-- the tool or Shift changes)
	App.refreshFocus = function()
		local what, where, erase = describe()
		local on = G.focus ~= false and what ~= nil
		if on then
			if not (gui and gui.Parent) then
				build()
			end
			local col = erase and P.danger or P.accent
			frame:FindFirstChildOfClass("UIStroke").Color = col
			glowLine.Color = col
			dot.BackgroundColor3 = col
			title.Text = what
			-- the colour key, for the tools the overlay colours the ground for
			keyRow:ClearAllChildren()
			new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 10),
				SortOrder = Enum.SortOrder.LayoutOrder,
				Parent = keyRow,
			})
			local painting = App.mode == "Paint" or App.mode == "Erase" or LAYER_MODES[App.mode] ~= nil
			keyRow.Visible = painting and App.overlayLegend ~= nil
			if keyRow.Visible then
				for i, e in App.overlayLegend() do
					local item = box({ Size = UDim2.fromOffset(0, 18), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = i, Parent = keyRow }, {
						new("UIListLayout", {
							FillDirection = Enum.FillDirection.Horizontal,
							VerticalAlignment = Enum.VerticalAlignment.Center,
							Padding = UDim.new(0, 4),
						}),
					})
					local sw = box(
						{ BackgroundTransparency = 0, BackgroundColor3 = e[1], Size = UDim2.fromOffset(9, 9), Parent = item },
						{ corner(2) }
					)
					App.stroke(Color3.new(0, 0, 0)).Parent = sw
					local t = label(
						e[2],
						11,
						Color3.fromRGB(225, 225, 225),
						SANS_M,
						{ Size = UDim2.fromOffset(0, 18), AutomaticSize = Enum.AutomaticSize.X, Parent = item }
					)
					t.TextStrokeColor3, t.TextStrokeTransparency = Color3.new(0, 0, 0), 0.55
				end
			end
			detail.Text = (where ~= "" and (where .. "  ·  ") or "") .. App.keyText("cancel") .. " to stop"
			local cam = workspace.CurrentCamera
			if cam and not (cc and cc.Parent == cam) then
				cc = new(
					"ColorCorrectionEffect",
					{ Name = "SmartScatterFocus", Archivable = false, Saturation = 0, Brightness = 0, Contrast = 0, Parent = cam }
				)
			end
			if not shown then
				tween(group, MED, { GroupTransparency = 0 })
				if cc then
					tween(cc, MED, LOOK)
				end
			end
			if cc then
				cc.TintColor = Color3.new(1, 1, 1):Lerp(col, 0.05)
			end
			shown = true
		elseif shown then
			shown = false
			if group then
				tween(group, FAST, { GroupTransparency = 1 })
			end
			if cc then
				local gone = cc
				cc = nil
				tween(gone, MED, { Saturation = 0, Brightness = 0, Contrast = 0 })
				task.delay(0.3, function()
					gone:Destroy()
				end)
			end
		end
	end

	-- gone for good (the plugin unloads or updates)
	App.clearFocus = function()
		shown = false
		if cc then
			cc:Destroy()
			cc = nil
		end
		if gui then
			gui:Destroy()
			gui = nil
		end
	end
	-- (one left by an earlier load of the plugin)
	local cam = workspace.CurrentCamera
	local old = cam and cam:FindFirstChild("SmartScatterFocus")
	if old then
		old:Destroy()
	end
	pcall(function()
		local g = game:GetService("CoreGui"):FindFirstChild("SmartScatterFocus")
		if g then
			g:Destroy()
		end
	end)
end
