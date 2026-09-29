--[[
	Smart Scatter — Object tab: the active object (the one picked in the outliner or the Objects list). Its name and
	actions, then its rules, a card each; what was done to it by hand is one of them. Only there while an object is
	active.
	Runs once, in the order App/init.lua sets; shared state and cross-module functions live on App.
]]

return function(App)
	App.registerTab({
		id = "object",
		icon = "tag",
		title = "Object",
		order = 20,
		kinds = { Zone = true, Path = true },
		when = function(_, active)
			return active ~= nil
		end,
		build = function(page)
			App.objectInspector(page)
		end,
	})
end
