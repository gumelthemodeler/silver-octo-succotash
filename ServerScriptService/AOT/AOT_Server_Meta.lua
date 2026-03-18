-- @ScriptType: Script
-- AOT_Server_Meta  (Script — NOT a ModuleScript)
-- Place in: ServerScriptService > AOT > AOT_Server_Meta
-- Handles:
--   • Global OrderedDataStore leaderboard (top-N by ELO, totalKills, prestige)
--   • Periodic leaderboard snapshots written every 5 minutes
--   • Server-startup global announcement (version + update log)
--   • RF_GetLeaderboard  → returns top-N records for the requested board
--   • RE_AnnounceAll     → admin-only broadcast (userId whitelist in D.ADMIN_IDS)
--   • Server uptime + player-count heartbeat (for analytics / monitoring)

local DataStoreService = game:GetService("DataStoreService")
local Players          = game:GetService("Players")
local RS               = game:GetService("ReplicatedStorage")
local RunService       = game:GetService("RunService")
local AOTF             = RS:WaitForChild("AOT", 10)
local D                = require(AOTF:WaitForChild("AOT_Data"))
local S                = require(script.Parent:WaitForChild("AOT_Sessions"))

-- ── DataStores ─────────────────────────────────────────────────────────────
-- Ordered stores: value = sort key (integer); key = userId string
local DS_ELO      = DataStoreService:GetOrderedDataStore("AOT_v1_LB_ELO")
local DS_KILLS    = DataStoreService:GetOrderedDataStore("AOT_v1_LB_Kills")
local DS_PRESTIGE = DataStoreService:GetOrderedDataStore("AOT_v1_LB_Prestige")

-- Regular store: maps userId → snapshot {name, elo, kills, prestige, ...}
local DS_SNAP     = DataStoreService:GetDataStore("AOT_v1_LB_Snap")

local LEADERBOARD_TOP = 50   -- how many entries we pull per board
local FLUSH_INTERVAL  = 300  -- seconds between full leaderboard flushes (5 min)
local ANNOUNCE_DELAY  = 8    -- seconds after server start before broadcasting update log

-- ── In-memory cache for RF_GetLeaderboard ─────────────────────────────────
-- Refreshed each flush cycle; served instantly to clients on request.
local cache = {
	elo      = {},
	kills    = {},
	prestige = {},
	lastUpdate = 0,
}

-- ── Helpers ────────────────────────────────────────────────────────────────
local function safeSet(ds, key, value)
	local ok, err = pcall(function() ds:SetAsync(key, value) end)
	if not ok then warn("[Meta] DataStore write failed: " .. tostring(err)) end
end

local function safeGet(ds, key)
	local ok, val = pcall(function() return ds:GetAsync(key) end)
	if ok then return val end
	warn("[Meta] DataStore read failed: " .. tostring(key))
	return nil
end

local function orderedGetTop(ds, count)
	local ok, pages = pcall(function()
		return ds:GetSortedAsync(false, count)  -- descending
	end)
	if not ok or not pages then return {} end
	local ok2, data = pcall(function() return pages:GetCurrentPage() end)
	if not ok2 then return {} end
	return data  -- array of {key=userId, value=sortKey}
end

-- ── Flush one player's stats to the ordered stores ─────────────────────────
local function flushPlayer(pl)
	local d = S.sessions[pl.UserId]
	if not d then return end
	local uid = tostring(pl.UserId)

	-- Write sort keys
	safeSet(DS_ELO,      uid, math.floor(d.pvpElo or 1000))
	safeSet(DS_KILLS,    uid, math.floor(d.totalKills or 0))
	safeSet(DS_PRESTIGE, uid, math.floor(d.prestige or 0))

	-- Write snapshot (name + display fields)
	local snap = {
		name     = pl.Name,
		elo      = d.pvpElo or 1000,
		kills    = d.totalKills or 0,
		prestige = d.prestige or 0,
		clan     = d.clan,
		title    = D.GetPrestigeTitle and D.GetPrestigeTitle(d.prestige or 0) or "Recruit",
		path     = d.path,
	}
	safeSet(DS_SNAP, uid, snap)
end

-- ── Refresh in-memory leaderboard cache ────────────────────────────────────
local function refreshCache()
	local function buildBoard(ds, field)
		local rows = orderedGetTop(ds, LEADERBOARD_TOP)
		local board = {}
		for rank, row in ipairs(rows) do
			local snap = safeGet(DS_SNAP, row.key) or {}
			table.insert(board, {
				rank     = rank,
				userId   = row.key,
				name     = snap.name or ("Player " .. row.key),
				[field]  = row.value,
				clan     = snap.clan,
				title    = snap.title or "Recruit",
				path     = snap.path,
				prestige = snap.prestige or 0,
			})
		end
		return board
	end

	cache.elo      = buildBoard(DS_ELO,      "elo")
	cache.kills    = buildBoard(DS_KILLS,    "kills")
	cache.prestige = buildBoard(DS_PRESTIGE, "prestige")
	cache.lastUpdate = os.time()
end

-- ── RF_GetLeaderboard ──────────────────────────────────────────────────────
-- Client calls:  RF_GetLeaderboard:InvokeServer("elo" | "kills" | "prestige")
-- Returns: array of top-N entries from cache
S.RF_GetLeaderboard.OnServerInvoke = function(pl, boardType)
	-- Serve cache; if stale (>5 min old), refresh synchronously on next request
	if os.time() - cache.lastUpdate > FLUSH_INTERVAL then
		refreshCache()
	end
	local board = cache[boardType] or cache.elo
	-- Inject the requesting player's own rank if they're not in top-N
	local uid = tostring(pl.UserId)
	local found = false
	for _, row in ipairs(board) do
		if row.userId == uid then found = true break end
	end
	local result = {board = board}
	if not found then
		local d = S.sessions[pl.UserId]
		if d then
			local myVal = boardType == "elo" and d.pvpElo
				or boardType == "kills" and d.totalKills
				or d.prestige or 0
			result.self = {
				userId   = uid,
				name     = pl.Name,
				[boardType] = math.floor(myVal or 0),
				clan     = d.clan,
				title    = D.GetPrestigeTitle and D.GetPrestigeTitle(d.prestige or 0) or "Recruit",
				path     = d.path,
				prestige = d.prestige or 0,
				rank     = "N/A",
			}
		end
	end
	return result
end

-- ── RE_AnnounceAll  (admin only) ───────────────────────────────────────────
-- A server admin fires this with a message; it broadcasts to all players.
local RE_Announce = (function()
	local Rem = AOTF:FindFirstChild("Remotes")
	if Rem then
		local r = Rem:FindFirstChild("AnnounceAll") or Instance.new("RemoteEvent")
		r.Name = "AnnounceAll"
		r.Parent = Rem
		return r
	end
end)()

if RE_Announce then
	RE_Announce.OnServerEvent:Connect(function(pl, message)
		-- Whitelist check
		local isAdmin = false
		if D.ADMIN_IDS then
			for _, id in ipairs(D.ADMIN_IDS) do
				if id == pl.UserId then isAdmin = true break end
			end
		end
		if not isAdmin then
			S.Msg(pl, "You are not an admin.", "system") return
		end
		for _, p in ipairs(Players:GetPlayers()) do
			S.Pop(p, "SERVER ANNOUNCEMENT", tostring(message), "amber")
			S.Msg(p, "[ADMIN] " .. tostring(message), "system")
		end
	end)
end

-- ── Update log broadcast on server start ──────────────────────────────────
task.delay(ANNOUNCE_DELAY, function()
	if not D.UPDATE_LOG or #D.UPDATE_LOG == 0 then return end
	local latest = D.UPDATE_LOG[1]  -- most recent entry is first
	if not latest then return end
	local lines = {"v" .. latest.version .. " — What's new:"}
	for _, entry in ipairs(latest.entries or {}) do
		table.insert(lines, "• " .. tostring(entry))
	end
	local body = table.concat(lines, "\n")
	for _, p in ipairs(Players:GetPlayers()) do
		S.Pop(p, "UPDATE — v" .. latest.version, body, "amber")
	end
	-- Also broadcast to anyone who joins later in this session
	Players.PlayerAdded:Connect(function(p)
		task.wait(3)  -- give them time to fully load
		S.Pop(p, "UPDATE — v" .. latest.version, body, "amber")
	end)
end)

-- ── Periodic leaderboard flush loop ───────────────────────────────────────
task.spawn(function()
	-- Initial refresh shortly after server start (avoid hammering DS at boot)
	task.wait(30)
	refreshCache()

	while true do
		task.wait(FLUSH_INTERVAL)
		-- Flush all online players
		for _, pl in ipairs(Players:GetPlayers()) do
			flushPlayer(pl)
			task.wait(0.2)   -- space out writes to stay within DS rate limits
		end
		refreshCache()
	end
end)

-- Also flush each player when they leave (catch final stats)
Players.PlayerRemoving:Connect(function(pl)
	flushPlayer(pl)
end)

-- ── Uptime heartbeat (optional analytics / server health) ─────────────────
-- Prints to server output every 10 minutes so you can see the server is alive.
local startTime = os.time()
task.spawn(function()
	while true do
		task.wait(600)
		local upMin = math.floor((os.time() - startTime) / 60)
		local pc    = #Players:GetPlayers()
		print(string.format("[AOT_Meta] Uptime: %dm | Players: %d | LB last refresh: %ds ago",
			upMin, pc, os.time() - cache.lastUpdate))
	end
end)

-- ── Note: add these to AOT_Sessions if not already present ────────────────
-- S.RE_RaidState  = RE("RaidState")
-- S.RE_RaidStart  = RE("RaidStart")
-- S.RE_RaidAction = RE("RaidAction")
-- S.RE_RaidShift  = RE("RaidShift")
