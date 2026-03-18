-- @ScriptType: Script
-- AOT_Server_Combat  (Script)
-- Place in: ServerScriptService > AOT_Server_Combat
-- Handles: mission start, player turn actions, enemy AI, rewards, PvP turns.
-- v1.0.0

local Players  = game:GetService("Players")
local SS       = game:GetService("ServerScriptService")
local S        = require(SS:WaitForChild("AOT_Sessions"))
local D        = require(game:GetService("ReplicatedStorage"):WaitForChild("AOT"):WaitForChild("AOT_Data"))
local sessions = S.sessions

-- ────────────────────────────────────────────────────────────
-- INTERNAL HELPERS
-- ────────────────────────────────────────────────────────────

-- Clamp cooldown table entries down by 1 each turn
local function TickCooldowns(d)
	if not d.moveCooldowns then return end
	for move, cd in pairs(d.moveCooldowns) do
		if cd > 0 then d.moveCooldowns[move] = cd - 1 end
	end
end

-- Tick titan heat decay when not in titan mode
local function TickTitanHeat(d)
	if d.titanShifterMode then return end
	local decay = D.TITAN_HEAT_DECAY
	-- Eldian path gives extra heat decay
	if d.path == "eldian" then
		decay = decay + D.PATHS.eldian.passives.titanHeatDecay
	end
	d.titanHeat = math.max(0, (d.titanHeat or 0) - decay)
	if (d.titanSuppressTurns or 0) > 0 then
		d.titanSuppressTurns = d.titanSuppressTurns - 1
	end
end

-- Tick player status effects (bleed, slow, fear)
local function TickPlayerStatus(player, d)
	if (d.playerBleedTurns or 0) > 0 then
		local bleedDmg = math.floor((d.maxHp or 100) * 0.04)
		d.hp = math.max(1, d.hp - bleedDmg)
		d.playerBleedTurns = d.playerBleedTurns - 1
		S.Msg(player, "You take " .. bleedDmg .. " bleed damage! (" .. d.playerBleedTurns .. " turns remaining)", "warn")
	end
	if (d.playerSlowTurns or 0) > 0 then
		d.playerSlowTurns = d.playerSlowTurns - 1
	end
	if (d.playerFearTurns or 0) > 0 then
		d.playerFearTurns = d.playerFearTurns - 1
	end
end

-- Compute player attack damage for a given move
local function CalcPlayerDamage(player, d, cs, moveData, isTitan)
	local base = moveData.baseDamage or 10
	local dmg  = base

	-- Multi-stat contribution
	if moveData.strMult       then dmg = dmg + math.floor((cs.str           or 0) * moveData.strMult)       end
	if moveData.bladeMult     then dmg = dmg + math.floor((cs.bladeMastery  or 0) * moveData.bladeMult)     end
	if moveData.affinityMult  then dmg = dmg + math.floor((cs.titanAffinity or 0) * moveData.affinityMult)  end
	if moveData.spdMult       then dmg = dmg + math.floor((cs.spd           or 0) * moveData.spdMult)       end
	if moveData.wilMult       then dmg = dmg + math.floor((cs.wil           or 0) * moveData.wilMult)       end

	-- Fallback: old single statKey system
	if not moveData.strMult and not moveData.bladeMult and moveData.statKey then
		local stat = cs[moveData.statKey] or cs.str or 0
		dmg = dmg + math.floor(stat * (moveData.damageMult or 1.0))
	end

	-- Status debuffs
	if (d.playerFearTurns or 0) > 0 then dmg = math.floor(dmg * 0.70) end
	if (d.playerSlowTurns or 0) > 0 then dmg = math.floor(dmg * 0.85) end

	-- Next attack buff (titan roar)
	if (d.nextAttackMult or 1) > 1 then
		dmg = math.floor(dmg * d.nextAttackMult)
		d.nextAttackMult = 1
	end
	-- Wandering path guaranteed crit
	if d.wanderingCritPending then
		dmg = math.floor(dmg * (D.PATH_MOVES.wandering.critMult or 2.0))
		d.wanderingCritPending = false
		S.Msg(player, "CRITICAL HIT! Wandering Ghost Step strikes true!", "combat")
	end
	-- Yeager titan special boost
	if isTitan and (d.nextTitanSpecialBoost or 1) > 1 then
		dmg = math.floor(dmg * d.nextTitanSpecialBoost)
		d.nextTitanSpecialBoost = 1
	end

	return math.max(1, dmg)
end

-- Apply damage to enemy, routing through active boss mechanics.
-- Returns actual damage dealt (after reductions), plus a "blocked" flag.
local function DamageEnemy(player, d, rawDmg, moveId)
	local cs        = S.CalcCS(d)
	local mechId    = d.bossActiveMechanic
	local mech      = mechId and D.BOSS_MECHANICS[mechId]
	local isPierce  = D.IsPierceMove(moveId) or D.IsTitanAffinityMove(moveId)
	local isTrueAtk = moveId and (D.GetMoveDef(moveId) or {}).trueDamage

	-- ── Nape Armor: redirect damage to the armor HP pool ─────
	if mech and mechId == "nape_armor" and (d.bossGimmickState or {}).armorActive then
		local gs = d.bossGimmickState
		-- Pierce moves deal full damage to armor; normal attacks deal 30% to armor
		local armorDmg = isPierce and rawDmg or math.floor(rawDmg * (1 - mech.damageReductionPct))
		-- Consecutive heavy_strike bonus
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
			S.Pop(player, "ARMOUR BROKEN", "Reiner's nape is exposed. Full damage restored.", "amber")
		else
			S.Msg(player, "Armour HP: " .. gs.armorHp .. " remaining.", "combat")
		end
		d.enemyHp = math.max(0, d.enemyHp - 0)  -- no HP damage to boss while armor active
		return armorDmg, true

		-- ── Crystal Construct: redirect all damage to barrier HP ─
	elseif mech and mechId == "crystal_construct" and (d.bossGimmickState or {}).barrierActive then
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
			S.Pop(player, "BARRIER BROKEN", "The crystal construct collapses. Attack the War Hammer Titan!", "amber")
		else
			S.Msg(player, "Barrier HP: " .. gs.barrierHp .. " remaining.", "combat")
		end
		return barrierDmg, true

		-- ── Crystal Hardening: reduce non-pierce damage 60% ──────
	elseif mech and mechId == "crystal_hardening" and (d.bossGimmickState or {}).hardened then
		local gs = d.bossGimmickState
		local finalDmg = rawDmg
		if isPierce or isTrueAtk then
			-- Full damage; chance to shatter hardening
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

		-- ── Coordinate Authority: reflect non-pierce attacks ─────
	elseif mech and mechId == "coordinate_authority" and (d.bossGimmickState or {}).fieldActive then
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

		-- ── Steam Release: during steam turns, attacks deal 20% ──
	elseif mech and mechId == "steam_release" and (d.bossGimmickState or {}).steamActive then
		local finalDmg = math.floor(rawDmg * (1 - mech.steamDmgReductionPct))
		S.Msg(player, "Steam blocks most damage! Wait for a window turn.", "warn")
		d.enemyHp = math.max(0, d.enemyHp - finalDmg)
		return finalDmg, true
	end

	-- ── Default: no active mechanic ───────────────────────────
	d.enemyHp = math.max(0, d.enemyHp - rawDmg)
	return rawDmg, false
end

-- Check boss phase transitions and activate per-boss mechanics.
-- Called after every player action that damages the boss.
local function CheckBossPhases(player, d, enemyData)
	if not d.enemyIsBoss or not enemyData then return end
	local phases = enemyData.phases
	if not phases then
		-- Fallback: generic phase system for bosses with no custom phases
		local hpPct = d.enemyHp / d.enemyMaxHp
		if not d.bossPhase2 and hpPct <= 0.60 then
			d.bossPhase2 = true
			d.enemyAtk   = math.floor(d.enemyAtk * 1.25)
			d.enemyRegen = math.floor((d.enemyRegen or 0) * 1.20 + 10)
			S.Msg(player, "⚠ " .. d.enemyName .. " enters PHASE 2!", "warn")
		elseif not d.bossPhase3 and hpPct <= 0.30 then
			d.bossPhase3 = true
			d.enemyAtk   = math.floor(d.enemyAtk * 1.20)
			S.Msg(player, "⚠ " .. d.enemyName .. " enters FINAL PHASE!", "warn")
		end
		return
	end

	local hpPct = d.enemyHp / d.enemyMaxHp
	d.bossGimmickState = d.bossGimmickState or {}

	-- Phase 3 check (lower threshold — check first)
	if not d.bossPhase3 and phases[3] and hpPct <= (phases[3].hpThreshold or 0.30) then
		d.bossPhase3 = true
		local p = phases[3]
		if p.atkMult   then d.enemyAtk   = math.floor(d.enemyAtk * p.atkMult) end
		if p.regenMult then d.enemyRegen = math.floor((d.enemyRegen or 0) * p.regenMult) end
		S.Msg(player, "⚠ PHASE 3 — " .. (p.msg or d.enemyName .. " reaches its final form!"), "warn")
		S.Pop(player, "FINAL PHASE", p.msg or "Survive!", "red")
		-- Activate secondary mechanic if stacked (e.g. Eren ch8)
		if p.activateMechanic2 and enemyData.mechanicPhase2 then
			d.bossActiveMechanic = enemyData.mechanicPhase2
			local m2 = D.BOSS_MECHANICS[enemyData.mechanicPhase2]
			if m2 then
				ActivateMechanic(player, d, m2)
			end
		end

		-- Phase 2 check
	elseif not d.bossPhase2 and phases[2] and hpPct <= (phases[2].hpThreshold or 0.60) then
		d.bossPhase2 = true
		local p = phases[2]
		if p.atkMult   then d.enemyAtk   = math.floor(d.enemyAtk * p.atkMult) end
		if p.regenMult then d.enemyRegen = math.floor((d.enemyRegen or 0) * p.regenMult) end
		S.Msg(player, "⚠ PHASE 2 — " .. (p.msg or d.enemyName .. " powers up!"), "warn")
		S.Pop(player, "PHASE 2", p.msg or "Power up!", "amber")
		-- Activate primary mechanic at phase 2 if flagged
		if p.activateMechanic and enemyData.mechanic then
			d.bossActiveMechanic = enemyData.mechanic
			local m = D.BOSS_MECHANICS[enemyData.mechanic]
			if m then ActivateMechanic(player, d, m) end
		end
	end
end

-- Initialise a mechanic's runtime state in d.bossGimmickState
function ActivateMechanic(player, d, mech)
	d.bossGimmickState = d.bossGimmickState or {}
	local gs = d.bossGimmickState
	if mech.id == "crystal_hardening" then
		gs.hardened = true
		S.Pop(player, "HARDENING", mech.announcement, "amber")
	elseif mech.id == "nape_armor" then
		gs.armorActive = true
		gs.armorHp     = mech.armorHp
		S.Pop(player, "ARMORED NAPE", mech.announcement, "amber")
	elseif mech.id == "boulder_barrage" then
		gs.barrageTimer = 0
		S.Msg(player, mech.announcement, "warn")
	elseif mech.id == "steam_release" then
		gs.steamActive = false  -- starts on a window turn
		S.Pop(player, "STEAM RELEASE", mech.announcement, "amber")
	elseif mech.id == "crystal_construct" then
		gs.barrierActive = true
		gs.barrierHp     = mech.barrierHp
		S.Pop(player, "CRYSTAL CONSTRUCT", mech.announcement, "amber")
	elseif mech.id == "coordinate_authority" then
		gs.fieldActive    = true
		gs.statusIndex    = 1  -- cycles through mech.statusCycle
		S.Pop(player, "COORDINATE", mech.announcement, "red")
	end
	S.Msg(player, "MECHANIC: " .. mech.name .. " — " .. (mech.announcement or ""), "warn")
end

-- Apply any per-enemy-turn mechanic effects (steam burn, barrage tick, coordinate status)
local function TickMechanicEnemyTurn(player, d, enemyData)
	local mechId = d.bossActiveMechanic
	if not mechId then return end
	local mech = D.BOSS_MECHANICS[mechId]
	if not mech then return end
	local gs = d.bossGimmickState or {}
	local cs = S.CalcCS(d)

	if mechId == "steam_release" then
		-- Flip steam flag each enemy turn
		gs.steamActive = not gs.steamActive
		if gs.steamActive then
			-- Apply steam burn: 8% max HP, reduced by WIL
			local burnPct = mech.steamBurnPct - math.floor(cs.wil / 10) * mech.wilBurnReductePer10
			burnPct = math.max(0.01, burnPct)
			-- Royal Vow immunity check
			if not gs.royalVowActive then
				local burn = math.floor(d.maxHp * burnPct)
				d.hp = math.max(1, d.hp - burn)
				S.Msg(player, "STEAM BURNS you for " .. burn .. " HP! Next attack greatly reduced.", "warn")
			end
		else
			S.Msg(player, "Steam clears — window turn! Deal full damage now!", "combat")
		end

	elseif mechId == "boulder_barrage" then
		gs.barrageTimer = (gs.barrageTimer or 0) + 1
		if gs.barrageTimer >= mech.barrageInterval then
			gs.barrageTimer = 0
			-- Deliver the barrage this turn (telegraphed via announcement, then hit)
			local barrageDmg = math.floor((d.enemyAtk or 50) * mech.barrageDamageMult)
			-- Check if evasive_maneuver is currently active on the player
			if d.evasionActive then
				d.evasionActive = false
				S.Msg(player, "You evade the Boulder Barrage! ODM to safety!", "combat")
			else
				local fortitude = cs.fortitude or 0
				local slowTurns = math.max(0, mech.inflictsSlowTurns - math.floor(fortitude / 10) * mech.fortitudeSlowReduce)
				local taken = DamagePlayer(player, d, barrageDmg)
				if slowTurns > 0 then
					d.playerSlowTurns = (d.playerSlowTurns or 0) + math.floor(slowTurns)
					S.Msg(player, "BOULDER BARRAGE hits for " .. taken .. " — SLOWED for " .. math.floor(slowTurns) .. " turns!", "warn")
				else
					S.Msg(player, "BOULDER BARRAGE hits for " .. taken .. " — Fortitude resists the slow!", "combat")
				end
			end
		else
			local turnsLeft = mech.barrageInterval - gs.barrageTimer
			if turnsLeft == 1 then
				S.Msg(player, "⚠ Zeke is winding up a BOULDER BARRAGE — act fast!", "warn")
			end
		end

	elseif mechId == "coordinate_authority" then
		if not gs.fieldActive then return end
		-- Royal Vow active: skip all status infliction
		if gs.royalVowActive then
			gs.royalVowTurns = (gs.royalVowTurns or 0) - 1
			if gs.royalVowTurns <= 0 then
				gs.royalVowActive = false
				S.Msg(player, "Royal Vow expires — the Coordinate field reasserts!", "warn")
			end
			return
		end
		-- Cycle through status effects
		local cycle  = mech.statusCycle
		local idx    = gs.statusIndex or 1
		local status = cycle[idx]
		gs.statusIndex = (idx % #cycle) + 1
		-- Fortitude reduces duration
		local fortitude = cs.fortitude or 0
		local dur = math.max(1, mech.statusDuration
			- math.floor(fortitude / 10) * mech.fortitudeStatusReduce)
		dur = math.ceil(dur)
		if status == "bleed" then
			d.playerBleedTurns = (d.playerBleedTurns or 0) + dur
			S.Msg(player, "The Coordinate inflicts BLEED for " .. dur .. " turns!", "warn")
		elseif status == "slow" then
			d.playerSlowTurns = (d.playerSlowTurns or 0) + dur
			S.Msg(player, "The Coordinate inflicts SLOW for " .. dur .. " turns!", "warn")
		elseif status == "fear" then
			d.playerFearTurns = (d.playerFearTurns or 0) + dur
			S.Msg(player, "The Coordinate inflicts FEAR for " .. dur .. " turns!", "warn")
		end
	end
	d.bossGimmickState = gs
end

-- Apply damage to player; returns actual damage taken
local function DamagePlayer(player, d, rawAtk)
	local cs  = S.CalcCS(d)
	-- Royal Founding Scream: enemy ATK debuffed for N turns
	local atk = rawAtk
	if (d.enemyAtkDebuffTurns or 0) > 0 then
		atk = math.floor(atk * (1 - (d.enemyAtkDebuffPct or 0.50)))
		d.enemyAtkDebuffTurns = d.enemyAtkDebuffTurns - 1
	end
	-- Tybur crystal shield absorbs hits and counters
	if (d.tyburShieldHits or 0) > 0 then
		d.tyburShieldHits = d.tyburShieldHits - 1
		local counter = math.floor(atk * (d.tyburCounterDmgMult or 0.8))
		d.enemyHp = math.max(0, d.enemyHp - counter)
		S.Msg(player, "Crystal shield absorbs the hit and counters for " .. counter .. "!", "titan")
		return 0
	end
	-- DEF reduction
	local red = math.floor(cs.def * 0.6)
	local dmg = math.max(1, atk - red)
	d.hp = math.max(0, d.hp - dmg)
	return dmg
end

-- ────────────────────────────────────────────────────────────
-- ENEMY AI — takes enemy turn after player acts
-- ────────────────────────────────────────────────────────────
local function EnemyTurn(player, d)
	if d.enemyHp <= 0 then return end  -- already dead

	-- Enemy regen
	if d.enemyRegen and d.enemyRegen > 0 then
		d.enemyHp = math.min(d.enemyMaxHp, d.enemyHp + d.enemyRegen)
	end

	-- Stunned — skip turn
	if d.enemyStunned then
		d.enemyStunned = false
		S.RE_EnemyAct:FireClient(player, d.enemyName, "STUNNED")
		S.Msg(player, d.enemyName .. " is stunned and loses their turn!", "combat")
		return
	end

	local behavior = d.enemyBehavior or "default"
	local baseAtk  = d.enemyAtk or 20

	-- Telegraph: warn one turn before the big attack
	if behavior == "telegraph" then
		if d.telegraphWindup then
			-- Deliver the telegraphed attack
			d.telegraphWindup = false
			local titanAtk = D.TITAN_ATTACKS[d.enemyTitanId or "pure"]
			if titanAtk then
				local bigDmg = math.floor(baseAtk * titanAtk.mult)
				-- Apply special effect
				if titanAtk.special == "burn" then
					d.playerBleedTurns = 3
					S.Msg(player, "You are BURNING! 3 turns of bleed.", "warn")
				elseif titanAtk.special == "stun" then
					-- Player can't act next turn (handled via fear)
					d.playerFearTurns = 1
					S.Msg(player, "You are FEARED by the titan's power! Miss next turn.", "warn")
				elseif titanAtk.special == "confuse" then
					d.playerFearTurns = 2
				elseif titanAtk.special == "pierce" then
					bigDmg = math.floor(bigDmg * 1.20)  -- pierce adds extra
				end
				local taken = DamagePlayer(player, d, bigDmg)
				S.RE_EnemyAct:FireClient(player, d.enemyName, titanAtk.name)
				S.Msg(player, "⚠ " .. d.enemyName .. " unleashes " .. titanAtk.name .. "! You take " .. taken .. " damage!", "combat")
			end
		else
			-- Wind up — warn the player
			d.telegraphWindup = true
			S.RE_EnemyAct:FireClient(player, d.enemyName, "TELEGRAPH")
			S.Msg(player, "⚠ " .. d.enemyName .. " is WINDING UP for a massive attack next turn!", "warn")
		end
		return
	end

	-- Aberrant: sometimes skips, sometimes double-hits
	if behavior == "aberrant" then
		local roll = math.random()
		if roll < 0.15 then
			S.Msg(player, d.enemyName .. " lurches erratically and misses!", "combat")
			return
		elseif roll > 0.80 then
			-- Double hit
			for i = 1, 2 do
				local taken = DamagePlayer(player, d, baseAtk)
				S.Msg(player, d.enemyName .. " strikes twice! Hit " .. i .. ": " .. taken .. " damage.", "combat")
			end
			return
		end
	end

	-- Armored: 25% damage reduction, occasional power strike
	local atkMult = 1.0
	if behavior == "armored" then
		-- Already handled in DamageEnemy; for enemy attacks, armored adds 15% more
		atkMult = 1.15
		if math.random() < 0.25 then
			atkMult = 2.0
			S.Msg(player, d.enemyName .. " charges with FULL ARMOUR!", "warn")
		end
	end

	-- Crawler: applies slow on hit
	if behavior == "crawler" then
		if math.random() < 0.40 then
			d.playerSlowTurns = 2
			S.Msg(player, d.enemyName .. " wraps around you! SLOWED for 2 turns.", "warn")
		end
	end

	-- Standard attack
	local finalAtk = math.floor(baseAtk * atkMult)
	local taken    = DamagePlayer(player, d, finalAtk)
	S.RE_EnemyAct:FireClient(player, d.enemyName, "ATTACK")
	S.Msg(player, d.enemyName .. " attacks for " .. taken .. " damage!", "combat")

	-- Tick per-boss mechanic effects (steam, barrage, coordinate status cycling)
	TickMechanicEnemyTurn(player, d, nil)

	-- ────────────────────────────────────────────────────────────
	-- COMBAT VICTORY — award rewards and advance progress
	-- ────────────────────────────────────────────────────────────
	local function CombatVictory(player, d, enemyData)
		local cs     = S.CalcCS(d)
		d.totalKills = (d.totalKills or 0) + 1
		d.killStreak = (d.killStreak or 0) + 1
		d.bestStreak = math.max(d.bestStreak or 0, d.killStreak)
		if enemyData.isBoss then
			d.bossKills = (d.bossKills or 0) + 1
		end

		-- Endless: track highest floor reached
		if enemyData.isEndless then
			d.endlessHighFloor = math.max(d.endlessHighFloor or 0, enemyData.floor or 0)
		end

		-- AutoTrain: bonus XP on every kill
		local baseXp = enemyData.xp or 0
		if d.hasAutoTrain then
			baseXp = baseXp + 20
		end

		local xpGain   = S.AwardXP(player, d, baseXp, cs)
		local fundsGain = S.AwardFunds(player, d, enemyData.funds or 0, cs)

		-- Boss bonus funds
		if enemyData.isBoss and (enemyData.bossBonus or 0) > 0 then
			local bonusFunds = S.AwardFunds(player, d, enemyData.bossBonus, cs)
			fundsGain = fundsGain + bonusFunds
			S.Msg(player, "BOSS BONUS: +" .. bonusFunds .. " Funds!", "reward")
		end

		-- Titan XP: equipped titan gains XP from kills
		if d.equippedTitan and d.titanSlots[d.equippedTitan] then
			local slot     = d.titanSlots[d.equippedTitan]
			local rarityMult = D.TITAN_RARITY_XP_SCALE[slot.rarity] or 1.0
			local titanXp  = math.floor((enemyData.xp or 10) * 0.25 / rarityMult)
			slot.titanXP   = (slot.titanXP or 0) + titanXp
			local xpNeeded = D.TITAN_XP_PER_LEVEL * rarityMult
			while (slot.titanXP or 0) >= xpNeeded and (slot.titanLevel or 0) < D.TITAN_LEVEL_MAX do
				slot.titanXP    = slot.titanXP - xpNeeded
				slot.titanLevel = (slot.titanLevel or 0) + 1
				-- Apply stat gains
				for stat, gain in pairs(D.TITAN_STAT_PER_LEVEL) do
					slot.bonus = slot.bonus or {}
					slot.bonus[stat] = (slot.bonus[stat] or 0) + gain
				end
				S.Msg(player, slot.name .. " reached level " .. slot.titanLevel .. "!", "system")
			end
		end

		-- Daily challenge progress
		S.BumpChallenge(player, d, "kill", 1)
		if enemyData.isBoss then
			S.BumpChallenge(player, d, "bossKill", 1)
		end
		if d.titanShifterMode then
			-- counted here as a titan kill tick even if they de-shifted mid-fight
		end

		-- Item / material drop
		local drop = nil
		if enemyData.drops and #enemyData.drops > 0 then
			if math.random() < 0.60 then
				drop = enemyData.drops[math.random(#enemyData.drops)]
			end
		else
			drop = D.RollDrop(enemyData.tier or "weak")
		end
		if drop and D.ITEM_MAP[drop] then
			table.insert(d.inventory, {id=drop, forgeLevel=0})
			S.Msg(player, "ITEM DROP: " .. D.ITEM_MAP[drop].name
				.. " [" .. D.ITEM_MAP[drop].rarity .. "]!", "reward")
		elseif drop then
			d.consumables = d.consumables or {}
			d.consumables[drop] = (d.consumables[drop] or 0) + 1
			S.Msg(player, "MATERIAL: " .. drop .. " ×1", "reward")
		end

		-- Reiss clan: heal on boss kill
		if enemyData.isBoss and d.clan == "reiss" then
			local healAmt = math.floor(d.maxHp * 0.10)
			d.hp = math.min(d.maxHp, d.hp + healAmt)
			S.Msg(player, "Reiss bloodline heals " .. healAmt .. " HP on boss kill.", "heal")
		end

		-- Zoe clan: bonus XP from bosses
		if enemyData.isBoss and d.clan == "zoe" then
			local bonusXp = math.floor(baseXp * 0.20)
			S.AwardXP(player, d, bonusXp, cs)
			S.Msg(player, "Zoe Survey Bonus: +" .. bonusXp .. " XP!", "reward")
		end

		S.Msg(player, "Victory!  +" .. xpGain .. " XP   +" .. fundsGain .. " Funds", "reward")
		S.CheckAchievements(player, d)
	end

	-- ────────────────────────────────────────────────────────────
	-- COMBAT DEFEAT
	-- ────────────────────────────────────────────────────────────
	local function CombatDefeat(player, d)
		d.killStreak = 0
		S.Msg(player, "== You have been defeated. Your kill streak resets. ==", "warn")
		-- Restore 30% HP on defeat so they're not stuck at 0
		local cs = S.CalcCS(d)
		d.maxHp  = cs.maxHp
		d.hp     = math.max(1, math.floor(d.maxHp * 0.30))
	end

	-- ────────────────────────────────────────────────────────────
	-- START MISSION
	-- payload = {missionType, chapterId/raidId, partyId?}
	-- ────────────────────────────────────────────────────────────
	S.RE_SelectMission.OnServerEvent:Connect(function(player, payload)
		local d = sessions[player.UserId]
		if not d or d.inCombat then return end
		if type(payload) ~= "table" then return end

		local missionType = payload.missionType
		local cs = S.CalcCS(d)
		d.maxHp  = cs.maxHp
		d.hp     = math.min(d.hp, d.maxHp)

		S.ResetVolatile(d)
		d.hp = math.min(d.hp, d.maxHp)

		local enemy = nil

		if missionType == "campaign" then
			local chapter = D.CAMPAIGN[d.campaignChapter]
			if not chapter then
				S.Msg(player, "All campaign chapters complete. Prestige to continue.", "warn")
				return
			end
			local enemyData = chapter.enemies[d.campaignEnemy]
			if not enemyData then
				S.Msg(player, "Chapter complete.", "system")
				return
			end
			enemy = D.ScaleCampaignEnemy(enemyData, d.prestige)

		elseif missionType == "raid" then
			local raidId  = payload.raidId
			local raidDef = nil
			for _, r in ipairs(D.RAIDS) do
				if r.id == raidId then raidDef = r break end
			end
			if not raidDef then return end
			if not d.raidUnlocks[raidId] then
				S.Msg(player, "Raid not yet unlocked.", "warn")
				return
			end
			local scaled = D.ScaleRaid(raidDef, 1, d.prestige)
			enemy = {
				name      = raidDef.name,
				hp        = scaled.hp,
				atk       = scaled.atk,
				regen     = scaled.regen,
				xp        = raidDef.xp,
				funds     = raidDef.funds,
				isBoss    = true,
				tier      = "boss",
				behavior  = raidDef.behavior,
				titanId   = raidDef.titanId,
				drops     = raidDef.drops,
			}
		elseif missionType == "endless" then
			-- Endless mode: floor stored on player, increments on each victory
			local floor = (d.endlessFloor or 0) + 1
			d.endlessFloor = floor
			enemy = D.EndlessEnemy(floor, d.prestige)

		elseif missionType == "quick_battle" then
			-- Quick battle: a random enemy scaled to the player's current chapter
			local chapter = D.CAMPAIGN[math.min(d.campaignChapter, #D.CAMPAIGN)]
			local pool    = {}
			for _, e in ipairs(chapter.enemies) do
				if not e.isBoss then table.insert(pool, e) end
			end
			if #pool == 0 then pool = chapter.enemies end
			local pick = pool[math.random(#pool)]
			enemy = D.ScaleCampaignEnemy(pick, d.prestige)

		else
			S.Msg(player, "Unknown mission type.", "warn")
			return
		end

		if not enemy then return end

		-- Set enemy state
		d.inCombat      = true
		d.awaitingTurn  = true
		d.enemyHp       = enemy.hp
		d.enemyMaxHp    = enemy.hp
		d.enemyName     = enemy.name
		d.enemyIsBoss   = enemy.isBoss or false
		d.enemyAtk      = enemy.atk
		d.enemyRegen    = enemy.regen
		d.enemyTier     = enemy.tier or "medium"
		d.enemyBehavior = enemy.behavior
		d.enemyTitanId  = enemy.titanId
		d._activeEnemy  = enemy   -- store full enemy ref for victory processing

		-- Reset boss gimmick state for each new fight
		d.bossGimmickState   = {}
		d.bossActiveMechanic = nil
		d.bossHeavyStreak    = 0

		-- Activate any mechanic that is active from the start of the fight
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

	-- ────────────────────────────────────────────────────────────
	-- COMBAT ACTION — player submits a move
	-- ────────────────────────────────────────────────────────────
	S.RE_CombatAction.OnServerEvent:Connect(function(player, moveId)
		local d = sessions[player.UserId]
		if not d or not d.inCombat or not d.awaitingTurn then return end
		if type(moveId) ~= "string" then return end

		-- Resolve move definition from any table (base, clan, path)
		local moveData = D.GetMoveDef(moveId)
		if not moveData then
			S.Msg(player, "Unknown move: " .. moveId, "warn")
			d.awaitingTurn = true
			S.Push(player, d)
			return
		end

		-- Validate that the move is actually available to this player right now
		local available = D.GetAvailableMoves(d)
		local isAvail   = false
		for _, id in ipairs(available) do
			if id == moveId then isAvail = true break end
		end
		if not isAvail then
			S.Msg(player, moveData.name .. " is not available to you right now.", "warn")
			d.awaitingTurn = true
			S.Push(player, d)
			return
		end

		local cs = S.CalcCS(d)
		d.awaitingTurn = false

		-- ── Validate move availability ───────────────────────────
		-- Check level requirement
		if (d.level or 1) < (moveData.unlockLevel or 1) then
			S.Msg(player, "You haven't unlocked " .. moveData.name .. " yet.", "warn")
			d.awaitingTurn = true
			S.Push(player, d)
			return
		end
		-- Check cooldown
		local cd = d.moveCooldowns and d.moveCooldowns[moveId] or 0
		if cd > 0 then
			S.Msg(player, moveData.name .. " is on cooldown for " .. cd .. " more turn(s).", "warn")
			d.awaitingTurn = true
			S.Push(player, d)
			return
		end
		-- Titan-only moves require titan mode
		if moveData.type == "titan_attack" or moveData.type == "titan_buff" or moveData.type == "titan_special" then
			if not d.titanShifterMode then
				S.Msg(player, "You must be in titan form to use " .. moveData.name .. ".", "warn")
				d.awaitingTurn = true
				S.Push(player, d)
				return
			end
			if (d.titanSuppressTurns or 0) > 0 then
				S.Msg(player, "Your titan form is suppressed for " .. d.titanSuppressTurns .. " more turn(s).", "warn")
				d.awaitingTurn = true
				S.Push(player, d)
				return
			end
		end
		-- Thunder spear moves require spears
		if moveData.spearCost and moveData.spearCost > 0 then
			if (d.thunderSpears or 0) < moveData.spearCost then
				S.Msg(player, "Not enough thunder spears! (Need " .. moveData.spearCost .. ")", "warn")
				d.awaitingTurn = true
				S.Push(player, d)
				return
			end
		end
		-- Clan active: check unlock condition
		if moveData.type == "clan_active" then
			local cm = D.CLAN_MOVES[d.clan]
			if not cm or not cm.unlockCond(d) then
				S.Msg(player, "Clan move not yet unlocked.", "warn")
				d.awaitingTurn = true
				S.Push(player, d)
				return
			end
		end
		-- Path active: check unlock condition
		if moveData.type == "path_active" then
			local pm = D.PATH_MOVES[d.path]
			if not pm or not pm.unlockCond(d) then
				S.Msg(player, "Path move not yet unlocked.", "warn")
				d.awaitingTurn = true
				S.Push(player, d)
				return
			end
		end
		-- Fear debuff blocks most actions
		if (d.playerFearTurns or 0) > 0 and moveId ~= "retreat" then
			d.playerFearTurns = d.playerFearTurns - 1
			S.Msg(player, "You are FEARED and cannot act! (" .. d.playerFearTurns .. " turns remaining)", "warn")
			-- Enemy still acts
			EnemyTurn(player, d)
			TickCooldowns(d)
			TickTitanHeat(d)
			TickPlayerStatus(player, d)
			d.awaitingTurn = d.enemyHp > 0 and d.hp > 0
			if d.hp <= 0 then
				CombatDefeat(player, d)
				d.inCombat     = false
				d.awaitingTurn = false
			end
			S.Push(player, d)
			return
		end

		-- ── RETREAT ─────────────────────────────────────────────
		if moveId == "retreat" then
			d.inCombat     = false
			d.awaitingTurn = false
			d.killStreak   = 0
			S.ResetVolatile(d)
			d.hp           = math.max(1, math.floor(d.maxHp * 0.50))
			S.Msg(player, "You retreat from battle. No rewards. Kill streak lost.", "system")
			S.Push(player, d)
			return
		end

		-- ── Set cooldown ─────────────────────────────────────────
		if moveData.cooldown and moveData.cooldown > 0 then
			d.moveCooldowns = d.moveCooldowns or {}
			d.moveCooldowns[moveId] = moveData.cooldown
			-- Wandering path reduces evasive maneuver CD
			if moveId == "evasive_maneuver" and d.path == "wandering" then
				d.moveCooldowns[moveId] = math.max(0, d.moveCooldowns[moveId] - D.PATHS.wandering.passives.evasionCDReduce)
			end
		end

		-- ── Apply move effects ───────────────────────────────────
		if moveData.type == "attack" then
			-- Accuracy check
			local accuracy = moveData.accuracy or 0.95
			if math.random() > accuracy then
				S.Msg(player, moveData.name .. " missed!", "combat")
			else
				-- Consume spears
				if moveData.spearCost then
					d.thunderSpears = d.thunderSpears - moveData.spearCost
				end
				local dmg = CalcPlayerDamage(player, d, cs, moveData, false)
				-- Armored enemy behavior reduces damage taken
				if d.enemyBehavior == "armored" then
					dmg = math.floor(dmg * 0.75)
				end
				-- Marleyan path: anti-titan bonus
				if d.path == "marleyan" and d.enemyTitanId then
					dmg = math.floor(dmg * D.PATHS.marleyan.passives.antiTitanStrMult)
				end
				-- Spear damage mult (from path + set bonus)
				if moveData.spearCost and cs.spearDamageMult > 0 then
					dmg = math.floor(dmg * (1 + cs.spearDamageMult))
				end
				local actual, blocked = DamageEnemy(player, d, dmg, moveId)
				if not blocked then
					S.Msg(player, moveData.name .. " deals " .. actual .. " damage to " .. d.enemyName .. "!", "combat")
				end
				CheckBossPhases(player, d, d._activeEnemy)
			end

		elseif moveData.type == "heal" then
			local healAmt = D.GetRecoverHeal(cs.wil, d.maxHp)
			d.hp = math.min(d.maxHp, d.hp + healAmt)
			S.Msg(player, moveData.name .. " restores " .. healAmt .. " HP!", "heal")

		elseif moveData.type == "evade" then
			d.evasionActive = true
			S.Msg(player, "Evasive Maneuver! You will dodge the next attack.", "system")

		elseif moveData.type == "titan_attack" or moveData.type == "titan_special" then
			-- Apply titanAffinity heat cost reduction
			local heatCost = D.GetHeatCost(moveId, cs.titanAffinity or 0)
			d.titanHeat = math.min(D.TITAN_HEAT_MAX, (d.titanHeat or 0) + heatCost)
			local dmg = CalcPlayerDamage(player, d, cs, moveData, true)
			-- Titan Affinity multiplier on specials
			if moveData.type == "titan_special" then
				local slot = d.equippedTitan and d.titanSlots[d.equippedTitan]
				if slot then
					local tAtk = D.TITAN_ATTACKS[slot.id]
					if tAtk then
						local affinityMult = D.GetAffinitySpecialMult(cs.titanAffinity or 0)
						dmg = math.floor(dmg * (tAtk.mult or 1.0) * affinityMult)
						if tAtk.special == "stun"      then d.enemyStunned = true end
						if tAtk.special == "burn"      then d.enemyBurnTurns = (d.enemyBurnTurns or 0) + 3 end
						if tAtk.special == "lifesteal" then
							local heal = math.floor(dmg * 0.20)
							d.hp = math.min(d.maxHp, d.hp + heal)
							S.Msg(player, "Lifesteal! Recovered " .. heal .. " HP.", "heal")
						end
						S.Msg(player, "TITAN SPECIAL: " .. tAtk.name .. " — " .. tAtk.msg, "titan")
					end
				end
			end
			if d.enemyBehavior == "armored" then dmg = math.floor(dmg * 0.80) end
			local actual, blocked = DamageEnemy(player, d, dmg, moveId)
			if not blocked then
				S.Msg(player, moveData.name .. " smashes " .. d.enemyName .. " for " .. actual .. " damage!", "titan")
			end
			CheckBossPhases(player, d, d._activeEnemy)
			-- Heat suppression check
			if d.titanHeat >= D.TITAN_HEAT_MAX then
				d.titanShifterMode   = false
				d.titanSuppressTurns = D.TITAN_SUPPRESS_TURNS
				S.Msg(player, "TITAN HEAT MAX — forced back to human form for " .. D.TITAN_SUPPRESS_TURNS .. " turns!", "warn")
			end

		elseif moveData.type == "titan_buff" then
			if moveData.buffKey == "nextAttackMult" then
				d.nextAttackMult = moveData.buffValue or 1.5
				S.Msg(player, "Titan Roar! Your next attack deals " .. (d.nextAttackMult * 100) .. "% damage!", "titan")
			end
			local heatCost = D.GetHeatCost(moveId, cs.titanAffinity or 0)
			d.titanHeat = math.min(D.TITAN_HEAT_MAX, (d.titanHeat or 0) + heatCost)

		elseif moveData.type == "clan_active" then
			local clanMove = D.CLAN_MOVES[d.clan]
			if not clanMove then goto skipClanMove end
			local gs = d.bossGimmickState or {}
			-- Yeager: fear enemy + titan special boost
			if d.clan == "yeager" then
				d.enemyFearTurns = 2
				d.nextTitanSpecialBoost = 1.50
				S.Msg(player, "Coordinating Scream! Enemy feared 2 turns. Next titan special +50%!", "titan")
				-- Ackerman: true damage burst
			elseif d.clan == "ackerman" then
				local dmg = math.floor((cs.bladeMastery or 0) * clanMove.bladeMult
					+ (cs.spd or 0) * clanMove.spdMult
					+ (clanMove.baseDamage or 0))
				local actual = DamageEnemy(player, d, dmg, moveId)  -- trueDamage bypasses all mechanics
				S.Msg(player, "Ackerman Awakening! True damage: " .. actual .. "!", "titan")
				CheckBossPhases(player, d, d._activeEnemy)
				-- Reiss: Royal Vow — heal + status immunity
			elseif d.clan == "reiss" then
				local healAmt = math.floor(d.maxHp * clanMove.healPct)
				d.hp = math.min(d.maxHp, d.hp + healAmt)
				gs.royalVowActive = true
				gs.royalVowTurns  = clanMove.immuneTurns
				d.bossGimmickState = gs
				S.Msg(player, "Royal Vow! Healed " .. healAmt .. " HP. Status immune for " .. clanMove.immuneTurns .. " turns!", "heal")
				-- Tybur: crystal shield
			elseif d.clan == "tybur" then
				d.tyburShieldHits     = clanMove.shieldHits
				d.tyburCounterDmgMult = clanMove.counterDmgMult
				S.Msg(player, "War Hammer Construct! Crystal shield absorbs next " .. clanMove.shieldHits .. " hits!", "titan")
			end
			::skipClanMove::

		elseif moveData.type == "path_active" then
			local pathMove = D.PATH_MOVES[d.path]
			if not pathMove then goto skipPathMove end
			local dmgDealt = 0
			if d.path == "eldian" then
				local dmg = math.floor((cs.str or 0) * pathMove.strMult
					+ (cs.titanAffinity or 0) * pathMove.affinityMult)
				local actual, _ = DamageEnemy(player, d, dmg, moveId)
				dmgDealt = actual
				d.enemyFearTurns = 1
				S.Msg(player, "THE COORDINATE — " .. actual .. " damage! Enemy confused!", "titan")
				CheckBossPhases(player, d, d._activeEnemy)
			elseif d.path == "marleyan" then
				if (d.thunderSpears or 0) < (pathMove.spearCost or 3) then
					S.Msg(player, "Not enough thunder spears for Anti-Titan Barrage.", "warn")
					d.awaitingTurn = true
					S.Push(player, d)
					return
				end
				d.thunderSpears = d.thunderSpears - (pathMove.spearCost or 3)
				local dmg = math.floor((cs.str or 0) * pathMove.strMult
					+ (cs.bladeMastery or 0) * pathMove.bladeMult)
				local actual, _ = DamageEnemy(player, d, dmg, moveId)
				dmgDealt = actual
				S.Msg(player, "Anti-Titan Barrage! " .. actual .. " piercing damage!", "combat")
				CheckBossPhases(player, d, d._activeEnemy)
			elseif d.path == "wandering" then
				d.evasionActive        = true
				d.wanderingEvadeTurns  = pathMove.evadeTurns
				d.wanderingCritPending = true
				S.Msg(player, "Ghost Step! Evading for " .. pathMove.evadeTurns .. " turns. Next hit is a guaranteed crit!", "combat")
			elseif d.path == "royal" then
				local healAmt = math.floor(d.maxHp * pathMove.healPct)
				d.hp = math.min(d.maxHp, d.hp + healAmt)
				d.enemyAtkDebuffTurns = pathMove.enemyAtkDebuffTurns
				d.enemyAtkDebuffPct   = pathMove.enemyAtkDebuffPct
				S.Msg(player, "Founding Scream! Healed " .. healAmt .. " HP. Enemy ATK halved for " .. pathMove.enemyAtkDebuffTurns .. " turns!", "heal")
			end
			::skipPathMove::

			-- Enemy burn ticks
			if (d.enemyBurnTurns or 0) > 0 and d.enemyHp > 0 then
				local burnDmg = math.floor(d.enemyMaxHp * 0.03)
				d.enemyHp         = math.max(0, d.enemyHp - burnDmg)
				d.enemyBurnTurns  = d.enemyBurnTurns - 1
				S.Msg(player, d.enemyName .. " takes " .. burnDmg .. " burn damage! (" .. d.enemyBurnTurns .. " turns left)", "combat")
			end

			-- ── Check enemy death ────────────────────────────────────
			if d.enemyHp <= 0 then
				local enemyRef = d._activeEnemy or {}
				CombatVictory(player, d, enemyRef)
				-- Advance campaign pointer
				if d.inCombat then  -- only if came from campaign (raid handles separately)
					local ch = D.CAMPAIGN[d.campaignChapter]
					if ch then
						d.campaignEnemy = d.campaignEnemy + 1
						if d.campaignEnemy > #ch.enemies then
							-- Chapter cleared
							d.campaignEnemy   = 1
							d.chapterClearCounts = d.chapterClearCounts or {}
							local chId = ch.id
							d.chapterClearCounts[chId] = (d.chapterClearCounts[chId] or 0) + 1
							-- Unlock next chapter or raid
							local nextChapter = d.campaignChapter + 1
							if nextChapter <= #D.CAMPAIGN then
								d.campaignChapter = nextChapter
								S.Msg(player, "== CHAPTER COMPLETE! Advancing to: " .. D.CAMPAIGN[nextChapter].name .. " ==", "reward")
							else
								S.Msg(player, "== ALL CHAPTERS COMPLETE! Prestige to replay at higher difficulty. ==", "system")
							end
							-- Unlock any raids tied to this chapter
							for _, raid in ipairs(D.RAIDS) do
								if raid.unlockChapter == (nextChapter - 1) and not d.raidUnlocks[raid.id] then
									d.raidUnlocks[raid.id] = true
									S.Msg(player, "RAID UNLOCKED: " .. raid.name .. "!", "reward")
								end
							end
						end
					end
				end
				d.inCombat     = false
				d.awaitingTurn = false
				d._activeEnemy = nil
				S.Push(player, d)
				return
			end

			-- ── Enemy turn ───────────────────────────────────────────
			if d.evasionActive then
				d.evasionActive = false
				S.Msg(player, d.enemyName .. " attacks — you EVADE!", "system")
			else
				EnemyTurn(player, d)
			end

			TickCooldowns(d)
			TickTitanHeat(d)
			TickPlayerStatus(player, d)

			-- ── Check player death ───────────────────────────────────
			if d.hp <= 0 then
				CombatDefeat(player, d)
				d.inCombat     = false
				d.awaitingTurn = false
				d._activeEnemy = nil
				S.Push(player, d)
				return
			end

			d.awaitingTurn = true
			S.Push(player, d)
		end)

	-- ────────────────────────────────────────────────────────────
	-- RETREAT
	-- ────────────────────────────────────────────────────────────
	S.RE_Retreat.OnServerEvent:Connect(function(player)
		local d = sessions[player.UserId]
		if not d or not d.inCombat then return end
		d.inCombat     = false
		d.awaitingTurn = false
		d.killStreak   = 0
		d._activeEnemy = nil
		S.ResetVolatile(d)
		d.hp = math.max(1, math.floor((S.CalcCS(d).maxHp) * 0.50))
		S.Msg(player, "Retreat! No rewards. Kill streak reset.", "system")
		S.Push(player, d)
	end)

	-- ────────────────────────────────────────────────────────────
	-- TITAN SHIFT  (client fires this separately — not a "move" per se)
	-- Player shifts into titan form mid-combat. Consumes no action.
	-- ────────────────────────────────────────────────────────────
	local RE_TitanShift = game:GetService("ReplicatedStorage"):WaitForChild("AOT"):WaitForChild("Remotes"):WaitForChild("TitanShift", 5)
	if not RE_TitanShift then
		RE_TitanShift = Instance.new("RemoteEvent")
		RE_TitanShift.Name   = "TitanShift"
		RE_TitanShift.Parent = game:GetService("ReplicatedStorage"):WaitForChild("AOT"):WaitForChild("Remotes")
	end

	RE_TitanShift.OnServerEvent:Connect(function(player)
		local d = sessions[player.UserId]
		if not d or not d.inCombat then return end
		-- Ackerman clan cannot shift
		if d.clan == "ackerman" then
			S.Msg(player, "Ackerman bloodline cannot use titan form.", "warn")
			return
		end
		if not d.equippedTitan or not d.titanSlots[d.equippedTitan] then
			S.Msg(player, "No titan equipped.", "warn")
			return
		end
		if (d.titanSuppressTurns or 0) > 0 then
			S.Msg(player, "Titan form suppressed for " .. d.titanSuppressTurns .. " more turn(s).", "warn")
			return
		end
		if d.titanShifterMode then
			-- Revert to human
			d.titanShifterMode = false
			S.Msg(player, "You revert to human form.", "system")
		else
			d.titanShifterMode = true
			local slot = d.titanSlots[d.equippedTitan]
			S.Msg(player, "TITAN SHIFT — " .. slot.name .. " awakens!", "titan")
		end
		S.Push(player, d)
	end)

	-- ────────────────────────────────────────────────────────────
	-- PVP DUELS
	-- ────────────────────────────────────────────────────────────
	local pvpMatchCounter = 0

	local function NewMatchId()
		pvpMatchCounter = pvpMatchCounter + 1
		return "pvp_" .. pvpMatchCounter
	end

	S.RE_PVPChallenge.OnServerEvent:Connect(function(challenger, targetUserId)
		local d1 = sessions[challenger.UserId]
		if not d1 or d1.inCombat then
			S.Msg(challenger, "You cannot challenge while in combat.", "warn")
			return
		end
		local target = game:GetService("Players"):GetPlayerByUserId(targetUserId)
		if not target then
			S.Msg(challenger, "Player not found.", "warn")
			return
		end
		local d2 = sessions[targetUserId]
		if not d2 or d2.inCombat then
			S.Msg(challenger, target.DisplayName .. " is unavailable.", "warn")
			return
		end
		-- Send invite
		S.pendingInvites[targetUserId] = {
			type       = "pvp",
			fromUserId = challenger.UserId,
			expiry     = os.time() + D.PVP_INVITE_TIMEOUT,
		}
		S.Pop(target, "PVP CHALLENGE", challenger.DisplayName .. " challenges you to a duel!\nAccept or decline.", "amber")
		S.RE_PVPChallenge:FireClient(target, challenger.UserId, challenger.DisplayName)
		S.Msg(challenger, "Challenge sent to " .. target.DisplayName .. ".", "system")
	end)

	S.RE_PVPResponse.OnServerEvent:Connect(function(target, accepted)
		local invite = S.pendingInvites[target.UserId]
		if not invite or invite.type ~= "pvp" then return end
		if os.time() > invite.expiry then
			S.Msg(target, "Challenge expired.", "warn")
			S.pendingInvites[target.UserId] = nil
			return
		end
		local d2 = sessions[target.UserId]
		local challenger = game:GetService("Players"):GetPlayerByUserId(invite.fromUserId)
		local d1 = challenger and sessions[invite.fromUserId]
		S.pendingInvites[target.UserId] = nil

		if not accepted then
			S.Msg(target, "Duel declined.", "system")
			if challenger then S.Msg(challenger, target.DisplayName .. " declined the duel.", "system") end
			return
		end
		if not d1 or not d2 or not challenger then return end
		if d1.inCombat or d2.inCombat then
			S.Msg(target, "One or both players are now in combat.", "warn")
			return
		end

		local matchId = NewMatchId()
		local cs1     = S.CalcCS(d1)
		local cs2     = S.CalcCS(d2)

		S.pvpMatches[matchId] = {
			p1Id      = invite.fromUserId,
			p2Id      = target.UserId,
			turn      = invite.fromUserId,  -- challenger goes first
			round     = 1,
			p1Hp      = cs1.maxHp,
			p1MaxHp   = cs1.maxHp,
			p2Hp      = cs2.maxHp,
			p2MaxHp   = cs2.maxHp,
			matchId   = matchId,
		}
		d1.inCombat    = true
		d1.pvpMatchId  = matchId
		d2.inCombat    = true
		d2.pvpMatchId  = matchId

		S.Msg(challenger, "== PVP DUEL START vs " .. target.DisplayName .. "! You go first! ==", "system")
		S.Msg(target,     "== PVP DUEL START vs " .. challenger.DisplayName .. "! Challenger goes first. ==", "system")
		S.Push(challenger, d1)
		S.Push(target,     d2)
	end)

	S.RE_PVPAction.OnServerEvent:Connect(function(player, moveId)
		local d = sessions[player.UserId]
		if not d or not d.inCombat or not d.pvpMatchId then return end
		local match = S.pvpMatches[d.pvpMatchId]
		if not match then return end
		if match.turn ~= player.UserId then
			S.Msg(player, "It's not your turn.", "warn")
			return
		end

		local moveData = D.MOVES[moveId]
		if not moveData then return end

		local Players  = game:GetService("Players")
		local isP1     = match.p1Id == player.UserId
		local oppId    = isP1 and match.p2Id or match.p1Id
		local opponent = Players:GetPlayerByUserId(oppId)
		local dOpp     = sessions[oppId]

		if not opponent or not dOpp then return end

		local cs    = S.CalcCS(d)
		local csOpp = S.CalcCS(dOpp)

		-- Simple PvP: attacks deal damage based on own str vs opponent def
		local myHp   = isP1 and match.p1Hp or match.p2Hp
		local oppHp  = isP1 and match.p2Hp or match.p1Hp
		local oppMax = isP1 and match.p2MaxHp or match.p1MaxHp

		if moveData.type == "attack" or moveData.type == "titan_attack" then
			local dmg = math.floor((moveData.baseDamage or 12) + cs.str * 0.6)
			-- Path: Royal pvp bonus
			if d.path == "royal" then dmg = math.floor(dmg * D.PATHS.royal.passives.pvpStrMult) end
			-- Opponent DEF reduction; Royal path reduces incoming dmg
			local defReduction = math.floor(csOpp.def * 0.5)
			if dOpp.path == "royal" then defReduction = math.floor(defReduction * D.PATHS.royal.passives.pvpDefMult) end
			dmg = math.max(1, dmg - defReduction)
			oppHp = math.max(0, oppHp - dmg)
			S.Msg(player,   "Your " .. moveData.name .. " hits " .. opponent.DisplayName .. " for " .. dmg .. " damage!", "combat")
			S.Msg(opponent, player.DisplayName .. "'s " .. moveData.name .. " hits you for " .. dmg .. " damage!", "combat")

		elseif moveData.type == "heal" then
			local heal = math.floor(moveData.healBase + cs.wil * moveData.healMult)
			myHp = math.min((isP1 and match.p1MaxHp or match.p2MaxHp), myHp + heal)
			S.Msg(player, moveData.name .. " restores " .. heal .. " HP.", "heal")
		end

		-- Write back HP
		if isP1 then match.p1Hp = myHp match.p2Hp = oppHp
		else          match.p2Hp = myHp match.p1Hp = oppHp end

		-- Check end condition
		local ended = false
		if oppHp <= 0 or match.round >= D.PVP_MAX_TURNS * 2 then
			ended = true
			-- Determine winner by HP %
			local winnerId  = nil
			local p1Pct = match.p1Hp / match.p1MaxHp
			local p2Pct = match.p2Hp / match.p2MaxHp
			if oppHp <= 0 then
				winnerId = player.UserId
			elseif p1Pct > p2Pct then
				winnerId = match.p1Id
			elseif p2Pct > p1Pct then
				winnerId = match.p2Id
			end

			local d1 = sessions[match.p1Id] local d2 = sessions[match.p2Id]
			local pl1 = Players:GetPlayerByUserId(match.p1Id)
			local pl2 = Players:GetPlayerByUserId(match.p2Id)

			if winnerId and d1 and d2 then
				local winnerIsP1 = winnerId == match.p1Id
				local winnerD    = winnerIsP1 and d1 or d2
				local loserD     = winnerIsP1 and d2 or d1
				local winnerPl   = winnerIsP1 and pl1 or pl2
				local loserPl    = winnerIsP1 and pl2 or pl1

				local eloW = D.CalcEloChange(winnerD.pvpElo, loserD.pvpElo, true)
				local eloL = D.CalcEloChange(loserD.pvpElo, winnerD.pvpElo, false)
				winnerD.pvpElo  = (winnerD.pvpElo or 1000) + eloW
				loserD.pvpElo   = math.max(0, (loserD.pvpElo or 1000) + eloL)
				winnerD.pvpWins = (winnerD.pvpWins or 0) + 1
				loserD.pvpLosses= (loserD.pvpLosses or 0) + 1
				if winnerPl then S.BumpChallenge(winnerPl, winnerD, "pvpWin", 1) end

				-- Reward winner
				local reward = math.floor(500 + winnerD.pvpElo * 0.5)
				winnerD.funds = (winnerD.funds or 0) + reward
				if winnerPl then S.Msg(winnerPl, "== PVP WIN! +" .. eloW .. " ELO  +" .. reward .. " Funds ==", "reward") end
				if loserPl  then S.Msg(loserPl,  "== PVP LOSS. " .. eloL .. " ELO ==", "warn") end

				S.CheckAchievements(winnerPl, winnerD)
			else
				-- Draw
				if pl1 then S.Msg(pl1, "== PVP DRAW — no ELO change. ==", "system") end
				if pl2 then S.Msg(pl2, "== PVP DRAW — no ELO change. ==", "system") end
			end

			-- Clean up
			if d1 then d1.inCombat = false d1.pvpMatchId = nil end
			if d2 then d2.inCombat = false d2.pvpMatchId = nil end
			S.pvpMatches[d.pvpMatchId] = nil
			if pl1 and d1 then S.Push(pl1, d1) end
			if pl2 and d2 then S.Push(pl2, d2) end
			return
		end

		-- Swap turns
		match.round = match.round + 1
		match.turn  = oppId
		S.Msg(opponent, "It's your turn!", "system")
		S.Push(player,   d)
		S.Push(opponent, dOpp)
	end)

	print("[AOT_Server_Combat] Loaded.")
