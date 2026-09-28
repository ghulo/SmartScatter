--[[
	Smart Scatter — Backdrop: a few big, soft blobs of colour behind the panel (the accent, a warm amber and a dusty
	rose), drifting very slowly. They sit under everything and stay put while the page scrolls over them; cards let a
	little of them through. The soft round shape is drawn in code once (EditableImage), so nothing is uploaded; where
	that's unavailable each blob is a few stacked see-through circles instead. Settings › Look turns them off.
	Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]

return function(App)
	local G, P, new = App.G, App.P, App.new
	local TweenService = game:GetService("TweenService")

	-- where each blob sits (its centre, as a share of the panel), how wide (a share of the panel's width), its
	-- colour, and how far and how slowly it wanders
	local BLOBS = {
		{ at = Vector2.new(0.95, 0.06), size = 1.15, color = "accent", drift = Vector2.new(-0.08, 0.05), secs = 17 },
		{ at = Vector2.new(0.02, 0.48), size = 1.0, color = Color3.fromHex("E3A857"), drift = Vector2.new(0.07, -0.06), secs = 21 },
		{ at = Vector2.new(0.9, 0.92), size = 1.1, color = Color3.fromHex("D98C9A"), drift = Vector2.new(-0.06, -0.05), secs = 19 },
	}
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

	-- the blobs behind `root` (under everything in it); nothing when they're turned off
	App.backdrop = function(root)
		if G.blobs == false then
			return
		end
		local light = settings().Studio.Theme.Name == "Light"
		local layer = new("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ClipsDescendants = true,
			Active = false,
			ZIndex = 0,
			Parent = root,
		})
		for _, b in BLOBS do
			local color = b.color == "accent" and P.accent or b.color
			local h = blob(layer, color, light and 0.2 or 0.3)
			h.Size = UDim2.fromScale(b.size, b.size)
			h.Position = UDim2.fromScale(b.at.X, b.at.Y)
			local to = b.at + b.drift
			TweenService
				:Create(
					h,
					TweenInfo.new(b.secs, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
					{ Position = UDim2.fromScale(to.X, to.Y) }
				)
				:Play()
		end
		return layer
	end

	-- whether the panel's surfaces let the blobs through a little
	App.blobsOn = function()
		return G.blobs ~= false
	end
end
