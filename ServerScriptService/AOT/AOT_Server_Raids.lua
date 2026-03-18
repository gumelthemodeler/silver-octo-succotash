-- @ScriptType: ModuleScript
-- AOT_Server_Raids  (ModuleScript)
-- Place in: ServerScriptService > AOT > AOT_Server_Raids
-- Handles: party formation, invite/accept, shared raid HP, multi-player turn order,
--          per-player combat contributions, reward distribution.
--
-- Raid party structure (stored in S.raidParties[partyId]):
--   partyId     : string  -- tostring(leaderUserId)
--   raidId      : string  -- e.g. "raid_female"
--   leader      : Player
--   members     : {Player, ...}  -- ordered; leader is members[1]
--   turnIndex   : number         -- which member index acts next
--   state       : "lobby" | "active" | "finished"
--   -- Shared enemy state:
--   enemyHp     : number
--   enemyMaxHp  : number
--   enemyAtk    : number
--   enemyRegen  : number
--   enemyName   : string
--   behavior    : string
--   telegraphed : bool           -- beast/telegraph wind-up flag
--   stunned     : bool
--   burnTurns   : number
--   -- Per-player contribution tracking:
--   damage      : {[userId]=number}
--   turnOf      : Player         -- derived from members[turnIndex]

local Players = game:GetService("Players")
local RS      = game:GetService("ReplicatedStorage")
local AOTF    = RS:WaitForChild("AOT", 10)
local D       = require(AOTF:WaitForChild("AOT_Data"))
local S       = require(script.Parent:WaitForChild("AOT_Sessions"))

local Raids = {}

-- ── Constants ──────────────────────────────────────────────────────────────
local MAX_PARTY   = 4   -- max players per raid
local INVITE_TTL  = 30  -- seconds an invite stays open

-- ── Helpers ────────────────────────────────────────────────────────────────
local function partyId(leader)
	return tostring(leader.UserId)
end

local function getParty(leader)
	return S.raidParties[partyId(leader)]
end

local function getPartyByMember(pl)
	for _, party in pairs(S.raidParties) do
		for _, m in ipairs(party.members) do
			if m == pl then return party end
		end
	end
	return nil
end

local function broadcastParty(party, msg, t)
	for _, m in ipairs(party.members) do
		S.Msg(m, msg, t or "system")
	end
end

local function broadcastPartyPop(party, title, body, color)
	for _, m in ipairs(party.members) do
		S.Pop(m, title, body, color or "amber")
	end
end

-- Build and push a shared raid state payload to all members.
-- Each member also receives their own personal state (for HP display, buffs, etc.).
local function pushRaidState(party)
	local payload = {
		isRaid       = true,
		partyId      = party.partyId,
		raidId       = party.raidId,
		memberNames  = {},
		turnOf       = party.members[party.turnIndex] and party.members[party.turnIndex].Name or "",
		enemyHp      = party.enemyHp,
		enemyMaxHp   = party.enemyMaxHp,
		enemyName    = party.enemyName,
		enemyAtk     = party.enemyAtk,
		telegraphed  = party.telegraphed,
		stunned      = party.stunned,
		raidState    = party.state,
		damage       = party.damage,
	}
	for _, m in ipairs(party.members) do
		table.insert(payload.memberNames, m.Name)
	end
	-- Fire dedicated raid-state remote to each member
	S.RE_RaidState:FireAllClients(payload)
	-- Also push personal state (HP, inventory, etc.) for each member
	for _, m in ipairs(party.members) do
		local d = S.sessions[m.UserId]
		if d then S.Push(m, d) end
	end
end

-- Scale enemy stats for the party size and average prestige.
local function scaleEnemy(baseEnemy, memberCount, avgPrestige)
	local hpScale  = 1 + (memberCount - 1) * 0.70   -- +70% HP per extra member
	local atkScale = 1 + (avgPrestige or 0) * 0.18
	return {
		hp    = math.floor(baseEnemy.baseHp  * hpScale),
		atk   = math.floor(baseEnemy.baseAtk * atkScale),
		regen = math.floor((baseEnemy.regen  or 0) * hpScale),
		name  = baseEnemy.name,
		xp    = baseEnemy.xp,
		funds = baseEnemy.funds,
		behavior = baseEnemy.behavior,
	}
end

-- ── Enemy action (fires after the current member acts) ────────────────────
-- Returns the damage dealt to the acting player this round.
local function enemyTurn(party, targetPlayer, targetData)
	if party.stunned then
		party.stunned = false
		broadcastParty(party, "★ " .. party.enemyName .. " is stunned and loses its turn!", "combat")
		return 0
	end

	-- Telegraph behaviour: warn this turn, attack double next turn
	if party.behavior == "telegraph" and not party.telegraphed then
		party.telegraphed = true
		broadcastParty(party, "⚠ " .. party.enemyName .. " is winding up a powerful attack!", "combat")
		return 0
	end

	local mult = 1
	if party.telegraphed then
		mult = 2
		party.telegraphed = false
	end
	if party.behavior == "aberrant" and math.random() < 0.25 then
		broadcastParty(party, party.enemyName .. " moves erratically and skips its turn!", "combat")
		return 0
	end

	local raw = math.floor(party.enemyAtk * mult)
	-- Divide attack among all members (shared aggro model), targeting the actor
	local dmg = math.max(1, raw - math.floor(S.CalcCS(targetData).def * 0.6))

	-- Apply burn
	if party.burnTurns and party.burnTurns > 0 then
		local burnDmg = math.floor(party.enemyMaxHp * 0.04)
		party.enemyHp = math.max(0, party.enemyHp - burnDmg)
		party.burnTurns = party.burnTurns - 1
		broadcastParty(party, party.enemyName .. " burns for " .. burnDmg .. " damage.", "combat")
	end

	-- Armored behaviour: reduce damage taken from ALL members
	if party.behavior == "armored" then
		dmg = math.floor(dmg * 0.75)
	end

	targetData.hp = math.max(0, targetData.hp - dmg)
	broadcastParty(party, party.enemyName .. " attacks " .. targetPlayer.Name .. " for " .. dmg .. " damage!", "combat")

	-- Crawler: apply slow to the targeted member
	if party.behavior == "crawler" then
		targetData.playerSlowTurns = (targetData.playerSlowTurns or 0) + 2
		S.Msg(targetPlayer, party.enemyName .. " slows you!", "combat")
	end

	return dmg
end

-- ── Award raid rewards to all living members ──────────────────────────────
local function distributeRewards(party, raidDef)
	for _, m in ipairs(party.members) do
		local d = S.sessions[m.UserId]
		if not d then continue end

		local contrib     = (party.damage[m.UserId] or 0) / math.max(1, party.enemyMaxHp)
		local contribMult = 0.5 + contrib  -- minimum 50%, scales to 150% at full dmg

		-- XP and funds split with contribution weight
		local cs    = S.CalcCS(d)
		local xp    = math.floor(raidDef.xp    * contribMult * cs.xpMult   * cs.streakMult)
		local funds = math.floor(raidDef.funds  * contribMult * cs.fundMult)

		S.AwardXP(m, d, xp, cs)
		d.funds      = (d.funds or 0) + funds
		d.totalKills = (d.totalKills or 0) + 1
		d.bossKills  = (d.bossKills  or 0) + 1

		-- Record raid high score (best contribution %)
		d.raidHighScores = d.raidHighScores or {}
		local prev = d.raidHighScores[raidDef.id] or 0
		if contrib > prev then
			d.raidHighScores[raidDef.id] = contrib
		end

		-- Unlock this raid's chapter reward if first clear
		d.raidUnlocks = d.raidUnlocks or {}
		d.raidUnlocks[raidDef.id] = true

		-- Drop roll (each member gets their own roll)
		local drop = D.RollDrop("boss")
		if drop and D.ITEM_MAP[drop] then
			table.insert(d.inventory, {id=drop, forgeLevel=0})
			S.Msg(m, "★ Drop: " .. D.ITEM_MAP[drop].name
				.. " [" .. D.ITEM_MAP[drop].rarity .. "]", "reward")
		elseif drop then
			d.consumables = d.consumables or {}
			d.consumables[drop] = (d.consumables[drop] or 0) + 1
			S.Msg(m, "★ Material: " .. drop, "reward")
		end

		-- Challenge progress
		S.BumpChallenge(m, d, "bossKill",  1)
		S.BumpChallenge(m, d, "raidClear", 1)
		S.CheckAchievements(m, d)

		local pct = math.floor(contrib * 100)
		S.Msg(m, string.format(
			"Raid complete!  Contribution: %d%%  |  +%d XP  |  +%d Funds",
			pct, xp, funds), "reward")
		S.Save(m.UserId, d)
	end
end

-- ── Advance turn pointer to next living member ────────────────────────────
local function advanceTurn(party)
	local count = #party.members
	local start = party.turnIndex
	for i = 1, count do
		local next = (start + i - 1) % count + 1
		local m = party.members[next]
		local d = m and S.sessions[m.UserId]
		if d and d.hp > 0 then
			party.turnIndex = next
			return m
		end
	end
	return nil  -- everyone is dead
end

-- ── Check win/loss ────────────────────────────────────────────────────────
local function checkEndCondition(party, raidDef)
	-- Win: enemy dead
	if party.enemyHp <= 0 then
		party.state = "finished"
		broadcastPartyPop(party, "RAID CLEAR!", party.enemyName .. " has been defeated!", "amber")
		distributeRewards(party, raidDef)
		S.raidParties[party.partyId] = nil
		return true
	end
	-- Loss: all members at 0 HP
	local allDead = true
	for _, m in ipairs(party.members) do
		local d = S.sessions[m.UserId]
		if d and d.hp > 0 then allDead = false break end
	end
	if allDead then
		party.state = "finished"
		broadcastPartyPop(party, "RAID FAILED", "All soldiers have fallen.", "red")
		for _, m in ipairs(party.members) do
			local d = S.sessions[m.UserId]
			if d then
				d.hp = 1   -- leave at 1 so they can resume solo play
				d.inCombat = false
				d.awaitingTurn = false
				S.Push(m, d)
			end
		end
		S.raidParties[party.partyId] = nil
		return true
	end
	return false
end

-- ── Regen tick at end of enemy turn ──────────────────────────────────────
local function enemyRegen(party)
	if party.enemyHp > 0 and party.enemyRegen and party.enemyRegen > 0 then
		local regen = math.min(party.enemyRegen, party.enemyMaxHp - party.enemyHp)
		if regen > 0 then
			party.enemyHp = party.enemyHp + regen
			broadcastParty(party, party.enemyName .. " regenerates " .. regen .. " HP.", "combat")
		end
	end
end

-- ══════════════════════════════════════════════════════════════════════════
-- REMOTE HANDLERS
-- ══════════════════════════════════════════════════════════════════════════

-- RE_RaidInvite  (leader → invite a target player to their party)
S.RE_RaidInvite.OnServerEvent:Connect(function(leader, targetPlayer, raidId)
	local d = S.sessions[leader.UserId]
	if not d then return end
	if d.inCombat then S.Msg(leader, "Finish your current battle first.", "system") return end

	-- Validate raid unlock
	local raidDef
	for _, r in ipairs(D.RAIDS) do if r.id == raidId then raidDef = r break end end
	if not raidDef then S.Msg(leader, "Unknown raid.", "system") return end
	if not (d.raidUnlocks or {})[raidId] then
		S.Msg(leader, "You haven't unlocked " .. raidDef.name .. " yet.", "system") return
	end

	-- Create or fetch party
	local party = getParty(leader)
	if not party then
		party = {
			partyId    = partyId(leader),
			raidId     = raidId,
			leader     = leader,
			members    = {leader},
			turnIndex  = 1,
			state      = "lobby",
			enemyHp    = 0, enemyMaxHp=0, enemyAtk=0, enemyRegen=0,
			enemyName  = "", behavior="", telegraphed=false, stunned=false,
			burnTurns  = 0,
			damage     = {},
		}
		S.raidParties[party.partyId] = party
	end

	if #party.members >= MAX_PARTY then
		S.Msg(leader, "Party is full (" .. MAX_PARTY .. " max).", "system") return
	end

	-- Validate target
	local td = S.sessions[targetPlayer.UserId]
	if not td then S.Msg(leader, targetPlayer.Name .. " is not in-game.", "system") return end
	if td.inCombat then S.Msg(leader, targetPlayer.Name .. " is in combat.", "system") return end
	if getPartyByMember(targetPlayer) then
		S.Msg(leader, targetPlayer.Name .. " is already in a party.", "system") return end

	-- Store invite
	S.pendingInvites[targetPlayer.UserId] = {
		from      = leader,
		partyId   = party.partyId,
		raidId    = raidId,
		expiresAt = os.time() + INVITE_TTL,
	}

	S.Msg(targetPlayer, leader.Name .. " invites you to: " .. raidDef.name
		.. "  |  Use RE_RaidInviteResp to accept/decline.", "system")
	S.Pop(targetPlayer, "RAID INVITE", leader.Name .. " → " .. raidDef.name, "amber")
	S.Msg(leader, "Invite sent to " .. targetPlayer.Name .. ".", "system")
end)

-- RE_RaidInviteResp  (target → accept / decline)
S.RE_RaidInviteResp.OnServerEvent:Connect(function(pl, accept)
	local invite = S.pendingInvites[pl.UserId]
	if not invite then S.Msg(pl, "No pending raid invite.", "system") return end
	S.pendingInvites[pl.UserId] = nil

	if os.time() > invite.expiresAt then
		S.Msg(pl, "Invite expired.", "system") return
	end
	if not accept then
		S.Msg(invite.from, pl.Name .. " declined the raid invite.", "system")
		S.Msg(pl, "Declined.", "system") return
	end

	local party = S.raidParties[invite.partyId]
	if not party or party.state ~= "lobby" then
		S.Msg(pl, "That raid party is no longer available.", "system") return
	end
	if #party.members >= MAX_PARTY then
		S.Msg(pl, "Party is full.", "system") return
	end

	local d = S.sessions[pl.UserId]
	if not d then return end

	table.insert(party.members, pl)
	broadcastParty(party, pl.Name .. " joined the party! (" .. #party.members .. "/" .. MAX_PARTY .. ")", "system")
	S.Pop(pl, "JOINED PARTY", "You joined " .. party.leader.Name .. "'s raid party.", "amber")
end)

-- RE_RaidStart  (leader → start the raid when party is assembled)
S.RE_RaidStart.OnServerEvent:Connect(function(leader)
	local party = getParty(leader)
	if not party then S.Msg(leader, "You don't have a party.", "system") return end
	if party.leader ~= leader then S.Msg(leader, "Only the leader can start the raid.", "system") return end
	if party.state ~= "lobby" then S.Msg(leader, "Raid already in progress.", "system") return end
	if #party.members < 1 then S.Msg(leader, "Party is empty.", "system") return end

	local raidDef
	for _, r in ipairs(D.RAIDS) do if r.id == party.raidId then raidDef = r break end end
	if not raidDef then S.Msg(leader, "Raid definition missing.", "system") return end

	-- Verify all members are present and not in combat
	for i = #party.members, 1, -1 do
		local m = party.members[i]
		local d = S.sessions[m.UserId]
		if not d then
			table.remove(party.members, i)
		elseif d.inCombat then
			S.Msg(leader, m.Name .. " is in combat — cannot start.", "system") return
		end
	end

	-- Compute average prestige for scaling
	local avgPrestige = 0
	for _, m in ipairs(party.members) do
		local d = S.sessions[m.UserId]
		avgPrestige = avgPrestige + (d and d.prestige or 0)
	end
	avgPrestige = avgPrestige / math.max(1, #party.members)

	local scaled = scaleEnemy(raidDef, #party.members, avgPrestige)

	-- Initialise shared enemy state
	party.state       = "active"
	party.enemyHp     = scaled.hp
	party.enemyMaxHp  = scaled.hp
	party.enemyAtk    = scaled.atk
	party.enemyRegen  = scaled.regen or 0
	party.enemyName   = scaled.name
	party.behavior    = scaled.behavior or ""
	party.telegraphed = false
	party.stunned     = false
	party.burnTurns   = 0
	party.damage      = {}
	party.turnIndex   = 1

	-- Set all members into combat
	for _, m in ipairs(party.members) do
		local d = S.sessions[m.UserId]
		if d then
			local cs = S.CalcCS(d)
			d.hp = cs.maxHp
			d.inCombat = true
			d.awaitingTurn = (party.members[1] == m)
			party.damage[m.UserId] = 0
		end
	end

	broadcastParty(party, "══ RAID BEGINS: " .. raidDef.name .. " ══", "system")
	broadcastParty(party, scaled.name .. " appears! HP: " .. scaled.hp, "combat")
	S.Msg(party.members[1], "Your turn!", "combat")

	pushRaidState(party)
end)

-- RE_RaidAction  (current turn member → perform a combat action)
-- actionType: same strings as solo combat ("slash", "heavy_strike", "recover",
--             "evasive_maneuver", "retreat", "spear_strike", "spear_volley",
--             "titan_punch", "titan_kick", "titan_roar", "titan_special")
S.RE_RaidAction.OnServerEvent:Connect(function(pl, actionType)
	local party = getPartyByMember(pl)
	if not party or party.state ~= "active" then
		S.Msg(pl, "No active raid.", "system") return
	end

	local currentActor = party.members[party.turnIndex]
	if pl ~= currentActor then
		S.Msg(pl, "It's not your turn!", "system") return
	end

	local d = S.sessions[pl.UserId]
	if not d then return end
	if not d.awaitingTurn then
		S.Msg(pl, "Not awaiting your turn.", "system") return
	end
	d.awaitingTurn = false

	local cs = S.CalcCS(d)
	local raidDef
	for _, r in ipairs(D.RAIDS) do if r.id == party.raidId then raidDef = r break end end
	if not raidDef then return end

	-- ── Resolve the player's action ──────────────────────────────────────
	local dmgDealt = 0
	local logMsg   = ""

	-- Cooldown tick on all party-member cooldowns
	if d.moveCooldowns then
		for k, v in pairs(d.moveCooldowns) do
			if v > 0 then d.moveCooldowns[k] = v - 1 end
		end
	else
		d.moveCooldowns = {}
	end

	-- Status effects
	if (d.playerFearTurns or 0) > 0 then
		d.playerFearTurns = d.playerFearTurns - 1
		broadcastParty(party, pl.Name .. " is gripped by fear and cannot act!", "combat")
		goto afterAction
	end

	if actionType == "slash" then
		local base = math.floor(cs.str * 1.0)
		local slow  = (d.playerSlowTurns or 0) > 0 and 0.85 or 1
		dmgDealt = math.max(1, math.floor(base * slow))
		logMsg = pl.Name .. " slashes for " .. dmgDealt .. " damage."

	elseif actionType == "heavy_strike" then
		local cd = (d.moveCooldowns or {}).heavy_strike or 0
		if cd > 0 then S.Msg(pl, "Heavy strike on cooldown (" .. cd .. " turns).", "combat") goto skipAction end
		dmgDealt = math.max(1, math.floor(cs.str * 1.6))
		d.moveCooldowns.heavy_strike = 2
		logMsg = pl.Name .. " lands a heavy strike for " .. dmgDealt .. " damage!"

	elseif actionType == "recover" then
		local cd = (d.moveCooldowns or {}).recover or 0
		if cd > 0 then S.Msg(pl, "Recover on cooldown.", "combat") goto skipAction end
		local healAmt = math.floor(cs.maxHp * 0.25 + cs.wil * 2)
		d.hp = math.min(cs.maxHp, d.hp + healAmt)
		d.moveCooldowns.recover = 3
		broadcastParty(party, pl.Name .. " recovers " .. healAmt .. " HP.", "combat")
		goto afterAction

	elseif actionType == "evasive_maneuver" then
		local cd = (d.moveCooldowns or {}).evasive or 0
		if cd > 0 then S.Msg(pl, "Evasive maneuver on cooldown.", "combat") goto skipAction end
		d.evasionActive = true
		d.moveCooldowns.evasive = 4
		broadcastParty(party, pl.Name .. " leaps into an evasive maneuver!", "combat")
		goto afterAction

	elseif actionType == "spear_strike" then
		if (d.thunderSpears or 0) < 1 then S.Msg(pl, "No thunder spears.", "combat") goto skipAction end
		local pathMult = (d.path == "marleyan") and D.PATHS.marleyan.passives.spearDamageMult or 1
		dmgDealt = math.max(1, math.floor(cs.str * 2.0 * pathMult))
		d.thunderSpears = d.thunderSpears - 1
		logMsg = pl.Name .. " fires a Thunder Spear for " .. dmgDealt .. "!"

	elseif actionType == "spear_volley" then
		local cd = (d.moveCooldowns or {}).spear_volley or 0
		if cd > 0 then S.Msg(pl, "Spear volley on cooldown.", "combat") goto skipAction end
		local cost = (d.path == "marleyan") and 1 or 2
		if (d.thunderSpears or 0) < cost then
			S.Msg(pl, "Not enough thunder spears.", "combat") goto skipAction
		end
		local pathMult = (d.path == "marleyan") and D.PATHS.marleyan.passives.spearDamageMult or 1
		dmgDealt = math.max(1, math.floor(cs.str * 1.4 * pathMult * 2))
		d.thunderSpears = d.thunderSpears - cost
		d.moveCooldowns.spear_volley = 3
		logMsg = pl.Name .. " launches a Thunder Spear Volley for " .. dmgDealt .. "!"

	elseif actionType == "retreat" then
		-- Remove member from party; if they were the last one the raid fails naturally
		S.Msg(pl, "You retreat from the raid.", "combat")
		broadcastParty(party, pl.Name .. " has retreated from the raid.", "combat")
		for i, m in ipairs(party.members) do
			if m == pl then table.remove(party.members, i) break end
		end
		d.inCombat = false
		d.awaitingTurn = false
		S.Push(pl, d)
		if #party.members == 0 then
			party.state = "finished"
			S.raidParties[party.partyId] = nil
			return
		end
		-- Clamp turn index
		party.turnIndex = math.min(party.turnIndex, #party.members)
		local next = advanceTurn(party)
		if next then
			local nd = S.sessions[next.UserId]
			if nd then nd.awaitingTurn = true end
			broadcastParty(party, next.Name .. "'s turn.", "combat")
		end
		pushRaidState(party)
		return

			-- Titan moves ──────────────────────────────────────────────────────────
	elseif actionType == "titan_punch" then
		if not d.titanShifterMode then S.Msg(pl, "Not in titan form.", "combat") goto skipAction end
		local cd = (d.moveCooldowns or {}).titan_punch or 0
		if cd > 0 then S.Msg(pl, "Titan punch on cooldown.", "combat") goto skipAction end
		dmgDealt = math.max(1, math.floor(cs.str * 2.5))
		d.titanHeat = (d.titanHeat or 0) + D.TITAN_HEAT_PER_ACTION
		d.moveCooldowns.titan_punch = 0
		logMsg = pl.Name .. "'s titan smashes for " .. dmgDealt .. "!"

	elseif actionType == "titan_kick" then
		if not d.titanShifterMode then S.Msg(pl, "Not in titan form.", "combat") goto skipAction end
		local cd = (d.moveCooldowns or {}).titan_kick or 0
		if cd > 0 then S.Msg(pl, "Titan kick on cooldown.", "combat") goto skipAction end
		dmgDealt = math.max(1, math.floor(cs.str * 2.2))
		party.stunned = true
		d.titanHeat = (d.titanHeat or 0) + D.TITAN_HEAT_PER_ACTION
		d.moveCooldowns.titan_kick = 2
		logMsg = pl.Name .. "'s titan kicks for " .. dmgDealt .. " — enemy stunned!"

	elseif actionType == "titan_roar" then
		if not d.titanShifterMode then S.Msg(pl, "Not in titan form.", "combat") goto skipAction end
		local cd = (d.moveCooldowns or {}).titan_roar or 0
		if cd > 0 then S.Msg(pl, "Titan roar on cooldown.", "combat") goto skipAction end
		-- Roar: applies burn to enemy (DoT)
		party.burnTurns = (party.burnTurns or 0) + 3
		d.titanHeat = (d.titanHeat or 0) + D.TITAN_HEAT_PER_ACTION
		d.moveCooldowns.titan_roar = 4
		broadcastParty(party, pl.Name .. "'s titan roars — enemy is burning!", "combat")
		goto afterAction

	elseif actionType == "titan_special" then
		if not d.titanShifterMode then S.Msg(pl, "Not in titan form.", "combat") goto skipAction end
		local cd = (d.moveCooldowns or {}).titan_special or 0
		if cd > 0 then S.Msg(pl, "Titan special on cooldown.", "combat") goto skipAction end
		local titan = d.equippedTitan and d.titanSlots[d.equippedTitan]
		local attack = titan and D.TITAN_ATTACKS[titan.id]
		if not attack then S.Msg(pl, "No titan special available.", "combat") goto skipAction end
		dmgDealt = math.max(1, math.floor(cs.str * (attack.mult or 2.0)))
		d.titanHeat = (d.titanHeat or 0) + D.TITAN_HEAT_PER_ACTION * 1.5
		d.moveCooldowns.titan_special = 5
		logMsg = pl.Name .. " unleashes " .. attack.name .. " for " .. dmgDealt .. "!"
	end

	-- ── Apply damage to shared enemy ──────────────────────────────────────
	if dmgDealt > 0 then
		-- Armored reduces all incoming damage
		if party.behavior == "armored" then
			dmgDealt = math.floor(dmgDealt * 0.75)
		end
		party.enemyHp = math.max(0, party.enemyHp - dmgDealt)
		party.damage[pl.UserId] = (party.damage[pl.UserId] or 0) + dmgDealt
		if logMsg ~= "" then broadcastParty(party, logMsg, "combat") end
	end

	::afterAction::
	-- Titan heat management
	if d.titanShifterMode then
		local heatDecay = D.TITAN_HEAT_DECAY + ((d.path == "eldian") and D.PATHS.eldian.passives.titanHeatDecay or 0)
		d.titanHeat = math.max(0, (d.titanHeat or 0) - heatDecay)
		if d.titanHeat >= D.TITAN_HEAT_MAX then
			d.titanShifterMode = false
			d.titanHeat = 0
			S.Msg(pl, "Heat limit reached — you revert to human form!", "combat")
			broadcastParty(party, pl.Name .. " reverts from titan form.", "combat")
		end
	end

	-- Slow decay
	if (d.playerSlowTurns or 0) > 0 then d.playerSlowTurns = d.playerSlowTurns - 1 end

	-- Check if raid ended
	if checkEndCondition(party, raidDef) then return end

	-- Enemy turn (attacks the current actor)
	enemyRegen(party)
	if party.enemyHp > 0 then
		enemyTurn(party, pl, d)
		if d.hp <= 0 then
			broadcastParty(party, pl.Name .. " has fallen!", "combat")
		end
	end

	-- Check again after enemy turn
	if checkEndCondition(party, raidDef) then return end

	-- Advance turn to next living member
	local nextActor = advanceTurn(party)
	if nextActor then
		local nd = S.sessions[nextActor.UserId]
		if nd then nd.awaitingTurn = true end
		broadcastParty(party, nextActor.Name .. "'s turn! Enemy HP: " .. party.enemyHp, "combat")
	end

	pushRaidState(party)
	return

		::skipAction::
	-- Re-grant the turn if the action was invalid (cooldown, etc.)
	d.awaitingTurn = true
	S.Push(pl, d)
end)

-- RE_RaidShift  (member → enter titan form mid-raid)
S.RE_RaidShift.OnServerEvent:Connect(function(pl)
	local party = getPartyByMember(pl)
	if not party or party.state ~= "active" then return end
	if party.members[party.turnIndex] ~= pl then
		S.Msg(pl, "Not your turn.", "system") return
	end
	local d = S.sessions[pl.UserId]
	if not d or d.titanShifterMode then
		S.Msg(pl, "Already in titan form.", "combat") return
	end
	if not d.equippedTitan then
		S.Msg(pl, "No titan equipped.", "combat") return
	end
	-- Ackerman clan blocks titan shifting
	if d.clan == "ackerman" then
		S.Msg(pl, "Ackerman bloodline rejects the titan power.", "combat") return
	end

	d.titanShifterMode = true
	d.titanHeat = 0
	d.moveCooldowns = d.moveCooldowns or {}

	local titan = d.titanSlots[d.equippedTitan]
	broadcastParty(party, pl.Name .. " transforms into the " .. (titan and titan.name or "Titan") .. "!", "combat")
	pushRaidState(party)
end)

-- Cleanup on player leaving mid-raid
Players.PlayerRemoving:Connect(function(pl)
	local party = getPartyByMember(pl)
	if not party then return end
	for i, m in ipairs(party.members) do
		if m == pl then table.remove(party.members, i) break end
	end
	broadcastParty(party, pl.Name .. " disconnected from the raid.", "system")
	if #party.members == 0 then
		S.raidParties[party.partyId] = nil
		return
	end
	party.turnIndex = math.min(party.turnIndex, #party.members)
	local next = advanceTurn(party)
	if next then
		local nd = S.sessions[next.UserId]
		if nd then nd.awaitingTurn = true end
		broadcastParty(party, next.Name .. "'s turn.", "combat")
	end
	pushRaidState(party)
end)

-- ── Register extra remotes needed by this module ──────────────────────────
-- These must also be declared in AOT_Sessions:
--   S.RE_RaidStart  = RE("RaidStart")
--   S.RE_RaidAction = RE("RaidAction")
--   S.RE_RaidShift  = RE("RaidShift")
--   S.RE_RaidState  = RE("RaidState")   -- server→all clients broadcast

return Raids
