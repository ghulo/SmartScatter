--[[
	Just enough of Roblox for the engine's pure logic to run outside Studio (tools/offline.py puts this first).
	Vectors are real (the math under test depends on them); everything else is an inert stand-in that fails loudly if
	a test reaches code that needs Studio.
]]

local function studioOnly(name)
	return setmetatable({}, {
		__index = function(_, k)
			error(name .. "." .. tostring(k) .. " needs Studio (not available offline)", 2)
		end,
	})
end

-- Vector3 --------------------------------------------------------------------
local V3 = {}
V3.__index = function(v, k)
	if k == "Magnitude" then
		return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
	elseif k == "Unit" then
		local m = math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
		return m > 0 and Vector3.new(v.X / m, v.Y / m, v.Z / m) or Vector3.new(0, 0, 0)
	end
	return V3[k]
end
local function v3(x, y, z)
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V3)
end
V3.__add = function(a, b)
	return v3(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
V3.__sub = function(a, b)
	return v3(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
V3.__mul = function(a, b)
	if type(a) == "number" then
		return v3(a * b.X, a * b.Y, a * b.Z)
	elseif type(b) == "number" then
		return v3(a.X * b, a.Y * b, a.Z * b)
	end
	return v3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V3.__div = function(a, b)
	return type(b) == "number" and v3(a.X / b, a.Y / b, a.Z / b) or v3(a.X / b.X, a.Y / b.Y, a.Z / b.Z)
end
V3.__unm = function(a)
	return v3(-a.X, -a.Y, -a.Z)
end
V3.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y and a.Z == b.Z
end
V3.__tostring = function(a)
	return string.format("%g, %g, %g", a.X, a.Y, a.Z)
end
function V3.Dot(a, b)
	return a.X * b.X + a.Y * b.Y + a.Z * b.Z
end
function V3.Cross(a, b)
	return v3(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X)
end
function V3.Lerp(a, b, t)
	return a + (b - a) * t
end
Vector3 = { new = v3, zero = v3(0, 0, 0), one = v3(1, 1, 1), xAxis = v3(1, 0, 0), yAxis = v3(0, 1, 0), zAxis = v3(0, 0, 1) }

-- Vector2 --------------------------------------------------------------------
local V2 = {}
V2.__index = function(v, k)
	if k == "Magnitude" then
		return math.sqrt(v.X * v.X + v.Y * v.Y)
	elseif k == "Unit" then
		local m = math.sqrt(v.X * v.X + v.Y * v.Y)
		return m > 0 and Vector2.new(v.X / m, v.Y / m) or Vector2.new(0, 0)
	end
	return V2[k]
end
local function v2(x, y)
	return setmetatable({ X = x or 0, Y = y or 0 }, V2)
end
V2.__add = function(a, b)
	return v2(a.X + b.X, a.Y + b.Y)
end
V2.__sub = function(a, b)
	return v2(a.X - b.X, a.Y - b.Y)
end
V2.__mul = function(a, b)
	if type(a) == "number" then
		return v2(a * b.X, a * b.Y)
	end
	return type(b) == "number" and v2(a.X * b, a.Y * b) or v2(a.X * b.X, a.Y * b.Y)
end
function V2.Dot(a, b)
	return a.X * b.X + a.Y * b.Y
end
Vector2 = { new = v2, zero = v2(0, 0) }

-- Random: a small seeded generator (not Roblox's sequence; tests only rely on it being repeatable)
local R = {}
R.__index = R
function R:NextNumber(lo, hi)
	self.s = (self.s * 1103515245 + 12345) % 2147483648
	local t = self.s / 2147483648
	return lo and (lo + (hi - lo) * t) or t
end
function R:NextInteger(lo, hi)
	return math.min(hi, lo + math.floor(self:NextNumber() * (hi - lo + 1)))
end
Random = {
	new = function(seed)
		return setmetatable({ s = math.floor(seed or 1) % 2147483648 }, R)
	end,
}

-- the rest: stand-ins -------------------------------------------------------------
-- Color3 -----------------------------------------------------------------------
-- real colour maths (the seasons are tested through it): lerping and HSV, as Roblox does them
local C3 = {}
C3.__index = C3
local function c3(r, g, b)
	return setmetatable({ R = r, G = g, B = b }, C3)
end
C3.__eq = function(a, b)
	return a.R == b.R and a.G == b.G and a.B == b.B
end
function C3.Lerp(a, b, t)
	return c3(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
end
function C3.ToHSV(c)
	local mx, mn = math.max(c.R, c.G, c.B), math.min(c.R, c.G, c.B)
	local d, h = mx - mn, 0
	if d > 0 then
		if mx == c.R then
			h = ((c.G - c.B) / d) % 6
		elseif mx == c.G then
			h = (c.B - c.R) / d + 2
		else
			h = (c.R - c.G) / d + 4
		end
		h /= 6
	end
	return h, mx > 0 and d / mx or 0, mx
end
Color3 = {
	new = c3,
	fromRGB = function(r, g, b)
		return c3(r / 255, g / 255, b / 255)
	end,
	fromHex = function()
		return c3(0, 0, 0)
	end,
	fromHSV = function(h, s, v)
		local i = math.floor(h * 6) % 6
		local f = h * 6 - math.floor(h * 6)
		local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
		local row = ({ { v, t, p }, { q, v, p }, { p, v, t }, { p, q, v }, { t, p, v }, { v, p, q } })[i + 1]
		return c3(row[1], row[2], row[3])
	end,
}
-- any Enum.X.Y is a unique marker, so tables keyed by materials still work
Enum = setmetatable({}, {
	__index = function(t, group)
		local g = setmetatable({}, {
			__index = function(gt, item)
				local v = { Name = item, EnumType = group }
				rawset(gt, item, v)
				return v
			end,
		})
		rawset(t, group, g)
		return g
	end,
})
local services = {
	-- an empty ServerStorage: no live mirror of the plugin's code (the flattened engine looks there for a missing part)
	ServerStorage = {
		FindFirstChild = function()
			return nil
		end,
	},
}
game = {
	GetService = function(_, name)
		services[name] = services[name] or studioOnly(name)
		return services[name]
	end,
}
workspace = studioOnly("workspace")
Instance = studioOnly("Instance")
RaycastParams = studioOnly("RaycastParams")
OverlapParams = studioOnly("OverlapParams")
CFrame = studioOnly("CFrame")
