require("src/tiles")
require("src/deck")
require("src/hand")
require("src/sets")
require("src/enemy")
require("src/wall")
require("src/ui")
require("src/tilerender")
require("src/anim")
require("src/map")

flux  = require("lib/flux")
anim8 = require("lib/anim8")
-- svgrender is required lazily inside loadTileImages() (needs love.filesystem)

local Items = require("src/items")
local Shop  = require("src/shop")

-- Game state
local drawPile      = {}
local playerHand    = {}
local discardPile   = {}
local playedTiles   = {}
local hoveredTile   = nil   -- index of tile under mouse
local selectedIndices = {}  -- { [i] = true } for each selected tile index
local mustDiscard  = false
local freeReplace  = { available=false, mode=false }
local showPlayedHands     = false
local showItemsPanel      = false
local playerRevealedMelds = {}
local tileTooltip         = nil   -- tile object to show info for (right-click)
local itemTooltip         = nil   -- item id to show info for (right-click)
local itemPanelRects      = {}    -- hit rects for left-column item list, rebuilt each frame
local currentSet    = nil
local currentEffect = nil

-- ── Combat constants (modify here to tune baseline stats) ────────────────────
local BASE_MAX_HP   = 100   -- player HP before item bonuses
local BASE_MAX_MANA = 100   -- player MP before item bonuses
local BASE_HAND_CAP = 13    -- tile hand size before item bonuses
local HAND_CAP      = BASE_HAND_CAP  -- runtime value; updated by applyItemFlags()

local SUIT_ORDER = {
    [SUIT.CHARACTER] = 1,
    [SUIT.BAMBOO]    = 2,
    [SUIT.CIRCLE]    = 3,
    [SUIT.DRAGON]    = 4,
    [SUIT.WIND]      = 5,
    [SUIT.FLOWER]    = 6,
}

local function hitTest(mx, my, btn)
    return mx >= btn.x and mx <= btn.x + btn.w and my >= btn.y and my <= btn.y + btn.h
end

-- Returns a list of descriptive strings for a tile's info popup.
local function getTileInfo(tile)
    local s, v, l = tile.suit, tile.value or 0, tile.label or ""
    if s == SUIT.CHARACTER then
        return { "Character  " .. v, "Attack — deals " .. v .. " base damage in sets" }
    elseif s == SUIT.BAMBOO then
        return { "Bamboo  " .. v, "Defense — grants " .. v .. " Block in sets" }
    elseif s == SUIT.CIRCLE then
        return { "Circle  " .. v, "Mana — restores " .. v .. " MP in sets" }
    elseif s == SUIT.DRAGON then
        local role = l == "Red" and "Damage" or l == "Green" and "Block" or "Mana"
        return { l .. " Dragon", "Multiplier — boosts " .. role,
                 "Pair ×1.5   Pung ×2   Kong ×4" }
    elseif s == SUIT.WIND then
        return { l .. " Wind", "Turn Control — skip enemy turn + free draws",
                 "Pair +2   Pung +4   Kong +8 draws" }
    elseif s == SUIT.FLOWER then
        local fx = {
            Spring  = "Steal up to 4 tiles from the enemy",
            Summer  = "Deal damage equal to total discards",
            Autumn  = "Block the next incoming attack entirely",
            Winter  = "Freeze the enemy's next turn",
        }
        local desc = (l == "Winter")
            and "Season — select and play to freeze the enemy"
            or  "Season — triggers immediately on draw"
        return { l, desc, fx[l] or "Select tiles to swap from the deck" }
    end
    return { l }
end

-- Draws a compact info popup panel at (px, py).
local function drawInfoPopup(px, py, lines, titleColor)
    local PW, PH = 300, 14 + #lines * 16
    drawUIPanel(px, py, PW, PH, 5)
    love.graphics.setFont(FONT_UI)
    love.graphics.setColor(titleColor or 0.92, titleColor and 1 or 0.88, titleColor and 1 or 0.64)
    love.graphics.print(lines[1], px + 8, py + 5)
    love.graphics.setFont(FONT_SMALL)
    love.graphics.setColor(0.72, 0.70, 0.56)
    for i = 2, #lines do
        love.graphics.print(lines[i], px + 8, py + 5 + (i - 1) * 16)
    end
end

-- ── UI hit-rect buttons ───────────────────────────────────────────────────────
local SORT_BTN      = { x = 318, y = 541, w = 90,  h = 24 }
local MANA_DRAW_BTN = { x = 416, y = 541, w = 128, h = 24 }
local PLAY_SET_BTN  = { x = 552, y = 541, w = 108, h = 24 }
local CLAIM_BTN     = { x = 668, y = 541, w = 114, h = 24 }
local REPLACE_BTN   = { x = 790, y = 541, w = 115, h = 24 }

local playerHP      = BASE_MAX_HP
local playerMaxHP   = BASE_MAX_HP
local playerBlock   = 0
local playerMana    = 0
local playerMaxMana = BASE_MAX_MANA
local playerGold    = 0
local pendingGold   = 0

-- Item system
local playerItems = {}
local ITEM_FLAGS  = Items.computeFlags({})

-- Shop / reward / run-start state
local shopOffer         = {}
local shopItemRects     = {}
local shopExitBtn       = {}
local itemRewardOffer   = {}
local itemRewardRects   = {}
local itemRewardSkipBtn = {}
local runStartOffer     = {}   -- item IDs shown at the very start of a run
local runStartRects     = {}
local runStartSkipBtn   = {}

local enemy            = nil
local combatLog        = ""
local turnPhase        = "player"
local drawsThisTurn = 0
local gameOver         = false
local encounterWon     = false
local runComplete        = false
local gameState          = "map"   -- "map" | "combat" | "shop" | "item_reward" | "run_start"
local currentNodeType    = "combat"
local combatsThisAct     = 0   -- normal (non-elite) combat count this act; gates easy→hard pool
local freeDrawsRemaining  = 0   -- free draws from Wind tile plays (accumulate between turns)
local itemFreeDraws       = 0   -- free draws from items (reset to item value each turn)
local itemCombatFreeDraws = 0   -- item-granted draws at combat start (persist until used)
local skipNextEnemyTurn  = false
local flowerReplaceMode  = false
local springStealMode    = false
local springSelected     = {}
local replacementDrawsPending = 0
local autumnShieldActive = false
local playedMeldsCount   = 0
local claimableDiscard   = nil
local burstDiscardMode   = false   -- true while stepping through enemy discards one-by-one
local mult = { damage=1, block=1, mana=1 }

-- Recompute ITEM_FLAGS from playerItems and update derived stats.
-- Call whenever items change (purchase, game start).
local function applyItemFlags()
    local prevMaxHP   = playerMaxHP
    local prevMaxMana = playerMaxMana

    ITEM_FLAGS = Items.computeFlags(playerItems)

    if ITEM_FLAGS.sharedPool then
        local pool    = ITEM_FLAGS.sharedPoolSize or 300
        playerMaxHP   = pool
        playerMaxMana = pool
    else
        playerMaxHP   = BASE_MAX_HP   + (ITEM_FLAGS.maxHPBonus   or 0)
        playerMaxMana = BASE_MAX_MANA + (ITEM_FLAGS.maxManaBonus or 0)
    end
    HAND_CAP = BASE_HAND_CAP + (ITEM_FLAGS.handCapBonus or 0)

    local hpDelta   = playerMaxHP   - prevMaxHP
    local manaDelta = playerMaxMana - prevMaxMana
    if hpDelta   > 0 then playerHP   = math.min(playerMaxHP,   playerHP   + hpDelta)   end
    if manaDelta > 0 then playerMana = math.min(playerMaxMana, playerMana + manaDelta) end
    -- Clamp current values to new maximums (handles negative deltas from drawback items)
    playerHP   = math.min(playerHP,   playerMaxHP)
    playerMana = math.min(playerMana, playerMaxMana)

    -- Keep the shared pool in sync (HP is authoritative on item pickup)
    if ITEM_FLAGS.sharedPool then
        playerMana = playerHP
    end
end

-- Rebuild set detection whenever selection changes
local function refreshSet()
    local tiles = {}
    for i = 1, #playerHand do
        if selectedIndices[i] then
            table.insert(tiles, playerHand[i])
        end
    end
    local s = detectSet(tiles)
    -- Mixed sets are invisible until the player owns the unlocking item
    if s and not Items.canPlaySet(s, ITEM_FLAGS) then s = nil end
    -- Single Winter tile in hand: playable as a freeze action
    if not s and #tiles == 1 and tiles[1].suit == SUIT.FLOWER and tiles[1].label == "Winter" then
        s = { type = "winter", tiles = tiles }
        currentSet    = s
        currentEffect = { attack=0, block=0, mana=0, skipTurn=true, freeDraws=0,
                          damageMultiplier=1, blockMultiplier=1, manaMultiplier=1 }
        return
    end
    currentSet    = s
    currentEffect = s and calculateEffect(s) or nil
end

local function awardEncounterWin(message)
    encounterWon = true
    if pendingGold == 0 then
        local base  = currentNodeType == "elite" and 25 or
                      currentNodeType == "boss"  and 50 or 15
        pendingGold = math.random(base, base + 15)
        playerGold  = playerGold + pendingGold
    end
    if message then combatLog = message end
end

local function checkPlayerMahjong()
    if encounterWon then return true end
    local needMelds = 4 - playedMeldsCount
    if needMelds >= 0 and canCompleteWithPlayed(playerHand, needMelds) then
        awardEncounterWin("MAHJONG! Combat won!")
        return true
    end
    return false
end

local function enemyMeldsNeeded()
    return math.max(0, 4 - (enemy and #enemy.revealedMelds or 0))
end

local function enemyReadyHandSize()
    return math.max(2, 14 - ((enemy and #enemy.revealedMelds or 0) * 3))
end

local function checkEnemyMahjong()
    if enemy and canCompleteWithPlayedAllowingLeftovers(enemy.hand, enemyMeldsNeeded()) then
        gameOver  = true
        combatLog = "Enemy completed a mahjong hand - the run is over!"
        return true
    end
    return false
end

local function enemyDiscardIfReady()
    local discarded = false
    while enemy and #enemy.hand >= enemyReadyHandSize() do
        if checkEnemyMahjong() then return discarded end
        enemyDiscard(enemy)
        claimableDiscard = enemy.discards[#enemy.discards]
        discarded = true
    end
    return discarded
end

local processTileFromDraw
local playCurrentSet

local function resolvePlayerHandAfterGain(logMsg, startingLog)
    if checkPlayerMahjong() then return true end
    if #playerHand > HAND_CAP then
        mustDiscard     = true
        selectedIndices = {}
        hoveredTile     = nil
    else
        mustDiscard = false
    end
    if logMsg and combatLog == startingLog then
        combatLog = logMsg
    end
    refreshSet()
    return false
end

local function drawPendingReplacementTiles(logMsg)
    local startingLog = combatLog
    while replacementDrawsPending > 0
    and #drawPile > 0
    and not encounterWon
    and not flowerReplaceMode
    and not springStealMode do
        replacementDrawsPending = replacementDrawsPending - 1
        processTileFromDraw(drawTile(drawPile))
    end

    if replacementDrawsPending > 0
    and #drawPile == 0
    and not encounterWon
    and not flowerReplaceMode
    and not springStealMode then
        replacementDrawsPending = 0
        combatLog = "The draw pile is empty!"
    end

    if not encounterWon and not flowerReplaceMode and not springStealMode then
        resolvePlayerHandAfterGain(logMsg, startingLog)
    end
end

local function startEncounterFromDef(def, nodeType)
    currentNodeType = nodeType or "combat"
    -- Pool every tile (including player hand) for a fresh shuffle each combat
    local pool = {}
    for _, t in ipairs(playerHand)  do table.insert(pool, t) end
    for _, t in ipairs(drawPile)    do table.insert(pool, t) end
    for _, t in ipairs(discardPile) do table.insert(pool, t) end
    for _, t in ipairs(playedTiles) do table.insert(pool, t) end
    if enemy then
        for _, t in ipairs(enemy.hand) do table.insert(pool, t) end
        for _, meld in ipairs(enemy.revealedMelds) do
            for _, t in ipairs(meld.tiles) do table.insert(pool, t) end
        end
        for _, t in ipairs(enemy.discards) do table.insert(pool, t) end
    end
    shuffleDeck(pool)
    playerHand  = {}
    drawPile    = pool
    discardPile = {}
    playedTiles          = {}
    playerRevealedMelds  = {}
    tileTooltip          = nil
    itemTooltip          = nil
    showPlayedHands      = false
    showItemsPanel       = false

    while #playerHand < HAND_CAP and #drawPile > 0 do
        local t = table.remove(drawPile, 1)
        if t.suit == SUIT.FLOWER then
            table.insert(drawPile, t)
        else
            table.insert(playerHand, t)
        end
    end

    enemy           = def.create and def.create() or createEnemy(def.name, def.hp, def.minAtk, def.maxAtk)
    enemy.hand      = dealHand(drawPile, 13)
    encounterWon    = false
    combatLog       = ""
    selectedIndices = {}
    hoveredTile     = nil
    pendingGold          = 0
    playedMeldsCount     = 0
    claimableDiscard     = nil
    burstDiscardMode     = false
    mustDiscard          = false
    freeReplace.available = false
    freeReplace.mode      = false
    freeDrawsRemaining    = 0
    itemFreeDraws         = 0
    itemCombatFreeDraws   = 0
    skipNextEnemyTurn    = false
    flowerReplaceMode    = false
    springStealMode      = false
    springSelected       = {}
    replacementDrawsPending = 0
    autumnShieldActive   = false
    mult.damage = 1
    mult.block  = 1
    mult.mana   = 1
    playerMana           = ITEM_FLAGS.sharedPool and playerHP or 0
    playerBlock          = 0

    -- Red Endless Knot: 1 free draw per 10 gold at combat start
    if ITEM_FLAGS.goldDrawBonus then
        itemCombatFreeDraws = math.floor(playerGold / 10)
    end

    -- Auto-sort hand at combat start
    table.sort(playerHand, function(a, b)
        local sa = SUIT_ORDER[a.suit] or 99
        local sb = SUIT_ORDER[b.suit] or 99
        if sa ~= sb then return sa < sb end
        return a.value < b.value
    end)

    refreshSet()
end

-- Handles a tile drawn from the pile: flowers/seasons trigger immediately,
-- normal tiles are added to playerHand.
-- NOTE: assigned to the forward-declared upvalue so drawPendingReplacementTiles can call it.
processTileFromDraw = function(tile)
    if not tile then return end
    if tile.suit == SUIT.FLOWER then
        local lbl = tile.label
        if lbl == "Winter" then
            -- Winter stays in hand and triggers when played, not on draw
            table.insert(playerHand, tile)
            combatLog = "Winter drawn — select it and play to freeze the enemy."
        else
            table.insert(discardPile, tile)
            if lbl == "Spring" then
                if enemy and not enemyIsDead(enemy) and #enemy.hand > 0 then
                    springStealMode  = true
                    springSelected   = {}
                    claimableDiscard = nil
                    selectedIndices  = {}
                    combatLog = "Spring! Select up to 4 enemy tiles to steal, then press ENTER."
                else
                    combatLog = "Spring drawn - no enemy tiles to steal."
                end
            elseif lbl == "Summer" then
                local dmg = #discardPile + (enemy and #enemy.discards or 0)
                if enemy and not enemyIsDead(enemy) then
                    enemyTakeDamage(enemy, dmg)
                    if enemyIsDead(enemy) then
                        awardEncounterWin()
                    end
                end
                combatLog = "Summer scorches for " .. dmg .. " damage!"
            elseif lbl == "Autumn" then
                autumnShieldActive = true
                combatLog = "Autumn shield active - next hit ignored."
            else
                flowerReplaceMode = true
                claimableDiscard  = nil
                selectedIndices   = {}
                combatLog = "Flower drawn! Select tiles to replace, then press ENTER."
            end
        end
    else
        table.insert(playerHand, tile)
    end
end

local function tryDraw()
    local useWindDraw = freeDrawsRemaining > 0 and drawsThisTurn > 0
    local useItemDraw = (itemFreeDraws > 0 or itemCombatFreeDraws > 0) and drawsThisTurn > 0 and not useWindDraw
    local baseCost    = math.ceil(drawsThisTurn / 2) * 5
    local cost        = (useWindDraw or useItemDraw) and 0
                        or (ITEM_FLAGS.sharedPool and baseCost * 2 or baseCost)
    if playerMana < cost then return end
    if #drawPile == 0 then
        if cost == 0 then
            gameOver  = true
            combatLog = "Draw pile exhausted - the run ends!"
        else
            combatLog = "The draw pile is empty!"
        end
        return
    end
    local tile     = drawTile(drawPile)
    local prevSize = #playerHand
    if useWindDraw then
        freeDrawsRemaining = freeDrawsRemaining - 1
    elseif useItemDraw then
        if itemCombatFreeDraws > 0 then
            itemCombatFreeDraws = itemCombatFreeDraws - 1
        else
            itemFreeDraws = itemFreeDraws - 1
        end
    else
        playerMana    = playerMana - cost
        if ITEM_FLAGS.sharedPool then playerHP = playerMana end
        drawsThisTurn = drawsThisTurn + 1
    end
    processTileFromDraw(tile)
    if #playerHand > prevSize then
        local sx, sy, tw, th, tg = getHandLayout(#playerHand)
        local destX = sx + (#playerHand - 1) * (tw + tg)
        queueDrawAnim(playerHand[#playerHand], #playerHand, destX, sy, 580, 355, tw, th)
    end
    drawPendingReplacementTiles()
end

local function startPlayerTurn()
    drawsThisTurn        = 0
    itemFreeDraws        = ITEM_FLAGS.extraFreeDraw or 0
    selectedIndices      = {}
    hoveredTile          = nil
    turnPhase            = "player"
    freeReplace.available = true
    freeReplace.mode      = false

    local manaRegen = ITEM_FLAGS.turnManaBonus or 0
    if manaRegen > 0 then
        playerMana = math.min(playerMaxMana, playerMana + manaRegen)
        if ITEM_FLAGS.sharedPool then playerHP = playerMana end
    end

    if #playerHand > HAND_CAP then
        mustDiscard = true
        refreshSet()
        return
    end

    mustDiscard = false
    -- Refresh: most recent enemy discard is always claimable until the player draws
    if enemy and not enemyIsDead(enemy) and #enemy.discards > 0 then
        claimableDiscard = enemy.discards[#enemy.discards]
    end
    if not claimableDiscard then
        tryDraw()
    end
    selectedIndices = {}
    hoveredTile     = nil
    refreshSet()
end

-- Step through enemy discards one tile at a time.
-- Called once per discard; SPACE/C in the key handler call it again for the next one.
local function processBurstDiscard()
    if not enemy or enemyIsDead(enemy) or #enemy.hand < enemyReadyHandSize() then
        burstDiscardMode = false
        claimableDiscard = nil
        if not gameOver then startPlayerTurn() end
        return
    end
    if checkEnemyMahjong() then
        burstDiscardMode = false
        return
    end

    enemyDiscard(enemy)
    claimableDiscard = enemy.discards[#enemy.discards]

    if canClaimTile(claimableDiscard, playerHand, ITEM_FLAGS) then
        combatLog = "Enemy discarded — [C] Claim  or  [SPACE] Pass"
        turnPhase = "player"   -- pause for player to decide
    else
        -- Not claimable — skip it silently and check the next discard
        claimableDiscard = nil
        processBurstDiscard()
    end
end

local function isNumberedSuit(suit)
    return suit == SUIT.CHARACTER or suit == SUIT.BAMBOO or suit == SUIT.CIRCLE
end

-- Returns the hand indices that form the best playable set including `claimedIdx`.
local function findClaimSet(claimedIdx)
    local t       = playerHand[claimedIdx]
    local isHonor = not isNumberedSuit(t.suit)

    -- Tiles in hand that share identity with the claimed tile
    local matchIdxs = {}
    for i = 1, #playerHand do
        if i ~= claimedIdx then
            local o = playerHand[i]
            local same = isHonor
                and (o.suit == t.suit and o.label == t.label)
                or  (not isHonor and isNumberedSuit(o.suit) and o.value == t.value)
            if same then table.insert(matchIdxs, i) end
        end
    end

    -- Try kong → pung → pair (largest playable match-based set first)
    for size = math.min(4, 1 + #matchIdxs), 2, -1 do
        local idxs, tiles = {claimedIdx}, {t}
        for j = 1, size - 1 do
            table.insert(idxs,  matchIdxs[j])
            table.insert(tiles, playerHand[matchIdxs[j]])
        end
        local s = detectSet(tiles)
        if s and Items.canPlaySet(s, ITEM_FLAGS) then return idxs end
    end

    -- Try chow patterns (numbered tiles only)
    if not isHonor then
        local v = t.value
        for _, pat in ipairs({{v+1,v+2},{v-1,v+1},{v-2,v-1}}) do
            if pat[1] >= 1 and pat[2] <= 9 then
                local i2, i3
                for i = 1, #playerHand do
                    if i ~= claimedIdx and isNumberedSuit(playerHand[i].suit) then
                        if playerHand[i].value == pat[1] and not i2 then i2 = i
                        elseif playerHand[i].value == pat[2] and not i3 then i3 = i end
                    end
                end
                if i2 and i3 then
                    local s = detectSet({t, playerHand[i2], playerHand[i3]})
                    if s and Items.canPlaySet(s, ITEM_FLAGS) then return {claimedIdx, i2, i3} end
                end
            end
        end
    end
end

local function claimDiscard()
    if not claimableDiscard or turnPhase ~= "player" or mustDiscard or drawsThisTurn > 0 then return false end
    if not canClaimTile(claimableDiscard, playerHand, ITEM_FLAGS) then return false end
    if enemy and #enemy.discards > 0 then
        table.remove(enemy.discards)
    end
    table.insert(playerHand, claimableDiscard)
    claimableDiscard = nil
    drawsThisTurn    = 1

    local setIdxs = findClaimSet(#playerHand)
    if setIdxs then
        selectedIndices = {}
        for _, idx in ipairs(setIdxs) do selectedIndices[idx] = true end
        refreshSet()
        playCurrentSet()
    else
        resolvePlayerHandAfterGain()
    end
    return true
end

local function sortHand()
    table.sort(playerHand, function(a, b)
        local sa = SUIT_ORDER[a.suit] or 99
        local sb = SUIT_ORDER[b.suit] or 99
        if sa ~= sb then return sa < sb end
        return a.value < b.value
    end)
    selectedIndices = {}
    hoveredTile     = nil
    refreshSet()
end

-- Remove selected tiles from hand (in reverse index order to avoid shifting)
local function removeSelectedTiles(destination)
    local indices = {}
    for i = 1, #playerHand do
        if selectedIndices[i] then table.insert(indices, i) end
    end
    table.sort(indices, function(a, b) return a > b end)
    for _, idx in ipairs(indices) do
        local removed = table.remove(playerHand, idx)
        if destination then
            table.insert(destination, removed)
        end
    end
    selectedIndices = {}
    return #indices
end

local function applyEffect(effect)
    -- Dragon multipliers: take the maximum of current and new (never downgrade)
    if (effect.damageMultiplier or 1) > 1 then
        mult.damage = math.max(mult.damage, effect.damageMultiplier)
    end
    if (effect.blockMultiplier or 1) > 1 then
        mult.block = math.max(mult.block, effect.blockMultiplier)
    end
    if (effect.manaMultiplier or 1) > 1 then
        mult.mana = math.max(mult.mana, effect.manaMultiplier)
    end

    local atk  = math.floor(effect.attack * mult.damage)
    local blk  = math.floor(effect.block  * mult.block)
    local mana = math.floor(effect.mana   * mult.mana)

    if atk > 0 and enemy and not enemyIsDead(enemy) then
        enemyTakeDamage(enemy, atk)
        if enemyIsDead(enemy) then
            awardEncounterWin()
        end
    end
    playerBlock = playerBlock + blk
    playerMana  = math.min(playerMaxMana, playerMana + mana)
    if ITEM_FLAGS.sharedPool and mana > 0 then playerHP = playerMana end
    if effect.skipTurn then
        skipNextEnemyTurn = true
    end
    if effect.freeDraws and effect.freeDraws > 0 then
        freeDrawsRemaining = freeDrawsRemaining + effect.freeDraws
    end
end

playCurrentSet = function()
    if not currentSet or not currentEffect or mustDiscard then return end
    local setType = currentSet.type
    applyEffect(currentEffect)
    -- Feng Shui: flat damage on every set played
    local bonusDmg = ITEM_FLAGS.setPlayDamage or 0
    if bonusDmg > 0 and enemy and not enemyIsDead(enemy) then
        enemyTakeDamage(enemy, bonusDmg)
        if enemyIsDead(enemy) then awardEncounterWin() end
    end
    if setType == "winter" then
        combatLog = "Winter! Enemy's next turn is frozen."
    end
    table.insert(playerRevealedMelds, { type = currentSet.type, tiles = currentSet.tiles })
    removeSelectedTiles(playedTiles)
    triggerPlayFlash()
    if not encounterWon then
        if setType ~= "pair" and setType ~= "winter" then
            playedMeldsCount = playedMeldsCount + 1
        end
        checkPlayerMahjong()
    end
    currentSet    = nil
    currentEffect = nil
    hoveredTile   = nil
end

function love.load()
    math.randomseed(os.time())

    -- Global fonts used by tilerender, hand, enemy, and love.draw
    FONT_TILENUM = love.graphics.newFont(24)
    FONT_TITLE   = love.graphics.newFont(16)
    FONT_UI      = love.graphics.newFont(13)
    FONT_SMALL   = love.graphics.newFont(10)
    -- Try to load a CJK font for Chinese character tiles (Windows system fonts)
    local function _tryAbsFont(path, size)
        local ok, fh = pcall(io.open, path, "rb")
        if not ok or not fh then return nil end
        local data = fh:read("*a"); fh:close()
        if not data or #data == 0 then return nil end
        local ok2, fd = pcall(love.filesystem.newFileData, data, "cjk.ttc")
        if not ok2 or not fd then return nil end
        local ok3, f = pcall(love.graphics.newFont, fd, size)
        return ok3 and f or nil
    end
    local _cjkPaths = {
        "C:/Windows/Fonts/msyh.ttc",
        "C:/Windows/Fonts/simsun.ttc",
        "C:/Windows/Fonts/simhei.ttf",
    }
    FONT_CJK       = nil
    FONT_CJK_SMALL = nil
    for _, p in ipairs(_cjkPaths) do
        if not FONT_CJK       then FONT_CJK       = _tryAbsFont(p, 24) end
        if not FONT_CJK_SMALL then FONT_CJK_SMALL = _tryAbsFont(p, 13) end
        if FONT_CJK and FONT_CJK_SMALL then break end
    end
    if not FONT_CJK       then FONT_CJK       = FONT_TILENUM end
    if not FONT_CJK_SMALL then FONT_CJK_SMALL = FONT_SMALL   end
    love.graphics.setFont(FONT_UI)

    applyItemFlags()
    initAtmosphere()
    initAnim()
    loadTileImages()

    drawPile     = buildFullDeck()
    shuffleDeck(drawPile)
    generateMap()
    runStartOffer = Shop.generateOffer({}, Items.bySource("run_start"))
    gameState     = #runStartOffer > 0 and "run_start" or "map"
end

function love.update(dt)
    flux.update(dt)
    updateAtmosphere(dt)
    updateAnim(dt)
end

function love.draw()
    drawRoom()
    drawLighting()

    if gameState == "map" then
        drawMap(love.mouse.getX(), love.mouse.getY())
        -- Gold + items strip on map screen
        love.graphics.setFont(FONT_SMALL)
        love.graphics.setColor(0.72, 0.60, 0.16)
        love.graphics.print("Gold: " .. playerGold, 96, 686)
        if #playerItems > 0 then
            local names = {}
            for _, id in ipairs(playerItems) do
                local it = Items.ITEMS[id]
                if it then table.insert(names, it.name) end
            end
            love.graphics.setColor(0.50, 0.48, 0.36)
            love.graphics.print("Items: " .. table.concat(names, "  •  "), 200, 686)
        end
        return
    end

    if gameState == "run_start" then
        runStartRects, runStartSkipBtn = Shop.draw(runStartOffer, Items.ITEMS, playerItems, "run_start")
        return
    end

    if gameState == "shop" then
        shopItemRects, shopExitBtn = Shop.draw(shopOffer, Items.ITEMS, playerItems, "shop")
        return
    end

    if gameState == "item_reward" then
        itemRewardRects, itemRewardSkipBtn = Shop.draw(itemRewardOffer, Items.ITEMS, playerItems, "reward")
        return
    end

    -- Apply screen shake for combat (pop'd before full-screen overlays below)
    local _sx, _sy = getShakeOffset()
    love.graphics.push()
    love.graphics.translate(_sx, _sy)

    drawWallDisplay(#drawPile)

    -- Enemy top bar
    drawEnemyPanel(enemy, springStealMode, ITEM_FLAGS.revealEnemyHand)
    if springStealMode then
        drawSpringStealPanel(enemy, springSelected)
    end

    -- Enemy claimed melds / last discard (right of wall)
    drawCenterInfo(enemy)

    -- Combat log (slim, in gap between enemy bar and wall)
    if combatLog ~= "" then
        love.graphics.setColor(0, 0, 0, 0.62)
        love.graphics.rectangle("fill", 280, 200, 720, 18, 4, 4)
        love.graphics.setFont(FONT_SMALL)
        love.graphics.setColor(0.88, 0.74, 0.38)
        love.graphics.printf(combatLog, 0, 203, 1280, "center")
    end

    -- Action area — MIDDLE LEFT (x=90, left of wall)
    local AX, AY, AW = 90, 272, 344
    if flowerReplaceMode then
        local selCount = 0
        for _ in pairs(selectedIndices) do selCount = selCount + 1 end
        drawUIPanel(AX - 4, AY - 4, AW + 8, 66, 6)
        love.graphics.setFont(FONT_UI)
        love.graphics.setColor(0.80, 0.36, 0.68)
        love.graphics.printf("Flower!", AX, AY, AW, "left")
        love.graphics.setFont(FONT_SMALL)
        love.graphics.setColor(0.72, 0.60, 0.38)
        love.graphics.printf("Select tiles to swap  —  ENTER confirm", AX, AY + 18, AW, "left")
        love.graphics.setColor(0.96, 0.86, 0.62)
        love.graphics.printf("Replacing " .. selCount .. " tile(s)", AX, AY + 34, AW, "left")

    elseif currentSet and currentEffect then
        local label = effectToString(currentSet, currentEffect)
        local pf    = getPlayFlash()
        drawUIPanel(AX - 4, AY - 4, AW + 8, 66, 6)
        if pf > 0 then
            love.graphics.setColor(1, 0.84, 0.24, pf * 0.14)
            love.graphics.rectangle("fill", AX - 4, AY - 4, AW + 8, 66, 6, 6)
        end
        love.graphics.setFont(FONT_UI)
        love.graphics.setColor(0.96, 0.91, 0.46)
        love.graphics.printf(label, AX, AY, AW, "left")
        love.graphics.setFont(FONT_SMALL)
        love.graphics.setColor(0.54, 0.86, 0.54)
        love.graphics.printf("ENTER to play", AX, AY + 20, AW, "left")

    elseif next(selectedIndices) then
        drawUIPanel(AX - 4, AY - 4, AW + 8, 38, 6)
        love.graphics.setFont(FONT_UI)
        love.graphics.setColor(0.86, 0.30, 0.30)
        love.graphics.printf("Not a valid set", AX, AY, AW, "left")

    elseif hoveredTile and not mustDiscard then
        local tile = playerHand[hoveredTile]
        if tile then
            local desc
            if     tile.suit == SUIT.CHARACTER then desc = "Character  —  Attack damage"
            elseif tile.suit == SUIT.BAMBOO    then desc = "Bamboo  —  Block / Defense"
            elseif tile.suit == SUIT.CIRCLE    then desc = "Circle  —  Mana"
            elseif tile.suit == SUIT.DRAGON    then desc = "Dragon  —  Multiplier effect"
            elseif tile.suit == SUIT.WIND      then desc = "Wind  —  Turn effect"
            elseif tile.suit == SUIT.FLOWER    then desc = "Flower / Season  —  Special"
            end
            if desc then
                drawUIPanel(AX - 4, AY - 4, AW + 8, 30, 6)
                love.graphics.setFont(FONT_UI)
                love.graphics.setColor(0.68, 0.64, 0.44)
                love.graphics.printf(desc, AX, AY, AW, "left")
            end
        end
    end

    -- ── Owned items — left column (right-click any for details; I = full view) ──
    itemPanelRects = {}
    if #playerItems > 0 then
        local IX, IY = 90, 354
        local lineH  = 15
        drawUIPanel(82, IY - 6, 232, 10 + #playerItems * lineH, 4)
        love.graphics.setFont(FONT_SMALL)
        for _, id in ipairs(playerItems) do
            local it = Items.ITEMS[id]
            if it then
                local rc = it.rarity == "rare"     and {0.90, 0.62, 0.10} or
                           it.rarity == "uncommon" and {0.46, 0.72, 0.90} or
                                                       {0.64, 0.62, 0.52}
                local isActive = (itemTooltip == id)
                love.graphics.setColor(rc[1] * (isActive and 1 or 0.85),
                                       rc[2] * (isActive and 1 or 0.85),
                                       rc[3] * (isActive and 1 or 0.85))
                love.graphics.print("• " .. it.name, IX, IY)
                table.insert(itemPanelRects, { x = 82, y = IY - 2, w = 232, h = lineH, id = id })
                IY = IY + lineH
            end
        end
        love.graphics.setColor(0.28, 0.26, 0.20)
        love.graphics.print("(I) full view", IX, IY + 2)
    end

    -- ── Bottom strip ─────────────────────────────────────────────────────────

    -- Player stats — BOTTOM LEFT
    drawUIPanel(82, 508, 228, 70, 6)
    local BX, BY = 90, 516
    local BAR_W  = 212
    local BAR_H  = 12

    -- HP bar (shared-pool: crimson bleeds into blue to show it's also mana)
    love.graphics.setColor(0.10, 0.10, 0.10)
    love.graphics.rectangle("fill", BX, BY, BAR_W, BAR_H, 3, 3)
    if ITEM_FLAGS.sharedPool then
        love.graphics.setColor(0.52, 0.06, 0.30)   -- deep crimson-purple for fused pool
    else
        love.graphics.setColor(0.66, 0.09, 0.08)
    end
    love.graphics.rectangle("fill", BX, BY,
        BAR_W * math.max(0, playerHP / playerMaxHP), BAR_H, 3, 3)
    if playerBlock > 0 then
        local bf = math.min(1, playerBlock / playerMaxHP)
        love.graphics.setColor(0.25, 0.42, 0.78, 0.50)
        love.graphics.rectangle("fill", BX, BY, BAR_W * bf, BAR_H, 3, 3)
    end
    love.graphics.setFont(FONT_SMALL)
    love.graphics.setColor(0.88, 0.88, 0.88)
    local hpLabel = "HP " .. playerHP .. "/" .. playerMaxHP
    love.graphics.printf(hpLabel, BX, BY + 1, BAR_W, "center")
    if playerBlock > 0 then
        love.graphics.setColor(0.65, 0.84, 1.0)
        love.graphics.printf("+" .. playerBlock, BX, BY + 1, BAR_W - 2, "right")
    end

    -- MP bar (hidden when shared pool — the pool bar above already shows the value)
    local MPY = BY + 18
    if not ITEM_FLAGS.sharedPool then
        love.graphics.setColor(0.10, 0.10, 0.10)
        love.graphics.rectangle("fill", BX, MPY, BAR_W, BAR_H, 3, 3)
        love.graphics.setColor(0.10, 0.25, 0.66)
        love.graphics.rectangle("fill", BX, MPY,
            BAR_W * math.max(0, playerMana / playerMaxMana), BAR_H, 3, 3)
        love.graphics.setColor(0.88, 0.88, 0.88)
        love.graphics.printf("MP " .. playerMana .. "/" .. playerMaxMana, BX, MPY + 1, BAR_W, "center")
    end

    -- Gold coin icon + number
    local GY = MPY + 20
    love.graphics.setColor(0.68, 0.50, 0.06)
    love.graphics.circle("fill", BX + 7, GY + 7, 7)
    love.graphics.setColor(0.94, 0.76, 0.18)
    love.graphics.circle("fill", BX + 7, GY + 7, 5.5)
    love.graphics.setColor(0.72, 0.56, 0.10)
    love.graphics.circle("fill", BX + 7, GY + 7, 3)
    love.graphics.setFont(FONT_UI)
    love.graphics.setColor(0.90, 0.78, 0.22)
    love.graphics.print(tostring(playerGold), BX + 18, GY + 1)

    -- Dragon multipliers (compact, same line as gold if active)
    local multParts = {}
    if mult.damage > 1 then table.insert(multParts, "ATK×" .. mult.damage) end
    if mult.block  > 1 then table.insert(multParts, "BLK×" .. mult.block)  end
    if mult.mana   > 1 then table.insert(multParts, "MP×"  .. mult.mana)   end
    if #multParts > 0 then
        love.graphics.setFont(FONT_SMALL)
        love.graphics.setColor(0.86, 0.68, 0.09)
        love.graphics.print(table.concat(multParts, " "), BX + 60, GY + 3)
    end

    if autumnShieldActive then
        love.graphics.setFont(FONT_SMALL)
        love.graphics.setColor(0.70, 0.42, 0.66)
        love.graphics.print("Autumn shield", BX + 2, GY + 16)
    end

    -- Action buttons — BOTTOM CENTRE
    local function drawBtn(btn, lbl, active, r, g, b)
        love.graphics.setColor(0.04, 0.03, 0.02, 0.82)
        love.graphics.rectangle("fill", btn.x, btn.y, btn.w, btn.h, 4, 4)
        if active then
            love.graphics.setColor(r, g, b, 0.18)
            love.graphics.rectangle("fill", btn.x, btn.y, btn.w, btn.h, 4, 4)
        end
        love.graphics.setColor(
            active and r * 0.9 or r * 0.35,
            active and g * 0.9 or g * 0.35,
            active and b * 0.9 or b * 0.35, 0.85)
        love.graphics.setLineWidth(1)
        love.graphics.rectangle("line", btn.x, btn.y, btn.w, btn.h, 4, 4)
        love.graphics.setFont(FONT_SMALL)
        love.graphics.setColor(
            active and 0.86 or 0.36,
            active and 0.82 or 0.36,
            active and 0.68 or 0.30)
        love.graphics.printf(lbl, btn.x, btn.y + 6, btn.w, "center")
        love.graphics.setLineWidth(1)
    end

    drawBtn(SORT_BTN, "Sort Hand", true, 0.52, 0.42, 0.22)

    local useWindDraw  = freeDrawsRemaining > 0 and drawsThisTurn > 0
    local useItemDraw  = (itemFreeDraws > 0 or itemCombatFreeDraws > 0) and drawsThisTurn > 0 and not useWindDraw
    local baseDrawCost = math.ceil(drawsThisTurn / 2) * 5
    local drawCost     = (useWindDraw or useItemDraw) and 0
                         or (ITEM_FLAGS.sharedPool and baseDrawCost * 2 or baseDrawCost)
    local canDraw      = playerMana >= drawCost and turnPhase == "player" and not mustDiscard and not burstDiscardMode and not freeReplace.mode
    local drawLabel
    if useWindDraw then
        drawLabel = "Draw (Wind x" .. freeDrawsRemaining .. ")"
    elseif useItemDraw then
        drawLabel = "Draw (Free x" .. (itemFreeDraws + itemCombatFreeDraws) .. ")"
    elseif drawCost == 0 then
        drawLabel = "Draw (Free)"
    else
        drawLabel = "Draw (" .. drawCost .. " MP)"
    end
    drawBtn(MANA_DRAW_BTN, drawLabel, canDraw, 0.20, 0.36, 0.72)

    local canPlay = currentSet ~= nil and currentEffect ~= nil
                    and turnPhase == "player" and not mustDiscard and not burstDiscardMode and not freeReplace.mode
    drawBtn(PLAY_SET_BTN, "Play Set", canPlay, 0.88, 0.74, 0.14)

    if claimableDiscard and not encounterWon and drawsThisTurn == 0
    and turnPhase == "player" and canClaimTile(claimableDiscard, playerHand, ITEM_FLAGS) then
        drawBtn(CLAIM_BTN, "Claim  [C]", true, 0.68, 0.50, 0.12)
    end

    local canReplaceBtn = freeReplace.available and turnPhase == "player"
                          and not mustDiscard and not burstDiscardMode and #drawPile > 0
    if canReplaceBtn or freeReplace.mode then
        local replaceLabel = freeReplace.mode and "Cancel Replace" or "Replace (1×)"
        drawBtn(REPLACE_BTN, replaceLabel, true, 0.28, 0.62, 0.40)
    end

    -- Draw pile count (subtle, above buttons)
    love.graphics.setFont(FONT_SMALL)
    love.graphics.setColor(0.38, 0.36, 0.30)
    love.graphics.printf("Wall: " .. #drawPile, 318, 530, 464, "center")

    -- Keyboard hints — right of buttons
    love.graphics.setFont(FONT_SMALL)
    love.graphics.setColor(0.28, 0.26, 0.22)
    local HX, HY = 792, 514
    if burstDiscardMode then
        love.graphics.print("SPACE  Pass discard", HX, HY)
        love.graphics.print("C      Claim",        HX, HY + 13)
        love.graphics.print("TAB    Played",       HX, HY + 26)
    else
        love.graphics.print("SPACE  End Turn",  HX, HY)
        love.graphics.print("D      Draw",      HX, HY + 13)
        love.graphics.print("C      Claim",     HX, HY + 26)
        love.graphics.print("TAB    Played",    HX, HY + 39)
        love.graphics.print("ENTER  Play set",  HX, HY + 52)
        love.graphics.print("I      Items",     HX, HY + 65)
    end

    -- Turn indicator — BOTTOM RIGHT
    love.graphics.setFont(FONT_TITLE)
    if burstDiscardMode then
        love.graphics.setColor(0.82, 0.62, 0.10)
        love.graphics.print("DISCARD", 996, 547)
    elseif turnPhase == "player" then
        love.graphics.setColor(0.24, 0.72, 0.34)
        love.graphics.print("YOUR TURN", 980, 547)
    else
        love.graphics.setColor(0.78, 0.22, 0.22)
        love.graphics.print("ENEMY TURN", 980, 547)
    end

    -- Player hand
    local anim   = getDrawAnim()
    local flashI = getFlashIdx()
    local flashT = getFlashT()
    drawHand(playerHand, hoveredTile, selectedIndices, mustDiscard,
             flashI, flashT, anim and anim.idx)

    -- Fly-in animation tile on top
    if anim then
        drawMahjongTile(anim.tile, anim.cx, anim.cy, 64, 88,
                        false, false, false, false, 0)
    end

    -- Played hands overlay (TAB)
    if showPlayedHands and not gameOver and not runComplete then
        love.graphics.setColor(0, 0, 0, 0.88)
        love.graphics.rectangle("fill", 0, 0, 1280, 720)

        love.graphics.setFont(FONT_TITLE)
        love.graphics.setColor(0.92, 0.78, 0.22)
        love.graphics.printf("PLAYED HANDS", 0, 44, 1280, "center")

        local TW, TH, TG = 44, 60, 5
        local COL_W = 640

        -- Player melds (left half)
        love.graphics.setFont(FONT_UI)
        love.graphics.setColor(0.34, 0.88, 0.50)
        love.graphics.printf("YOUR MELDS", 0, 90, COL_W, "center")

        if #playerRevealedMelds == 0 then
            love.graphics.setFont(FONT_SMALL)
            love.graphics.setColor(0.38, 0.34, 0.26)
            love.graphics.printf("None played yet", 0, 118, COL_W, "center")
        else
            local rowY = 118
            for _, meld in ipairs(playerRevealedMelds) do
                local totalW = #meld.tiles * (TW + TG) - TG
                local rowX   = (COL_W - totalW) / 2
                for _, tile in ipairs(meld.tiles) do
                    drawMahjongTile(tile, rowX, rowY, TW, TH, false, false, false, false, 0)
                    rowX = rowX + TW + TG
                end
                rowY = rowY + TH + 10
            end
        end

        -- Enemy melds (right half)
        local enemyMelds = (enemy and enemy.revealedMelds) or {}
        love.graphics.setFont(FONT_UI)
        love.graphics.setColor(0.88, 0.38, 0.38)
        love.graphics.printf("ENEMY MELDS", COL_W, 90, COL_W, "center")

        if #enemyMelds == 0 then
            love.graphics.setFont(FONT_SMALL)
            love.graphics.setColor(0.38, 0.34, 0.26)
            love.graphics.printf("None revealed yet", COL_W, 118, COL_W, "center")
        else
            local rowY = 118
            for _, meld in ipairs(enemyMelds) do
                local totalW = #meld.tiles * (TW + TG) - TG
                local rowX   = COL_W + (COL_W - totalW) / 2
                for _, tile in ipairs(meld.tiles) do
                    drawMahjongTile(tile, rowX, rowY, TW, TH, false, false, false, false, 0)
                    rowX = rowX + TW + TG
                end
                rowY = rowY + TH + 10
            end
        end

        -- Divider
        love.graphics.setColor(0.30, 0.28, 0.20, 0.60)
        love.graphics.setLineWidth(1)
        love.graphics.line(640, 80, 640, 660)
        love.graphics.setLineWidth(1)

        love.graphics.setFont(FONT_SMALL)
        love.graphics.setColor(0.34, 0.32, 0.24)
        love.graphics.printf("TAB to close", 0, 682, 1280, "center")
    end

    love.graphics.pop()   -- end screen shake; overlays below are stable

    -- ── Tile / item info tooltip (right-click) ────────────────────────────────
    if tileTooltip and not gameOver and not runComplete then
        local lines = getTileInfo(tileTooltip)
        drawInfoPopup(440, 455, lines)
    elseif itemTooltip and not gameOver and not runComplete then
        local it = Items.ITEMS[itemTooltip]
        if it then
            local rc = it.rarity == "rare"     and {0.90, 0.62, 0.10} or
                       it.rarity == "uncommon" and {0.46, 0.72, 0.90} or
                                                   {0.64, 0.62, 0.52}
            drawInfoPopup(330, 354, { it.name, it.desc }, rc[1])
        end
    end

    -- ── Items panel overlay (I key) ───────────────────────────────────────────
    if showItemsPanel and not gameOver and not runComplete then
        love.graphics.setColor(0, 0, 0, 0.90)
        love.graphics.rectangle("fill", 0, 0, 1280, 720)

        love.graphics.setFont(FONT_TITLE)
        love.graphics.setColor(0.92, 0.78, 0.22)
        love.graphics.printf("YOUR ITEMS", 0, 44, 1280, "center")

        if #playerItems == 0 then
            love.graphics.setFont(FONT_UI)
            love.graphics.setColor(0.38, 0.34, 0.26)
            love.graphics.printf("No items yet.", 0, 300, 1280, "center")
        else
            local CARD_W, CARD_H, CARD_GAP = 260, 160, 20
            local cols    = math.min(#playerItems, 4)
            local totalW  = cols * CARD_W + (cols - 1) * CARD_GAP
            local startX  = (1280 - totalW) / 2
            local startY  = 110

            for i, id in ipairs(playerItems) do
                local it  = Items.ITEMS[id]
                if it then
                    local col = (i - 1) % cols
                    local row = math.floor((i - 1) / cols)
                    local cx  = startX + col * (CARD_W + CARD_GAP)
                    local cy  = startY + row * (CARD_H + CARD_GAP)
                    local rc  = it.rarity == "rare"     and {0.90, 0.62, 0.10} or
                                it.rarity == "uncommon" and {0.46, 0.72, 0.90} or
                                                           {0.64, 0.62, 0.52}

                    love.graphics.setColor(0.09, 0.11, 0.14, 0.97)
                    love.graphics.rectangle("fill", cx, cy, CARD_W, CARD_H, 7, 7)
                    love.graphics.setColor(rc[1]*0.10, rc[2]*0.10, rc[3]*0.10, 0.60)
                    love.graphics.rectangle("fill", cx, cy, CARD_W, CARD_H, 7, 7)
                    love.graphics.setColor(rc[1], rc[2], rc[3], 0.80)
                    love.graphics.rectangle("fill", cx, cy, CARD_W, 4, 4, 0)
                    love.graphics.setLineWidth(1.5)
                    love.graphics.rectangle("line", cx, cy, CARD_W, CARD_H, 7, 7)
                    love.graphics.setLineWidth(1)

                    love.graphics.setFont(FONT_TITLE)
                    love.graphics.setColor(0.96, 0.90, 0.72)
                    love.graphics.printf(it.name, cx + 10, cy + 12, CARD_W - 20, "left")

                    love.graphics.setFont(FONT_SMALL)
                    love.graphics.setColor(rc[1], rc[2], rc[3], 0.80)
                    love.graphics.printf(it.rarity:upper(), cx + 10, cy + 32, CARD_W - 20, "left")

                    love.graphics.setColor(0.78, 0.74, 0.60)
                    love.graphics.printf(it.desc, cx + 10, cy + 50, CARD_W - 20, "left")
                end
            end
        end

        love.graphics.setFont(FONT_SMALL)
        love.graphics.setColor(0.34, 0.32, 0.24)
        love.graphics.printf("I to close", 0, 682, 1280, "center")
    end

    -- Encounter won
    if encounterWon and not runComplete then
        love.graphics.setColor(0, 0, 0, 0.74)
        love.graphics.rectangle("fill", 0, 0, 1280, 720)
        love.graphics.setFont(FONT_TITLE)
        love.graphics.setColor(0.34, 0.88, 0.42)
        love.graphics.printf("Enemy Defeated!", 0, 286, 1280, "center")
        love.graphics.setColor(0.88, 0.72, 0.16)
        love.graphics.printf(
            "+" .. pendingGold .. " Gold  (total: " .. playerGold .. ")",
            0, 322, 1280, "center")
        love.graphics.setFont(FONT_UI)
        love.graphics.setColor(0.54, 0.54, 0.54)
        love.graphics.printf("Press SPACE to continue", 0, 358, 1280, "center")
    end

    -- Run complete
    if runComplete then
        love.graphics.setColor(0, 0, 0, 0.80)
        love.graphics.rectangle("fill", 0, 0, 1280, 720)
        love.graphics.setFont(FONT_TITLE)
        love.graphics.setColor(0.96, 0.80, 0.16)
        love.graphics.printf("RUN COMPLETE", 0, 296, 1280, "center")
        love.graphics.setFont(FONT_UI)
        love.graphics.setColor(0.54, 0.54, 0.54)
        love.graphics.printf("Press R to play again", 0, 346, 1280, "center")
    end

    -- Game over
    if gameOver then
        love.graphics.setColor(0, 0, 0, 0.80)
        love.graphics.rectangle("fill", 0, 0, 1280, 720)
        love.graphics.setFont(FONT_TITLE)
        love.graphics.setColor(0.86, 0.16, 0.16)
        love.graphics.printf("GAME OVER", 0, 296, 1280, "center")
        love.graphics.setFont(FONT_UI)
        if combatLog ~= "" then
            love.graphics.setColor(0.64, 0.64, 0.64)
            love.graphics.printf(combatLog, 0, 340, 1280, "center")
        end
        love.graphics.setColor(0.44, 0.44, 0.44)
        love.graphics.printf("Press R to restart", 0, 372, 1280, "center")
    end
end

function love.mousemoved(x, y)
    hoveredTile = getHoveredTileIndex(playerHand, x, y, selectedIndices)
end

function love.mousepressed(x, y, button)
    -- Right-click: toggle tile or item info tooltip
    if button == 2 and gameState == "combat" and not gameOver and not runComplete then
        local tileIdx = getHoveredTileIndex(playerHand, x, y, selectedIndices)
        if tileIdx then
            local t = playerHand[tileIdx]
            if tileTooltip == t then tileTooltip = nil else tileTooltip = t end
            itemTooltip = nil
            return
        end
        for _, r in ipairs(itemPanelRects) do
            if hitTest(x, y, r) then
                if itemTooltip == r.id then itemTooltip = nil else itemTooltip = r.id end
                tileTooltip = nil
                return
            end
        end
        tileTooltip = nil
        itemTooltip = nil
        return
    end

    if button ~= 1 or gameOver or runComplete then return end

    -- Run-start item selection
    if gameState == "run_start" then
        if hitTest(x, y, runStartSkipBtn) then
            gameState = "map"
            return
        end
        for _, rect in ipairs(runStartRects) do
            if hitTest(x, y, rect) then
                table.insert(playerItems, rect.id)
                applyItemFlags()
                gameState = "map"
                return
            end
        end
        return
    end

    -- Shop
    if gameState == "shop" then
        if hitTest(x, y, shopExitBtn) then
            gameState = "map"
            return
        end
        for _, rect in ipairs(shopItemRects) do
            if hitTest(x, y, rect) then
                table.insert(playerItems, rect.id)
                applyItemFlags()
                gameState = "map"
                return
            end
        end
        return
    end

    -- Elite item reward
    if gameState == "item_reward" then
        if hitTest(x, y, itemRewardSkipBtn) then
            gameState = "map"
            return
        end
        for _, rect in ipairs(itemRewardRects) do
            if hitTest(x, y, rect) then
                table.insert(playerItems, rect.id)
                applyItemFlags()
                gameState = "map"
                return
            end
        end
        return
    end

    -- Map navigation
    if gameState == "map" then
        local clicked = getClickedMapNode(x, y)
        if clicked then
            local node = visitMapNode(clicked.floor, clicked.col)
            if not node then return end
            if node.type == "rest" then
                local heal = math.floor(playerMaxHP * 0.25)
                playerHP   = math.min(playerMaxHP, playerHP + heal)
                if ITEM_FLAGS.sharedPool then playerMana = playerHP end
                combatLog  = "Rested — recovered " .. heal .. " HP"
            elseif node.type == "shop" then
                shopOffer = Shop.generateOffer(playerItems, Items.bySource("shop"))
                gameState = "shop"
            else
                local def = getNodeEnemyDef(node, combatsThisAct)
                if node.type == "combat" then combatsThisAct = combatsThisAct + 1 end
                if def then
                    startEncounterFromDef(def, node.type)
                    startPlayerTurn()
                    gameState = "combat"
                end
            end
        end
        return
    end

    if encounterWon then return end

    -- Spring steal: click enemy tiles to select, buttons blocked
    if springStealMode then
        local idx = getEnemyHandTileAt(enemy, x, y)
        if idx then
            local selCount = 0
            for _ in pairs(springSelected) do selCount = selCount + 1 end
            if springSelected[idx] then
                springSelected[idx] = nil
            elseif selCount < 4 then
                springSelected[idx] = true
            end
        end
        return
    end

    -- Flower replace: only allow tile toggling, no buttons
    if flowerReplaceMode then
        if hoveredTile then
            if selectedIndices[hoveredTile] then
                selectedIndices[hoveredTile] = nil
            else
                selectedIndices[hoveredTile] = true
            end
        end
        return
    end

    -- Sort button click
    if hitTest(x, y, SORT_BTN) then
        sortHand()
        return
    end

    -- Claim enemy discard button
    if hitTest(x, y, CLAIM_BTN) then
        claimDiscard()
        return
    end

    -- Mana draw button
    if hitTest(x, y, MANA_DRAW_BTN) then
        if turnPhase == "player" and not mustDiscard then
            claimableDiscard = nil
            tryDraw()
        end
        return
    end

    -- Play Set button
    if hitTest(x, y, PLAY_SET_BTN) then
        playCurrentSet()
        return
    end

    -- Replace button
    if hitTest(x, y, REPLACE_BTN) then
        if freeReplace.mode then
            freeReplace.mode = false
            combatLog       = ""
            selectedIndices = {}
            refreshSet()
        elseif freeReplace.available and turnPhase == "player" and not mustDiscard and not burstDiscardMode and #drawPile > 0 then
            freeReplace.mode = true
            selectedIndices = {}
            currentSet      = nil
            currentEffect   = nil
            combatLog       = "Select a tile to replace."
        end
        return
    end

    if mustDiscard then
        if hoveredTile then
            local discarded = table.remove(playerHand, hoveredTile)
            table.insert(discardPile, discarded)
            if enemy and not encounterWon then
                if enemyTryClaim(enemy, discardPile) then
                    claimableDiscard = nil
                    local enemyDiscarded = enemyDiscardIfReady()
                    if not gameOver then
                        if enemyDiscarded then
                            combatLog = "Enemy claimed your discard and discarded."
                        else
                            combatLog = "Enemy claimed your discard!"
                        end
                    end
                end
            end
            hoveredTile     = nil
            mustDiscard     = (#playerHand > HAND_CAP)
            selectedIndices = {}
            refreshSet()
        end
        return
    end

    -- Replace mode: clicking a tile swaps it out for a new draw
    if freeReplace.mode then
        if hoveredTile then
            local discarded = table.remove(playerHand, hoveredTile)
            table.insert(discardPile, discarded)
            freeReplace.mode      = false
            freeReplace.available = false
            selectedIndices      = {}
            hoveredTile          = nil
            local tile = drawTile(drawPile)
            processTileFromDraw(tile)
            if not mustDiscard then combatLog = "Tile replaced." end
        end
        return
    end

    -- Toggle tile selection (max 4) - only during player turn, not during discard sequence
    if turnPhase ~= "player" or burstDiscardMode then return end
    if hoveredTile then
        if selectedIndices[hoveredTile] then
            selectedIndices[hoveredTile] = nil
        else
            local count = 0
            for _ in pairs(selectedIndices) do count = count + 1 end
            if count < 4 then
                selectedIndices[hoveredTile] = true
            end
        end
        refreshSet()
    end
end

function love.keypressed(key)
    if key == "r" then
        love.event.quit("restart")

    elseif gameState == "run_start" or gameState == "shop" or gameState == "item_reward" then
        if key == "escape" then gameState = "map" end

    elseif gameOver or runComplete then
        return

    elseif encounterWon then
        if key == "space" then
            encounterWon = false
            if currentNodeType == "boss" then
                if isRunComplete() then
                    runComplete = true
                else
                    combatsThisAct = 0
                    startNextAct()
                    gameState = "map"
                end
            elseif currentNodeType == "elite" then
                local rewards = Shop.generateOffer(playerItems, Items.bySource("elite"), 3)
                if #rewards > 0 then
                    itemRewardOffer = rewards
                    gameState = "item_reward"
                else
                    gameState = "map"
                end
            else
                gameState = "map"
            end
        end
        return

    elseif freeReplace.mode then
        if key == "escape" then
            freeReplace.mode = false
            combatLog       = ""
            selectedIndices = {}
            refreshSet()
        end
        return

    elseif flowerReplaceMode then
        if key == "return" then
            local count = removeSelectedTiles(discardPile)
            flowerReplaceMode = false  -- clear before draws; re-set if another flower lands
            local logMsg = count > 0 and ("Replaced " .. count .. " tile(s).") or "Kept all tiles."
            replacementDrawsPending = replacementDrawsPending + count
            selectedIndices = {}
            hoveredTile     = nil
            drawPendingReplacementTiles(logMsg)
        end
        return

    elseif springStealMode then
        if key == "return" then
            local toSteal = {}
            for i in pairs(springSelected) do table.insert(toSteal, i) end
            table.sort(toSteal, function(a, b) return a > b end)
            local count = #toSteal
            for _, idx in ipairs(toSteal) do
                if enemy then table.insert(playerHand, table.remove(enemy.hand, idx)) end
            end
            springSelected  = {}
            springStealMode = false
            selectedIndices = {}
            hoveredTile     = nil
            local logMsg = count > 0 and ("Stole " .. count .. " tile(s) from the enemy!") or "Spring passed."
            drawPendingReplacementTiles(logMsg)
        end
        return

    elseif key == "escape" and gameState == "combat" then
        showPlayedHands = false
        showItemsPanel  = false
        tileTooltip     = nil
        itemTooltip     = nil

    elseif key == "tab" then
        showItemsPanel  = false
        showPlayedHands = not showPlayedHands

    elseif key == "i" and gameState == "combat" then
        showPlayedHands = false
        showItemsPanel  = not showItemsPanel

    elseif key == "space" and turnPhase == "player" and not mustDiscard and not enemyIsDead(enemy) then
        if burstDiscardMode then
            -- Pass on the current discard and reveal the next one
            claimableDiscard = nil
            processBurstDiscard()
            return
        end
        if drawsThisTurn == 0 and #drawPile > 0 then
            combatLog = "Take your free draw before ending your turn."
            return
        end
        claimableDiscard = nil
        -- Shield from block intent wears off at the start of the enemy's turn
        if enemy then enemy.shield = 0 end
        if skipNextEnemyTurn then
            skipNextEnemyTurn = false
            if not ITEM_FLAGS.retainBlock then playerBlock = 0 end
            combatLog = "Wind! Enemy turn skipped."
            startPlayerTurn()
        else
            turnPhase = "enemy"
            local result = enemyExecuteIntent(enemy, drawPile)

            local function applySingleHit(dmg)
                if autumnShieldActive then
                    autumnShieldActive = false
                    combatLog = combatLog .. " Autumn shield absorbed the hit!"
                    triggerShake(0.28)
                    return 0
                end
                local absorbed = math.min(playerBlock, dmg)
                playerBlock    = math.max(0, playerBlock - absorbed)
                local taken    = dmg - absorbed
                playerHP       = math.max(0, playerHP - taken)
                if ITEM_FLAGS.sharedPool then playerMana = playerHP end
                if taken > 0 then triggerShake(math.min(1.0, 0.3 + taken / 30)) end
                return taken, absorbed
            end

            if result.type == "attack" or result.type == "attack_single" then
                combatLog = ""
                local taken, absorbed = applySingleHit(result.damage)
                if combatLog == "" then
                    if absorbed > 0 and taken == 0 then
                        combatLog = "Enemy attacked for " .. result.damage .. " — fully blocked!"
                        triggerShake(0.35)
                    elseif absorbed > 0 then
                        combatLog = "Enemy attacked for " .. result.damage .. " — " .. absorbed .. " blocked, " .. taken .. " taken."
                    else
                        combatLog = "Enemy attacked for " .. taken .. " damage!"
                    end
                end

            elseif result.type == "attack_multi" then
                local totalTaken, totalAbsorbed = 0, 0
                for _ = 1, result.hits do
                    local taken, absorbed = applySingleHit(result.damage)
                    totalTaken    = totalTaken    + (taken    or 0)
                    totalAbsorbed = totalAbsorbed + (absorbed or 0)
                    if playerHP <= 0 then break end
                end
                if totalAbsorbed > 0 and totalTaken == 0 then
                    combatLog = "Enemy struck " .. result.hits .. "×" .. result.damage .. " — all blocked!"
                    triggerShake(0.35)
                elseif totalAbsorbed > 0 then
                    combatLog = "Enemy struck " .. result.hits .. "×" .. result.damage
                                .. " — " .. totalAbsorbed .. " blocked, " .. totalTaken .. " total damage."
                else
                    combatLog = "Enemy struck " .. result.hits .. "×" .. result.damage
                                .. " for " .. totalTaken .. " total damage!"
                    triggerShake(math.min(1.0, totalTaken / 20))
                end

            elseif result.type == "burst" then
                for _ = 1, result.count do
                    if enemy and #drawPile > 0 then
                        table.insert(enemy.hand, table.remove(drawPile, 1))
                    end
                end
                combatLog = "Wind Spirit draws " .. result.count .. " tiles!"

            elseif result.type == "block" then
                combatLog = "Wind Spirit raises a spirit shield! (+" .. result.amount .. " shield)"

            elseif result.type == "buff" then
                combatLog = "Wind Spirit grows stronger! (+" .. result.amount .. " strength)"

            else -- "draw"
                combatLog = "Enemy drew a tile."
            end

            if not ITEM_FLAGS.retainBlock then playerBlock = 0 end
            if not gameOver and playerHP <= 0 then
                gameOver = true
            end
            if not gameOver then
                -- Always pass through processBurstDiscard; it calls startPlayerTurn()
                -- immediately when no discards are needed, or pauses for each one.
                burstDiscardMode = true
                processBurstDiscard()
            end
        end

    elseif key == "c" and turnPhase == "player" and not mustDiscard then
        local claimed = claimDiscard()
        if claimed and burstDiscardMode and not gameOver and not encounterWon then
            processBurstDiscard()
        end

    elseif key == "d" and turnPhase == "player" and not mustDiscard then
        claimableDiscard = nil
        tryDraw()

    elseif key == "return" and currentSet and not mustDiscard then
        playCurrentSet()
    end
end
