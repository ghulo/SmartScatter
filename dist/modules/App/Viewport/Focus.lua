--[[
	Smart Scatter — Focus: while a tool of the plugin is on in the viewport (painting, erasing, drawing the path,
	brushing one object, removing copies), the world steps back a touch so the tool stands out, and the viewport's top
	left says what's going on, the way Blender's does: the tool, then what it works on, then how to stop. Small, plain
	text; no frame, no badges. The world only loses a little colour (a colour correction on the camera, never saved
	with the place). The tool's name turns red while it takes things away. Settings › Viewport can turn it off.
	Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]

return function(App)
	local G, P, tween, MED, FAST = App.G, App.P, App.tween, App.MED, App.FAST
	local new, box, label = App.new, App.box, App.label
	local SANS, SANS_M = App.SANS, App.SANS_M
	local LAYER_MODES = App.LAYER_MODES

	local LOOK = { Saturation = -0.18, Brightness = -0.03, Contrast = 0 } -- how far the world steps back
	local WHITE = Color3.fromRGB(235, 235, 235)
	local cc -- the camera's colour correction while focused
	local gui, group, tick, title, detail, stop -- the corner text, over the viewport

	-- what the tool is doing now: its name, what it works on, and whether it takes things away
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
			return erase and "Erase" or "Paint", on(area, G.tool), erase
		elseif m == "Spline" and App.shapeTool then
			return App.shapeTool, on(area, App.shapeTool == "Rectangle" and "drag corner to corner" or "drag from the centre"), false
		elseif m == "Spline" then
			return "Draw path", on(area), false
		elseif m == "Remove" then
			return "Remove copies", on(area, "click one"), true
		elseif LAYER_MODES[m] then
			local act = shift and App.LAYER_OPPOSITE[m] or m
			local name = App.paintLayer and App.paintLayer.inst.Name or nil
			return App.LAYER_LABEL[act], (area and name) and (area .. "  ›  " .. name) or on(area, name), act == "None" or act == "Less"
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
		-- top left: a short tick in the tool's colour, then three lines, each quieter than the one before
		local corner =
			box({ Position = UDim2.fromOffset(14, 12), Size = UDim2.fromOffset(0, 0), AutomaticSize = Enum.AutomaticSize.XY, Parent = group })
		tick = box({
			BackgroundTransparency = 0,
			BackgroundColor3 = P.accent,
			Position = UDim2.fromOffset(0, 3),
			Size = UDim2.fromOffset(2, 13),
			Parent = corner,
		})
		local lines = box(
			{ Position = UDim2.fromOffset(9, 0), Size = UDim2.fromOffset(0, 0), AutomaticSize = Enum.AutomaticSize.XY, Parent = corner },
			{
				new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 0) }),
			}
		)
		local function line(size, font, order)
			local t = label("", size, WHITE, font, {
				Size = UDim2.fromOffset(0, size + 5),
				AutomaticSize = Enum.AutomaticSize.X,
				LayoutOrder = order,
				Parent = lines,
			})
			t.TextTruncate = Enum.TextTruncate.None
			t.TextStrokeColor3, t.TextStrokeTransparency = Color3.new(0, 0, 0), 0.8 -- (just enough to read on a bright sky)
			return t
		end
		title = line(14, SANS_M, 1)
		detail = line(12, SANS, 2)
		detail.TextTransparency = 0.3
		stop = line(11, SANS, 3)
		stop.TextTransparency = 0.5
		pcall(function()
			gui.Parent = game:GetService("CoreGui")
		end)
	end

	local shown = false
	-- takes the focus on or off, and keeps its text and colour in step with the tool (called whenever the mode,
	-- the tool or Shift changes)
	App.refreshFocus = function()
		local what, where, erase = describe()
		local on = G.focus ~= false and what ~= nil
		if on then
			if not (gui and gui.Parent) then
				build()
			end
			local col = erase and P.danger:Lerp(WHITE, 0.25) or WHITE
			tick.BackgroundColor3 = erase and P.danger or P.accent
			title.Text = what
			title.TextColor3 = col
			detail.Text = where or ""
			detail.Visible = where ~= nil and where ~= ""
			stop.Text = App.keyText("cancel") .. " to stop"
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
