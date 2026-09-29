--[[
	Smart Scatter — Kit: UI kit: layout helpers, labels, links, sliders, switches, segmented controls, chips, icons.
	Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]

return function(App)
	local TextService = game:GetService("TextService")
	local UIS = game:GetService("UserInputService")
	local RunService, FAST, tween, P, SANS = App.RunService, App.FAST, App.tween, App.P, App.SANS
	local SANS_M, SANS_B = App.SANS_M, App.SANS_B
	local TweenService = game:GetService("TweenService")
	local G = App.G

	--------------------------------------------------------------------------------
	-- UI kit
	--------------------------------------------------------------------------------
	local seqN = 0
	local function seq()
		seqN += 1
		return seqN
	end

	-- every text size in the plugin goes through here, so the Text size setting scales all of it
	local TEXT_SIZES = { [1] = "Small", [1.2] = "Normal", [1.4] = "Large" }
	local function textSize(n)
		return math.round(n * (App.G.textScale or 1.2))
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
			elseif k == "TextSize" then
				o.TextSize = textSize(v)
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
			Size = UDim2.new(1, 0, 0, textSize(size or 13) + 8),
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

	-- glass: obj turns see-through, more toward the bottom, with a lighter tint at the top (a sheen), and its border
	-- catches the light along the top edge and fades down the sides. The colour blobs behind show through it. Plain
	-- when the blobs are off. (Gradients only: nothing is added inside obj, so its layout is untouched.)
	local function glass(obj)
		if G.blobs == false then
			return
		end
		local light = settings().Studio.Theme.Name == "Light"
		local base = obj.BackgroundColor3
		obj.BackgroundColor3 = base:Lerp(Color3.new(1, 1, 1), light and 0.3 or 0.07)
		obj.BackgroundTransparency = 0
		local k = light and 0.97 or 0.86
		new("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(k, k, k)),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, light and 0.1 or 0.12),
				NumberSequenceKeypoint.new(1, light and 0.2 or 0.32),
			}),
			Parent = obj,
		})
		local st = obj:FindFirstChildOfClass("UIStroke") or stroke(P.line)
		st.Color = Color3.new(1, 1, 1)
		st.Transparency = 0
		st.Parent = obj
		new("UIGradient", {
			Rotation = 90,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, light and 0.1 or 0.7),
				NumberSequenceKeypoint.new(0.35, light and 0.5 or 0.88),
				NumberSequenceKeypoint.new(1, light and 0.6 or 0.93),
			}),
			Parent = st,
		})
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
	local GLOW = { { 1, 1.5, 0.62 }, { 3, 4, 0.93 } } -- { out, thickness, transparency when fully lit }
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
	-- hint: the tooltip's text, or a function giving it when the mouse arrives (for a hint that changes)
	local function hintOn(obj, hint)
		if not hint then
			return
		end
		obj.MouseEnter:Connect(function()
			local text = type(hint) == "function" and hint() or hint
			if text then
				showTip(obj, text)
			end
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
		local name = label(text, 13, P.text, SANS, { Size = UDim2.new(1, -94, 0, 26), Parent = f })
		-- the value reads as plain text at the row's end; it turns into a field under the mouse or while typing
		local value = new("TextBox", {
			BackgroundTransparency = 1,
			BackgroundColor3 = P.field,
			Text = "",
			Font = SANS_M,
			TextSize = 13,
			TextColor3 = P.dim,
			TextXAlignment = Enum.TextXAlignment.Right,
			ClearTextOnFocus = false,
			Size = UDim2.new(0, 96, 0, 22),
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 0, 2),
			Parent = f,
		}, { corner(5), pad(6, 6, 0, 0) })
		local valueStroke = stroke(P.line)
		valueStroke.Transparency = 1
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
			-- the value's pill just fits what it says; the name gets the rest of the row
			local ok, bounds = pcall(TextService.GetTextSize, TextService, value.Text, value.TextSize, value.Font, Vector2.new(400, 40))
			if ok and typeof(bounds) == "Vector2" then
				local w = math.clamp(math.ceil(bounds.X) + 20, 44, 110)
				value.Size = UDim2.new(0, w, 0, 22)
				name.Size = UDim2.new(1, -(w + 8), 0, 26)
			end
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
			if not value:IsFocused() then
				value.BackgroundTransparency = hovering and 0 or 1
				valueStroke.Transparency = hovering and 0 or 1
				value.TextColor3 = hot and P.text or P.dim
			end
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
			local sawHeld = false -- (the button found up ends the drag: let go outside the panel, no end event comes)
			conn = RunService.Heartbeat:Connect(function()
				if not dragging then
					conn:Disconnect()
					return
				end
				local ok, held = pcall(UIS.IsMouseButtonPressed, UIS, Enum.UserInputType.MouseButton1)
				if ok and held then
					sawHeld = true
				elseif ok and sawHeld then
					stop()
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
			value.BackgroundTransparency, value.TextColor3 = 0, P.text
			valueStroke.Color, valueStroke.Transparency = P.accent, 0
		end)
		value.FocusLost:Connect(function()
			valueStroke.Color = P.line
			look()
			local n = tonumber(string.match(value.Text, "%-?[%d%.]+"))
			if n and pct then
				n /= 100
			end
			local was = get()
			apply(n, true)
			show(get(), true)
			if onCommit and get() ~= was then -- (a click in and out again changes nothing: no empty undo step)
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

	-- a setting that's on or off: its name (wrapping onto a second line when long), the switch on the right
	local function switchRow(text, get, set, onChange, hint)
		local f = box({ Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y }, { pad(0, 0, 10, 10) })
		hintOn(f, hint)
		label(text, 13, P.text, SANS, {
			Size = UDim2.new(1, -52, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			TextWrapped = true,
			TextTruncate = Enum.TextTruncate.None,
			Parent = f,
		})
		local s = switch(get, set, onChange)
		s.Position = UDim2.new(1, -38, 0.5, -11)
		s.Parent = f
		return f
	end

	-- Icons, drawn from frames (no uploaded images) in a unit square scaled to `size`. One consistent set, in the
	-- manner of modern UI icon sets: even, rounded strokes about a tenth of the size, a faint tint inside outlines,
	-- and small solid details (handles, nodes, dots) that make each one read at a glance. Shapes sit inside the square
	-- with a little room all round, so icons of different shapes look the same size.
	local ICON_FILL = 0.88 -- transparency of the faint tint inside outlines
	local function icon(name, size, color)
		local f = box({ Size = UDim2.fromOffset(size, size) })
		local th = math.max(1.5, size / 10)
		local function outline(o)
			local st = stroke(color)
			st.Thickness = th
			st.LineJoinMode = Enum.LineJoinMode.Round
			st.Parent = o
		end
		-- a circle: an outline with a faint tint, or solid
		local function ring(cx, cy, r, filled)
			local o = box({
				BackgroundTransparency = filled and 0 or ICON_FILL,
				BackgroundColor3 = color,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(cx * size, cy * size),
				Size = UDim2.fromOffset(r * 2 * size, r * 2 * size),
				Parent = f,
			}, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
			if not filled then
				outline(o)
			end
			return o
		end
		-- a rounded rectangle (rad: its corner, as a share of the size), outlined or solid
		local function rect(cx, cy, w, h, filled, rad)
			local o = box({
				BackgroundTransparency = filled and 0 or ICON_FILL,
				BackgroundColor3 = color,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset(cx * size, cy * size),
				Size = UDim2.fromOffset(w * size, h * size),
				Parent = f,
			}, { corner(math.max(1, (rad or 0.12) * size)) })
			if not filled then
				outline(o)
			end
			return o
		end
		-- a stroke from one point to another, with round ends
		local function bar(x1, y1, x2, y2)
			local dx, dy = (x2 - x1) * size, (y2 - y1) * size
			box({
				BackgroundTransparency = 0,
				BackgroundColor3 = color,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromOffset((x1 + x2) / 2 * size, (y1 + y2) / 2 * size),
				Size = UDim2.fromOffset(math.sqrt(dx * dx + dy * dy) + th, th),
				Rotation = math.deg(math.atan2(dy, dx)),
				Parent = f,
			}, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
		end
		-- strokes through a list of points { x1, y1, x2, y2, … }
		local function path(pts)
			for k = 1, #pts - 3, 2 do
				bar(pts[k], pts[k + 1], pts[k + 2], pts[k + 3])
			end
		end
		local dot = function(cx, cy, r)
			return ring(cx, cy, r or 0.07, true)
		end

		if name == "brush" then -- the brush's ring and its centre
			ring(0.5, 0.5, 0.34)
			dot(0.5, 0.5, 0.09)
		elseif name == "lasso" then -- a loop with its tail and knot
			rect(0.5, 0.42, 0.7, 0.5, false, 0.25)
			bar(0.36, 0.66, 0.28, 0.84)
			dot(0.27, 0.87, 0.07)
		elseif name == "box" then -- a selection square with its corner handles
			rect(0.5, 0.5, 0.56, 0.56, false, 0.04)
			for _, c in { { 0.22, 0.22 }, { 0.78, 0.22 }, { 0.22, 0.78 }, { 0.78, 0.78 } } do
				rect(c[1], c[2], 0.13, 0.13, true, 0.02)
			end
		elseif name == "polygon" then -- an outline with its points
			path({ 0.5, 0.18, 0.84, 0.78, 0.16, 0.78, 0.5, 0.18 })
			dot(0.5, 0.18)
			dot(0.84, 0.78)
			dot(0.16, 0.78)
		elseif name == "fill" then -- a tipped bucket and a drop
			rect(0.42, 0.5, 0.44, 0.44, false, 0.08).Rotation = 45
			bar(0.2, 0.5, 0.64, 0.5)
			dot(0.82, 0.78, 0.08)
		elseif name == "erase" then
			ring(0.5, 0.5, 0.34)
			bar(0.28, 0.72, 0.72, 0.28)
		elseif name == "spline" then -- a curve through its points
			path({ 0.16, 0.76, 0.36, 0.44, 0.56, 0.58, 0.84, 0.26 })
			dot(0.16, 0.76, 0.08)
			dot(0.84, 0.26, 0.08)
			ring(0.36, 0.44, 0.06, true)
			ring(0.56, 0.58, 0.06, true)
		elseif name == "area" then -- ground with things on it
			rect(0.5, 0.5, 0.72, 0.72, false, 0.14)
			dot(0.38, 0.4, 0.07)
			dot(0.62, 0.52, 0.07)
			dot(0.42, 0.66, 0.06)
		elseif name == "clear" then -- a keep-clear zone: a patch, struck out
			rect(0.5, 0.5, 0.72, 0.72, false, 0.14)
			bar(0.3, 0.7, 0.7, 0.3)
		elseif name == "layers" then -- sheets stacked
			rect(0.5, 0.34, 0.68, 0.22, false, 0.06)
			path({ 0.16, 0.56, 0.5, 0.7, 0.84, 0.56 })
			path({ 0.16, 0.74, 0.5, 0.88, 0.84, 0.74 })
		elseif name == "settings" then -- two sliders
			bar(0.16, 0.32, 0.84, 0.32)
			bar(0.16, 0.68, 0.84, 0.68)
			ring(0.36, 0.32, 0.1, true)
			ring(0.64, 0.68, 0.1, true)
		elseif name == "plus" then
			bar(0.5, 0.2, 0.5, 0.8)
			bar(0.2, 0.5, 0.8, 0.5)
		elseif name == "minus" then
			bar(0.2, 0.5, 0.8, 0.5)
		elseif name == "close" then
			bar(0.26, 0.26, 0.74, 0.74)
			bar(0.26, 0.74, 0.74, 0.26)
		elseif name == "info" then
			ring(0.5, 0.5, 0.36)
			bar(0.5, 0.47, 0.5, 0.68)
			dot(0.5, 0.32, 0.05)
		elseif name == "right" then
			path({ 0.4, 0.22, 0.66, 0.5, 0.4, 0.78 })
		elseif name == "left" then
			path({ 0.6, 0.22, 0.34, 0.5, 0.6, 0.78 })
		elseif name == "down" then
			path({ 0.22, 0.4, 0.5, 0.66, 0.78, 0.4 })
		elseif name == "undo" then -- a hooked arrow back
			path({ 0.3, 0.36, 0.44, 0.22 })
			path({ 0.3, 0.36, 0.44, 0.5 })
			local last
			for k = 0, 6 do
				local a = math.rad(-90 + k * 30)
				local pt = Vector2.new(0.58 + 0.22 * math.cos(a), 0.58 + 0.22 * math.sin(a))
				if last then
					bar(last.X, last.Y, pt.X, pt.Y)
				else
					bar(0.3, 0.36, pt.X, pt.Y)
				end
				last = pt
			end
			bar(last.X, last.Y, 0.34, 0.8)
		elseif name == "refresh" then -- a circle closing on its arrow
			ring(0.5, 0.52, 0.3).BackgroundTransparency = 1
			path({ 0.62, 0.12, 0.8, 0.2, 0.72, 0.38 })
		elseif name == "search" then
			ring(0.43, 0.43, 0.26)
			bar(0.63, 0.63, 0.84, 0.84)
		elseif name == "trash" then -- a bin: lid, handle, body with ribs
			bar(0.18, 0.28, 0.82, 0.28)
			path({ 0.4, 0.28, 0.42, 0.16, 0.58, 0.16, 0.6, 0.28 })
			rect(0.5, 0.6, 0.5, 0.52, false, 0.08)
			bar(0.42, 0.48, 0.42, 0.72)
			bar(0.58, 0.48, 0.58, 0.72)
		elseif name == "stamp" then -- a rubber stamp: knob, stem, pad, and the mark it leaves
			ring(0.5, 0.22, 0.11)
			bar(0.5, 0.33, 0.5, 0.48)
			rect(0.5, 0.58, 0.66, 0.18, false, 0.06)
			bar(0.2, 0.84, 0.8, 0.84)
		elseif name == "spray" then -- copies scattered where the brush goes
			ring(0.5, 0.5, 0.36).BackgroundTransparency = 1
			dot(0.38, 0.38, 0.06)
			dot(0.62, 0.36, 0.06)
			dot(0.52, 0.56, 0.06)
			dot(0.34, 0.64, 0.06)
			dot(0.66, 0.64, 0.06)
		elseif name == "logo" then
			dot(0.5, 0.2, 0.08)
			dot(0.24, 0.74, 0.08)
			dot(0.76, 0.74, 0.08)
			bar(0.5, 0.3, 0.5, 0.44)
			bar(0.36, 0.64, 0.44, 0.5)
			bar(0.64, 0.64, 0.56, 0.5)
		-- the cards' icons
		elseif name == "leaf" then -- biomes, surfaces
			rect(0.54, 0.46, 0.44, 0.62, false, 0.3).Rotation = 40
			bar(0.22, 0.84, 0.56, 0.44)
		elseif name == "grid" then -- pattern
			for _, c in { { 0.32, 0.32 }, { 0.68, 0.32 }, { 0.32, 0.68 }, { 0.68, 0.68 } } do
				rect(c[1], c[2], 0.26, 0.26, false, 0.06)
			end
		elseif name == "blend" then -- colour zones: two colours overlapping
			ring(0.38, 0.5, 0.24)
			ring(0.62, 0.5, 0.24)
		elseif name == "wind" then -- edges and wind
			path({ 0.14, 0.36, 0.6, 0.36, 0.7, 0.26 })
			bar(0.14, 0.54, 0.8, 0.54)
			path({ 0.14, 0.72, 0.52, 0.72, 0.62, 0.82 })
		elseif name == "bookmark" then -- presets
			path({ 0.3, 0.16, 0.7, 0.16, 0.7, 0.84, 0.5, 0.68, 0.3, 0.84, 0.3, 0.16 })
		elseif name == "chart" then -- performance
			bar(0.16, 0.84, 0.84, 0.84)
			rect(0.3, 0.64, 0.14, 0.28, false, 0.03)
			rect(0.5, 0.5, 0.14, 0.56, false, 0.03)
			rect(0.7, 0.58, 0.14, 0.4, false, 0.03)
		elseif name == "snow" then -- seasons
			for _, a in { 90, 30, -30 } do
				local r = math.rad(a)
				bar(0.5 - math.cos(r) * 0.34, 0.5 - math.sin(r) * 0.34, 0.5 + math.cos(r) * 0.34, 0.5 + math.sin(r) * 0.34)
			end
			dot(0.5, 0.5, 0.07)
		elseif name == "swap" then -- two arrows passing
			bar(0.2, 0.36, 0.78, 0.36)
			path({ 0.64, 0.22, 0.8, 0.36, 0.64, 0.5 })
			bar(0.22, 0.64, 0.8, 0.64)
			path({ 0.36, 0.5, 0.2, 0.64, 0.36, 0.78 })
		elseif name == "camera" then -- snapshot
			rect(0.5, 0.58, 0.72, 0.5, false, 0.1)
			rect(0.38, 0.3, 0.2, 0.1, true, 0.03)
			ring(0.5, 0.58, 0.13)
		elseif name == "eye" then -- the viewport
			rect(0.5, 0.5, 0.76, 0.44, false, 0.22)
			dot(0.5, 0.5, 0.1)
		elseif name == "cube" then -- game-ready output
			path({ 0.5, 0.14, 0.84, 0.32, 0.84, 0.68, 0.5, 0.86, 0.16, 0.68, 0.16, 0.32, 0.5, 0.14 })
			path({ 0.16, 0.32, 0.5, 0.5, 0.84, 0.32 })
			bar(0.5, 0.5, 0.5, 0.86)
		elseif name == "keyboard" then -- shortcuts
			rect(0.5, 0.5, 0.8, 0.5, false, 0.1)
			for _, x in { 0.32, 0.5, 0.68 } do
				dot(x, 0.42, 0.04)
			end
			bar(0.34, 0.6, 0.66, 0.6)
		elseif name == "palette" then -- look: accent and text
			ring(0.5, 0.5, 0.36)
			dot(0.36, 0.4, 0.06)
			dot(0.58, 0.34, 0.06)
			dot(0.66, 0.54, 0.06)
		elseif name == "road" then -- a road and its middle line
			bar(0.3, 0.86, 0.42, 0.14)
			bar(0.7, 0.86, 0.58, 0.14)
			bar(0.5, 0.78, 0.5, 0.66)
			bar(0.5, 0.48, 0.5, 0.4)
			bar(0.5, 0.24, 0.5, 0.2)
		elseif name == "align" then -- lining up: bars of three lengths against one edge
			bar(0.2, 0.14, 0.2, 0.86)
			bar(0.34, 0.3, 0.8, 0.3)
			bar(0.34, 0.5, 0.62, 0.5)
			bar(0.34, 0.7, 0.72, 0.7)
		elseif name == "cursor" then -- selecting: a pointer, its tip at the top left
			path({ 0.26, 0.16, 0.26, 0.8, 0.44, 0.62, 0.58, 0.88 })
			path({ 0.26, 0.16, 0.72, 0.58, 0.46, 0.6 })
		elseif name == "pin" then -- marking what the scan sees
			ring(0.5, 0.38, 0.2)
			bar(0.5, 0.58, 0.5, 0.86)
			dot(0.5, 0.38, 0.06)
		elseif name == "wand" then -- tidying: a wand and its sparkle
			bar(0.2, 0.82, 0.6, 0.42)
			bar(0.74, 0.12, 0.74, 0.36)
			bar(0.62, 0.24, 0.86, 0.24)
		elseif name == "spread" then -- evenly spread copies
			for _, x in { 0.26, 0.5, 0.74 } do
				for _, y in { 0.26, 0.5, 0.74 } do
					dot(x, y, 0.06)
				end
			end
		elseif name == "filter" then -- paint only on
			path({ 0.16, 0.22, 0.84, 0.22, 0.58, 0.52, 0.58, 0.8, 0.42, 0.86, 0.42, 0.52, 0.16, 0.22 })
		elseif name == "scale" then -- size
			rect(0.4, 0.6, 0.4, 0.4, false, 0.06)
			path({ 0.52, 0.18, 0.82, 0.18, 0.82, 0.48 })
			bar(0.82, 0.18, 0.58, 0.42)
		elseif name == "stack" then -- groups and piles
			rect(0.3, 0.7, 0.28, 0.24, false, 0.05)
			rect(0.7, 0.7, 0.28, 0.24, false, 0.05)
			rect(0.5, 0.3, 0.28, 0.24, false, 0.05)
		elseif name == "shield" then -- keep away from
			path({ 0.5, 0.14, 0.82, 0.26, 0.78, 0.56, 0.5, 0.86, 0.22, 0.56, 0.18, 0.26, 0.5, 0.14 })
		elseif name == "magnet" then -- grow close to
			path({ 0.26, 0.2, 0.26, 0.56 })
			path({ 0.74, 0.2, 0.74, 0.56 })
			local last
			for k = 0, 6 do
				local a = math.rad(k * 30)
				local pt = Vector2.new(0.5 + 0.24 * math.cos(a), 0.56 + 0.24 * math.sin(a))
				if last then
					bar(last.X, last.Y, pt.X, pt.Y)
				end
				last = pt
			end
		elseif name == "mountain" then -- slopes and terrain
			path({ 0.12, 0.8, 0.42, 0.3, 0.6, 0.6, 0.7, 0.46, 0.88, 0.8, 0.12, 0.8 })
		elseif name == "tag" then -- the object's basics
			path({ 0.16, 0.18, 0.54, 0.18, 0.84, 0.5, 0.52, 0.82, 0.16, 0.46, 0.16, 0.18 })
			dot(0.32, 0.33, 0.06)
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
		label(text, 12, P.dim, SANS_B, { Size = UDim2.fromOffset(0, 22), AutomaticSize = Enum.AutomaticSize.X, Parent = row })
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

	-- keyboard hints: { { "Shift", "height" }, ... } as a quiet line of keycaps, each with what it does
	local function keyChips(parent, list)
		local row = buttonRow(parent, 12)
		for _, k in list do
			local chip = new("Frame", {
				BackgroundTransparency = 1,
				Size = UDim2.fromOffset(0, 20),
				AutomaticSize = Enum.AutomaticSize.X,
				Parent = row,
			}, { hlist(5) })
			local key = label(k[1], 10, P.dim, SANS_B, {
				Size = UDim2.fromOffset(0, 18),
				AutomaticSize = Enum.AutomaticSize.X,
				TextXAlignment = Enum.TextXAlignment.Center,
				BackgroundTransparency = 0,
				BackgroundColor3 = P.raised,
				Parent = chip,
			})
			corner(4).Parent = key
			pad(5, 5, 0, 0).Parent = key
			local edge = stroke(P.line)
			edge.Parent = key
			label(k[2], 11, P.faint, SANS, { Size = UDim2.fromOffset(0, 18), AutomaticSize = Enum.AutomaticSize.X, Parent = chip })
		end
		return row
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

	-- Listens for the next key pressed while `over` (a button) waits for one, then calls done(KeyCode name), or
	-- done(nil) on Esc or a click away. Keys reach a plugin panel by different routes depending on focus, so it
	-- listens to all of them (a focused text box's key events and typed text, and Studio's input) and takes the
	-- first. Returns a function that stops listening.
	local TYPED = {
		["["] = "LeftBracket",
		["]"] = "RightBracket",
		["-"] = "Minus",
		["="] = "Equals",
		[";"] = "Semicolon",
		[","] = "Comma",
		["."] = "Period",
		["/"] = "Slash",
		[" "] = "Space",
		["'"] = "Quote",
	}
	for d, n in
		{
			["1"] = "One",
			["2"] = "Two",
			["3"] = "Three",
			["4"] = "Four",
			["5"] = "Five",
			["6"] = "Six",
			["7"] = "Seven",
			["8"] = "Eight",
			["9"] = "Nine",
			["0"] = "Zero",
		}
	do
		TYPED[d] = n
	end
	local function captureKey(over, done)
		local tb = new("TextBox", {
			Text = "",
			TextTransparency = 1,
			BackgroundTransparency = 1,
			ClearTextOnFocus = true,
			Size = UDim2.fromScale(1, 1),
			ZIndex = over.ZIndex + 2,
			Parent = over,
		})
		local conns, finished = {}, false
		-- key: a KeyCode name; the modifiers held with it (Ctrl, Alt, Shift) make it a combo ("Ctrl+Shift+G").
		-- Esc on its own keeps the old binding.
		local function finish(key)
			if finished then
				return
			end
			finished = true
			for _, c in conns do
				c:Disconnect()
			end
			tb:Destroy()
			if not key or key == "Escape" then
				done(nil)
			else
				done(App.combo(key, App.modsHeld()))
			end
		end
		local function fromInput(input)
			if input.UserInputType ~= Enum.UserInputType.Keyboard then
				return
			end
			if App.UNBINDABLE[input.KeyCode.Name] then -- a modifier on its own: show it, and wait for the key
				if over:IsA("TextButton") or over:IsA("TextLabel") then
					over.Text = App.combo("…", App.modsHeld())
				end
				return
			end
			finish(input.KeyCode.Name)
		end
		table.insert(conns, tb.InputBegan:Connect(fromInput))
		table.insert(conns, UIS.InputBegan:Connect(fromInput))
		table.insert(
			conns,
			tb:GetPropertyChangedSignal("Text"):Connect(function()
				local ch = string.sub(tb.Text, -1)
				if ch ~= "" then
					finish(TYPED[ch] or (string.match(ch, "%a") and string.upper(ch)) or nil)
				end
			end)
		)
		table.insert(
			conns,
			tb.FocusLost:Connect(function(enter)
				task.defer(finish, enter and "Return" or nil) -- after any key event of the same press
			end)
		)
		tb:CaptureFocus()
		return function()
			finish(nil)
		end
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
		local b = new("TextButton", {
			Text = text,
			TextSize = 12,
			TextTruncate = Enum.TextTruncate.AtEnd,
			AutoButtonColor = false,
			Parent = parent,
		}, { corner(8), pad(swatch and 22 or 8, 8, 0, 0) })
		local st = stroke(P.line)
		st.Parent = b
		if swatch then -- a colour dot before the name
			box({
				BackgroundTransparency = 0,
				BackgroundColor3 = swatch,
				Size = UDim2.fromOffset(8, 8),
				Position = UDim2.new(0, -13, 0.5, -4), -- (in the padding before the name)
				ZIndex = b.ZIndex + 1,
				Parent = b,
			}, { corner(4) })
		end
		pressable(b)
		local function look()
			local on = isOn ~= nil and isOn() == true
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
	-- a grid of chips or tiles: up to `cols` a row, fewer when the panel is too narrow for cells of minCell pixels
	-- (so names never spill out of their cell), more room again when it's widened
	local function chipGrid(parent, cols, h, minCell)
		local layout = new("UIGridLayout", {
			CellSize = UDim2.new(1 / cols, -6, 0, h or 30),
			CellPadding = UDim2.fromOffset(6, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
		})
		local g = col({ Parent = parent }, { layout })
		local shown
		local function fit()
			local w = g.AbsoluteSize.X
			local n = cols
			if type(w) == "number" and w > 0 then
				n = math.clamp(math.floor((w + 6) / ((minCell or 84) + 6)), 1, cols)
			end
			if n ~= shown then
				shown = n
				layout.CellSize = UDim2.new(1 / n, -6 * (n - 1) / n, 0, h or 30)
			end
		end
		fit()
		g:GetPropertyChangedSignal("AbsoluteSize"):Connect(fit)
		return g
	end

	-- A grid of tool tiles: an icon and a name, and optionally a line under it saying what the tool does (so it reads
	-- without hovering). The picked one glows in its colour; a tinted one (Erase: red) shows its colour even when not
	-- picked, so it's never taken for another tool. tiles.add{ icon, text, sub?, color?, tinted?, hint?, on(), click() };
	-- tiles.refresh() after anything that changes which is picked.
	local function toolTiles(parent, cols, h, minCell)
		local grid = chipGrid(parent, cols, h, minCell)
		local tiles = { cells = {} }
		function tiles.add(spec)
			local color = spec.color or P.accent
			local b = new("TextButton", { Text = "", AutoButtonColor = false, BackgroundColor3 = P.raised, Parent = grid }, { corner(8) })
			local st = stroke(P.line)
			st.Parent = b
			local inner = box({ Size = UDim2.fromScale(1, 1), Parent = b }, {
				new("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal,
					HorizontalAlignment = spec.sub and Enum.HorizontalAlignment.Left or Enum.HorizontalAlignment.Center,
					VerticalAlignment = Enum.VerticalAlignment.Center,
					Padding = UDim.new(0, spec.sub and 8 or 6),
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
				spec.sub and pad(10, 8, 0, 0) or nil,
			})
			local ic = icon(spec.icon, spec.sub and 16 or 14, P.dim)
			ic.LayoutOrder = 0 -- (the icon first, then the words: its name, then what it does)
			ic.Parent = inner
			local words = box({ Size = UDim2.new(1, -26, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1, Parent = inner }, {
				new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 1) }),
			})
			if not spec.sub then
				words.Size, words.AutomaticSize = UDim2.fromOffset(0, 16), Enum.AutomaticSize.X
			end
			local t = label(spec.text, 12, P.dim, SANS_B, {
				Size = spec.sub and UDim2.new(1, 0, 0, 16) or UDim2.fromOffset(0, 16),
				AutomaticSize = not spec.sub and Enum.AutomaticSize.X or nil,
				LayoutOrder = 0,
				Parent = words,
			})
			local sub = spec.sub -- (wraps onto a second line in a narrow panel)
				and label(spec.sub, 11, P.faint, SANS, {
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					TextWrapped = true,
					TextTruncate = Enum.TextTruncate.None,
					LineHeight = 1.05,
					LayoutOrder = 1,
					Parent = words,
				})
			if spec.hint then
				hintOn(b, spec.hint)
			end
			pressable(b, 0.96)
			local lit = glow(b, 8, 0.6, color)
			local c = { hot = false }
			function c.look()
				local on = spec.on() == true
				lit:set(on)
				local idle = spec.tinted and color:Lerp(P.raised, c.hot and 0.8 or 0.9) or (c.hot and P.hover or P.raised)
				b.BackgroundColor3 = on and color:Lerp(P.card, 0.8) or idle
				st.Color = on and color:Lerp(P.card, 0.4) or (spec.tinted and color:Lerp(P.card, 0.6) or P.line)
				local fg = on and color or (spec.tinted and color:Lerp(P.dim, 0.2) or (c.hot and P.text or P.dim))
				setIconColor(ic, fg)
				t.TextColor3 = fg
				if sub then
					sub.TextColor3 = on and color:Lerp(P.dim, 0.35) or P.faint
				end
			end
			b.MouseEnter:Connect(function()
				c.hot = true
				c.look()
			end)
			b.MouseLeave:Connect(function()
				c.hot = false
				c.look()
			end)
			b.MouseButton1Click:Connect(function()
				spec.click()
				tiles.refresh()
			end)
			table.insert(tiles.cells, c)
			c.look()
			return c
		end
		function tiles.refresh()
			for _, c in tiles.cells do
				c.look()
			end
		end
		return tiles
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

	-- A button that takes something away: red, with a trash can, so it's never mistaken for another one.
	-- opts.on(): lit up solid while it returns true (a brush that erases); opts.confirm: text shown after a first
	-- click, and only a second click within 3 seconds does it; opts.full: the row's whole width.
	-- Returns the button and a function that redraws it (after opts.on changes).
	local function dangerButton(text, onClick, opts)
		opts = opts or {}
		local b = new("TextButton", {
			Text = "",
			AutoButtonColor = false,
			Size = opts.full and UDim2.new(1, 0, 0, 32) or UDim2.fromOffset(0, 30),
			AutomaticSize = opts.full and Enum.AutomaticSize.None or Enum.AutomaticSize.X,
		}, { corner(8) })
		-- the trash can and the text in a row of their own: the glow's frames sit on the button itself, and must
		-- never be laid out with them (they'd push the row off the button's edge)
		local content = box({
			Size = opts.full and UDim2.fromScale(1, 1) or UDim2.new(0, 0, 1, 0),
			AutomaticSize = opts.full and Enum.AutomaticSize.None or Enum.AutomaticSize.X,
			Parent = b,
		}, {
			pad(10, 12, 0, 0),
			new("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				Padding = UDim.new(0, 6),
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		})
		local st = stroke(P.danger)
		st.Parent = b
		local ic = icon("trash", 14, P.danger)
		ic.LayoutOrder = 1
		ic.Parent = content
		local t = label(text, 13, P.danger, SANS_B, {
			Size = UDim2.fromOffset(0, 30),
			AutomaticSize = Enum.AutomaticSize.X,
			LayoutOrder = 2,
			Parent = content,
		})
		local lit = glow(b, 8, 0.7, P.danger)
		local hot, armed = false, 0
		local function look()
			local on = opts.on and opts.on()
			local fg = on and Color3.new(1, 1, 1) or P.danger
			b.BackgroundColor3 = on and P.danger or P.danger:Lerp(P.card, hot and 0.74 or 0.86)
			st.Color = P.danger:Lerp(P.card, on and 0 or 0.45)
			t.TextColor3 = fg
			setIconColor(ic, fg)
			lit:set(on == true)
		end
		look()
		b.MouseEnter:Connect(function()
			hot = true
			look()
		end)
		b.MouseLeave:Connect(function()
			hot = false
			look()
		end)
		pressable(b, 0.96)
		b.MouseButton1Click:Connect(function()
			if opts.confirm and os.clock() - armed > 3 then -- asks twice
				armed = os.clock()
				t.Text = opts.confirm
				task.delay(3, function()
					if os.clock() - armed >= 2.9 then
						t.Text = text
					end
				end)
				return
			end
			armed = 0
			t.Text = text
			onClick()
			look()
		end)
		return b, look
	end

	-- used by later modules
	App.new = new
	App.textSize = textSize
	App.TEXT_SIZES = TEXT_SIZES
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
	App.glass = glass
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
	App.dangerButton = dangerButton
	App.buttonRow = buttonRow
	App.hintOn = hintOn
	App.refreshSliders = refreshSliders
	App.slider = slider
	App.switch = switch
	App.switchRow = switchRow
	App.segmented = segmented
	App.icon = icon
	App.setIconColor = setIconColor
	App.stepLabel = stepLabel
	App.hintBox = hintBox
	App.keyChips = keyChips
	App.pageHead = pageHead
	App.chip = chip
	App.emptyState = emptyState
	App.captureKey = captureKey
	App.chipGrid = chipGrid
	App.toolTiles = toolTiles
	App.iconButton = iconButton
end
