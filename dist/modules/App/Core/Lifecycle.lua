--[[
	Smart Scatter — Lifecycle: undo/redo reload, wiring and cleanup.
	Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]

return function(App)
	local ChangeHistoryService, ctx, plugin, Engine, conns = App.ChangeHistoryService, App.ctx, App.plugin, App.Engine, App.conns
	local track, LAYER_MODES, toggleBtn, clearOverlay = App.track, App.LAYER_MODES, App.toggleBtn, App.clearOverlay
	local switchArea, eachThumb, closePopup, removeGizmo = App.switchArea, App.eachThumb, App.closePopup, App.removeGizmo
	local removeSplineViz = App.removeSplineViz

	local function alive(folder)
		return folder ~= nil and folder:IsDescendantOf(workspace)
	end

	-- Ctrl+Z / Ctrl+Y on anything Smart Scatter did: reload the area from its (restored) saved state and rebuild its
	-- objects from it (they're never in the undo history themselves; see the engine's generate)
	local function afterHistory()
		local f = App.area and App.area.folder
		local keep = App.expanded and Engine.layerKey(App.expanded)
		App.resetSplineDrag(true) -- a drag the undo just rolled back is dropped, not committed
		App.stopGestures()
		if LAYER_MODES[App.mode] then
			App.setMode("Off")
		end
		switchArea(alive(f) and f or Engine.listAreas()[1])
		if keep and App.area then
			for _, l in App.area.layers do
				if Engine.layerKey(l) == keep then
					App.expanded = l
				end
			end
			App.rebuildAll()
		end
		if App.canGenerate() then
			App.runGenerate(false)
		end
	end
	App.afterHistory = afterHistory -- (a jump along the history timeline runs it once, at the end)
	local function onHistory(name)
		local echoes = App.historyEchoes
		if echoes and echoes.rebuild > 0 then -- one step of a jump along the timeline: it rebuilds once, at its end
			echoes.rebuild -= 1
			return
		end
		if type(name) ~= "string" or not string.find(name, "Smart Scatter", 1, true) then
			return
		end
		task.defer(afterHistory)
	end
	track(ChangeHistoryService.OnUndo:Connect(onHistory))
	track(ChangeHistoryService.OnRedo:Connect(onHistory))

	--------------------------------------------------------------------------------
	-- Wiring
	--------------------------------------------------------------------------------
	track(toggleBtn.Click:Connect(function()
		App.widget.Enabled = not App.widget.Enabled
	end))
	track(App.widget:GetPropertyChangedSignal("Enabled"):Connect(function()
		toggleBtn:SetActive(App.widget.Enabled)
		if App.widget.Enabled then
			local f = App.area and App.area.folder
			switchArea(alive(f) and f or Engine.listAreas()[1])
			App.maybeStartTour()
		else
			if App.mode ~= "Off" then
				App.setMode("Off")
			end
			closePopup()
			clearOverlay()
			App.drawSpline()
		end
	end))

	switchArea(Engine.listAreas()[1])
	toggleBtn:SetActive(App.widget.Enabled)
	App.maybeStartTour()
	-- the loader found a newer release while you're working: ask before swapping it in
	ctx.offerUpdate = function(version, apply)
		App.dialog(
			"Update available",
			"Smart Scatter " .. tostring(version) .. " is ready. Updating takes a second, needs no restart and changes nothing in your place.",
			{ { "Update now", "accent", apply }, { "Later", nil, function() end } },
			"info",
			"accent"
		)
	end
	if ctx.reloaded then
		App.status("Updated to v" .. tostring(ctx.version) .. ".")
	end

	-- cleanup (called by the loader before a hot-reload or when the plugin unloads)
	return function()
		App.cancelJob() -- a running Generate belongs to this copy of the plugin: it stops with it
		pcall(App.stopGestures) -- closes any open stroke or drag recording
		if App.mode ~= "Off" then
			App.mode = "Off"
			pcall(function()
				plugin:Deactivate()
			end)
		end
		for _, c in conns do
			c:Disconnect()
		end
		removeGizmo()
		removeSplineViz()
		clearOverlay()
		if App.clearFocus then
			App.clearFocus()
		end
		if App.root then
			App.root:Destroy()
			App.root = nil
		end
		eachThumb(function(vp)
			vp:Destroy()
		end)
	end
end
