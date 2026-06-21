-- Item registry: definitions, flag computation, play-gating.
-- Each item has a `source` that controls where it can be acquired:
--   "run_start" — offered at the beginning of a run
--   "elite"     — dropped as a reward from elite combat
--   "shop"      — available to pick up in shop nodes
-- Add new items to M.ITEMS; flags/stats auto-accumulate via computeFlags().

local M = {}

-- ── Item Definitions ─────────────────────────────────────────────────────────
-- flags:  boolean keys OR'd; numeric keys summed across owned items
-- stats:  numeric bonuses summed across owned items

M.ITEMS = {
    Shamanism = {
        id     = "Shamanism",
        name   = "Shamanism",
        desc   = "Unlocks mixed hands — pungs, kongs, and chows across different suits. Lose 15 Max HP.",
        source = "run_start",
        rarity = "uncommon",
        flags  = { mixedPungKong = true, mixedChow = true, maxHPBonus = -15 },
    },
    Seven_Star_Altar = {
        id     = "Seven_Star_Altar",
        name   = "Seven-Star Altar",
        desc   = "Increases max hand size to 15. Gain 2 free draws at the start of each turn.",
        source = "run_start",
        rarity = "uncommon",
        flags  = { handCapBonus = 2, extraFreeDraw = 2 },
    },
    Blood_Pact = {
        id     = "Blood_Pact",
        name   = "Blood Pact",
        desc   = "HP and Mana are one pool of 300. Mana gains heal you. Extra draws cost 2× mana.",
        source = "run_start",
        rarity = "rare",
        flags  = { sharedPool = true, sharedPoolSize = 300 },
    },
    Qi_Manipulation = {
        id     = "Qi_Manipulation",
        name   = "Qi Manipulation",
        desc   = "Gain 15 Mana at the start of every turn.",
        source = "run_start",
        rarity = "uncommon",
        flags  = { turnManaBonus = 15 },
    },
    Feng_Shui = {
        id     = "Feng_Shui",
        name   = "Feng Shui",
        desc   = "Every time you play a set, deal 15 damage to the enemy.",
        source = "run_start",
        rarity = "uncommon",
        flags  = { setPlayDamage = 15 },
    },
    Red_Endless_Knot = {
        id     = "Red_Endless_Knot",
        name   = "Red Endless Knot",
        desc   = "At the start of each combat, gain 1 free draw for every 10 gold you have.",
        source = "run_start",
        rarity = "rare",
        flags  = { goldDrawBonus = true },
    },
    Chi_Hsi = {
        id     = "Chi_Hsi",
        name   = "Chi Hsi",
        desc   = "Block is retained between turns — it does not reset when the enemy acts.",
        source = "run_start",
        rarity = "legendary",
        flags  = { retainBlock = true },
    },
    Jade_Eye = {
        id     = "Jade_Eye",
        name   = "Jade Eye",
        desc   = "Enemy tiles are always revealed face-up.",
        source = "run_start",
        rarity = "rare",
        flags  = { revealEnemyHand = true },
    },
    Forsaken_Knowledge = {
        id     = "Forsaken_Knowledge",
        name   = "Forsaken Knowledge",
        desc   = "All tiles can be played individually or as pairs.",
        source = "elite",
        rarity = "rare",
        flags  = { singlePlay = true, pairPlay = true },
    },
    Fortune_Cookie = {
        id     = "Fortune_Cookie",
        name   = "Fortune Cookie",
        desc   = "Whenever you gain free draws, gain one extra free draw.",
        source = "elite",
        rarity = "uncommon",
        flags  = { bonusFreeDrawOnGrant = true },
    },
    Ace_in_the_Sleeve = {
        id     = "Ace_in_the_Sleeve",
        name   = "Ace in the Sleeve",
        desc   = "Hand size cap is increased by 2.",
        source = "elite",
        rarity = "uncommon",
        flags  = { handCapBonus = 2 },
    },
    Glasswork_Alloy = {
        id     = "Glasswork_Alloy",
        name   = "Glasswork Alloy",
        desc   = "The first time you draw each turn, Scry the top 3 tiles. Choose any to discard.",
        source = "elite",
        rarity = "rare",
        flags  = { scryOnFirstDraw = true },
    },
    Panda_Express = {
        id     = "Panda_Express",
        name   = "Panda Express",
        desc   = "Gain 24 Max HP.",
        source = "shop",
        rarity = "uncommon",
        flags  = { maxHPBonus = 24 },
    },
    Cultivation_Manual = {
        id     = "Cultivation_Manual",
        name   = "Cultivation Manual",
        desc   = "After each combat you win, gain +1 Mana at the start of each turn.",
        source = "shop",
        rarity = "rare",
        flags  = { manaGrowthOnWin = 1 },
    },
    Snake_Eyes = {
        id     = "Snake_Eyes",
        name   = "Snake Eyes",
        desc   = "At the start of each combat, roll 2 dice. Gain that many free draws.",
        source = "shop",
        rarity = "rare",
        flags  = { diceRollFreeDraw = true },
    },
    Crimson_Mantle = {
        id        = "Crimson_Mantle",
        name      = "Crimson Mantle",
        desc      = "At the start of each turn, lose 1 HP and gain 15 Block.",
        cost_desc = "−1 Hand Size",
        source    = "jiangshi",
        rarity    = "uncommon",
        flags     = { turnStartHPLoss = 1, turnStartBlock = 15, handCapBonus = -1 },
    },
    Furnace = {
        id        = "Furnace",
        name      = "Furnace",
        desc      = "Whenever you discard a tile, it is also played for its suit effect.",
        cost_desc = "−50% Max HP, −1 Hand Size",
        source    = "jiangshi",
        rarity    = "rare",
        flags     = { discardAlsoPlays = true, maxHPMult = 0.5, handCapBonus = -1 },
    },
    Daoquie = {
        id        = "Daoquie",
        name      = "Dàoqiè",
        desc      = "When replacing a tile, steal from the enemy's hand instead of the wall. Your replaced tile goes to the discard pile.",
        cost_desc = "−50 Max Mana",
        source    = "jiangshi",
        rarity    = "rare",
        flags     = { replaceStealFromEnemy = true, maxManaBonus = -50 },
    },
    Bloodletting = {
        id        = "Bloodletting",
        name      = "Bloodletting",
        desc      = "At the start of your turn, gain Mana equal to the HP the enemy lost last turn.",
        cost_desc = "Cannot gain free draws",
        source    = "jiangshi",
        rarity    = "rare",
        flags     = { noFreeDraws = true, manaFromEnemyDamage = true },
    },

}

-- All item IDs (sorted for determinism)
function M.allIds()
    local ids = {}
    for id in pairs(M.ITEMS) do table.insert(ids, id) end
    table.sort(ids)
    return ids
end

-- Item IDs filtered to a specific source
function M.bySource(source)
    local ids = {}
    for id, it in pairs(M.ITEMS) do
        if it.source == source then table.insert(ids, id) end
    end
    table.sort(ids)
    return ids
end

-- Merges all owned items' flags/stats into one flat table.
-- Add new flag/stat keys here when you create items that use them.
function M.computeFlags(ownedIds)
    local f = {
        -- defensive
        retainBlock   = false,   -- Chi Hsi: block persists across enemy turns
        -- playable set gates
        pairPlay      = false,   -- pairs are not standard combat sets
        mixedPungKong = false,
        mixedChow     = false,
        -- stat bonuses (summed)
        maxHPBonus    = 0,
        maxManaBonus  = 0,
        handCapBonus  = 0,
        extraFreeDraw = 0,
        -- turn-start mana regen
        turnManaBonus  = 0,
        -- per-combat-win turn-start mana growth
        manaGrowthOnWin = 0,
        -- flat damage on every set played
        setPlayDamage  = 0,
        -- gold-scaled combat-start free draws (Red Endless Knot)
        goldDrawBonus     = false,
        -- reveal enemy hand (Jade Eye)
        revealEnemyHand   = false,
        -- shared pool (Blood Pact)
        sharedPool        = false,
        sharedPoolSize    = 0,
        -- single tile play (Forsaken Knowledge)
        singlePlay        = false,
        -- Fortune Cookie: +1 draw whenever a free-draw grant happens
        bonusFreeDrawOnGrant = false,
        -- scry top 3 on first draw each turn (Glasswork Alloy)
        scryOnFirstDraw   = false,
        -- dice roll free draws at combat start (Snake Eyes)
        diceRollFreeDraw  = false,
        -- Crimson Mantle: HP lost and block gained at turn start
        turnStartHPLoss   = 0,
        turnStartBlock    = 0,
        -- Furnace: discarded tiles trigger their suit effect
        discardAlsoPlays  = false,
        -- Furnace: multiplier on max HP (0.5 = half)
        maxHPMult         = 1.0,
        -- Dàoqiè: replace steals from enemy hand instead of the wall
        replaceStealFromEnemy = false,
        -- Bloodletting: no free draws; gain mana equal to enemy HP lost last turn
        noFreeDraws           = false,
        manaFromEnemyDamage   = false,
    }
    for _, id in ipairs(ownedIds) do
        local it = M.ITEMS[id]
        if it then
            for k, v in pairs(it.flags or {}) do
                if     type(v) == "boolean" then f[k] = f[k] or v
                elseif type(v) == "number"  then f[k] = (f[k] or 0) + v end
            end
            for k, v in pairs(it.stats or {}) do
                if type(v) == "number" then f[k] = (f[k] or 0) + v end
            end
        end
    end
    return f
end

-- Returns true if setInfo (from detectSet) can be played as a combat action.
-- Pairs are non-standard and require the pairPlay flag.
-- Mixed sets require their respective unlock flags.
function M.canPlaySet(setInfo, flags)
    if not setInfo then return false end
    if setInfo.type == "single" then return flags.singlePlay end
    if setInfo.type == "pair" then return flags.pairPlay end
    local mt = setInfo.mixedType
    if mt == "mixedPK"   then return flags.mixedPungKong end
    if mt == "mixedChow" then return flags.mixedChow end
    return true
end

return M
