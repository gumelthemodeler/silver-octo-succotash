-- @ScriptType: Script
-- @ScriptType: Script
-- AOT_Server_Combat (Optimized & Secured)
-- Place in: ServerScriptService > AOT_Server_Combat

local Players  = game:GetService("Players")
local SS       = game:GetService("ServerScriptService")
local S        = require(SS:WaitForChild("AOT_Sessions"))
local D        = require(game:GetService("ReplicatedStorage"):WaitForChild("AOT"):WaitForChild("AOT_Data"))
local sessions = S.sessions

-- ============================================================================
-- 1. TURN-BASED TICK HELPERS
-- ============================================================================

local function TickCooldowns(d)
	if not d.moveCooldowns then return end
	for move, cd in pairs(d.moveCooldowns) do
		if cd > 0 then d.moveCooldowns[move] = cd - 1 end
	end
end

local function TickTitanHeat(d)
	if d.titanShifterMode then return end
	local decay = D.TITAN_HEAT_DECAY
	if d.path == "eldian" then
		decay = decay + D.PATHS.eldian.passives.titanHeatDecay
	end
	d.titanHeat = math.max(0, (d.titanHeat or 0) - decay)
	if (d.titanSuppressTurns or 0) > 0 then
		d.titanSuppressTurns = d.titanSuppressTurns - 1
	end
end

local function TickPlayerStatus(player, d)
	if (d.playerBleedTurns or 0) > 0 then
		local bleedDmg = math.floor((d.maxHp or 100) * 0.04)
		d.hp = math.max(1, d.hp - bleedDmg)
		d.playerBleedTurns = d.playerBleedTurns - 1
		S.Msg(player, "You bleed for " .. bleedDmg .. " damage. (" .. d.playerBleedTurns .. " turns remaining)", "warn")
	end
	if (d.playerSlowTurns or 0) > 0 then
		d.playerSlowTurns = d.playerSlowTurns - 1
	end
	if (d.playerFearTurns or 0) > 0 then
		d.playerFearTurns = d.playerFearTurns - 1
	end
end

-- ============================================================================
-- 2. DAMAGE CALCULATION & MECHANIC ROUTING
-- ============================================================================

local function CalcPlayerDamage(player, d, cs, moveData, isTitan)
	local dmg = moveData.baseDamage or 10

	if moveData.strMult then dmg = dmg + math.floor((cs.str or 0) * moveData.strMult) end
	if moveData.bladeMult then dmg = dmg + math.floor((cs.bladeMastery or 0) * moveData.bladeMult) end
	if moveData.affinityMult then dmg = dmg + math.floor((cs.titanAffinity or 0) * moveData.affinityMult) end
	if moveData.spdMult then dmg = dmg + math.floor((cs.spd or 0) * moveData.spdMult) end
	if moveData.wilMult then dmg = dmg + math.floor((cs.wil or 0) * moveData.wilMult) end

	if (d.playerFearTurns or 0) > 0 then dmg = math.floor(dmg * 0.70) end
	if (d.playerSlowTurns or 0) > 0 then dmg = math.floor(dmg * 0.85) end

	if (d.nextAttackMult or 1) > 1 then
		dmg = math.floor(dmg * d.nextAttackMult)
		d.nextAttackMult = 1
	end

	if d.wanderingCritPending then
		dmg = math.floor(dmg * (D.PATH_MOVES.wandering.critMult or 2.0))
		d.wanderingCritPending = false
		S.Msg(player, "CRITICAL HIT! Wandering Ghost Step strikes true!", "combat")
	end

	if isTitan and (d.nextTitanSpecialBoost or 1) > 1 then
		dmg = math.floor(dmg * d.nextTitanSpecialBoost)
		d.nextTitanSpecialBoost = 1
	end

	return math.max(1, dmg)
end

local function DamageEnemy(player, d, rawDmg, moveId)
	local mechId = d.bossActiveMechanic
	local mech = mechId and D.BOSS_MECHANICS[mechId]
	local isPierce = D.IsPierceMove(moveId) or D.IsTitanAffinityMove(moveId)
	local isTrueAtk = moveId and (D.GetMoveDef(moveId) or {}).trueDamage

	-- Nape Armor
	if mech and mechId == "nape_armor" and (d.bossGimmickState or {}).armorActive then
		local gs = d.bossGimmickState
		local armorDmg = isPierce and rawDmg or math.floor(rawDmg * (1 - mech.damageReductionPct))
		if moveId == "heavy_strike" then
			d.bossHeavyStreak = (d.bossHeavyStreak or 0) + 1
			if d.bossHeavyStreak >= 2 then
				armorDmg = math.floor(armorDmg * mech.heavyStreakBonus)
				S.Msg(player, "Consecutive heavy strikes hammer the armour!", "combat")
			end
		else
			d.bossHeavyStreak = 0
		end
		gs.armorHp = math.max(0, gs.armorHp - armorDmg)
		if gs.armorHp <= 0 then
			gs.armorActive = false
			d.bossActiveMechanic = nil
			S.Msg(player, "★ " .. mech.shatterMsg, "warn")
		else
			S.Msg(player, "Armour HP: " .. gs.armorHp .. " remaining.", "combat")
		end
		return armorDmg, true
	end

	-- Crystal Construct
	if mech and mechId == "crystal_construct" and (d.bossGimmickState or {}).barrierActive then
		local gs = d.bossGimmickState
		local barrierDmg = rawDmg
		if D.IsTitanAffinityMove(moveId) then
			barrierDmg = math.floor(rawDmg * mech.titanAffinityDamageMult)
			S.Msg(player, "Titan move strikes the crystal — double damage!", "combat")
		elseif moveId == "eldian_coordinate" then
			barrierDmg = math.floor(rawDmg * mech.coordinateDamageMult)
			S.Msg(player, "The Coordinate shatters the crystal!", "combat")
		end
		gs.barrierHp = math.max(0, gs.barrierHp - barrierDmg)
		if gs.barrierHp <= 0 then
			gs.barrierActive = false
			d.bossActiveMechanic = nil
			S.Msg(player, "★ " .. mech.shatterMsg, "warn")
		else
			S.Msg(player, "Barrier HP: " .. gs.barrierHp .. " remaining.", "combat")
		end
		return barrierDmg, true
	end

	-- Crystal Hardening
	if mech and mechId == "crystal_hardening" and (d.bossGimmickState or {}).hardened then
		local gs = d.bossGimmickState
		local finalDmg = rawDmg
		if isPierce or isTrueAtk then
			if math.random() < mech.pierceBreakChance then
				gs.hardened = false
				S.Msg(player, "★ " .. mech.shatterMsg, "warn")
			end
		else
			finalDmg = math.floor(rawDmg * (1 - mech.damageReductionPct))
			S.Msg(player, "Hardening absorbs most of the damage! (Pierce to break through)", "warn")
		end
		d.enemyHp = math.max(0, d.enemyHp - finalDmg)
		return finalDmg, (not isPierce)
	end

	-- Coordinate Authority
	if mech and mechId == "coordinate_authority" and (d.bossGimmickState or {}).fieldActive then
		local finalDmg = rawDmg
		if not isPierce and not isTrueAtk then
			if math.random() < mech.reflectChance then
				local reflectedDmg = math.floor(rawDmg * mech.reflectPct)
				d.hp = math.max(1, d.hp - reflectedDmg)
				S.Msg(player, "⚠ The Coordinate reflects " .. reflectedDmg .. " damage back at you!", "warn")
			end
		end
		d.enemyHp = math.max(0, d.enemyHp - finalDmg)
		return finalDmg, false
	end

	-- Steam Release
	if mech and mechId == "steam_release" and (d.bossGimmickState or {}).steamActive then
		local finalDmg = math.floor(rawDmg * (1 - mech.steamDmgReductionPct))
		S.Msg(player, "Steam blocks most damage! Wait for a window turn.", "warn")
		d.enemyHp = math.max(0, d.enemyHp - finalDmg)
		return finalDmg, true
	end

	-- Default
	d.enemyHp = math.max(0, d.enemyHp - rawDmg)
	return rawDmg, false
end

-- ============================================================================
-- 3. BOSS PHASE & MECHANIC MANAGERS
-- ============================================================================

local function ActivateMechanic(player, d, mech)
	d.bossGimmickState = d.bossGimmickState or {}
	local gs = d.bossGimmickState
	if mech.id == "crystal_hardening" then
		gs.hardened = true
	elseif mech.id == "nape_armor" then
		gs.armorActive = true
		gs.armorHp = mech.armorHp
	elseif mech.id == "boulder_barrage" then
		gs.barrageTimer = 0
	elseif mech.id == "steam_release" then
		gs.steamActive = false
	elseif mech.id == "crystal_construct" then
		gs.barrierActive = true
		gs.barrierHp = mech.barrierHp
	elseif mech.id == "coordinate_authority" then
		gs.fieldActive = true
		gs.statusIndex = 1
	end
	S.Msg(player, "MECHANIC: " .. mech.name .. " — " .. (mech.announcement or ""), "warn")
end

local function CheckBossPhases(player, d, enemyData)
	if not d.enemyIsBoss or not enemyData then return end
	local phases = enemyData.phases
	local hpPct = d.enemyHp / d.enemyMaxHp
	d.bossGimmickState = d.bossGimmickState or {}

	if phases then
		if not d.bossPhase3 and phases[3] and hpPct <= (phases[3].hpThreshold or 0.30) then
			d.bossPhase3 = true
			if phases[3].atkMult then d.enemyAtk = math.floor(d.enemyAtk * phases[3].atkMult) end
			if phases[3].regenMult then d.enemyRegen = math.floor((d.enemyRegen or 0) * phases[3].regenMult) end
			S.Msg(player, "⚠ PHASE 3 — " .. (phases[3].msg or d.enemyName .. " reaches its final form!"), "warn")
			if phases[3].activateMechanic2 and enemyData.mechanicPhase2 then
				d.bossActiveMechanic = enemyData.mechanicPhase2
				local m2 = D.BOSS_MECHANICS[enemyData.mechanicPhase2]
				if m2 then ActivateMechanic(player, d, m2) end
			end
		elseif not d.bossPhase2 and phases[2] and hpPct <= (phases[2].hpThreshold or 0.60) then
			d.bossPhase2 = true
			if phases[2].atkMult then d.enemyAtk = math.floor(d.enemyAtk * phases[2].atkMult) end
			if phases[2].regenMult then d.enemyRegen = math.floor((d.enemyRegen or 0) * phases[2].regenMult) end
			S.Msg(player, "⚠ PHASE 2 — " .. (phases[2].msg or d.enemyName .. " powers up!"), "warn")
			if phases[2].activateMechanic and enemyData.mechanic then
				d.bossActiveMechanic = enemyData.mechanic
				local m = D.BOSS_MECHANICS[enemyData.mechanic]
				if m then ActivateMechanic(player, d, m) end
			end
		end
	else
		if not d.bossPhase2 and hpPct <= 0.60 then
			d.bossPhase2 = true
			d.enemyAtk = math.floor(d.enemyAtk * 1.25)
			d.enemyRegen = math.floor((d.enemyRegen or 0) * 1.20 + 10)
			S.Msg(player, "⚠ " .. d.enemyName .. " enters PHASE 2!", "warn")
		elseif not d.bossPhase3 and hpPct <= 0.30 then
			d.bossPhase3 = true
			d.enemyAtk = math.floor(d.enemyAtk * 1.20)
			S.Msg(player, "⚠ " .. d.enemyName .. " enters FINAL PHASE!", "warn")
		end
	end
end

-- ============================================================================
-- 4. ENEMY AI & COMBAT RESOLUTION
-- ============================================================================

local function DamagePlayer(player, d, rawAtk)
	local cs = S.CalcCS(d)
	local atk = rawAtk

	if (d.enemyAtkDebuffTurns or 0) > 0 then
		atk = math.floor(atk * (1 - (d.enemyAtkDebuffPct or 0.50)))
		d.enemyAtkDebuffTurns = d.enemyAtkDebuffTurns - 1
	end

	if (d.tyburShieldHits or 0) > 0 then
		d.tyburShieldHits = d.tyburShieldHits - 1
		local counter = math.floor(atk * (d.tyburCounterDmgMult or 0.8))
		d.enemyHp = math.max(0, d.enemyHp - counter)
		S.Msg(player, "Crystal shield absorbs the hit and counters for " .. counter .. "!", "titan")
		return 0
	end

	local red = math.floor(cs.def * 0.6)
	local dmg = math.max(1, atk - red)
	d.hp = math.max(0, d.hp - dmg)
	return dmg
end

local function TickMechanicEnemyTurn(player, d)
	local mechId = d.bossActiveMechanic
	local mech = mechId and D.BOSS_MECHANICS[mechId]
	if not mech then return end
	local gs = d.bossGimmickState or {}
	local cs = S.CalcCS(d)

	if mechId == "steam_release" then
		gs.steamActive = not gs.steamActive
		if gs.steamActive and not gs.royalVowActive then
			local burnPct = math.max(0.01, mech.steamBurnPct - math.floor(cs.wil / 10) * mech.wilBurnReductePer10)
			local burn = math.floor(d.maxHp * burnPct)
			d.hp = math.max(1, d.hp - burn)
			S.Msg(player, "STEAM BURNS you for " .. burn .. " HP!", "warn")
		elseif not gs.steamActive then
			S.Msg(player, "Steam clears — window turn! Deal full damage now!", "combat")
		end
	elseif mechId == "boulder_barrage" then
		gs.barrageTimer = (gs.barrageTimer or 0) + 1
		if gs.barrageTimer >= mech.barrageInterval then
			gs.barrageTimer = 0
			local barrageDmg = math.floor((d.enemyAtk or 50) * mech.barrageDamageMult)
			if d.evasionActive then
				d.evasionActive = false
				S.Msg(player, "You evade the Boulder Barrage!", "combat")
			else
				local slowTurns = math.max(0, mech.inflictsSlowTurns - math.floor((cs.fortitude or 0) / 10) * mech.fortitudeSlowReduce)
				local taken = DamagePlayer(player, d, barrageDmg)
				if slowTurns > 0 then
					d.playerSlowTurns = (d.playerSlowTurns or 0) + math.floor(slowTurns)
					S.Msg(player, "BOULDER BARRAGE hits for " .. taken .. " — SLOWED for " .. math.floor(slowTurns) .. " turns!", "warn")
				end
			end
		elseif (mech.barrageInterval - gs.barrageTimer) == 1 then
			S.Msg(player, "⚠ Zeke is winding up a BOULDER BARRAGE — act fast!", "warn")
		end
	elseif mechId == "coordinate_authority" and gs.fieldActive then
		if gs.royalVowActive then
			gs.royalVowTurns = (gs.royalVowTurns or 0) - 1
			if gs.royalVowTurns <= 0 then gs.royalVowActive = false end
			return
		end
		local status = mech.statusCycle[gs.statusIndex or 1]
		gs.statusIndex = ((gs.statusIndex or 1) % #mech.statusCycle) + 1
		local dur = math.ceil(math.max(1, mech.statusDuration - math.floor((cs.fortitude or 0) / 10) * mech.fortitudeStatusReduce))
		if status == "bleed" then d.playerBleedTurns = (d.playerBleedTurns or 0) + dur
		elseif status == "slow" then d.playerSlowTurns = (d.playerSlowTurns or 0) + dur
		elseif status == "fear" then d.playerFearTurns = (d.playerFearTurns or 0) + dur end
		S.Msg(player, "The Coordinate inflicts " .. status:upper() .. " for " .. dur .. " turns!", "warn")
	end
end

local function EnemyTurn(player, d)
	if d.enemyHp <= 0 then return end
	if d.enemyRegen and d.enemyRegen > 0 then
		d.enemyHp = math.min(d.enemyMaxHp, d.enemyHp + d.enemyRegen)
	end
	if d.enemyStunned then
		d.enemyStunned = false
		S.RE_EnemyAct:FireClient(player, d.enemyName, "STUNNED")
		return
	end

	local behavior = d.enemyBehavior or "default"
	local baseAtk = d.enemyAtk or 20

	if behavior == "telegraph" then
		if d.telegraphWindup then
			d.telegraphWindup = false
			local titanAtk = D.TITAN_ATTACKS[d.enemyTitanId or "pure"]
			if titanAtk then
				local bigDmg = math.floor(baseAtk * titanAtk.mult)
				if titanAtk.special == "burn" then d.playerBleedTurns = 3
				elseif titanAtk.special == "stun" then d.playerFearTurns = 1
				elseif titanAtk.special == "confuse" then d.playerFearTurns = 2
				elseif titanAtk.special == "pierce" then bigDmg = math.floor(bigDmg * 1.20) end
				local taken = DamagePlayer(player, d, bigDmg)
				S.RE_EnemyAct:FireClient(player, d.enemyName, titanAtk.name)
				S.Msg(player, "⚠ " .. d.enemyName .. " unleashes " .. titanAtk.name .. "! You take " .. taken .. " damage!", "combat")
			end
		else
			d.telegraphWindup = true
			S.RE_EnemyAct:FireClient(player, d.enemyName, "TELEGRAPH")
			S.Msg(player, "⚠ " .. d.enemyName .. " is WINDING UP for a massive attack next turn!", "warn")
		end
		return
	end

	if behavior == "aberrant" then
		local roll = math.random()
		if roll < 0.15 then S.Msg(player, d.enemyName .. " lurches erratically and misses!", "combat") return
		elseif roll > 0.80 then
			for i = 1, 2 do
				local taken = DamagePlayer(player, d, baseAtk)
				S.Msg(player, d.enemyName .. " strikes twice! Hit " .. i .. ": " .. taken .. " damage.", "combat")
			end
			return
		end
	end

	local atkMult = 1.0
	if behavior == "armored" then
		atkMult = 1.15
		if math.random() < 0.25 then atkMult = 2.0 S.Msg(player, d.enemyName .. " charges with FULL ARMOUR!", "warn") end
	end
	if behavior == "crawler" and math.random() < 0.40 then
		d.playerSlowTurns = 2
		S.Msg(player, d.enemyName .. " wraps around you! SLOWED for 2 turns.", "warn")
	end

	local finalAtk = math.floor(baseAtk * atkMult)
	local taken = DamagePlayer(player, d, finalAtk)
	S.RE_EnemyAct:FireClient(player, d.enemyName, "ATTACK")
	S.Msg(player, d.enemyName .. " attacks for " .. taken .. " damage!", "combat")

	TickMechanicEnemyTurn(player, d)
end

local function HandleCombatVictory(player, d)
	local enemyData = d._activeEnemy or {}
	local cs = S.CalcCS(d)
	d.totalKills = (d.totalKills or 0) + 1
	d.killStreak = (d.killStreak or 0) + 1
	d.bestStreak = math.max(d.bestStreak or 0, d.killStreak)

	if enemyData.isBoss then d.bossKills = (d.bossKills or 0) + 1 end
	if enemyData.isEndless then d.endlessHighFloor = math.max(d.endlessHighFloor or 0, enemyData.floor or 0) end

	local baseXp = (enemyData.xp or 0) + (d.hasAutoTrain and 20 or 0)
	local xpGain = S.AwardXP(player, d, baseXp, cs)
	local fundsGain = S.AwardFunds(player, d, enemyData.funds or 0, cs)

	if enemyData.isBoss and (enemyData.bossBonus or 0) > 0 then
		local bonusFunds = S.AwardFunds(player, d, enemyData.bossBonus, cs)
		fundsGain = fundsGain + bonusFunds
	end

	if d.equippedTitan and d.titanSlots[d.equippedTitan] then
		local slot = d.titanSlots[d.equippedTitan]
		local rarityMult = D.TITAN_RARITY_XP_SCALE[slot.rarity] or 1.0
		local titanXp = math.floor((enemyData.xp or 10) * 0.25 / rarityMult)
		slot.titanXP = (slot.titanXP or 0) + titanXp
		local xpNeeded = D.TITAN_XP_PER_LEVEL * rarityMult
		while (slot.titanXP or 0) >= xpNeeded and (slot.titanLevel or 0) < D.TITAN_LEVEL_MAX do
			slot.titanXP = slot.titanXP - xpNeeded
			slot.titanLevel = (slot.titanLevel or 0) + 1
			for stat, gain in pairs(D.TITAN_STAT_PER_LEVEL) do
				slot.bonus = slot.bonus or {}
				slot.bonus[stat] = (slot.bonus[stat] or 0) + gain
			end
			S.Msg(player, slot.name .. " reached level " .. slot.titanLevel .. "!", "system")
		end
	end

	S.BumpChallenge(player, d, "kill", 1)
	if enemyData.isBoss then S.BumpChallenge(player, d, "bossKill", 1) end

	local drop = nil
	if enemyData.drops and #enemyData.drops > 0 then
		if math.random() < 0.60 then drop = enemyData.drops[math.random(#enemyData.drops)] end
	else
		drop = D.RollDrop(enemyData.tier or "weak")
	end
	if drop and D.ITEM_MAP[drop] then
		table.insert(d.inventory, {id=drop, forgeLevel=0})
		S.Msg(player, "ITEM DROP: " .. D.ITEM_MAP[drop].name .. " [" .. D.ITEM_MAP[drop].rarity .. "]!", "reward")
	elseif drop then
		d.consumables = d.consumables or {}
		d.consumables[drop] = (d.consumables[drop] or 0) + 1
		S.Msg(player, "MATERIAL: " .. drop .. " ×1", "reward")
	end

	if enemyData.isBoss and d.clan == "reiss" then
		local healAmt = math.floor(d.maxHp * 0.10)
		d.hp = math.min(d.maxHp, d.hp + healAmt)
	end
	if enemyData.isBoss and d.clan == "zoe" then
		local bonusXp = math.floor(baseXp * 0.20)
		S.AwardXP(player, d, bonusXp, cs)
	end

	S.Msg(player, "Victory! +" .. xpGain .. " XP   +" .. fundsGain .. " Funds", "reward")
	S.CheckAchievements(player, d)

	if d.inCombat then
		local ch = D.CAMPAIGN[d.campaignChapter]
		if ch then
			d.campaignEnemy = d.campaignEnemy + 1
			if d.campaignEnemy > #ch.enemies then
				d.campaignEnemy = 1
				d.chapterClearCounts = d.chapterClearCounts or {}
				d.chapterClearCounts[ch.id] = (d.chapterClearCounts[ch.id] or 0) + 1
				local nextChapter = d.campaignChapter + 1
				if nextChapter <= #D.CAMPAIGN then
					d.campaignChapter = nextChapter
					S.Msg(player, "== CHAPTER COMPLETE! Advancing to: " .. D.CAMPAIGN[nextChapter].name .. " ==", "reward")
				end
				for _, raid in ipairs(D.RAIDS) do
					if raid.unlockChapter == (nextChapter - 1) and not d.raidUnlocks[raid.id] then
						d.raidUnlocks[raid.id] = true
						S.Msg(player, "RAID UNLOCKED: " .. raid.name .. "!", "reward")
					end
				end
			end
		end
	end

	d.inCombat = false
	d.awaitingTurn = false
	d._activeEnemy = nil
	S.Push(player, d)
end

local function HandleCombatDefeat(player, d)
	d.killStreak = 0
	S.Msg(player, "== You have been defeated. Kill streak lost. ==", "warn")
	local cs = S.CalcCS(d)
	d.maxHp = cs.maxHp
	d.hp = math.max(1, math.floor(d.maxHp * 0.30))
	d.inCombat = false
	d.awaitingTurn = false
	d._activeEnemy = nil
	S.Push(player, d)
end

-- ============================================================================
-- 5. SECURE COMBAT ENGINE & VALIDATION (The Core Upgrade)
-- ============================================================================

local function ValidateMove(player, d, moveId)
	if type(moveId) ~= "string" then return false, "Invalid request." end
	if not d.inCombat or not d.awaitingTurn then return false, "Not your turn." end

	local moveData = D.GetMoveDef(moveId)
	if not moveData then return false, "Unknown move." end

	local available = D.GetAvailableMoves(d)
	if not table.find(available, moveId) then return false, moveData.name .. " is not currently available." end
	if (d.level or 1) < (moveData.unlockLevel or 1) then return false, "Level requirement not met." end

	local cd = d.moveCooldowns and d.moveCooldowns[moveId] or 0
	if cd > 0 then return false, moveData.name .. " is on cooldown." end

	if moveData.spearCost and (d.thunderSpears or 0) < moveData.spearCost then return false, "Not enough Thunder Spears." end

	if moveData.type:match("^titan_") then
		if not d.titanShifterMode then return false, "Must be in Titan form." end
		if (d.titanSuppressTurns or 0) > 0 then return false, "Titan form suppressed." end
	end

	return true, moveData
end

local function ProcessPlayerAction(player, d, cs, moveData)
	if moveData.spearCost then d.thunderSpears = d.thunderSpears - moveData.spearCost end
	if moveData.cooldown and moveData.cooldown > 0 then
		d.moveCooldowns = d.moveCooldowns or {}
		d.moveCooldowns[moveData.id] = moveData.cooldown
		if moveData.id == "evasive_maneuver" and d.path == "wandering" then
			d.moveCooldowns[moveData.id] = math.max(0, d.moveCooldowns[moveData.id] - D.PATHS.wandering.passives.evasionCDReduce)
		end
	end

	if moveData.type == "attack" or moveData.type == "titan_attack" or moveData.type == "titan_special" then
		if math.random() > (moveData.accuracy or 1) then
			S.Msg(player, moveData.name .. " missed!", "combat")
			return
		end

		local isTitan = moveData.type:match("^titan_")
		if isTitan then
			d.titanHeat = math.min(D.TITAN_HEAT_MAX, (d.titanHeat or 0) + D.GetHeatCost(moveData.id, cs.titanAffinity or 0))
		end

		local rawDmg = CalcPlayerDamage(player, d, cs, moveData, isTitan)

		if moveData.type == "titan_special" then
			local tAtk = D.TITAN_ATTACKS[(d.equippedTitan and d.titanSlots[d.equippedTitan] and d.titanSlots[d.equippedTitan].id)]
			if tAtk then
				rawDmg = math.floor(rawDmg * (tAtk.mult or 1.0) * D.GetAffinitySpecialMult(cs.titanAffinity or 0))
				if tAtk.special == "stun" then d.enemyStunned = true end
				if tAtk.special == "burn" then d.enemyBurnTurns = (d.enemyBurnTurns or 0) + 3 end
				if tAtk.special == "lifesteal" then
					local heal = math.floor(rawDmg * 0.20)
					d.hp = math.min(d.maxHp, d.hp + heal)
				end
				S.Msg(player, "TITAN SPECIAL: " .. tAtk.name .. " — " .. tAtk.msg, "titan")
			end
		end

		if d.enemyBehavior == "armored" then rawDmg = math.floor(rawDmg * 0.75) end
		if d.path == "marleyan" and d.enemyTitanId then rawDmg = math.floor(rawDmg * D.PATHS.marleyan.passives.antiTitanStrMult) end
		if moveData.spearCost and cs.spearDamageMult > 0 then rawDmg = math.floor(rawDmg * (1 + cs.spearDamageMult)) end

		local actualDmg, blocked = DamageEnemy(player, d, rawDmg, moveData.id)
		if not blocked then S.Msg(player, moveData.name .. " deals " .. actualDmg .. " damage!", isTitan and "titan" or "combat") end
		CheckBossPhases(player, d, d._activeEnemy)

	elseif moveData.type == "heal" then
		local healAmt = D.GetRecoverHeal(cs.wil, d.maxHp)
		d.hp = math.min(d.maxHp, d.hp + healAmt)
		S.Msg(player, moveData.name .. " restores " .. healAmt .. " HP!", "heal")

	elseif moveData.type == "evade" then
		d.evasionActive = true
		S.Msg(player, "Evasive Maneuver! You will dodge the next attack.", "system")

	elseif moveData.type == "titan_buff" then
		if moveData.buffKey == "nextAttackMult" then d.nextAttackMult = moveData.buffValue or 1.5 end
		d.titanHeat = math.min(D.TITAN_HEAT_MAX, (d.titanHeat or 0) + D.GetHeatCost(moveData.id, cs.titanAffinity or 0))

	elseif moveData.type == "clan_active" then
		if d.clan == "yeager" then
			d.enemyFearTurns = 2
			d.nextTitanSpecialBoost = 1.50
		elseif d.clan == "ackerman" then
			local dmg = math.floor((cs.bladeMastery or 0) * moveData.bladeMult + (cs.spd or 0) * moveData.spdMult + (moveData.baseDamage or 0))
			local actual = DamageEnemy(player, d, dmg, moveData.id)
			S.Msg(player, "Ackerman Awakening! True damage: " .. actual .. "!", "titan")
			CheckBossPhases(player, d, d._activeEnemy)
		elseif d.clan == "reiss" then
			d.hp = math.min(d.maxHp, d.hp + math.floor(d.maxHp * moveData.healPct))
			d.bossGimmickState = d.bossGimmickState or {}
			d.bossGimmickState.royalVowActive = true
			d.bossGimmickState.royalVowTurns = moveData.immuneTurns
		elseif d.clan == "tybur" then
			d.tyburShieldHits = moveData.shieldHits
			d.tyburCounterDmgMult = moveData.counterDmgMult
		end

	elseif moveData.type == "path_active" then
		if d.path == "eldian" then
			local dmg = math.floor((cs.str or 0) * moveData.strMult + (cs.titanAffinity or 0) * moveData.affinityMult)
			local actual = DamageEnemy(player, d, dmg, moveData.id)
			d.enemyFearTurns = 1
			CheckBossPhases(player, d, d._activeEnemy)
		elseif d.path == "marleyan" then
			local dmg = math.floor((cs.str or 0) * moveData.strMult + (cs.bladeMastery or 0) * moveData.bladeMult)
			local actual = DamageEnemy(player, d, dmg, moveData.id)
			CheckBossPhases(player, d, d._activeEnemy)
		elseif d.path == "wandering" then
			d.evasionActive = true
			d.wanderingEvadeTurns = moveData.evadeTurns
			d.wanderingCritPending = true
		elseif d.path == "royal" then
			d.hp = math.min(d.maxHp, d.hp + math.floor(d.maxHp * moveData.healPct))
			d.enemyAtkDebuffTurns = moveData.enemyAtkDebuffTurns
			d.enemyAtkDebuffPct = moveData.enemyAtkDebuffPct
		end
	end

	-- Global Heat Suppression Check
	if d.titanHeat and d.titanHeat >= D.TITAN_HEAT_MAX then
		d.titanShifterMode = false
		d.titanSuppressTurns = D.TITAN_SUPPRESS_TURNS
		S.Msg(player, "TITAN HEAT MAX — forced back to human form for " .. D.TITAN_SUPPRESS_TURNS .. " turns!", "warn")
	end
end

local function ResolveTurnEnd(player, d)
	if d.enemyHp <= 0 then HandleCombatVictory(player, d) return end

	if (d.enemyBurnTurns or 0) > 0 then
		local burnDmg = math.floor(d.enemyMaxHp * 0.03)
		d.enemyHp = math.max(0, d.enemyHp - burnDmg)
		d.enemyBurnTurns = d.enemyBurnTurns - 1
		if d.enemyHp <= 0 then HandleCombatVictory(player, d) return end
	end

	if d.evasionActive then
		d.evasionActive = false
		S.Msg(player, d.enemyName .. " attacks — you EVADE!", "system")
	else
		EnemyTurn(player, d)
	end

	TickCooldowns(d)
	TickTitanHeat(d)
	TickPlayerStatus(player, d)

	if d.hp <= 0 then HandleCombatDefeat(player, d) return end

	d.awaitingTurn = true
	S.Push(player, d)
end

-- ============================================================================
-- 6. PUBLIC REMOTES
-- ============================================================================

S.RE_SelectMission.OnServerEvent:Connect(function(player, payload)
	local d = sessions[player.UserId]
	if not d or d.inCombat then return end
	if type(payload) ~= "table" then return end

	local missionType = payload.missionType
	local cs = S.CalcCS(d)
	S.ResetVolatile(d)
	d.maxHp = cs.maxHp
	d.hp = math.min(d.hp or d.maxHp, d.maxHp)

	local enemy = nil

	if missionType == "campaign" then
		local chapter = D.CAMPAIGN[d.campaignChapter]
		if not chapter then return end
		local enemyData = chapter.enemies[d.campaignEnemy]
		if not enemyData then return end
		enemy = D.ScaleCampaignEnemy(enemyData, d.prestige)
	elseif missionType == "raid" then
		local raidDef
		for _, r in ipairs(D.RAIDS) do if r.id == payload.raidId then raidDef = r break end end
		if not raidDef or not d.raidUnlocks[payload.raidId] then return end
		local scaled = D.ScaleRaid(raidDef, 1, d.prestige)
		enemy = { name = raidDef.name, hp = scaled.hp, atk = scaled.atk, regen = scaled.regen, xp = raidDef.xp, funds = raidDef.funds, isBoss = true, tier = "boss", behavior = raidDef.behavior, titanId = raidDef.titanId, drops = raidDef.drops }
	elseif missionType == "endless" then
		d.endlessFloor = (d.endlessFloor or 0) + 1
		enemy = D.EndlessEnemy(d.endlessFloor, d.prestige)
	elseif missionType == "quick_battle" then
		local chapter = D.CAMPAIGN[math.min(d.campaignChapter, #D.CAMPAIGN)]
		local pool = {}
		for _, e in ipairs(chapter.enemies) do if not e.isBoss then table.insert(pool, e) end end
		enemy = D.ScaleCampaignEnemy(pool[math.random(#pool)], d.prestige)
	end

	if not enemy then return end

	d.inCombat = true
	d.awaitingTurn = true
	d.enemyHp = enemy.hp
	d.enemyMaxHp = enemy.hp
	d.enemyName = enemy.name
	d.enemyIsBoss = enemy.isBoss or false
	d.enemyAtk = enemy.atk
	d.enemyRegen = enemy.regen
	d.enemyTier = enemy.tier or "medium"
	d.enemyBehavior = enemy.behavior
	d.enemyTitanId = enemy.titanId
	d._activeEnemy = enemy
	d.bossGimmickState = {}
	d.bossActiveMechanic = nil
	d.bossHeavyStreak = 0

	if enemy.isBoss and enemy.mechanic then
		local mech = D.BOSS_MECHANICS[enemy.mechanic]
		if mech and mech.activeByDefault then
			d.bossActiveMechanic = enemy.mechanic
			ActivateMechanic(player, d, mech)
		end
	end

	S.Msg(player, "== Mission Start: " .. enemy.name .. "  HP: " .. enemy.hp .. " ==", "combat")
	S.Push(player, d)
end)

S.RE_CombatAction.OnServerEvent:Connect(function(player, moveId)
	local d = sessions[player.UserId]
	if not d then return end

	local isValid, result = ValidateMove(player, d, moveId)
	if not isValid then
		S.Msg(player, result, "warn")
		S.Push(player, d)
		return
	end

	local moveData = result
	local cs = S.CalcCS(d)
	d.awaitingTurn = false

	if (d.playerFearTurns or 0) > 0 and moveId ~= "retreat" then
		d.playerFearTurns = d.playerFearTurns - 1
		S.Msg(player, "You are FEARED and cannot act! (" .. d.playerFearTurns .. " turns remaining)", "warn")
		ResolveTurnEnd(player, d)
		return
	end

	if moveId == "retreat" then
		S.RE_Retreat:Fire(player)
		return
	end

	ProcessPlayerAction(player, d, cs, moveData)
	ResolveTurnEnd(player, d)
end)

S.RE_Retreat.OnServerEvent:Connect(function(player)
	local d = sessions[player.UserId]
	if not d or not d.inCombat then return end
	d.inCombat = false
	d.awaitingTurn = false
	d.killStreak = 0
	d._activeEnemy = nil
	S.ResetVolatile(d)
	d.hp = math.max(1, math.floor((S.CalcCS(d).maxHp) * 0.50))
	S.Msg(player, "Retreat! No rewards. Kill streak reset.", "system")
	S.Push(player, d)
end)

local RE_TitanShift = game:GetService("ReplicatedStorage"):WaitForChild("AOT"):WaitForChild("Remotes"):WaitForChild("TitanShift", 5)
if not RE_TitanShift then
	RE_TitanShift = Instance.new("RemoteEvent")
	RE_TitanShift.Name = "TitanShift"
	RE_TitanShift.Parent = game:GetService("ReplicatedStorage"):WaitForChild("AOT"):WaitForChild("Remotes")
end

RE_TitanShift.OnServerEvent:Connect(function(player)
	local d = sessions[player.UserId]
	if not d or not d.inCombat then return end
	if d.clan == "ackerman" then S.Msg(player, "Ackerman bloodline cannot use titan form.", "warn") return end
	if not d.equippedTitan or not d.titanSlots[d.equippedTitan] then return end
	if (d.titanSuppressTurns or 0) > 0 then S.Msg(player, "Titan form suppressed for " .. d.titanSuppressTurns .. " more turn(s).", "warn") return end

	if d.titanShifterMode then
		d.titanShifterMode = false
		S.Msg(player, "You revert to human form.", "system")
	else
		d.titanShifterMode = true
		S.Msg(player, "TITAN SHIFT — " .. d.titanSlots[d.equippedTitan].name .. " awakens!", "titan")
	end
	S.Push(player, d)
end)

-- ============================================================================
-- 7. PVP DUEL SYSTEM
-- ============================================================================

local pvpMatchCounter = 0
local function NewMatchId() pvpMatchCounter = pvpMatchCounter + 1 return "pvp_" .. pvpMatchCounter end

S.RE_PVPChallenge.OnServerEvent:Connect(function(challenger, targetUserId)
	local d1 = sessions[challenger.UserId]
	if not d1 or d1.inCombat then return end
	local target = Players:GetPlayerByUserId(targetUserId)
	local d2 = target and sessions[targetUserId]
	if not d2 or d2.inCombat then return end

	S.pendingInvites[targetUserId] = { type = "pvp", fromUserId = challenger.UserId, expiry = os.time() + D.PVP_INVITE_TIMEOUT }
	S.Pop(target, "PVP CHALLENGE", challenger.DisplayName .. " challenges you to a duel!", "amber")
	S.RE_PVPChallenge:FireClient(target, challenger.UserId, challenger.DisplayName)
end)

S.RE_PVPResponse.OnServerEvent:Connect(function(target, accepted)
	local invite = S.pendingInvites[target.UserId]
	if not invite or invite.type ~= "pvp" then return end
	if os.time() > invite.expiry then S.pendingInvites[target.UserId] = nil return end

	local challenger = Players:GetPlayerByUserId(invite.fromUserId)
	S.pendingInvites[target.UserId] = nil
	if not accepted then return end

	local d1 = challenger and sessions[invite.fromUserId]
	local d2 = sessions[target.UserId]
	if not d1 or not d2 or d1.inCombat or d2.inCombat then return end

	local matchId = NewMatchId()
	local cs1, cs2 = S.CalcCS(d1), S.CalcCS(d2)

	S.pvpMatches[matchId] = {
		p1Id = invite.fromUserId, p2Id = target.UserId, turn = invite.fromUserId, round = 1,
		p1Hp = cs1.maxHp, p1MaxHp = cs1.maxHp, p2Hp = cs2.maxHp, p2MaxHp = cs2.maxHp, matchId = matchId
	}
	d1.inCombat, d1.pvpMatchId = true, matchId
	d2.inCombat, d2.pvpMatchId = true, matchId

	S.Msg(challenger, "== PVP DUEL START vs " .. target.DisplayName .. "! You go first! ==", "system")
	S.Msg(target, "== PVP DUEL START vs " .. challenger.DisplayName .. "! Challenger goes first. ==", "system")
	S.Push(challenger, d1)
	S.Push(target, d2)
end)

S.RE_PVPAction.OnServerEvent:Connect(function(player, moveId)
	local d = sessions[player.UserId]
	if not d or not d.inCombat or not d.pvpMatchId then return end
	local match = S.pvpMatches[d.pvpMatchId]
	if not match or match.turn ~= player.UserId then return end

	local moveData = D.GetMoveDef(moveId)
	if not moveData then return end

	local isP1 = match.p1Id == player.UserId
	local oppId = isP1 and match.p2Id or match.p1Id
	local opponent = Players:GetPlayerByUserId(oppId)
	local dOpp = sessions[oppId]
	if not opponent or not dOpp then return end

	local cs, csOpp = S.CalcCS(d), S.CalcCS(dOpp)
	local myHp, oppHp = (isP1 and match.p1Hp or match.p2Hp), (isP1 and match.p2Hp or match.p1Hp)

	if moveData.type == "attack" or moveData.type == "titan_attack" then
		local dmg = math.floor((moveData.baseDamage or 12) + cs.str * 0.6)
		if d.path == "royal" then dmg = math.floor(dmg * D.PATHS.royal.passives.pvpStrMult) end
		local defReduction = math.floor(csOpp.def * 0.5)
		if dOpp.path == "royal" then defReduction = math.floor(defReduction * D.PATHS.royal.passives.pvpDefMult) end

		dmg = math.max(1, dmg - defReduction)
		oppHp = math.max(0, oppHp - dmg)
		S.Msg(player, "Your " .. moveData.name .. " hits for " .. dmg .. " damage!", "combat")
		S.Msg(opponent, player.DisplayName .. "'s " .. moveData.name .. " hits you for " .. dmg .. " damage!", "combat")
	elseif moveData.type == "heal" then
		local heal = math.floor(moveData.healBase + cs.wil * moveData.healMult)
		myHp = math.min((isP1 and match.p1MaxHp or match.p2MaxHp), myHp + heal)
		S.Msg(player, moveData.name .. " restores " .. heal .. " HP.", "heal")
	end

	if isP1 then match.p1Hp, match.p2Hp = myHp, oppHp else match.p2Hp, match.p1Hp = myHp, oppHp end

	if oppHp <= 0 or match.round >= D.PVP_MAX_TURNS * 2 then
		local winnerId = (oppHp <= 0) and player.UserId or ((match.p1Hp / match.p1MaxHp > match.p2Hp / match.p2MaxHp) and match.p1Id or match.p2Id)
		local d1, d2 = sessions[match.p1Id], sessions[match.p2Id]
		local pl1, pl2 = Players:GetPlayerByUserId(match.p1Id), Players:GetPlayerByUserId(match.p2Id)

		if winnerId and d1 and d2 then
			local winnerIsP1 = winnerId == match.p1Id
			local winnerD, loserD = (winnerIsP1 and d1 or d2), (winnerIsP1 and d2 or d1)
			local winnerPl, loserPl = (winnerIsP1 and pl1 or pl2), (winnerIsP1 and pl2 or pl1)

			local eloW = D.CalcEloChange(winnerD.pvpElo, loserD.pvpElo, true)
			local eloL = D.CalcEloChange(loserD.pvpElo, winnerD.pvpElo, false)
			winnerD.pvpElo = (winnerD.pvpElo or 1000) + eloW
			loserD.pvpElo = math.max(0, (loserD.pvpElo or 1000) + eloL)
			winnerD.pvpWins, loserD.pvpLosses = (winnerD.pvpWins or 0) + 1, (loserD.pvpLosses or 0) + 1

			local reward = math.floor(500 + winnerD.pvpElo * 0.5)
			winnerD.funds = (winnerD.funds or 0) + reward
			if winnerPl then S.Msg(winnerPl, "== PVP WIN! +" .. eloW .. " ELO  +" .. reward .. " Funds ==", "reward") end
			if loserPl then S.Msg(loserPl, "== PVP LOSS. " .. eloL .. " ELO ==", "warn") end
		end

		if d1 then d1.inCombat, d1.pvpMatchId = false, nil end
		if d2 then d2.inCombat, d2.pvpMatchId = false, nil end
		S.pvpMatches[d.pvpMatchId] = nil
		if pl1 and d1 then S.Push(pl1, d1) end
		if pl2 and d2 then S.Push(pl2, d2) end
		return
	end

	match.round = match.round + 1
	match.turn = oppId
	S.Msg(opponent, "It's your turn!", "system")
	S.Push(player, d)
	S.Push(opponent, dOpp)
end)

print("[AOT_Server_Combat] Optimized Module Loaded.")