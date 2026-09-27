--[[
	Smart Scatter — Shapes: path shape presets (square, rectangle, triangle, hexagon, octagon, circle), for a fence
	round a field, a ring road or a plaza in one drag. Pick one on the Path card, then drag in the viewport: from the
	centre out (a corner follows the mouse and the turn snaps to 15°; Shift turns it freely), or corner to corner for the
	rectangle. The shape is a real closed curve of the path from the first move, so what shows while dragging is what
	you get, each corner on the ground under it. An empty path becomes the shape; otherwise it's a loop of its own in the
	same path (same width and objects). One shape per pick, then it's back to editing points, Blender style.
	The spline editor (Viewport/Spline) hands its mouse over while a shape is picked.
	Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]

return function(App)
	local Engine, beginRec, endRec, rawMouse = App.Engine, App.beginRec, App.endRec, App.rawMouse
	local MIN = 2 -- studs: a drag shorter than this places nothing
	local placing -- the shape being dragged: { kind, from, up, cv, rec, main, wasClosed, text }

	App.shapeTool = nil -- the picked preset's name, waiting for its drag

	local function refresh()
		if App.ui.refreshShapes then
			App.ui.refreshShapes()
		end
		if App.refreshFocus then
			App.refreshFocus()
		end
	end

	-- where the mouse points on the flat plane at the shape's height (steady, unlike the ground under a hill)
	local function onPlane(y)
		local ray = rawMouse.UnitRay
		if ray.Direction.Y < -1e-3 then
			local t = (y - ray.Origin.Y) / ray.Direction.Y
			if t > 0 then
				return ray.Origin + ray.Direction * t
			end
		end
		local hit = App.splinePointHit()
		return hit and hit.Position
	end
	-- a corner dropped onto the ground under it (reach grows with the shape, for hills); stays put over a drop-off
	local function ground(v, up, reach)
		local hit = Engine.cast(v + Vector3.new(0, reach, 0), Vector3.new(0, -reach * 3 - 50, 0), App.probeParams)
		if hit then
			return hit.Position, hit.Normal
		end
		return v, up
	end

	local function fill(to, free)
		local pl = placing
		local corners, smooth = Engine.shapePoints(pl.kind, pl.from, to, free)
		local dx, dz = to.X - pl.from.X, to.Z - pl.from.Z
		local size = math.sqrt(dx * dx + dz * dz)
		local pts = pl.cv.pts
		table.clear(pts)
		for _, c in corners do
			local p, n = ground(c, pl.up, 10 + size * 0.6)
			table.insert(pts, { p = p, n = n, sharp = not smooth or nil })
		end
		pl.size = size
		pl.text = pl.kind == "Rectangle" and string.format("Rectangle · %s × %s studs", App.num(math.abs(dx)), App.num(math.abs(dz)))
			or string.format("%s · %s studs across", pl.kind, App.num(size * 2))
	end

	-- takes the half-made shape back out of the path
	local function unplace(pl)
		local sp = App.area and App.area.spline
		if not sp then
			return
		end
		if pl.main then
			table.clear(sp.pts)
			sp.closed = pl.wasClosed
		else
			local i = table.find(sp.branches, pl.cv)
			if i then
				table.remove(sp.branches, i)
			end
		end
	end

	-- a pick on the Path card: arms that shape (the same pick again puts it away)
	App.pickShape = function(kind)
		if App.shapeTool == kind then
			App.cancelShape()
			return
		end
		if App.mode ~= "Spline" then
			App.ensureSplineFn()
			App.setMode("Spline")
			if App.mode ~= "Spline" then -- (a locked area)
				return
			end
		end
		App.cancelShape()
		App.shapeTool = kind
		App.selectSplinePoint(nil)
		refresh()
		App.status(
			kind == "Rectangle" and "Drag from one corner of the rectangle to the opposite one."
				or string.format("Drag from the centre of the %s outward. It turns in 15° steps; hold Shift to turn freely.", string.lower(kind))
		)
	end

	-- the spline editor's mouse, while a shape is picked
	App.shapeDown = function()
		local hit = App.splinePointHit()
		if not hit then
			return
		end
		local sp = App.ensureSplineFn()
		local main = #sp.pts == 0
		local cv = main and sp or { pts = {}, closed = true }
		placing = {
			kind = App.shapeTool,
			from = hit.Position,
			up = hit.Normal,
			cv = cv,
			main = main,
			wasClosed = sp.closed,
			rec = beginRec("Smart Scatter: " .. App.shapeTool),
			size = 0,
		}
		if main then
			sp.closed = true
		else
			table.insert(sp.branches, cv)
		end
	end
	App.shapeMove = function()
		if not placing then
			local hit = App.splinePointHit()
			App.splineLabel(
				hit,
				App.shapeTool == "Rectangle" and "Rectangle · drag from one corner to the other"
					or App.shapeTool .. " · drag from its centre outward"
			)
			return
		end
		local to = onPlane(placing.from.Y)
		if to then
			fill(to, App.shiftHeld())
			App.drawSpline()
		end
		App.splineLabel({ Position = to or placing.from }, placing.text or placing.kind)
	end
	App.shapeUp = function()
		local pl = placing
		placing = nil
		if not pl then
			return
		end
		if pl.size < MIN or #pl.cv.pts < 3 then -- a click, not a drag: nothing placed, the shape stays picked
			unplace(pl)
			endRec(pl.rec, true)
			App.drawSpline()
			App.status("Hold and drag to size the shape.")
			return
		end
		App.shapeTool = nil
		App.selectSplinePoint({ cv = pl.cv, i = 1 })
		App.commitSplineFn(pl.rec)
		refresh()
		App.status(
			pl.kind
				.. " placed. Drag a corner to move it, click an edge to add a point, "
				.. App.keyText("delete")
				.. " deletes one, and Subdivide adds one on every side."
		)
	end

	-- Esc, another mode, an area switch or an undo: a half-dragged shape is taken back and the pick put away
	App.cancelShape = function()
		local pl = placing
		placing = nil
		if pl then
			unplace(pl)
			endRec(pl.rec, true)
			if App.drawSpline then
				App.drawSpline()
			end
		end
		if App.shapeTool then
			App.shapeTool = nil
			refresh()
		end
	end
end
