--[[
	Smart Scatter — History: the steps Smart Scatter took this session, as a timeline you can jump along (like
	ZBrush's undo history). Every step it records goes on the list; Ctrl+Z and Ctrl+Y move the marker with Studio;
	a jump undoes or redoes, one Studio step at a time, until the marker is where you clicked. Studio edits in
	between are undone and redone with them, as a timeline does.
	Studio doesn't let a plugin read its undo list, so the list is Smart Scatter's own; before each step of a jump
	it checks the name of the step Studio would undo or redo next, so the two never drift apart.
	Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]

return function(App)
	local CHS, track = App.ChangeHistoryService, App.track
	local MAX = 200 -- steps remembered (the oldest go first)

	-- App.history.list: { { name, time } }, oldest first; App.history.pos: how many of them are done (0 = none)
	App.history = { list = {}, pos = 0 }
	local H = App.history
	local function changed()
		if App.onHistoryChanged then
			App.onHistoryChanged()
		end
	end

	-- a step was recorded: it goes after the current one, and anything ahead (undone steps) is gone, as in Studio
	App.historyPush = function(name)
		for i = #H.list, H.pos + 1, -1 do
			table.remove(H.list, i)
		end
		table.insert(H.list, { name = name, time = os.time() })
		if #H.list > MAX then
			table.remove(H.list, 1)
		end
		H.pos = #H.list
		changed()
	end

	-- the name of the step Studio would undo (or redo) next, or nil when there's none
	local function nextName(redo)
		local ok, can, name = pcall(redo and CHS.GetCanRedo or CHS.GetCanUndo, CHS)
		if ok and can then
			return name or ""
		end
		return nil
	end

	-- Studio may fire OnUndo / OnRedo during the call or a moment after it (deferred events), so a jump counts the
	-- events its own undos and redos will cause, and each listener lets exactly that many pass: this one, and the
	-- plugin's rebuild after an undo (App.historyEchoes.rebuild, read by Core/Lifecycle)
	App.historyEchoes = { marker = 0, rebuild = 0 }
	local echoes = App.historyEchoes

	-- plain Ctrl+Z / Ctrl+Y: the marker follows when it was one of ours
	track(CHS.OnUndo:Connect(function(name)
		if echoes.marker > 0 then
			echoes.marker -= 1
		elseif H.pos > 0 and H.list[H.pos].name == name then
			H.pos -= 1
			changed()
		end
	end))
	track(CHS.OnRedo:Connect(function(name)
		if echoes.marker > 0 then
			echoes.marker -= 1
		elseif H.list[H.pos + 1] and H.list[H.pos + 1].name == name then
			H.pos += 1
			changed()
		end
	end))

	-- Goes to step `target` (0: before them all): undoes or redoes until the marker is there. Returns how many
	-- Studio steps it took.
	App.historyJump = function(target)
		target = math.clamp(target, 0, #H.list)
		if target == H.pos or App.historyJumping then
			return 0
		end
		App.historyJumping = true
		local steps, back = 0, target < H.pos
		for _ = 1, 400 do -- (a bound, whatever happens)
			if H.pos == target then
				break
			end
			local name = nextName(not back)
			if not name then -- Studio has nothing more that way: the rest of the list can't be reached
				if not back then
					for i = #H.list, H.pos + 1, -1 do
						table.remove(H.list, i)
					end
				end
				break
			end
			if back then
				-- a step of ours that never reached Studio (it changed nothing) is dropped, not waited for
				local j = H.pos
				while j > 0 and H.list[j].name ~= name do
					j -= 1
				end
				if j > 0 and j < H.pos and H.pos - j <= 3 then
					for i = H.pos, j + 1, -1 do
						table.remove(H.list, i)
					end
					target = math.min(target, #H.list)
					H.pos = j
				end
				if H.pos <= target then
					break
				end
				echoes.marker += 1
				echoes.rebuild += 1
				if not pcall(CHS.Undo, CHS) then
					echoes.marker -= 1
					echoes.rebuild -= 1
					break
				end
				if H.list[H.pos] and H.list[H.pos].name == name then
					H.pos -= 1
				end
			else
				echoes.marker += 1
				echoes.rebuild += 1
				if not pcall(CHS.Redo, CHS) then
					echoes.marker -= 1
					echoes.rebuild -= 1
					break
				end
				if H.list[H.pos + 1] and H.list[H.pos + 1].name == name then
					H.pos += 1
				end
			end
			steps += 1
		end
		App.historyJumping = false
		if steps > 0 and App.afterHistory then
			task.defer(App.afterHistory) -- one rebuild for the whole jump
		end
		changed()
		return steps
	end
end
