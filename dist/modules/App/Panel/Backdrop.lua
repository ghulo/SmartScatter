--[[
	Smart Scatter — Backdrop: a few big, soft blobs of colour behind the panel (the accent and two neighbouring
	shades of it, so they follow the colour theme), wandering slowly round their spots and gently changing shape.
	They sit under everything, the page scrolls over them and they carry on across panel rebuilds; cards let a
	little of them through. The soft round shape is drawn in code once (EditableImage), so nothing is uploaded; where
	that's unavailable each blob is a few stacked see-through circles instead. Settings › Look turns them off.
	Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]

return function(App)
	local G, P, new = App.G, App.P, App.new
	local TweenService = game:GetService("TweenService")

	-- where each blob sits (its centre, as a share of the panel), how wide (a share of the panel's width), its colour
	-- (the accent turned round the colour wheel by `hue`, a little richer or brighter), and how far and how slowly
	-- it wanders. So the blobs are always the accent's own family: sage gives greens and teals, rose gives pinks.
	local BLOBS = {
		{ at = Vector2.new(0.95, 0.06), size = 1.15, hue = 0, sat = 1.15, val = 1.0, drift = Vector2.new(-0.08, 0.05), secs = 17 },
		{ at = Vector2.new(0.02, 0.48), size = 1.0, hue = 0.08, sat = 1.25, val = 0.95, drift = Vector2.new(0.07, -0.06), secs = 21 },
		{ at = Vector2.new(0.9, 0.92), size = 1.1, hue = -0.07, sat = 1.1, val = 1.05, drift = Vector2.new(-0.06, -0.05), secs = 19 },
	}
	local function shadeOf(b)
		local h, sa, v = P.accent:ToHSV()
		return Color3.fromHSV((h + b.hue) % 1, math.clamp(sa * b.sat, 0, 1), math.clamp(v * b.val, 0, 1))
	end
	local SIDE = 96 -- the soft circle's texture, in pixels

	-- a white disc whose edge fades out smoothly (false when EditableImage isn't available here)
	local soft
	local function softContent()
		if soft == nil then
			local ok, c = pcall(function()
				local img = game:GetService("AssetService"):CreateEditableImage({ Size = Vector2.new(SIDE, SIDE) })
				local buf = buffer.create(SIDE * SIDE * 4)
				local mid = (SIDE - 1) / 2
				for y = 0, SIDE - 1 do
					for x = 0, SIDE - 1 do
						local d = math.min(math.sqrt((x - mid) ^ 2 + (y - mid) ^ 2) / mid, 1)
						local a = (1 - d * d) ^ 2 -- full in the middle, gone at the rim, no hard edge anywhere
						local i = (y * SIDE + x) * 4
						buffer.writeu8(buf, i, 255)
						buffer.writeu8(buf, i + 1, 255)
						buffer.writeu8(buf, i + 2, 255)
						buffer.writeu8(buf, i + 3, math.floor(a * 255 + 0.5))
					end
				end
				img:WritePixelsBuffer(Vector2.zero, Vector2.new(SIDE, SIDE), buf)
				return Content.fromObject(img)
			end)
			soft = ok and c or false
		end
		return soft or nil
	end

	-- one blob: a soft disc, or (without the texture) five stacked circles that add up to about the same falloff
	local function blob(parent, color, strength)
		local holder = new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Active = false, Parent = parent }, {
			new("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Width }),
		})
		local c = softContent()
		local img = c
			and new("ImageLabel", {
				BackgroundTransparency = 1,
				Size = UDim2.fromScale(1, 1),
				ImageColor3 = color,
				ImageTransparency = 1 - strength,
				Active = false,
				Parent = holder,
			})
		if img and pcall(function()
			img.ImageContent = c
		end) then
			return holder
		elseif img then
			img:Destroy()
		end
		for k = 1, 5 do
			local s = 1 - (k - 1) * 0.18
			new("Frame", {
				BackgroundColor3 = color,
				BackgroundTransparency = 1 - strength / 3.2,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(s, s),
				Active = false,
				Parent = holder,
			}, { App.corner(9999) })
		end
		return holder
	end

	-- one blob wandering round its home: every few seconds it heads for a new spot near home, stretching a little
	-- one way or the other and turning as it goes, so it looks alive rather than sliding back and forth. It stops by
	-- itself when the blob is gone.
	local rng = Random.new()
	local function wander(h, b)
		local shape = h:FindFirstChildOfClass("UIAspectRatioConstraint")
		local reach = math.sqrt(b.drift.X ^ 2 + b.drift.Y ^ 2) * 1.5
		local function go()
			if not h.Parent then
				return
			end
			local a = rng:NextNumber(0, math.pi * 2)
			local r = reach * rng:NextNumber(0.35, 1)
			local toX, toY = b.at.X + math.cos(a) * r, b.at.Y + math.sin(a) * r
			local k = b.size * rng:NextNumber(0.92, 1.08)
			local info = TweenInfo.new(b.secs * rng:NextNumber(0.25, 0.45), Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
			local tw = TweenService:Create(h, info, {
				Position = UDim2.fromScale(toX, toY),
				Size = UDim2.fromScale(k, k),
				Rotation = h.Rotation + rng:NextNumber(-40, 40),
			})
			if shape then
				TweenService:Create(shape, info, { AspectRatio = rng:NextNumber(0.8, 1.25) }):Play()
			end
			tw.Completed:Connect(function(state)
				if state == Enum.PlaybackState.Completed then
					go()
				end
			end)
			tw:Play()
		end
		go()
	end

	-- the backdrop: the panel's background colour with the blobs on it, under everything in `widget`. It stays across
	-- panel rebuilds (so the blobs keep drifting rather than jumping back), and is made again only when the accent,
	-- the Studio theme or the switch changes. Returns true when it's there (the panel's own background then goes).
	local layer, made
	App.backdrop = function(widget)
		local light = settings().Studio.Theme.Name == "Light"
		local key = G.blobs ~= false and (P.accent:ToHex() .. (light and "L" or "D")) or "off"
		if layer and layer.Parent == widget and made == key then
			return key ~= "off"
		end
		if layer then
			layer:Destroy()
			layer = nil
		end
		for _, old in widget:GetChildren() do -- (one left by the plugin before it updated)
			if old.Name == "SS_Backdrop" then
				old:Destroy()
			end
		end
		made = key
		if key == "off" then
			return false
		end
		layer = new("Frame", {
			BackgroundTransparency = 0,
			BackgroundColor3 = P.bg,
			Size = UDim2.fromScale(1, 1),
			ClipsDescendants = true,
			Active = false,
			ZIndex = 0,
			Name = "SS_Backdrop",
			Parent = widget,
		})
		for _, b in BLOBS do
			local h = blob(layer, shadeOf(b), light and 0.2 or 0.3)
			h.Size = UDim2.fromScale(b.size, b.size)
			h.Position = UDim2.fromScale(b.at.X, b.at.Y)
			wander(h, b)
		end
		-- fading in when it's (re)made: a new accent washes over instead of snapping. Everything in it sits at ZIndex 0,
		-- under the panel whichever way the widget stacks its children.
		for _, d in layer:GetDescendants() do
			if d:IsA("GuiObject") then
				d.ZIndex = 0
			end
			if d:IsA("ImageLabel") then
				local t = d.ImageTransparency
				d.ImageTransparency = 1
				App.tween(d, TweenInfo.new(0.8, Enum.EasingStyle.Quad), { ImageTransparency = t })
			end
		end
		return true
	end

	-- whether the panel's surfaces let the blobs through a little
	App.blobsOn = function()
		return G.blobs ~= false
	end
end
