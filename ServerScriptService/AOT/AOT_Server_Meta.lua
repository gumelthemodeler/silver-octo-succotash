-- @ScriptType: Script
-- @ScriptType: Script
-- AOT_Server_Meta (Optimized)
-- Place in: ServerScriptService > AOT > AOT_Server_Meta

local DataStoreService = game:GetService("DataStoreService")
local Players          = game:GetService("Players")
local RS               = game:GetService("ReplicatedStorage")
local AOTF             = RS:WaitForChild("AOT", 10)
local D                = require(AOTF:WaitForChild("AOT_Data"))
local S = require(script.Parent.Parent:WaitForChild("AOT_Sessions"))

local DS_ELO      = DataStoreService:GetOrderedDataStore("AOT_v1_LB_ELO")
local DS_KILLS    = DataStoreService:GetOrderedDataStore("AOT_v1_LB_Kills")
local DS_PRESTIGE = DataStoreService:GetOrderedDataStore("AOT_v1_LB_Prestige")
local DS_SNAP     = DataStoreService:GetDataStore("AOT_v1_LB_Snap")

local LEADERBOARD_TOP = 50
local FLUSH_INTERVAL  = 300
local cache = { elo = {}, kills = {}, prestige = {}, lastUpdate = 0 }

local function safeSet(ds, key, value) pcall(function() ds:SetAsync(key, value) end) end
local function safeGet(ds, key) local ok, val = pcall(function() return ds:GetAsync(key) end) return ok and val or nil end

local function orderedGetTop(ds, count)
	local ok, pages = pcall(function() return ds:GetSortedAsync(false, count) end)
	if not ok or not pages then return {} end
	local ok2, data = pcall(function() return pages:GetCurrentPage() end)
	return ok2 and data or {}
end

local function flushPlayer(pl)
	local d = S.sessions[pl.UserId]
	if not d then return end
	local uid = tostring(pl.UserId)

	safeSet(DS_ELO, uid, math.floor(d.pvpElo or 1000))
	safeSet(DS_KILLS, uid, math.floor(d.totalKills or 0))
	safeSet(DS_PRESTIGE, uid, math.floor(d.prestige or 0))

	safeSet(DS_SNAP, uid, {
		name = pl.Name, elo = d.pvpElo or 1000, kills = d.totalKills or 0, prestige = d.prestige or 0,
		clan = d.clan, title = D.GetPrestigeTitle(d.prestige or 0), path = d.path,
	})
end

local function refreshCache()
	local function buildBoard(ds, field)
		local rows, board = orderedGetTop(ds, LEADERBOARD_TOP), {}
		for rank, row in ipairs(rows) do
			local snap = safeGet(DS_SNAP, row.key) or {}
			table.insert(board, { rank = rank, userId = row.key, name = snap.name or ("Player " .. row.key), [field] = row.value, clan = snap.clan, title = snap.title or "Recruit", path = snap.path, prestige = snap.prestige or 0 })
		end
		return board
	end

	cache.elo, cache.kills, cache.prestige, cache.lastUpdate = buildBoard(DS_ELO, "elo"), buildBoard(DS_KILLS, "kills"), buildBoard(DS_PRESTIGE, "prestige"), os.time()
end

S.RF_GetLeaderboard.OnServerInvoke = function(pl, boardType)
	if os.time() - cache.lastUpdate > FLUSH_INTERVAL then refreshCache() end
	local board = cache[boardType] or cache.elo

	local uid, found = tostring(pl.UserId), false
	for _, row in ipairs(board) do if row.userId == uid then found = true break end end

	local result = {board = board}
	if not found and S.sessions[pl.UserId] then
		local d = S.sessions[pl.UserId]
		result.self = { userId = uid, name = pl.Name, [boardType] = math.floor((boardType == "elo" and d.pvpElo) or (boardType == "kills" and d.totalKills) or d.prestige or 0), clan = d.clan, title = D.GetPrestigeTitle(d.prestige or 0), path = d.path, prestige = d.prestige or 0, rank = "N/A" }
	end
	return result
end

local RE_Announce = AOTF:FindFirstChild("Remotes") and (AOTF.Remotes:FindFirstChild("AnnounceAll") or Instance.new("RemoteEvent", AOTF.Remotes))
if RE_Announce then
	RE_Announce.Name = "AnnounceAll"
	RE_Announce.OnServerEvent:Connect(function(pl, message)
		if not table.find(D.ADMIN_IDS or {}, pl.UserId) then return end
		for _, p in ipairs(Players:GetPlayers()) do S.Pop(p, "SERVER ANNOUNCEMENT", tostring(message), "amber") end
	end)
end

task.delay(8, function()
	if not D.UPDATE_LOG or #D.UPDATE_LOG == 0 then return end
	local latest = D.UPDATE_LOG[1]
	local lines = {"v" .. latest.version .. " — What's new:"}
	for _, entry in ipairs(latest.entries or {}) do table.insert(lines, "• " .. tostring(entry)) end
	local body = table.concat(lines, "\n")

	for _, p in ipairs(Players:GetPlayers()) do S.Pop(p, "UPDATE — v" .. latest.version, body, "amber") end
	Players.PlayerAdded:Connect(function(p) task.wait(3) S.Pop(p, "UPDATE — v" .. latest.version, body, "amber") end)
end)

task.spawn(function()
	task.wait(30)
	refreshCache()
	while true do
		task.wait(FLUSH_INTERVAL)
		for _, pl in ipairs(Players:GetPlayers()) do flushPlayer(pl) task.wait(0.2) end
		refreshCache()
	end
end)

Players.PlayerRemoving:Connect(flushPlayer)

print("[AOT_Server_Meta] Optimized Module Loaded.")