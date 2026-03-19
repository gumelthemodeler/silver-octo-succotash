-- @ScriptType: ModuleScript
-- @ScriptType: ModuleScript
-- AOT_Server_Raids (Optimized & Secured)
-- Place in: ServerScriptService > AOT > AOT_Server_Raids

local Players = game:GetService("Players")
local RS      = game:GetService("ReplicatedStorage")
local AOTF    = RS:WaitForChild("AOT", 10)
local D       = require(AOTF:WaitForChild("AOT_Data"))
local S = require(script.Parent.Parent:WaitForChild("AOT_Sessions"))

local Raids = {}

-- ==========================================
-- 1. CONSTANTS & STATE HELPERS
-- ==========================================
local MAX_PARTY   = 4
local INVITE_TTL  = 30

local function partyId(leader) return tostring(leader.UserId) end
local function getParty(leader) return S.raidParties[partyId(leader)] end

local function getPartyByMember(pl)
	for _, party in pairs(S.raidParties) do
		for _, m in ipairs(party.members) do
			if m == pl then return party end
		end
	end
	return nil
end

local function broadcastParty(party, msg, t)
	for _, m in ipairs(party.members) do S.Msg(m, msg, t or "system") end
end

local function broadcastPartyPop(party, title, body, color)
	for _, m in ipairs(party.members) do S.Pop(m, title, body, color or "amber") end
end

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
	for _, m in ipairs(party.members) do table.insert(payload.memberNames, m.Name) end
	S.RE_RaidState:FireAllClients(payload)
	for _, m in ipairs(party.members) do
		local d = S.sessions[m.UserId]
		if d then S.Push(m, d) end
	end
end

local function scaleEnemy(baseEnemy, memberCount, avgPrestige)
	local hpScale  = 1 + (memberCount - 1) * 0.70
	local atkScale = 1 + (avgPrestige or 0) * 0.18
	return {
		hp    = math.floor(baseEnemy.baseHp * hpScale),
		atk   = math.floor(baseEnemy.baseAtk * atkScale),
		regen = math.floor((baseEnemy.regen or 0) * hpScale),
		name  = baseEnemy.name,
		xp    = baseEnemy.xp,
		funds = baseEnemy.funds,
		behavior = baseEnemy.behavior,
	}
end

-- ==========================================
-- 2. RAID COMBAT EXECUTION ENGINE
-- ==========================================
local function CalcPlayerDamage(player, d, cs, moveData, isTitan)
	local dmg = moveData.baseDamage or 10

	if moveData.strMult then dmg = dmg + math.floor((cs.str or 0) * moveData.strMult) end
	if moveData.bladeMult then dmg = dmg + math.floor((cs.bladeMastery or 0) * moveData.bladeMult) end
	if moveData.affinityMult then dmg = dmg + math.floor((cs.titanAffinity or 0) * moveData.affinityMult) end
	if moveData.spdMult then dmg = dmg + math.floor((cs.spd or 0) * moveData.spdMult) end
	if moveData.wilMult then dmg = dmg + math.floor((cs.wil or 0) * moveData.wilMult) end

	if (d.playerFearTurns or 0) > 0 then dmg = math.floor(dmg * 0.70) end
	if (d.playerSlowTurns or 0) > 0 then dmg = math.floor(dmg * 0.85) end
	if (d.nextAttackMult or 1) > 1 then dmg = math.floor(dmg * d.nextAttackMult) d.nextAttackMult = 1 end
	if d.wanderingCritPending then dmg = math.floor(dmg * (D.PATH_MOVES.wandering.critMult or 2.0)) d.wanderingCritPending = false end
	if isTitan and (d.nextTitanSpecialBoost or 1) > 1 then dmg = math.floor(dmg * d.nextTitanSpecialBoost) d.nextTitanSpecialBoost = 1 end

	return math.max(1, dmg)
end

local function DamageRaidEnemy(party, pl, rawDmg, moveId)
	if party.behavior == "armored" then rawDmg = math.floor(rawDmg * 0.75) end
	party.enemyHp = math.max(0, party.enemyHp - rawDmg)
	party.damage[pl.UserId] = (party.damage[pl.UserId] or 0) + rawDmg
	return rawDmg
end

-- ==========================================
-- 3. ENEMY TURN & RESOLUTION
-- ==========================================
local function enemyTurn(party, targetPlayer, targetData)
	if party.stunned then
		party.stunned = false
		broadcastParty(party, "★ " .. party.enemyName .. " is stunned and loses its turn!", "combat")
		return 0
	end

	if party.behavior == "telegraph" and not party.telegraphed then
		party.telegraphed = true
		broadcastParty(party, "⚠ " .. party.enemyName .. " is winding up a powerful attack!", "combat")
		return 0
	end

	local mult = party.telegraphed and 2 or 1
	party.telegraphed = false

	if party.behavior == "aberrant" and math.random() < 0.25 then
		broadcastParty(party, party.enemyName .. " moves erratically and skips its turn!", "combat")
		return 0
	end

	local raw = math.floor(party.enemyAtk * mult)
	local dmg = math.max(1, raw - math.floor(S.CalcCS(targetData).def * 0.6))

	if party.burnTurns and party.burnTurns > 0 then
		local burnDmg = math.floor(party.enemyMaxHp * 0.04)
		party.enemyHp = math.max(0, party.enemyHp - burnDmg)
		party.burnTurns = party.burnTurns - 1
		broadcastParty(party, party.enemyName .. " burns for " .. burnDmg .. " damage.", "combat")
	end

	if party.behavior == "armored" then dmg = math.floor(dmg * 0.75) end

	targetData.hp = math.max(0, targetData.hp - dmg)
	broadcastParty(party, party.enemyName .. " attacks " .. targetPlayer.Name .. " for " .. dmg .. " damage!", "combat")

	if party.behavior == "crawler" then
		targetData.playerSlowTurns = (targetData.playerSlowTurns or 0) + 2
		S.Msg(targetPlayer, party.enemyName .. " slows you!", "combat")
	end

	return dmg
end

local function distributeRewards(party, raidDef)
	for _, m in ipairs(party.members) do
		local d = S.sessions[m.UserId]
		if not d then continue end

		local contrib = (party.damage[m.UserId] or 0) / math.max(1, party.enemyMaxHp)
		local contribMult = 0.5 + contrib

		local cs = S.CalcCS(d)
		local xp = math.floor(raidDef.xp * contribMult * cs.xpMult * cs.streakMult)
		local funds = math.floor(raidDef.funds * contribMult * cs.fundMult)

		S.AwardXP(m, d, xp, cs)
		d.funds = (d.funds or 0) + funds
		d.totalKills = (d.totalKills or 0) + 1
		d.bossKills = (d.bossKills or 0) + 1

		d.raidHighScores = d.raidHighScores or {}
		if contrib > (d.raidHighScores[raidDef.id] or 0) then d.raidHighScores[raidDef.id] = contrib end
		d.raidUnlocks = d.raidUnlocks or {}
		d.raidUnlocks[raidDef.id] = true

		local drop = D.RollDrop("boss")
		if drop and D.ITEM_MAP[drop] then
			table.insert(d.inventory, {id=drop, forgeLevel=0})
			S.Msg(m, "★ Drop: " .. D.ITEM_MAP[drop].name .. " [" .. D.ITEM_MAP[drop].rarity .. "]", "reward")
		elseif drop then
			d.consumables = d.consumables or {}
			d.consumables[drop] = (d.consumables[drop] or 0) + 1
			S.Msg(m, "★ Material: " .. drop, "reward")
		end

		S.BumpChallenge(m, d, "bossKill", 1)
		S.BumpChallenge(m, d, "raidClear", 1)
		S.CheckAchievements(m, d)

		S.Msg(m, string.format("Raid complete! Contribution: %d%% | +%d XP | +%d Funds", math.floor(contrib * 100), xp, funds), "reward")
		S.Save(m.UserId, d)
	end
end

local function advanceTurn(party)
	local count = #party.members
	local start = party.turnIndex
	for i = 1, count do
		local nextIdx = (start + i - 1) % count + 1
		local m = party.members[nextIdx]
		local d = m and S.sessions[m.UserId]
		if d and d.hp > 0 then
			party.turnIndex = nextIdx
			return m
		end
	end
	return nil
end

local function checkEndCondition(party, raidDef)
	if party.enemyHp <= 0 then
		party.state = "finished"
		broadcastPartyPop(party, "RAID CLEAR!", party.enemyName .. " has been defeated!", "amber")
		distributeRewards(party, raidDef)
		S.raidParties[party.partyId] = nil
		return true
	end

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
				d.hp = 1
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

-- ==========================================
-- 4. REMOTE HANDLERS
-- ==========================================

S.RE_RaidInvite.OnServerEvent:Connect(function(leader, targetPlayer, raidId)
	local d = S.sessions[leader.UserId]
	if not d or d.inCombat then return end

	local raidDef
	for _, r in ipairs(D.RAIDS) do if r.id == raidId then raidDef = r break end end
	if not raidDef or not (d.raidUnlocks or {})[raidId] then return end

	local party = getParty(leader)
	if not party then
		party = {
			partyId = partyId(leader), raidId = raidId, leader = leader, members = {leader}, turnIndex = 1, state = "lobby",
			enemyHp = 0, enemyMaxHp = 0, enemyAtk = 0, enemyRegen = 0, enemyName = "", behavior = "", telegraphed = false, stunned = false, burnTurns = 0, damage = {}
		}
		S.raidParties[party.partyId] = party
	end

	if #party.members >= MAX_PARTY then return end

	local td = S.sessions[targetPlayer.UserId]
	if not td or td.inCombat or getPartyByMember(targetPlayer) then return end

	S.pendingInvites[targetPlayer.UserId] = { from = leader, partyId = party.partyId, raidId = raidId, expiresAt = os.time() + INVITE_TTL }
	S.Pop(targetPlayer, "RAID INVITE", leader.Name .. " → " .. raidDef.name, "amber")
end)

S.RE_RaidInviteResp.OnServerEvent:Connect(function(pl, accept)
	local invite = S.pendingInvites[pl.UserId]
	if not invite then return end
	S.pendingInvites[pl.UserId] = nil

	if os.time() > invite.expiresAt or not accept then return end

	local party = S.raidParties[invite.partyId]
	if not party or party.state ~= "lobby" or #party.members >= MAX_PARTY then return end

	table.insert(party.members, pl)
	broadcastParty(party, pl.Name .. " joined the party! (" .. #party.members .. "/" .. MAX_PARTY .. ")", "system")
end)

S.RE_RaidStart.OnServerEvent:Connect(function(leader)
	local party = getParty(leader)
	if not party or party.leader ~= leader or party.state ~= "lobby" or #party.members < 1 then return end

	local raidDef
	for _, r in ipairs(D.RAIDS) do if r.id == party.raidId then raidDef = r break end end
	if not raidDef then return end

	local avgPrestige = 0
	for i = #party.members, 1, -1 do
		local m = party.members[i]
		local d = S.sessions[m.UserId]
		if not d or d.inCombat then table.remove(party.members, i) else avgPrestige = avgPrestige + (d.prestige or 0) end
	end
	if #party.members == 0 then return end
	avgPrestige = avgPrestige / #party.members

	local scaled = scaleEnemy(raidDef, #party.members, avgPrestige)

	party.state = "active"
	party.enemyHp = scaled.hp; party.enemyMaxHp = scaled.hp; party.enemyAtk = scaled.atk; party.enemyRegen = scaled.regen or 0
	party.enemyName = scaled.name; party.behavior = scaled.behavior or ""; party.telegraphed = false; party.stunned = false; party.burnTurns = 0; party.damage = {}; party.turnIndex = 1

	for _, m in ipairs(party.members) do
		local d = S.sessions[m.UserId]
		if d then
			local cs = S.CalcCS(d)
			d.hp = cs.maxHp; d.inCombat = true; d.awaitingTurn = (party.members[1] == m); party.damage[m.UserId] = 0
		end
	end

	broadcastParty(party, "══ RAID BEGINS: " .. raidDef.name .. " ══", "system")
	pushRaidState(party)
end)

-- THE NEW DATA-DRIVEN ACTION HANDLER
S.RE_RaidAction.OnServerEvent:Connect(function(pl, actionId)
	local party = getPartyByMember(pl)
	if not party or party.state ~= "active" or party.members[party.turnIndex] ~= pl then return end

	local d = S.sessions[pl.UserId]
	if not d or not d.awaitingTurn then return end

	local moveData = D.GetMoveDef(actionId)
	if not moveData then return end

	local cs = S.CalcCS(d)
	d.awaitingTurn = false

	-- Status Check
	if (d.playerFearTurns or 0) > 0 and actionId ~= "retreat" then
		d.playerFearTurns = d.playerFearTurns - 1
		broadcastParty(party, pl.Name .. " is gripped by fear and cannot act!", "combat")
		goto endTurn
	end

	-- Resource Checks
	if moveData.spearCost and (d.thunderSpears or 0) < moveData.spearCost then
		S.Msg(pl, "Not enough Thunder Spears.", "warn")
		d.awaitingTurn = true; S.Push(pl, d); return
	end
	if moveData.cooldown and (d.moveCooldowns and d.moveCooldowns[actionId] or 0) > 0 then
		S.Msg(pl, moveData.name .. " is on cooldown.", "warn")
		d.awaitingTurn = true; S.Push(pl, d); return
	end

	-- Execute
	if moveData.spearCost then d.thunderSpears = d.thunderSpears - moveData.spearCost end
	if moveData.cooldown and moveData.cooldown > 0 then
		d.moveCooldowns = d.moveCooldowns or {}
		d.moveCooldowns[actionId] = moveData.cooldown
	end

	if actionId == "retreat" then
		S.Msg(pl, "You retreat from the raid.", "combat")
		broadcastParty(party, pl.Name .. " has retreated from the raid.", "combat")
		for i, m in ipairs(party.members) do if m == pl then table.remove(party.members, i) break end end
		d.inCombat, d.awaitingTurn = false, false
		S.Push(pl, d)
		if #party.members == 0 then party.state = "finished" S.raidParties[party.partyId] = nil return end
		party.turnIndex = math.min(party.turnIndex, #party.members)
		local nextAct = advanceTurn(party)
		if nextAct then local nd = S.sessions[nextAct.UserId] if nd then nd.awaitingTurn = true end end
		pushRaidState(party)
		return
	end

	if moveData.type == "attack" or moveData.type == "titan_attack" or moveData.type == "titan_special" then
		local isTitan = moveData.type:match("^titan_")
		if isTitan then d.titanHeat = math.min(D.TITAN_HEAT_MAX, (d.titanHeat or 0) + D.GetHeatCost(actionId, cs.titanAffinity or 0)) end

		local rawDmg = CalcPlayerDamage(pl, d, cs, moveData, isTitan)
		if d.path == "marleyan" and moveData.spearCost then rawDmg = math.floor(rawDmg * D.PATHS.marleyan.passives.spearDamageMult) end

		if moveData.type == "titan_special" then
			local tAtk = D.TITAN_ATTACKS[(d.equippedTitan and d.titanSlots[d.equippedTitan] and d.titanSlots[d.equippedTitan].id)]
			if tAtk then
				rawDmg = math.floor(rawDmg * (tAtk.mult or 1.0))
				if tAtk.special == "stun" then party.stunned = true end
				if tAtk.special == "burn" then party.burnTurns = (party.burnTurns or 0) + 3 end
				if tAtk.special == "lifesteal" then d.hp = math.min(d.maxHp, d.hp + math.floor(rawDmg * 0.20)) end
			end
		end

		local actual = DamageRaidEnemy(party, pl, rawDmg, actionId)
		broadcastParty(party, pl.Name .. " uses " .. moveData.name .. " for " .. actual .. " damage!", isTitan and "titan" or "combat")

	elseif moveData.type == "heal" then
		local healAmt = D.GetRecoverHeal(cs.wil, d.maxHp)
		d.hp = math.min(cs.maxHp, d.hp + healAmt)
		broadcastParty(party, pl.Name .. " recovers " .. healAmt .. " HP.", "heal")

	elseif moveData.type == "evade" then
		d.evasionActive = true
		broadcastParty(party, pl.Name .. " prepares to evade!", "combat")

	elseif moveData.type == "titan_buff" then
		if moveData.buffKey == "nextAttackMult" then d.nextAttackMult = moveData.buffValue or 1.5 end
		d.titanHeat = math.min(D.TITAN_HEAT_MAX, (d.titanHeat or 0) + D.GetHeatCost(actionId, cs.titanAffinity or 0))
	end

	::endTurn::
	if d.titanShifterMode then
		d.titanHeat = math.max(0, (d.titanHeat or 0) - D.TITAN_HEAT_DECAY)
		if d.titanHeat >= D.TITAN_HEAT_MAX then
			d.titanShifterMode, d.titanHeat = false, 0
			broadcastParty(party, pl.Name .. " reverts from titan form (Heat Maxed).", "combat")
		end
	end

	if (d.playerSlowTurns or 0) > 0 then d.playerSlowTurns = d.playerSlowTurns - 1 end

	local raidDef
	for _, r in ipairs(D.RAIDS) do if r.id == party.raidId then raidDef = r break end end

	if checkEndCondition(party, raidDef) then return end

	if party.enemyHp > 0 and party.enemyRegen and party.enemyRegen > 0 then
		local regen = math.min(party.enemyRegen, party.enemyMaxHp - party.enemyHp)
		party.enemyHp = party.enemyHp + regen
	end

	if party.enemyHp > 0 then
		enemyTurn(party, pl, d)
		if d.hp <= 0 then broadcastParty(party, pl.Name .. " has fallen!", "combat") end
	end

	if checkEndCondition(party, raidDef) then return end

	local nextActor = advanceTurn(party)
	if nextActor then
		local nd = S.sessions[nextActor.UserId]
		if nd then nd.awaitingTurn = true end
		broadcastParty(party, nextActor.Name .. "'s turn! Enemy HP: " .. party.enemyHp, "combat")
	end

	pushRaidState(party)
end)

S.RE_RaidShift.OnServerEvent:Connect(function(pl)
	local party = getPartyByMember(pl)
	if not party or party.state ~= "active" or party.members[party.turnIndex] ~= pl then return end
	local d = S.sessions[pl.UserId]
	if not d or d.titanShifterMode or not d.equippedTitan or d.clan == "ackerman" then return end

	d.titanShifterMode = true
	d.titanHeat = 0
	broadcastParty(party, pl.Name .. " transforms into the " .. d.titanSlots[d.equippedTitan].name .. "!", "combat")
	pushRaidState(party)
end)

Players.PlayerRemoving:Connect(function(pl)
	local party = getPartyByMember(pl)
	if not party then return end
	for i, m in ipairs(party.members) do if m == pl then table.remove(party.members, i) break end end
	if #party.members == 0 then S.raidParties[party.partyId] = nil return end

	party.turnIndex = math.min(party.turnIndex, #party.members)
	local nextAct = advanceTurn(party)
	if nextAct then local nd = S.sessions[nextAct.UserId] if nd then nd.awaitingTurn = true end end
	pushRaidState(party)
end)

return Raids