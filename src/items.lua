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
        -- flat damage on every set played
        setPlayDamage  = 0,
        -- gold-scaled combat-start free draws (Red Endless Knot)
        goldDrawBonus     = false,
        -- reveal enemy hand (Jade Eye)
        revealEnemyHand   = false,
        -- shared pool (Blood Pact)
        sharedPool     = false,
        sharedPoolSize = 0,
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
    if setInfo.type == "pair" then return flags.pairPlay end
    local mt = setInfo.mixedType
    if mt == "mixedPK"   then return flags.mixedPungKong end
    if mt == "mixedChow" then return flags.mixedChow end
    return true
end

return M
