--[[
	Panel preview (a dev tool): dumps the preview panel (panel.lua) as it's laid out, every visible GuiObject in paint
	order with its rectangle, colours, corners, border, gradient, text and clipping, and posts it to server.py as
	out/<_G.SS_DumpName or "panel">.json for render.py. It also lists text that doesn't fit and things spilling out of
	what clips them. HttpService must be on for the call.
]]
local HS = game:GetService("HttpService")
local pv = _G.SS_Preview
assert(pv, "no preview running")
task.wait(0.7) -- (cards arriving and tabs sliding in settle first)
local gui = pv.app.widget
local out, issues = {}, {}
local function hex(c)
	return c and c:ToHex() or nil
end
local function cornerOf(o)
	local c = o:FindFirstChildOfClass("UICorner")
	if not c then
		return 0
	end
	local m = math.min(o.AbsoluteSize.X, o.AbsoluteSize.Y)
	return math.min(c.CornerRadius.Scale * m + c.CornerRadius.Offset, m / 2)
end
local function walk(o, fade, clip, path)
	if not o:IsA("GuiObject") then
		return
	end
	if not o.Visible then
		return
	end
	if o:IsA("CanvasGroup") then
		fade = 1 - (1 - fade) * (1 - o.GroupTransparency)
	end
	local p, s = o.AbsolutePosition, o.AbsoluteSize
	local rec = {
		t = o.ClassName,
		n = o.Name,
		x = math.floor(p.X + 0.5),
		y = math.floor(p.Y + 0.5),
		w = math.floor(s.X + 0.5),
		h = math.floor(s.Y + 0.5),
		bg = hex(o.BackgroundColor3),
		bt = 1 - (1 - o.BackgroundTransparency) * (1 - fade),
		r = cornerOf(o),
		clip = clip,
	}
	-- a gradient's transparency (the sheens, glass and fades): its average over the keypoints
	local g = o:FindFirstChildOfClass("UIGradient")
	if g and g.Enabled then
		local sum, n = 0, 0
		for _, k in g.Transparency.Keypoints do
			sum += k.Value
			n += 1
		end
		rec.bt = 1 - (1 - rec.bt) * (1 - (n > 0 and sum / n or 0))
		local c = g.Color.Keypoints[1] and g.Color.Keypoints[1].Value
		if c and rec.bg then -- (a tinted gradient: its first colour over the background)
			local b = o.BackgroundColor3
			rec.bg = hex(Color3.new(b.R * c.R, b.G * c.G, b.B * c.B))
		end
	end
	local st = o:FindFirstChildOfClass("UIStroke")
	if st and st.Enabled then
		rec.s, rec.st, rec.sw = hex(st.Color), 1 - (1 - st.Transparency) * (1 - fade), st.Thickness
	end
	if o:IsA("TextLabel") or o:IsA("TextButton") or o:IsA("TextBox") then
		local text = o.Text
		if o:IsA("TextBox") and text == "" then
			text = o.PlaceholderText
		end
		if text ~= "" and o.TextTransparency < 1 then
			rec.tx = text
			rec.tc = hex(o.TextColor3)
			rec.tt = 1 - (1 - o.TextTransparency) * (1 - fade)
			rec.ts = o.TextSize
			rec.tb = string.find(tostring(o.Font), "Bold") ~= nil or (o.FontFace and o.FontFace.Weight.Value >= 600)
			rec.ax = o.TextXAlignment.Name
			rec.ay = o.TextYAlignment.Name
			rec.wrap = o.TextWrapped
			if not o.TextFits and s.X > 4 and s.Y > 4 then
				table.insert(issues, "text cut: " .. path .. '  "' .. string.sub(text, 1, 40) .. '"')
			end
		end
	end
	if (o:IsA("ImageLabel") or o:IsA("ImageButton")) and o.Image ~= "" then
		rec.img = true
	end
	-- spilling out of what clips it
	if clip and s.X > 1 and s.Y > 1 and (p.X < clip[1] - 1 or p.Y < clip[2] - 1 or p.X + s.X > clip[3] + 1 or p.Y + s.Y > clip[4] + 1) then
		rec.out = true
	end
	if s.X > 0 and s.Y > 0 then
		table.insert(out, rec)
	end
	local c2 = clip
	if o.ClipsDescendants then
		local r = { p.X, p.Y, p.X + s.X, p.Y + s.Y }
		c2 = clip and { math.max(r[1], clip[1]), math.max(r[2], clip[2]), math.min(r[3], clip[3]), math.min(r[4], clip[4]) } or r
	end
	-- children in paint order: by ZIndex, then as they come
	local kids = {}
	for i, k in o:GetChildren() do
		if k:IsA("GuiObject") then
			table.insert(kids, { k, i })
		end
	end
	table.sort(kids, function(a, b)
		if a[1].ZIndex ~= b[1].ZIndex then
			return a[1].ZIndex < b[1].ZIndex
		end
		return a[2] < b[2]
	end)
	for _, k in kids do
		walk(k[1], fade, c2, path .. "/" .. k[1].Name)
	end
end
local tops = {}
for i, k in gui:GetChildren() do
	if k:IsA("GuiObject") then
		table.insert(tops, { k, i })
	end
end
table.sort(tops, function(a, b)
	if a[1].ZIndex ~= b[1].ZIndex then
		return a[1].ZIndex < b[1].ZIndex
	end
	return a[2] < b[2]
end)
local W, H = gui.AbsoluteSize.X, gui.AbsoluteSize.Y
for _, k in tops do
	walk(k[1], 0, { 0, 0, W, H }, k[1].Name)
end
local body = HS:JSONEncode({ w = W, h = H, items = out, issues = issues })
local ok, res = pcall(HS.PostAsync, HS, "http://127.0.0.1:8766/" .. (_G.SS_DumpName or "panel"), body)
return string.format("%d items, %d issues, post %s %s", #out, #issues, tostring(ok), tostring(res))
