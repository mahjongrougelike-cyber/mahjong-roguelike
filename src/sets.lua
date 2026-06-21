require("src/tiles")

-- Set type multipliers
local TYPE_MULT = {
    single = 1,
    pair = 1,
    chow = 1.5,
    pung = 3,
    kong = 4,
}

-- Only these suits can form chows (sequences require numeric order)
local NUMBERED = {
    [SUIT.CHARACTER] = true,
    [SUIT.BAMBOO]    = true,
    [SUIT.CIRCLE]    = true,
}

-- Validates identity match for pair/pung/kong.
-- Numbered tiles match by value (mixed suits allowed).
-- Honor tiles (Dragon/Wind/Flower) must share the same suit AND label — no cross-mixing.
local function allMatch(sorted)
    local allNum = true
    for _, t in ipairs(sorted) do
        if not NUMBERED[t.suit] then allNum = false; break end
    end
    if allNum then
        local v = sorted[1].value
        for i = 2, #sorted do
            if sorted[i].value ~= v then return false end
        end
        return true
    else
        local s, l = sorted[1].suit, sorted[1].label
        for i = 2, #sorted do
            if sorted[i].suit ~= s or sorted[i].label ~= l then return false end
        end
        return true
    end
end

-- Detect what kind of set a list of tiles forms.
-- Returns: { type, pure, mixedType, tiles } or nil.
-- mixedType is nil for pure/honour sets, "mixedPK" for cross-suit same-value, "mixedChow" for cross-suit sequences.
function detectSet(tiles)
    local n = #tiles
    if n < 2 or n > 4 then return nil end

    local sorted = {}
    for _, t in ipairs(tiles) do table.insert(sorted, t) end
    table.sort(sorted, function(a, b) return a.value < b.value end)

    local firstSuit = sorted[1].suit
    local pureSuit  = true
    for i = 2, n do
        if sorted[i].suit ~= firstSuit then pureSuit = false; break end
    end

    -- mixedType: "mixedPK" for same-value cross-suit sets, "mixedChow" for cross-suit sequences,
    -- nil for pure or honour sets (always playable without items).
    if n == 2 then
        if allMatch(sorted) then
            local mt = (not pureSuit and NUMBERED[sorted[1].suit]) and "mixedPK" or nil
            return { type = "pair", pure = pureSuit, mixedType = mt, tiles = sorted }
        end

    elseif n == 3 then
        if allMatch(sorted) then
            local mt = not pureSuit and "mixedPK" or nil
            return { type = "pung", pure = pureSuit, mixedType = mt, tiles = sorted }
        end
        local allNumbered = NUMBERED[sorted[1].suit]
                        and NUMBERED[sorted[2].suit]
                        and NUMBERED[sorted[3].suit]
        if allNumbered
        and sorted[2].value == sorted[1].value + 1
        and sorted[3].value == sorted[2].value + 1 then
            local mt = not pureSuit and "mixedChow" or nil
            return { type = "chow", pure = pureSuit, mixedType = mt, tiles = sorted }
        end

    elseif n == 4 then
        if allMatch(sorted) then
            local mt = not pureSuit and "mixedPK" or nil
            return { type = "kong", pure = pureSuit, mixedType = mt, tiles = sorted }
        end
    end

    return nil
end

-- Adds a single suit's contribution to an effect table.
-- Used by both the mixed-pung and mixed-chow paths.
local function applySuitEffect(effect, suit, value)
    if suit == SUIT.CHARACTER then
        effect.attack = effect.attack + value
    elseif suit == SUIT.BAMBOO then
        effect.block = effect.block + value
    elseif suit == SUIT.CIRCLE then
        effect.mana = effect.mana + value
    elseif suit == SUIT.DRAGON then
        local half    = math.floor(value / 2)
        effect.attack = effect.attack + half
        effect.mana   = effect.mana + (value - half)
    elseif suit == SUIT.FLOWER then
        local half   = math.floor(value / 2)
        effect.block = effect.block + half
        effect.mana  = effect.mana + (value - half)
    elseif suit == SUIT.WIND then
        effect.skipTurn  = true
        effect.freeDraws = effect.freeDraws + 1
    end
end

-- Calculate the combat effect of a detected set
-- Returns: { attack, block, mana, skipTurn, pickStatValue }
function calculateEffect(setInfo)
    local tiles     = setInfo.tiles
    local typeMult  = TYPE_MULT[setInfo.type] or 1
    local matchMult = (setInfo.type == "single") and 1 or (setInfo.pure and 2 or 1)

    local sum = 0
    for _, t in ipairs(tiles) do sum = sum + t.value end

    local total  = math.floor(sum * typeMult * matchMult)
    local effect = { attack = 0, block = 0, mana = 0, skipTurn = false, freeDraws = 0,
                     damageMultiplier = 1, blockMultiplier = 1, manaMultiplier = 1 }

    if setInfo.type == "single" then
        applySuitEffect(effect, tiles[1].suit, tiles[1].value or 0)
        return effect
    end

    if setInfo.pure then
        local suit = tiles[1].suit
        if suit == SUIT.CHARACTER then
            effect.attack = total
        elseif suit == SUIT.BAMBOO then
            effect.block = total
        elseif suit == SUIT.CIRCLE then
            effect.mana = total
        elseif suit == SUIT.DRAGON then
            local DRAGON_MULT = { pair = 1.5, pung = 2, kong = 4 }
            local mult  = DRAGON_MULT[setInfo.type] or 1
            local label = tiles[1].label
            if label == "Red" then
                effect.damageMultiplier = mult
            elseif label == "Green" then
                effect.blockMultiplier = mult
            elseif label == "White" then
                effect.manaMultiplier = mult
            end
        elseif suit == SUIT.FLOWER then
            effect.block = math.floor(total / 2)
            effect.mana  = total - effect.block
        elseif suit == SUIT.WIND then
            local WIND_DRAWS = { pair = 2, pung = 4, kong = 8 }
            effect.skipTurn  = true
            effect.freeDraws = WIND_DRAWS[setInfo.type] or 2
        end
    else
        -- Check if all tiles share the same value (mixed pung/pair/kong)
        local allSameValue = true
        local firstVal = tiles[1].value
        for i = 2, #tiles do
            if tiles[i].value ~= firstVal then allSameValue = false; break end
        end

        if allSameValue then
            -- Group by suit; each group's output = suit_sum × group_count
            local groups = {}
            for _, t in ipairs(tiles) do
                groups[t.suit] = groups[t.suit] or { sum = 0, count = 0 }
                groups[t.suit].sum   = groups[t.suit].sum   + t.value
                groups[t.suit].count = groups[t.suit].count + 1
            end
            for suit, g in pairs(groups) do
                applySuitEffect(effect, suit, g.sum * g.count)
            end
        else
            -- Mixed chow: each tile contributes its raw value only
            for _, t in ipairs(tiles) do
                applySuitEffect(effect, t.suit, t.value)
            end
        end
    end

    return effect
end

-- ── Mahjong win detection ──────────────────────────────────────────────────

local function copyList(t)
    local c = {}
    for i, v in ipairs(t) do c[i] = v end
    return c
end

local function sortTiles(tiles)
    table.sort(tiles, function(a, b)
        if a.value ~= b.value then return a.value < b.value end
        if a.suit  ~= b.suit  then return a.suit  < b.suit  end
        return (a.label or "") < (b.label or "")
    end)
end

local function sameSetIdentity(a, b)
    local aNumbered = NUMBERED[a.suit]
    local bNumbered = NUMBERED[b.suit]
    if aNumbered and bNumbered then
        return a.value == b.value
    end
    return a.suit == b.suit and a.label == b.label
end

-- Returns true if `tiles` can be split into exactly n melds (pungs or chows)
local function canFormMelds(tiles, n)
    if n == 0 then return #tiles == 0 end
    if #tiles < 3 then return false end
    sortTiles(tiles)
    local first   = tiles[1]
    local isHonor = not NUMBERED[first.suit]

    -- Try pung, following detectSet's identity rules.
    local pi = {1}
    for i = 2, #tiles do
        local t  = tiles[i]
        if sameSetIdentity(first, t) then
            table.insert(pi, i)
            if #pi == 3 then break end
        end
    end
    if #pi == 3 then
        local rem = copyList(tiles)
        table.remove(rem, pi[3]); table.remove(rem, pi[2]); table.remove(rem, pi[1])
        if canFormMelds(rem, n - 1) then return true end
    end

    -- Try chow, following detectSet's mixed-numbered sequence rules.
    if not isHonor then
        local v    = first.value
        local rem1 = copyList(tiles); table.remove(rem1, 1)
        local idx2 = nil
        for i, t in ipairs(rem1) do
            if NUMBERED[t.suit] and t.value == v + 1 then idx2 = i; break end
        end
        if idx2 then
            local rem2 = copyList(rem1); table.remove(rem2, idx2)
            local idx3 = nil
            for i, t in ipairs(rem2) do
                if NUMBERED[t.suit] and t.value == v + 2 then idx3 = i; break end
            end
            if idx3 then
                local rem3 = copyList(rem2); table.remove(rem3, idx3)
                if canFormMelds(rem3, n - 1) then return true end
            end
        end
    end

    return false
end

-- Like canFormMelds but leftover tiles are allowed (used for enemy hand > 14)
local function hasEnoughMelds(tiles, n)
    if n == 0 then return true end
    if #tiles < 3 then return false end
    sortTiles(tiles)
    local first   = tiles[1]
    local isHonor = not NUMBERED[first.suit]

    local pi = {1}
    for i = 2, #tiles do
        local t  = tiles[i]
        if sameSetIdentity(first, t) then table.insert(pi, i); if #pi == 3 then break end end
    end
    if #pi == 3 then
        local rem = copyList(tiles)
        table.remove(rem, pi[3]); table.remove(rem, pi[2]); table.remove(rem, pi[1])
        if hasEnoughMelds(rem, n - 1) then return true end
    end

    if not isHonor then
        local v = first.value
        local rem1 = copyList(tiles); table.remove(rem1, 1)
        local idx2 = nil
        for i, t in ipairs(rem1) do
            if NUMBERED[t.suit] and t.value == v + 1 then idx2 = i; break end
        end
        if idx2 then
            local rem2 = copyList(rem1); table.remove(rem2, idx2)
            local idx3 = nil
            for i, t in ipairs(rem2) do
                if NUMBERED[t.suit] and t.value == v + 2 then idx3 = i; break end
            end
            if idx3 then
                local rem3 = copyList(rem2); table.remove(rem3, idx3)
                if hasEnoughMelds(rem3, n - 1) then return true end
            end
        end
    end

    local rem = copyList(tiles); table.remove(rem, 1)
    return hasEnoughMelds(rem, n)
end

local function canCompleteWithPlayedInternal(hand, meldsNeeded, allowLeftovers)
    if meldsNeeded < 0 then return false end
    local requiredTiles = meldsNeeded * 3 + 2
    if allowLeftovers then
        if #hand < requiredTiles then return false end
    elseif #hand ~= requiredTiles then
        return false
    end

    local tiles = copyList(hand)
    sortTiles(tiles)
    local tried = {}
    for i = 1, #tiles - 1 do
        local t   = tiles[i]
        local key = t.suit .. "|" .. (t.label or tostring(t.value))
        if not tried[key] then
            local j = nil
            for k = i + 1, #tiles do
                local t2  = tiles[k]
                if sameSetIdentity(t, t2) then j = k; break end
            end
            if j then
                tried[key] = true
                local rem = copyList(tiles)
                table.remove(rem, j); table.remove(rem, i)
                if allowLeftovers then
                    if hasEnoughMelds(rem, meldsNeeded) then return true end
                elseif canFormMelds(rem, meldsNeeded) then
                    return true
                end
            end
        end
    end
    return false
end

-- Returns true if `hand` is exactly a pair + meldsNeeded melds.
-- Used for player partial mahjong via played melds.
function canCompleteWithPlayed(hand, meldsNeeded)
    return canCompleteWithPlayedInternal(hand, meldsNeeded, false)
end

-- Returns true if `hand` contains at least a pair + meldsNeeded melds.
-- Used for enemy searches where extra hidden tiles can be discarded.
function canCompleteWithPlayedAllowingLeftovers(hand, meldsNeeded)
    return canCompleteWithPlayedInternal(hand, meldsNeeded, true)
end

-- Returns true if hand is exactly 14 tiles forming one pair + four melds
function isMahjong(hand)
    if #hand ~= 14 then return false end
    local tiles = copyList(hand)
    sortTiles(tiles)
    local tried = {}
    for i = 1, #tiles - 1 do
        local t   = tiles[i]
        local key = t.suit .. "|" .. (t.label or tostring(t.value))
        if not tried[key] then
            local j = nil
            for k = i + 1, #tiles do
                local t2  = tiles[k]
                if sameSetIdentity(t, t2) then j = k; break end
            end
            if j then
                tried[key] = true
                local rem = copyList(tiles)
                table.remove(rem, j); table.remove(rem, i)
                if canFormMelds(rem, 4) then return true end
            end
        end
    end
    return false
end

-- Returns true if `tile` can form at least one *playable* set with tiles in `hand`.
-- flags mirrors ITEM_FLAGS; pairs and mixed sets are gated behind their respective flags.
function canClaimTile(tile, hand, flags)
    flags = flags or {}
    if flags.singlePlay then return true end
    local isHonor = not NUMBERED[tile.suit]

    -- Collect hand tiles that share identity with the claimed tile
    local matches = {}
    for _, t in ipairs(hand) do
        local hit = isHonor
            and (t.suit == tile.suit and t.label == tile.label)
            or  (not isHonor and NUMBERED[t.suit] and t.value == tile.value)
        if hit then table.insert(matches, t) end
    end
    local n = #matches

    if n >= 2 then
        -- Pung/kong possible — check if pure or mixed
        local pure = (tile.suit ~= nil)
        for _, t in ipairs(matches) do
            if t.suit ~= tile.suit then pure = false; break end
        end
        if pure or flags.mixedPungKong then return true end
    end
    if n >= 1 and flags.pairPlay then
        -- Pair possible — pure pair always ok when pairPlay set, mixed needs mixedPungKong too
        local purePair = false
        for _, t in ipairs(matches) do
            if t.suit == tile.suit then purePair = true; break end
        end
        if purePair or flags.mixedPungKong then return true end
    end

    -- Chow: need two numbered tiles in hand that complete a sequence with this tile
    if not isHonor then
        local v = tile.value
        local function tilesWithVal(val)
            if val < 1 or val > 9 then return {} end
            local out = {}
            for _, t in ipairs(hand) do
                if NUMBERED[t.suit] and t.value == val then table.insert(out, t) end
            end
            return out
        end
        -- Three patterns: tile is low / mid / high of the chow
        for _, pair in ipairs({ {v+1,v+2}, {v-1,v+1}, {v-2,v-1} }) do
            local a = tilesWithVal(pair[1])
            local b = tilesWithVal(pair[2])
            if #a > 0 and #b > 0 then
                -- Pure chow: all three tiles same suit
                local pureChow = false
                for _, ta in ipairs(a) do
                    for _, tb in ipairs(b) do
                        if ta.suit == tile.suit and tb.suit == tile.suit then
                            pureChow = true; break
                        end
                    end
                    if pureChow then break end
                end
                if pureChow or flags.mixedChow then return true end
            end
        end
    end

    return false
end

-- Build a readable summary string for a set's effect
function effectToString(setInfo, effect)
    local setLabel
    if setInfo.type == "single" or setInfo.type == "winter" then
        setLabel = setInfo.type:upper()
    else
        setLabel = (setInfo.pure and "Pure " or "Mixed ") .. setInfo.type:upper()
    end
    local parts    = {}
    if effect.attack > 0                       then table.insert(parts, "ATK "  .. effect.attack) end
    if effect.block  > 0                       then table.insert(parts, "BLK "  .. effect.block)  end
    if effect.mana   > 0                       then table.insert(parts, "MANA " .. effect.mana)   end
    if effect.skipTurn                         then table.insert(parts, "SKIP TURN") end
    if effect.freeDraws > 0                   then table.insert(parts, "+" .. effect.freeDraws .. " Free Draws") end
    if (effect.damageMultiplier or 1) > 1     then table.insert(parts, effect.damageMultiplier .. "x Damage") end
    if (effect.blockMultiplier  or 1) > 1     then table.insert(parts, effect.blockMultiplier  .. "x Block")  end
    if (effect.manaMultiplier   or 1) > 1     then table.insert(parts, effect.manaMultiplier   .. "x Mana")   end
    return setLabel .. "  —  " .. table.concat(parts, "  |  ")
end
