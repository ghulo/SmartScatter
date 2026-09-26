--[[
	Smart Scatter — Kit: UI kit: layout helpers, labels, links, sliders, switches, segmented controls, sections.
	Part of Main; loaded in order by the bundle. Shared state and cross-module functions live on App.
]]

return function(App)
	local RunService, FAST, tween, G, saveG, P, SANS = App.RunService, App.FAST, App.tween, App.G, App.saveG, App.P, App.SANS
	local SANS_M, SANS_B = App.SANS_M, App.SANS_B
	local TweenService = game:GetService("TweenService")

	--------------------------------------------------------------------------------
	-- UI kit
	--------------------------------------------------------------------------------
	local seqN = 0
	local function seq()
		seqN += 1
		return seqN
	end

	local function new(cls, props, kids)
		local o = Instance.new(cls)
		if o:IsA("GuiObject") then
			o.LayoutOrder = seq()
			o.BorderSizePixel = 0
		end
		local parent
		for k, v in props or {} do
			if k == "Parent" then
				parent = v
			else
				o[k] = v
			end
		end
		for _, c in kids or {} do
			c.Parent = o
		end
		if parent then
			o.Parent = parent
		end
		return o
	end
	local function corner(r)
		return new("UICorner", { CornerRadius = UDim.new(0, r or 6) })
	end
	local function stroke(c)
		return new("UIStroke", { Color = c, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
	end
	local function pad(l, r, t, b)
		return new("UIPadding", {
			PaddingLeft = UDim.new(0, l),
			PaddingRight = UDim.new(0, r or l),
			PaddingTop = UDim.new(0, t or l),
			PaddingBottom = UDim.new(0, b or t or l),
		})
	end
	local function vlist(gap)
		return new("UIListLayout", { Padding = UDim.new(0, gap or 0), SortOrder = Enum.SortOrder.LayoutOrder })
	end
	local function hlist(gap)
		return new("UIListLayout", {
			Padding = UDim.new(0, gap or 0),
			SortOrder = Enum.SortOrder.LayoutOrder,
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
		})
	end
	local function box(props, kids)
		props.BackgroundTransparency = props.BackgroundTransparency or 1
		return new("Frame", props, kids)
	end
	local function col(props, kids) -- auto-height column
		props.Size = props.Size or UDim2.new(1, 0, 0, 0)
		props.AutomaticSize = Enum.AutomaticSize.Y
		return box(props, kids)
	end
	local function label(t, size, color, font, props)
		local o = new("TextLabel", {
			BackgroundTransparency = 1,
			Text = t,
			TextSize = size or 13,
			TextColor3 = color or P.text,
			Font = font or SANS,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Center,
			Size = UDim2.new(1, 0, 0, (size or 13) + 8),
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		for k, v in props or {} do
			o[k] = v
		end
		return o
	end
	local function para(t, props)
		local o = label(t, 12, P.faint, SANS, props)
		o.TextWrapped = true
		o.TextTruncate = Enum.TextTruncate.None
		o.AutomaticSize = Enum.AutomaticSize.Y
		o.Size = UDim2.new(1, 0, 0, 0)
		o.LineHeight = 1.2
		return o
	end
	--------------------------------------------------------------------------------
	-- Surface effects from the design: a fine halftone grain, a soft sheen from the top, lines that fade out at
	-- both ends, and a light-to-dark shade on raised things. The grain is a tiny dot texture drawn in code
	-- (EditableImage) and tiled, so nothing has to be uploaded; where that's unavailable the panel is just plain.
	--------------------------------------------------------------------------------
	local grain -- Content of a 4×4 tile with one white dot (false: not available here)
	local function grainContent()
		if grain == nil then
			local ok, c = pcall(function()
				local img = game:GetService("AssetService"):CreateEditableImage({ Size = Vector2.new(4, 4) })
				local buf = buffer.create(4 * 4 * 4) -- RGBA, all clear
				local i = (1 * 4 + 1) * 4 -- the dot at (1, 1)
				buffer.writeu8(buf, i, 255)
				buffer.writeu8(buf, i + 1, 255)
				buffer.writeu8(buf, i + 2, 255)
				buffer.writeu8(buf, i + 3, 255)
				img:WritePixelsBuffer(Vector2.zero, Vector2.new(4, 4), buf)
				return Content.fromObject(img)
			end)
			grain = ok and c or false
		end
		return grain or nil
	end
	-- halftone dots over `parent` (strength 0–1; they never take clicks)
	local function halftone(parent, strength, spacing, z)
		local c = grainContent()
		if not c then
			return nil
		end
		local l = new("ImageLabel", {
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ScaleType = Enum.ScaleType.Tile,
			TileSize = UDim2.fromOffset(spacing or 4, spacing or 4),
			ResampleMode = Enum.ResamplerMode.Pixelated,
			ImageTransparency = 1 - (strength or 0.04),
			ImageColor3 = settings().Studio.Theme.Name == "Light" and Color3.new(0, 0, 0) or Color3.new(1, 1, 1),
			Active = false,
			ZIndex = z or 1,
			Parent = parent,
		})
		if not pcall(function()
			l.ImageContent = c
		end) then
			l:Destroy()
			return nil
		end
		return l
	end
	-- a soft light from the top of `parent`, fading out over `height` px
	local function sheen(parent, strength, height, z)
		local f = new("Frame", {
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0,
			Size = UDim2.new(1, 0, 0, height or 120),
			Active = false,
			ZIndex = z or 1,
			Parent = parent,
		})
		new("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new(1 - (strength or 0.04), 1),
			Parent = f,
		})
		return f
	end
	-- a 1 px line that fades in and out at the ends (edge "left": strong on the left, fading right)
	local function fadeLine(parent, edge, strength)
		local f = new("Frame", {
			BackgroundColor3 = P.text,
			BackgroundTransparency = 0,
			Size = UDim2.new(1, 0, 0, 1),
			Parent = parent,
		})
		local a = 1 - (strength or 0.16)
		new("UIGradient", {
			Transparency = edge == "left" and NumberSequence.new({
				NumberSequenceKeypoint.new(0, a),
				NumberSequenceKeypoint.new(0.7, 1),
				NumberSequenceKeypoint.new(1, 1),
			}) or NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.4, a),
				NumberSequenceKeypoint.new(0.6, a),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Parent = f,
		})
		return f
	end
	-- a light-to-dark shade on a filled thing (multiplies its colour, so hover colours keep working)
	local function shade(obj, amount)
		local d = 1 - (amount or 0.08)
		return new("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(d, d, d)),
			Parent = obj,
		})
	end
	-- a faint highlight along the inside of the top edge (the "inset" light on cards and buttons)
	local function topLight(obj, strength, inset)
		local f = fadeLine(obj, nil, strength or 0.07)
		f.Position = UDim2.fromOffset(inset or 10, 0)
		f.Size = UDim2.new(1, -(inset or 10) * 2, 0, 1)
		f.ZIndex = obj.ZIndex + 1
		return f
	end

	--------------------------------------------------------------------------------
	-- Light and motion: neon glow, depth, press-in and a moving sheen. Every control uses these, so the whole
	-- panel lights and moves the same way. Plugin UI can't blur, so glass is layers: a shade, a top light, a glow.
	--------------------------------------------------------------------------------
	-- a ring just outside obj's edge (a child frame, so it moves and hides with obj; it never takes clicks).
	-- obj's own padding is undone, so the ring hugs its real edge.
	local function ring(obj, radius, out, thickness, color, dy)
		local p = obj:FindFirstChildOfClass("UIPadding")
		local l, r = p and p.PaddingLeft.Offset or 0, p and p.PaddingRight.Offset or 0
		local t, bt = p and p.PaddingTop.Offset or 0, p and p.PaddingBottom.Offset or 0
		local f = new("Frame", {
			BackgroundTransparency = 1,
			Position = UDim2.fromOffset(-out - l, -out - t + (dy or 0)),
			Size = UDim2.new(1, out * 2 + l + r, 1, out * 2 + t + bt),
			Active = false,
			ZIndex = obj.ZIndex,
			Parent = obj,
		}, { corner(radius + out) })
		local st = stroke(color)
		st.Thickness = thickness
		st.Transparency = 1
		st.Parent = f
		return st
	end
	-- a soft neon glow round obj (the accent, or color): two rings, bright close in, faint further out. Returns a
	-- controller: :set(on, instant) lights it or puts it out; :pulse(on) breathes while something runs.
	local GLOW = { { 1, 2, 0.45 }, { 4, 5, 0.86 } } -- { out, thickness, transparency when fully lit }
	local function glow(obj, radius, strength, color)
		strength = strength or 1
		local rings, lit, pulses = {}, false, {}
		for i, g in GLOW do
			rings[i] = { st = ring(obj, radius or 8, g[1], g[2], color or P.accent), rest = 1 - (1 - g[3]) * strength }
		end
		local c = {}
		function c:set(on, instant)
			lit = on
			for _, r in rings do
				local t = on and r.rest or 1
				if instant then
					r.st.Transparency = t
				else
					tween(r.st, FAST, { Transparency = t })
				end
			end
		end
		function c:pulse(on)
			for _, p in pulses do
				p:Cancel()
			end
			table.clear(pulses)
			if not on then
				self:set(lit, false)
				return
			end
			for _, r in rings do
				r.st.Transparency = r.rest
				local p = TweenService:Create(
					r.st,
					TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
					{ Transparency = (r.rest + 1) / 2 }
				)
				p:Play()
				table.insert(pulses, p)
			end
		end
		return c
	end
	-- depth: a soft dark ring offset downward, so a card sits a little above what's behind it
	local function shadow(obj, radius)
		local st = ring(obj, radius or 12, 1, 3, Color3.new(0, 0, 0), 2)
		st.Transparency = settings().Studio.Theme.Name == "Light" and 0.93 or 0.75
		return st
	end
	-- press-in: the control shrinks a touch while held
	local function pressable(b, amount)
		local sc = new("UIScale", { Parent = b })
		b.MouseButton1Down:Connect(function()
			tween(sc, FAST, { Scale = amount or 0.97 })
		end)
		for _, ev in { b.MouseButton1Up, b.MouseLeave } do
			ev:Connect(function()
				tween(sc, App.MED, { Scale = 1 })
			end)
		end
		return sc
	end
	-- a band of light sweeping across obj, over and over, while :play(true)
	local function sweep(obj, strength)
		local f = new("Frame", {
			BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 0,
			Size = UDim2.fromScale(1, 1),
			Visible = false,
			Active = false,
			ZIndex = obj.ZIndex + 1,
			Parent = obj,
		}, { corner(8) })
		local a = 1 - (strength or 0.35)
		local g = new("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.4, 1),
				NumberSequenceKeypoint.new(0.5, a),
				NumberSequenceKeypoint.new(0.6, 1),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Offset = Vector2.new(-1, 0),
			Parent = f,
		})
		local run
		local c = {}
		function c:play(on)
			if run then
				run:Cancel()
				run = nil
			end
			f.Visible = on
			if on then
				g.Offset = Vector2.new(-1, 0)
				run = TweenService:Create(g, TweenInfo.new(1.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1), {
					Offset = Vector2.new(1, 0),
				})
				run:Play()
			end
		end
		return c
	end

	local function hoverable(b, rest, over)
		b.MouseEnter:Connect(function()
			if b:GetAttribute("active") ~= true then
				tween(b, FAST, { BackgroundColor3 = over, BackgroundTransparency = 0 })
			end
		end)
		b.MouseLeave:Connect(function()
			if b:GetAttribute("active") ~= true then
				tween(b, FAST, { BackgroundColor3 = rest, BackgroundTransparency = rest == P.bg and 1 or 0 })
			end
		end)
	end

	-- a button for actions (Shuffle, Save, Remove…): a raised block with a faint border.
	-- kind: nil (raised), "accent" (the main next step: filled, dark text), "ghost" (just a border, dim text)
	-- or "danger" (removes something: no fill, warm red text)
	local function button(t, kind, onClick, props)
		local filled = kind == "accent"
		local flat = kind == "danger" or kind == "ghost"
		local rest = filled and P.accent or P.raised
		local b = new("TextButton", {
			Text = t,
			Font = filled and SANS_B or SANS_B,
			TextSize = 13,
			TextColor3 = filled and P.onAccent or (kind == "danger" and P.danger or kind == "ghost" and P.dim or P.text),
			BackgroundColor3 = rest,
			BackgroundTransparency = flat and 1 or 0,
			AutoButtonColor = false,
			Size = UDim2.fromOffset(0, 30),
			AutomaticSize = Enum.AutomaticSize.X,
		}, { corner(8), pad(kind == "danger" and 4 or 13, kind == "danger" and 4 or 13, 0, 0) })
		if kind ~= "danger" and not filled then
			stroke(P.line).Parent = b
		end
		if not flat then
			shade(b, filled and 0.1 or 0.06)
			topLight(b, filled and 0.3 or 0.06, 6)
		end
		if filled then
			glow(b, 8, 0.55):set(true, true)
		end
		pressable(b)
		b.MouseEnter:Connect(function()
			if filled then
				b.BackgroundColor3 = P.accent:Lerp(Color3.new(1, 1, 1), 0.1)
			elseif kind == "danger" then
				b.TextColor3 = P.danger:Lerp(Color3.new(1, 1, 1), 0.2)
			else
				b.BackgroundTransparency = 0
				b.BackgroundColor3 = P.hover
			end
		end)
		b.MouseLeave:Connect(function()
			b.BackgroundColor3 = rest
			b.BackgroundTransparency = flat and 1 or 0
			if kind == "danger" then
				b.TextColor3 = P.danger
			end
		end)
		if onClick then
			b.MouseButton1Click:Connect(onClick)
		end
		for k, v in props or {} do
			b[k] = v
		end
		return b
	end
	-- a row of buttons that wraps onto the next line when the panel is narrow
	local function buttonRow(parent, gap)
		local row = new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Parent = parent,
		}, {
			new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				Wraps = true,
				Padding = UDim.new(0, gap or 8),
				SortOrder = Enum.SortOrder.LayoutOrder,
				VerticalAlignment = Enum.VerticalAlignment.Center,
			}),
		})
		return row
	end

	-- tooltips: a small card next to the hovered control, after a short delay (like Studio's own)
	local tip, tipText, tipToken = nil, nil, 0
	local function hideTip()
		tipToken += 1
		if tip then
			tip.Visible = false
		end
	end
	local function showTip(obj, text)
		tipToken += 1
		local my = tipToken
		task.delay(0.4, function()
			local root = App.root
			if my ~= tipToken or not root or not obj:IsDescendantOf(root) or App.tour then -- no tips under the tour
				return
			end
			if not tip or not tip:IsDescendantOf(root) then
				tip = new("Frame", {
					BackgroundColor3 = P.tip,
					AutomaticSize = Enum.AutomaticSize.Y,
					ZIndex = 200,
					Visible = false,
					Parent = root,
				}, { corner(6), stroke(P.line), pad(10, 10, 7, 8) })
				tipText = new("TextLabel", {
					BackgroundTransparency = 1,
					Font = SANS,
					TextSize = 12,
					TextColor3 = P.text,
					TextWrapped = true,
					TextXAlignment = Enum.TextXAlignment.Left,
					LineHeight = 1.15,
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					ZIndex = 201,
					Parent = tip,
				})
			end
			local rw, rh = root.AbsoluteSize.X, root.AbsoluteSize.Y
			local w = math.min(rw - 24, 270)
			tipText.Text = text
			tip.Size = UDim2.fromOffset(w, 0)
			local ox, oy = obj.AbsolutePosition.X - root.AbsolutePosition.X, obj.AbsolutePosition.Y - root.AbsolutePosition.Y
			local x = math.clamp(ox, 12, math.max(rw - w - 12, 12))
			tip.Position = UDim2.fromOffset(x, oy + obj.AbsoluteSize.Y + 6)
			tip.Visible = true
			task.defer(function() -- flip above the control if it would run off the bottom
				if my == tipToken and tip.Parent and oy + obj.AbsoluteSize.Y + 6 + tip.AbsoluteSize.Y > rh - 8 then
					tip.Position = UDim2.fromOffset(x, math.max(oy - tip.AbsoluteSize.Y - 6, 8))
				end
			end)
		end)
	end
	local function hintOn(obj, hint)
		if not hint then
			return
		end
		obj.MouseEnter:Connect(function()
			showTip(obj, hint)
		end)
		obj.MouseLeave:Connect(hideTip)
		obj.AncestryChanged:Connect(hideTip)
	end

	-- An explanation belongs in the tooltip of the control it explains, not as a paragraph under it: attaches `text`
	-- to the last control added to `parent` (a hint it already has is kept first).
	local function explain(parent, text)
		local last
		for _, c in parent:GetChildren() do
			if c:IsA("GuiObject") and c.Visible and (not last or c.LayoutOrder > last.LayoutOrder) then
				last = c
			end
		end
		if last then
			local prev = last:GetAttribute("hint")
			last:SetAttribute("hint", prev and (prev .. "\n\n" .. text) or text)
			if not prev then
				last.MouseEnter:Connect(function()
					showTip(last, last:GetAttribute("hint"))
				end)
				last.MouseLeave:Connect(hideTip)
				last.AncestryChanged:Connect(hideTip)
			end
		end
	end

	-- live sliders, so outside changes (e.g. [ ] keys) can refresh them. The refresh closures hold their frame, so a
	-- weak table alone would never let go: entries whose frame left the panel are dropped here.
	local sliderViews = {}
	local function refreshSliders()
		for f, show in sliderViews do
			if f.Parent then
				show()
			else
				sliderViews[f] = nil
			end
		end
	end
	-- a setting with a value: its name and value on one line, the track full width under them
	local function slider(text, min, max, get, set, fmt, step, onLive, onCommit, hint, def)
		local f = box({ Size = UDim2.new(1, 0, 0, 50) })
		hintOn(f, hint and (def ~= nil and (hint .. "\nRight-click to reset.") or hint))
		local name = label(text, 13, P.text, SANS, { Size = UDim2.new(1, -78, 0, 26), Parent = f })
		local value = new("TextBox", {
			BackgroundTransparency = 0,
			BackgroundColor3 = P.raised,
			Text = "",
			Font = SANS_B,
			TextSize = 12,
			TextColor3 = P.dim,
			TextXAlignment = Enum.TextXAlignment.Center,
			ClearTextOnFocus = false,
			Size = UDim2.new(0, 70, 0, 22),
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 0, 2),
			Parent = f,
		}, { corner(6), pad(4, 4, 0, 0) })
		local valueStroke = stroke(P.raised)
		valueStroke.Parent = value
		local track = box({
			BackgroundTransparency = 0,
			BackgroundColor3 = P.track,
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 7, 0, 38),
			Size = UDim2.new(1, -14, 0, 4),
			Parent = f,
		}, { corner(2) })
		local fill = box({ BackgroundTransparency = 0, BackgroundColor3 = P.accent, Size = UDim2.fromScale(0, 1), Parent = track }, { corner(2) })
		local knob = box({
			BackgroundTransparency = 0,
			BackgroundColor3 = P.knob,
			Size = UDim2.fromOffset(14, 14),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0, 0.5),
			ZIndex = 3,
			Parent = track,
		}, { corner(7) })
		local knobStroke = stroke(P.track)
		knobStroke.Transparency = 1
		knobStroke.Parent = knob
		local hit = new("TextButton", {
			Text = "",
			BackgroundTransparency = 1,
			Position = UDim2.new(0, 0, 0, 26),
			Size = UDim2.new(1, 0, 0, 24),
			ZIndex = 4,
			Parent = f,
		})

		local pct = string.find(fmt, "%%%%") ~= nil -- "%" formats show 0–1 values as 0–100%
		local function show(v, animate)
			local a = math.clamp((v - min) / (max - min), 0, 1)
			if animate then
				tween(fill, FAST, { Size = UDim2.fromScale(a, 1) })
				tween(knob, FAST, { Position = UDim2.fromScale(a, 0.5) })
			else
				fill.Size = UDim2.fromScale(a, 1)
				knob.Position = UDim2.fromScale(a, 0.5)
			end
			value.Text = string.format(fmt, pct and v * 100 or v)
		end
		local function apply(v, animate)
			v = math.clamp(tonumber(v) or get(), min, max)
			if step then
				v = math.floor(v / step + 0.5) * step
			end
			if v ~= get() then
				set(v)
				show(v, animate)
				if onLive then
					onLive()
				end
			end
		end
		local function fromX(px)
			apply(min + (max - min) * math.clamp((px - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1))
		end
		local hovering, dragging = false, false
		local function look()
			local hot = hovering or dragging
			knobStroke.Transparency = hot and 0 or 1
			knobStroke.Color = P.accent
			knob.Size = UDim2.fromOffset(hot and 16 or 14, hot and 16 or 14)
			name.TextColor3 = P.text
		end
		f.MouseEnter:Connect(function()
			hovering = true
			look()
		end)
		f.MouseLeave:Connect(function()
			hovering = false
			look()
		end)
		local function stop()
			if not dragging then
				return
			end
			dragging = false
			look()
			if onCommit then
				onCommit()
			end
		end
		hit.InputBegan:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
				return
			end
			dragging = true
			look()
			fromX(input.Position.X)
			local conn
			conn = RunService.Heartbeat:Connect(function()
				if not dragging then
					conn:Disconnect()
					return
				end
				fromX(App.widget:GetRelativeMousePosition().X)
			end)
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					stop()
				end
			end)
		end)
		hit.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				stop()
			end
		end)
		if def ~= nil then
			hit.MouseButton2Click:Connect(function()
				if get() == def then
					return
				end
				set(def)
				show(def, true)
				if onLive then
					onLive()
				end
				if onCommit then
					onCommit()
				end
			end)
		end
		value.Focused:Connect(function()
			valueStroke.Color = P.accent
		end)
		value.FocusLost:Connect(function()
			valueStroke.Color = P.raised
			local n = tonumber(string.match(value.Text, "%-?[%d%.]+"))
			if n and pct then
				n /= 100
			end
			apply(n, true)
			show(get(), true)
			if onCommit then
				onCommit()
			end
		end)
		show(get())
		sliderViews[f] = function()
			if f.Parent then
				show(get(), true)
			end
		end
		return f
	end

	local function switch(get, set, onChange)
		local b = new(
			"TextButton",
			{ Text = "", Size = UDim2.fromOffset(38, 22), BackgroundColor3 = P.track, AutoButtonColor = false },
			{ corner(11) }
		)
		local dot = box({ BackgroundTransparency = 0, BackgroundColor3 = P.knob, Size = UDim2.fromOffset(18, 18), Parent = b }, { corner(9) })
		local lit = glow(b, 11, 0.7)
		local function refresh(animate)
			local on = get()
			lit:set(on, not animate)
			local props = { Position = on and UDim2.fromOffset(18, 2) or UDim2.fromOffset(2, 2) }
			if animate then
				tween(dot, FAST, props)
				tween(b, FAST, { BackgroundColor3 = on and P.accent or P.track })
			else
				dot.Position = props.Position
				b.BackgroundColor3 = on and P.accent or P.track
			end
		end
		b.MouseButton1Click:Connect(function()
			set(not get())
			refresh(true)
			if onChange then
				onChange()
			end
		end)
		refresh(false)
		return b, lit
	end

	local function switchRow(text, get, set, onChange, hint)
		local f = box({ Size = UDim2.new(1, 0, 0, 38) })
		hintOn(f, hint)
		label(text, 13, P.text, SANS, { Size = UDim2.new(1, -48, 1, 0), Parent = f })
		local s = switch(get, set, onChange)
		s.Position = UDim2.new(1, -38, 0.5, -11)
		s.Parent = f
		return f
	end

	-- small icons drawn from frames (no uploaded images), in a unit square scaled to `size`
	local function icon(name, size, color)
		local f = box({ Size = UDim2.fromOffset(size, size) })
		local th = math.max(1.2, size / 10)
		local function ring(cx, cy, r, filled)
			local o = box({
				BackgroundTransparency = filled and 0 or 1,
				BackgroundColor3 = color,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(cx * size, cy * size),
				Size = UDim2.fromOffset(r * 2 * size, r * 2 * size),
				Parent = f,
			}, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
			if not filled then
				local st = stroke(color)
				st.Thickness = th
				st.Parent = o
			end
			return o
		end
		local function rect(cx, cy, w, h, filled, rad)
			local o = box({
				BackgroundTransparency = filled and 0 or 1,
				BackgroundColor3 = color,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(cx * size, cy * size),
				Size = UDim2.fromOffset(w * size, h * size),
				Parent = f,
			}, { corner(rad or 1) })
			if not filled then
				local st = stroke(color)
				st.Thickness = th
				st.Parent = o
			end
			return o
		end
		local function bar(x1, y1, x2, y2)
			local dx, dy = (x2 - x1) * size, (y2 - y1) * size
			box({
				BackgroundTransparency = 0,
				BackgroundColor3 = color,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset((x1 + x2) / 2 * size, (y1 + y2) / 2 * size),
				Size = UDim2.fromOffset(math.sqrt(dx * dx + dy * dy) + th * 0.6, th),
				Rotation = math.deg(math.atan2(dy, dx)),
				Parent = f,
			}, { corner(1) })
		end
		if name == "brush" then
			ring(0.5, 0.5, 0.36)
			ring(0.5, 0.5, 0.09, true)
		elseif name == "erase" then
			ring(0.5, 0.5, 0.36)
			bar(0.24, 0.76, 0.76, 0.24)
		elseif name == "lasso" then
			ring(0.52, 0.4, 0.32)
			bar(0.36, 0.7, 0.24, 0.94)
		elseif name == "box" then
			rect(0.5, 0.5, 0.7, 0.7, false, 2)
		elseif name == "polygon" then
			bar(0.5, 0.14, 0.88, 0.82)
			bar(0.88, 0.82, 0.12, 0.82)
			bar(0.12, 0.82, 0.5, 0.14)
		elseif name == "fill" then
			rect(0.44, 0.5, 0.5, 0.5, false, 2).Rotation = 45
			ring(0.86, 0.8, 0.09, true)
		elseif name == "spline" then
			bar(0.14, 0.78, 0.5, 0.3)
			bar(0.5, 0.3, 0.86, 0.64)
			ring(0.14, 0.78, 0.1, true)
			ring(0.5, 0.3, 0.1, true)
			ring(0.86, 0.64, 0.1, true)
		elseif name == "area" then
			rect(0.5, 0.5, 0.78, 0.78, false, 3)
			ring(0.36, 0.38, 0.08, true)
			ring(0.64, 0.56, 0.08, true)
			ring(0.4, 0.68, 0.07, true)
		elseif name == "clear" then -- a keep-clear zone: a crossed-out patch
			rect(0.5, 0.5, 0.78, 0.78, false, 3)
			bar(0.26, 0.74, 0.74, 0.26)
		elseif name == "layers" then
			rect(0.5, 0.26, 0.8, 0.14, true, 2)
			rect(0.5, 0.5, 0.8, 0.14, true, 2)
			rect(0.5, 0.74, 0.8, 0.14, true, 2)
		elseif name == "settings" then
			bar(0.12, 0.3, 0.88, 0.3)
			bar(0.12, 0.7, 0.88, 0.7)
			ring(0.34, 0.3, 0.11, true)
			ring(0.66, 0.7, 0.11, true)
		elseif name == "plus" then
			bar(0.5, 0.16, 0.5, 0.84)
			bar(0.16, 0.5, 0.84, 0.5)
		elseif name == "close" then
			bar(0.22, 0.22, 0.78, 0.78)
			bar(0.22, 0.78, 0.78, 0.22)
		elseif name == "info" then
			ring(0.5, 0.5, 0.38)
			bar(0.5, 0.46, 0.5, 0.7)
			ring(0.5, 0.31, 0.05, true)
		elseif name == "right" then
			bar(0.38, 0.2, 0.66, 0.5)
			bar(0.66, 0.5, 0.38, 0.8)
		elseif name == "left" then
			bar(0.62, 0.2, 0.34, 0.5)
			bar(0.34, 0.5, 0.62, 0.8)
		elseif name == "down" then
			bar(0.2, 0.38, 0.5, 0.66)
			bar(0.5, 0.66, 0.8, 0.38)
		elseif name == "trash" then
			bar(0.16, 0.28, 0.84, 0.28)
			bar(0.38, 0.14, 0.62, 0.14)
			rect(0.5, 0.6, 0.52, 0.56, false, 2)
		elseif name == "logo" then
			ring(0.5, 0.2, 0.08, true)
			ring(0.24, 0.72, 0.08, true)
			ring(0.76, 0.72, 0.08, true)
			bar(0.5, 0.3, 0.5, 0.42)
			bar(0.36, 0.62, 0.44, 0.48)
			bar(0.64, 0.62, 0.56, 0.48)
		elseif name == "refresh" then
			ring(0.5, 0.52, 0.32)
			bar(0.62, 0.14, 0.84, 0.2)
			bar(0.84, 0.2, 0.8, 0.42)
		end
		return f
	end
	local function setIconColor(ic, color)
		for _, d in ic:GetDescendants() do
			if d:IsA("UIStroke") then
				d.Color = color
			elseif d:IsA("Frame") and d.BackgroundTransparency < 1 then
				d.BackgroundColor3 = color
			end
		end
	end

	-- names shown for stored option values that read differently in the UI
	local SHOWN = { Spline = "Path" }

	-- segmented control with a sliding selection pill; icons (optional) = { [option] = icon name }:
	-- icon beside the label, or above it when the control is 38+ px tall
	local function segmented(options, get, set, onChange, height, toggleable, icons, hints)
		local n = #options
		height = math.max(height or 30, 30)
		local f = new("Frame", { BackgroundColor3 = P.field, Size = UDim2.new(1, 0, 0, height) }, { corner(9), stroke(P.line) })
		local inner = box({ Position = UDim2.fromOffset(2, 2), Size = UDim2.new(1, -4, 1, -4), Parent = f })
		local pill = box({
			BackgroundTransparency = 1,
			BackgroundColor3 = P.accentSoft,
			Size = UDim2.new(1 / n, 0, 1, 0),
			Position = UDim2.new(0, 0, 0, 0),
			Parent = inner,
		}, { corner(7) })
		local pillStroke = stroke(P.accentLine)
		pillStroke.Transparency = 1
		pillStroke.Parent = pill
		local pillGlow = glow(pill, 7, 0.45)
		local row = box({ Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = inner }, { hlist(0) })
		local btns = {}
		local shown, init = false, false
		local function refresh()
			local cur = get()
			local idx = table.find(options, cur)
			if idx then
				local target = UDim2.new((idx - 1) / n, 0, 0, 0)
				if shown then
					tween(pill, FAST, { Position = target })
				else
					pill.Position = target
				end
				if init then
					tween(pill, FAST, { BackgroundTransparency = 0 })
					tween(pillStroke, FAST, { Transparency = 0 })
				else
					pill.BackgroundTransparency, pillStroke.Transparency = 0, 0
				end
			elseif init then
				tween(pill, FAST, { BackgroundTransparency = 1 })
				tween(pillStroke, FAST, { Transparency = 1 })
			end
			pillGlow:set(idx ~= nil, not init)
			shown, init = idx ~= nil, true
			for o, b in btns do
				local on = cur == o
				local lbl = b:FindFirstChild("Label", true) or b
				lbl.Font = on and SANS_M or SANS
				lbl.TextColor3 = on and P.accent or P.dim
				local ic = b:FindFirstChild("Icon", true)
				if ic then
					setIconColor(ic, on and P.accent or P.dim)
				end
			end
		end
		pillStroke.Color = P.accentLine
		for _, o in options do
			local b = new("TextButton", {
				Text = SHOWN[o] or o,
				Font = SANS_M,
				TextSize = 13,
				TextColor3 = P.dim,
				AutoButtonColor = false,
				BackgroundTransparency = 1,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Size = UDim2.new(1 / n, 0, 1, 0),
				ZIndex = 2,
				Parent = row,
			})
			if icons and icons[o] then
				b.Text = ""
				local tall = height >= 44
				local content = box({ Size = UDim2.fromScale(1, 1), ZIndex = 2, Parent = b }, {
					new("UIListLayout", {
						FillDirection = tall and Enum.FillDirection.Vertical or Enum.FillDirection.Horizontal,
						HorizontalAlignment = Enum.HorizontalAlignment.Center,
						VerticalAlignment = Enum.VerticalAlignment.Center,
						Padding = UDim.new(0, tall and 3 or 5),
						SortOrder = Enum.SortOrder.LayoutOrder,
					}),
				})
				local ic = icon(icons[o], tall and 16 or 13, P.dim)
				ic.Name = "Icon"
				ic.Parent = content
				label(SHOWN[o] or o, 12, P.dim, SANS_M, {
					Name = "Label",
					Size = UDim2.fromOffset(0, tall and 13 or 16),
					AutomaticSize = Enum.AutomaticSize.X,
					TextXAlignment = Enum.TextXAlignment.Center,
					ZIndex = 2,
					Parent = content,
				})
			end
			local function labelOf()
				local c = b:FindFirstChild("Label", true)
				return c or b
			end
			b.MouseEnter:Connect(function()
				if get() ~= o then
					labelOf().TextColor3 = P.text
				end
			end)
			b.MouseLeave:Connect(function()
				if get() ~= o then
					labelOf().TextColor3 = P.dim
				end
			end)
			b.MouseButton1Click:Connect(function()
				if get() == o and not toggleable then
					return
				end
				set(o)
				refresh()
				if onChange then
					onChange()
				end
			end)
			if hints and hints[o] then
				hintOn(b, hints[o])
			end
			btns[o] = b
		end
		refresh()
		return f, refresh
	end

	-- a row that opens something: a bordered block with a title, a line under it and a chevron (like a settings
	-- list). Used for groups that fold open and for "Add objects".
	local function rowHead(parent, iconName, title, sub, height)
		local b = new("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = P.card,
			Size = UDim2.new(1, 0, 0, height or (sub and 52 or 40)),
			Parent = parent,
		}, { corner(10), stroke(P.line) })
		shade(b, 0.05)
		topLight(b, 0.05)
		local x = 12
		local ic
		if iconName then
			local tile = box({
				BackgroundTransparency = 0,
				BackgroundColor3 = P.raised,
				Size = UDim2.fromOffset(32, 32),
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 10, 0.5, 0),
				Parent = b,
			}, { corner(8) })
			ic = icon(iconName, 15, P.dim)
			ic.AnchorPoint = Vector2.new(0.5, 0.5)
			ic.Position = UDim2.fromScale(0.5, 0.5)
			ic.Parent = tile
			x = 54
		end
		local t = label(title, 13, P.text, SANS_B, {
			Position = UDim2.new(0, x, 0.5, sub and -17 or -10),
			Size = UDim2.new(1, -x - 32, 0, 20),
			Parent = b,
		})
		local subLabel = sub
			and label(sub, 12, P.dim, SANS, {
				Position = UDim2.new(0, x, 0.5, 1),
				Size = UDim2.new(1, -x - 32, 0, 16),
				Parent = b,
			})
		local chev = icon("right", 13, P.faint)
		chev.AnchorPoint = Vector2.new(1, 0.5)
		chev.Position = UDim2.new(1, -12, 0.5, 0)
		chev.Parent = b
		b.MouseEnter:Connect(function()
			if b:GetAttribute("disabled") ~= true then
				b.BackgroundColor3 = P.card:Lerp(P.hover, 0.45)
			end
		end)
		b.MouseLeave:Connect(function()
			b.BackgroundColor3 = P.card
		end)
		return b, t, subLabel, chev, ic
	end

	-- a row that goes somewhere (another page); disabled rows show but don't react
	local function navRow(parent, iconName, title, sub, onClick, disabled)
		local b, t, subLabel, chev, ic = rowHead(parent, iconName, title, sub, sub and 58 or 44)
		b:SetAttribute("disabled", disabled == true)
		shadow(b, 10)
		if not disabled then
			pressable(b, 0.985)
		end
		if disabled then
			t.TextColor3 = P.faint
			if subLabel then
				subLabel.TextColor3 = P.faint
			end
			if ic then
				setIconColor(ic, P.faint)
			end
			setIconColor(chev, P.line)
		end
		b.MouseButton1Click:Connect(function()
			if not disabled and onClick then
				onClick()
			end
		end)
		return b, subLabel
	end

	-- one line under a group's title, so what's inside can be seen without opening it
	local SECTION_SUB = {
		scanfix = "Tell it what's a road, building or water",
		line = "What it follows and which way it faces",
		variants = "Mix several models in one object",
		layerpaint = "Brush more or less of it by hand",
		size = "Random sizes, smallest to largest",
		spread = "Spacing, clumping and a limit",
		groups = "Small piles, like rocks or crates",
		surfaces = "Grass, sand, rock… and a height band",
		avoid = "Distance from buildings, roads, water",
		attract = "Grow close to walls, water or roads",
		terrain = "Steepest ground and leaning",
		look = "Rotation, tilt, colour and sinking",
		presets = "Save this set of objects, reuse it anywhere",
		output = "Collision, shadows, streaming",
	}

	-- a group that folds open under its row. Remembers its open state.
	local function section(parent, id, title, defaultOpen, build)
		local open = G.groups[id]
		if open == nil then
			open = defaultOpen
		end
		local wrap = col({ Parent = parent }, { vlist(0) })
		local head, _, _, chev = rowHead(wrap, nil, title, SECTION_SUB[id])
		local body = col({ Parent = wrap }, { vlist(4), pad(2, 2, 10, 6) })
		local function look()
			body.Visible = open
			chev.Rotation = open and 90 or 0
		end
		look()
		build(body)
		head.MouseButton1Click:Connect(function()
			open = not open
			G.groups[id] = open
			saveG()
			look()
		end)
		return wrap
	end

	-- the title of a flat step: a small number in a ring (filled once the step is done) and an uppercase name.
	-- n nil: just the name.
	local function stepLabel(parent, n, text, done)
		local row = box({ Size = UDim2.new(1, 0, 0, 22), Parent = parent }, { hlist(8) })
		if n then
			local dot = label(tostring(n), 10, done and P.onAccent or P.faint, SANS_B, {
				Size = UDim2.fromOffset(16, 16),
				TextXAlignment = Enum.TextXAlignment.Center,
				BackgroundTransparency = done and 0 or 1,
				BackgroundColor3 = P.accent,
				Parent = row,
			})
			corner(8).Parent = dot
			local st = stroke(done and P.accent or P.faint)
			st.Thickness = 1.5
			st.Parent = dot
		end
		label(string.upper(text), 11, P.faint, SANS_B, { Size = UDim2.fromOffset(0, 22), AutomaticSize = Enum.AutomaticSize.X, Parent = row })
		return row
	end

	-- a soft accent note: what to do before a step can be used
	local function hintBox(parent, text)
		local f = col({
			BackgroundTransparency = 0,
			BackgroundColor3 = P.accent:Lerp(P.bg, 0.9),
			Parent = parent,
		}, { corner(10), stroke(P.accent:Lerp(P.bg, 0.72)), pad(12, 12, 10, 10) })
		local ic = icon("info", 15, P.accent)
		ic.Position = UDim2.fromOffset(0, 1)
		ic.Parent = f
		local t = para(text, { Position = UDim2.fromOffset(24, 0), Size = UDim2.new(1, -24, 0, 0), Parent = f })
		t.TextColor3 = P.dim
		return f, t
	end

	-- keyboard hints: { { "Shift", "height" }, ... } as small raised chips
	local function keyChips(parent, list)
		local row = buttonRow(parent, 6)
		for _, k in list do
			local chip = new("Frame", {
				BackgroundColor3 = P.raised,
				Size = UDim2.fromOffset(0, 24),
				AutomaticSize = Enum.AutomaticSize.X,
				Parent = row,
			}, { corner(6), pad(5, 8, 0, 0), hlist(5) })
			local key = label(k[1], 10, P.text, SANS_B, {
				Size = UDim2.fromOffset(0, 16),
				AutomaticSize = Enum.AutomaticSize.X,
				BackgroundTransparency = 0,
				BackgroundColor3 = P.raised:Lerp(Color3.new(1, 1, 1), 0.08),
				Parent = chip,
			})
			corner(4).Parent = key
			pad(5, 5, 0, 0).Parent = key
			label(k[2], 11, P.dim, SANS, { Size = UDim2.fromOffset(0, 16), AutomaticSize = Enum.AutomaticSize.X, Parent = chip })
		end
		return row
	end

	-- Step 1 of the page: its own card. A tinted badge with the step's icon and number, a title, a line saying what
	-- to do (opts.desc). Returns its body, the card and the line (so it can change as the step gets done).
	local function stepCard(parent, n, title, sub, done, id, opts)
		opts = opts or {}
		local card = col({ BackgroundTransparency = 0, BackgroundColor3 = P.card, Parent = parent }, { corner(14), stroke(P.line) })
		shade(card, 0.07)
		topLight(card, 0.12, 16)
		shadow(card, 14)
		if n and not done then -- the step to do now
			glow(card, 14, 0.35):set(true, true)
		end
		local inner = col({ Parent = card }, { pad(14, 14, 14, 14), vlist(12) })
		local head = col({ Parent = inner })
		local badge = box({
			BackgroundTransparency = 0,
			BackgroundColor3 = P.accent:Lerp(P.card, 0.86),
			Size = UDim2.fromOffset(32, 32),
			Parent = head,
		}, { corner(8), stroke(P.accent:Lerp(P.card, 0.8)) })
		local ic = icon(opts.icon or "spline", 16, P.accent)
		ic.AnchorPoint = Vector2.new(0.5, 0.5)
		ic.Position = UDim2.fromScale(0.5, 0.5)
		ic.Parent = badge
		if n or done then -- the step's number (a tick once done); optional cards have none
			local num = label(done and "✓" or tostring(n), 10, P.onAccent, SANS_B, {
				BackgroundTransparency = 0,
				BackgroundColor3 = P.accent,
				Size = UDim2.fromOffset(16, 16),
				Position = UDim2.fromOffset(22, -6),
				TextXAlignment = Enum.TextXAlignment.Center,
				ZIndex = 2,
				Parent = badge,
			})
			corner(8).Parent = num
			local ring = stroke(P.card)
			ring.Thickness = 2
			ring.Parent = num
		end
		local txt = col({ Position = UDim2.fromOffset(44, 0), Size = UDim2.new(1, -44, 0, 0), Parent = head }, { vlist(2) })
		local titleRow = box({ Size = UDim2.new(1, 0, 0, 18), Parent = txt }, { hlist(8) })
		label(title, 14, P.text, SANS_B, { Size = UDim2.fromOffset(0, 18), AutomaticSize = Enum.AutomaticSize.X, Parent = titleRow })
		if opts.tag then -- a small pill after the title ("Optional")
			local tag = label(opts.tag, 10, P.dim, SANS_B, {
				Size = UDim2.fromOffset(0, 18),
				AutomaticSize = Enum.AutomaticSize.X,
				BackgroundTransparency = 0,
				BackgroundColor3 = P.raised,
				Parent = titleRow,
			})
			corner(9).Parent = tag
			pad(7, 7, 0, 0).Parent = tag
		end
		local hint = para(opts.desc or sub or "", { Parent = txt })
		hint.TextColor3 = P.dim
		local body = col({ Parent = inner }, { vlist(10) })
		return body, card, hint
	end

	-- a square icon button (the + and settings next to the picker, a page's close)
	local function iconButton(iconName, hint, onClick, on, size)
		size = size or 32
		local b = new("TextButton", {
			Text = "",
			BackgroundColor3 = on and P.accentSoft or P.raised,
			AutoButtonColor = false,
			Size = UDim2.fromOffset(size, size),
		}, { corner(9), stroke(on and P.accentLine or P.line) })
		pressable(b, 0.94)
		local ic = icon(iconName, math.floor(size * 0.44), on and P.accent or P.dim)
		ic.AnchorPoint = Vector2.new(0.5, 0.5)
		ic.Position = UDim2.fromScale(0.5, 0.5)
		ic.Parent = b
		b.MouseEnter:Connect(function()
			if not on then
				b.BackgroundColor3 = P.hover
				setIconColor(ic, P.text)
			end
		end)
		b.MouseLeave:Connect(function()
			if not on then
				b.BackgroundColor3 = P.raised
				setIconColor(ic, P.dim)
			end
		end)
		hintOn(b, hint)
		if onClick then
			b.MouseButton1Click:Connect(function()
				onClick(b)
			end)
		end
		return b, ic
	end

	-- where a list is empty: the logo, a title, a line saying what to do, and (optionally) the button that does it
	local function emptyState(parent, title, text, actionText, onAction)
		local f = col({ Parent = parent }, {
			pad(8, 8, 18, 18),
			new("UIListLayout", {
				Padding = UDim.new(0, 8),
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		})
		new("ImageLabel", { Image = App.LOGO.mark, BackgroundTransparency = 1, Size = UDim2.fromOffset(40, 40), Parent = f })
		label(title, 14, P.text, SANS_B, { Size = UDim2.new(1, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Center, Parent = f })
		local t = para(text, { Parent = f })
		t.TextColor3, t.TextXAlignment = P.dim, Enum.TextXAlignment.Center
		if actionText then
			box({ Size = UDim2.new(1, 0, 0, 2), Parent = f })
			button(actionText, "accent", onAction, { Parent = f })
		end
		return f
	end

	-- a small selectable tile in a grid (surfaces, marks, road styles). isOn (optional): whether it shows as picked.
	-- Returns the tile and its refresh.
	local function chip(parent, text, isOn, onClick, swatch)
		local b = new(
			"TextButton",
			{ Text = (swatch and "     " or "") .. text, TextSize = 12, AutoButtonColor = false, Parent = parent },
			{ corner(8) }
		)
		local st = stroke(P.line)
		st.Parent = b
		if swatch then -- a colour dot before the name
			box({
				BackgroundTransparency = 0,
				BackgroundColor3 = swatch,
				Size = UDim2.fromOffset(8, 8),
				Position = UDim2.new(0, 9, 0.5, -4),
				ZIndex = b.ZIndex + 1,
				Parent = b,
			}, { corner(4) })
		end
		local lit = glow(b, 8, 0.45)
		pressable(b)
		local function look()
			local on = isOn ~= nil and isOn() == true
			lit:set(on)
			b.Font = on and SANS_B or SANS_M
			b.BackgroundColor3 = on and P.accentSoft or P.raised
			b.TextColor3 = on and P.accent or (isOn and P.dim or P.text)
			st.Color = on and P.accentLine or P.line
		end
		look()
		b.MouseButton1Click:Connect(function()
			onClick()
			look()
		end)
		return b, look
	end
	local function chipGrid(parent, cols, h)
		return col({ Parent = parent }, {
			new("UIGridLayout", {
				CellSize = UDim2.new(1 / cols, -6, 0, h or 30),
				CellPadding = UDim2.fromOffset(6, 6),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		})
	end

	-- a page's own top line: back, then its title
	local function pageHead(parent, backText, title, onBack)
		local row = box({ Size = UDim2.new(1, 0, 0, 30), Parent = parent })
		local back = new("TextButton", {
			Text = "",
			AutoButtonColor = false,
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(0, 30),
			AutomaticSize = Enum.AutomaticSize.X,
			Parent = row,
		}, { hlist(4) })
		local ic = icon("left", 13, P.dim)
		ic.Parent = back
		local t = label(backText, 13, P.dim, SANS_M, { Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X, Parent = back })
		back.MouseEnter:Connect(function()
			t.TextColor3 = P.text
			setIconColor(ic, P.text)
		end)
		back.MouseLeave:Connect(function()
			t.TextColor3 = P.dim
			setIconColor(ic, P.dim)
		end)
		back.MouseButton1Click:Connect(onBack)
		if title then
			box({ Size = UDim2.new(1, 0, 0, 4), Parent = parent })
			label(title, 17, P.text, SANS_B, { Size = UDim2.new(1, 0, 0, 24), Parent = parent })
		end
		return row
	end

	-- used by later modules
	App.new = new
	App.corner = corner
	App.stroke = stroke
	App.pad = pad
	App.vlist = vlist
	App.hlist = hlist
	App.box = box
	App.col = col
	App.label = label
	App.para = para
	App.explain = explain
	App.hoverable = hoverable
	App.halftone = halftone
	App.sheen = sheen
	App.fadeLine = fadeLine
	App.shade = shade
	App.glow = glow
	App.shadow = shadow
	App.pressable = pressable
	App.sweep = sweep
	App.topLight = topLight
	App.hideTip = hideTip
	App.button = button
	App.buttonRow = buttonRow
	App.hintOn = hintOn
	App.refreshSliders = refreshSliders
	App.slider = slider
	App.switch = switch
	App.switchRow = switchRow
	App.segmented = segmented
	App.icon = icon
	App.setIconColor = setIconColor
	App.section = section
	App.stepCard = stepCard
	App.stepLabel = stepLabel
	App.navRow = navRow
	App.hintBox = hintBox
	App.keyChips = keyChips
	App.pageHead = pageHead
	App.chip = chip
	App.emptyState = emptyState
	App.chipGrid = chipGrid
	App.iconButton = iconButton
end
