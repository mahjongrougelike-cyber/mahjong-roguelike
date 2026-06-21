require("src/tiles")

local SMALL_W      = 48
local SMALL_H      = 66
local SMALL_GAP    = 4
local PANEL_X      = 840
local HAND_START_Y = 142

local function isNumbered(tile)
    return tile.suit == SUIT.CHARACTER
        or tile.suit == SUIT.BAMBOO
        or tile.suit == SUIT.CIRCLE
end

local function sameSetIdentity(a, b)
    if isNumbered(a) and isNumbered(b) then
        return a.value == b.value
    end
    return a.suit == b.suit and a.label == b.label
end

-- ── Legacy random intent (used by placeholder enemies) ────────────────────────

local function pickIntent(enemy, currentIsAttack)
    if currentIsAttack then
        return { type = "draw" }
    elseif math.random() < 0.6 then
        return { type = "attack", damage = math.random(enemy.minAtk, enemy.maxAtk) }
    else
        return { type = "draw" }
    end
end

-- ── Wind Spirit cycle intent builder ─────────────────────────────────────────

local function buildWindSpiritIntent(e, intentType)
    if intentType == "attack" then
        if math.random() < 0.5 then
            return { type = "attack_single", damage = 14 + e.strength }
        else
            return { type = "attack_multi", hits = 3, damage = 3 + e.strength }
        end
    elseif intentType == "block" then
        return { type = "block", amount = 50 }
    elseif intentType == "burst" then
        return { type = "burst", count = 3 }
    elseif intentType == "buff" then
        return { type = "buff", amount = 2 }
    else
        return { type = "draw" }
    end
end

-- ── Xi cycle intent builder ───────────────────────────────────────────────────

local function buildXiIntent(e, intentType)
    if intentType == "attack" then
        if math.random() < 0.5 then
            return { type = "attack_single", damage = 20 }
        else
            return { type = "attack_multi", hits = 4, damage = 2 }
        end
    else -- "draw"
        return { type = "draw2" }
    end
end

-- ── Gaunxi cycle intent builder ───────────────────────────────────────────────

local function buildGaunxiIntent(e, intentType)
    if intentType == "attack" then
        if math.random() < 0.5 then
            return { type = "attack_single", damage = 5 }
        else
            return { type = "attack_multi", hits = 5, damage = 1 }
        end
    elseif intentType == "burst" then
        return { type = "burst", count = 3 }
    elseif intentType == "replace" then
        return { type = "replace" }
    else -- "draw_block"
        return { type = "draw_block", shield = 10 }
    end
end

-- ── Enemy factories ───────────────────────────────────────────────────────────

function createEnemy(name, hp, minAtk, maxAtk)
    local e = {
        name          = name,
        hp            = hp,
        maxHp         = hp,
        hand          = {},
        revealedMelds = {},
        discards      = {},
        minAtk        = minAtk or 8,
        maxAtk        = maxAtk or 16,
        shield        = 0,
        strength      = 0,
    }
    e.intent     = pickIntent(e, false)
    e.nextIntent = pickIntent(e, e.intent.type == "attack")
    return e
end

function createXi()
    local e = {
        name          = "Xi",
        hp            = 150,
        maxHp         = 150,
        hand          = {},
        revealedMelds = {},
        discards      = {},
        minAtk        = 0,
        maxAtk        = 0,
        shield        = 0,
        strength      = 0,
        attackBonus   = 0,
        cycle         = { "attack","attack","draw","attack","attack","draw","attack" },
        cycleIndex    = 3,
        buildIntent   = buildXiIntent,
    }
    e.intent     = buildXiIntent(e, e.cycle[1])
    e.nextIntent = buildXiIntent(e, e.cycle[2])
    return e
end

function createGaunxi()
    local e = {
        name          = "Gaunxi",
        hp            = 70,
        maxHp         = 70,
        hand          = {},
        revealedMelds = {},
        discards      = {},
        minAtk        = 0,
        maxAtk        = 0,
        shield        = 0,
        strength      = 0,
        cycle         = { "draw_block","attack","draw_block","burst","draw_block","replace","draw_block","attack" },
        cycleIndex    = 3,
        buildIntent   = buildGaunxiIntent,
    }
    e.intent     = buildGaunxiIntent(e, e.cycle[1])
    e.nextIntent = buildGaunxiIntent(e, e.cycle[2])
    return e
end

function createWindSpirit()
    local e = {
        name          = "Wind Spirit",
        hp            = 85,
        maxHp         = 85,
        hand          = {},
        revealedMelds = {},
        discards      = {},
        minAtk        = 0,
        maxAtk        = 0,
        shield        = 0,
        strength      = 0,
        -- intent rotation: draw interspersed between special moves
        cycle         = { "draw","attack","draw","burst","draw","block","draw","buff","attack" },
        cycleIndex    = 3,
    }
    -- pre-seed intent and nextIntent from first two slots
    e.intent     = buildWindSpiritIntent(e, e.cycle[1])
    e.nextIntent = buildWindSpiritIntent(e, e.cycle[2])
    return e
end

-- ── Shared combat functions ───────────────────────────────────────────────────

function enemyTakeDamage(enemy, amount)
    local absorbed   = math.min(enemy.shield or 0, amount)
    enemy.shield     = (enemy.shield or 0) - absorbed
    local actual     = amount - absorbed
    enemy.hp         = math.max(0, enemy.hp - actual)
    enemyDmgThisTurn = (enemyDmgThisTurn or 0) + actual
end

function enemyIsDead(enemy)
    return enemy.hp <= 0
end

-- Execute current intent, advance queue.
-- Returns a result table describing what happened; side-effects that need the
-- game's draw pile or discard logic are handled in main.lua based on result.type.
function enemyExecuteIntent(enemy, drawPile)
    local intent = enemy.intent
    local result = {
        type     = intent.type,
        damage   = 0,
        hits     = 1,
        count    = 0,
        amount   = 0,
    }

    local bonus = enemy.attackBonus or 0
    if intent.type == "attack" then
        result.damage = intent.damage + bonus
        if enemy.attackBonus ~= nil then enemy.attackBonus = 0 end
    elseif intent.type == "attack_single" then
        result.damage = intent.damage + bonus
        if enemy.attackBonus ~= nil then enemy.attackBonus = 0 end
    elseif intent.type == "attack_multi" then
        result.damage = intent.damage + bonus
        result.hits   = intent.hits or 3
        if enemy.attackBonus ~= nil then enemy.attackBonus = 0 end
    elseif intent.type == "buff" then
        enemy.strength = enemy.strength + (intent.amount or 2)
        result.amount  = intent.amount or 2
    elseif intent.type == "block" then
        enemy.shield  = intent.amount or 0
        result.amount = intent.amount or 0
    elseif intent.type == "burst" then
        result.count = intent.count or 3
        -- tile drawing + discard handled in main.lua
    elseif intent.type == "draw_block" then
        if #drawPile > 0 then
            table.insert(enemy.hand, table.remove(drawPile, 1))
        end
        enemy.shield = (enemy.shield or 0) + 10
    elseif intent.type == "replace" then
        -- Draw first (makes hand one over ready size); processBurstDiscard handles the discard
        if #drawPile > 0 then
            table.insert(enemy.hand, table.remove(drawPile, 1))
            enemy.shield = (enemy.shield or 0) + 10
        end
    elseif intent.type == "draw2" then
        for _ = 1, 2 do
            if #drawPile > 0 then
                table.insert(enemy.hand, table.remove(drawPile, 1))
            end
        end
    else -- "draw"
        if #drawPile > 0 then
            table.insert(enemy.hand, table.remove(drawPile, 1))
        end
    end

    -- advance the intent queue (use per-enemy builder if set)
    if enemy.cycle then
        enemy.intent   = enemy.nextIntent
        local nextType = enemy.cycle[enemy.cycleIndex]
        enemy.cycleIndex = (enemy.cycleIndex % #enemy.cycle) + 1
        local builder = enemy.buildIntent or buildWindSpiritIntent
        enemy.nextIntent = builder(enemy, nextType)
    else
        enemy.intent     = enemy.nextIntent
        enemy.nextIntent = pickIntent(enemy, enemy.intent.type == "attack")
    end

    return result
end

-- ── Tile scoring / discard AI ─────────────────────────────────────────────────

local function scoreTile(tile, hand)
    local score   = 0
    local numbered = tile.suit == SUIT.CHARACTER
                  or tile.suit == SUIT.BAMBOO
                  or tile.suit == SUIT.CIRCLE
    for _, other in ipairs(hand) do
        if other ~= tile then
            if not numbered then
                if other.suit == tile.suit and other.label == tile.label then
                    score = score + 3
                end
            else
                if other.value == tile.value then
                    score = score + 3
                elseif isNumbered(other) then
                    local d = math.abs(other.value - tile.value)
                    if d == 1 then score = score + 2
                    elseif d == 2 then score = score + 1
                    end
                end
            end
        end
    end
    return score
end

function enemyDiscard(enemy)
    if #enemy.hand == 0 then return end
    local minScore = math.huge
    local minIdx   = 1
    for i, tile in ipairs(enemy.hand) do
        local s = scoreTile(tile, enemy.hand)
        if s < minScore then
            minScore = s
            minIdx   = i
        end
    end
    table.insert(enemy.discards, table.remove(enemy.hand, minIdx))
end

function enemyTryClaim(enemy, playerDiscardPile)
    if #playerDiscardPile == 0 then return false end
    local claimed = playerDiscardPile[#playerDiscardPile]
    if claimed.suit == SUIT.FLOWER then return false end
    local matchIdx = {}
    for i, t in ipairs(enemy.hand) do
        if sameSetIdentity(t, claimed) then table.insert(matchIdx, i) end
    end
    if #matchIdx >= 2 then
        table.remove(playerDiscardPile)
        local t2 = table.remove(enemy.hand, matchIdx[2])
        local t1 = table.remove(enemy.hand, matchIdx[1])
        table.insert(enemy.revealedMelds, { tiles = {t1, t2, claimed}, type = "pung" })
        return true
    end
    return false
end

-- ── Top-bar layout ────────────────────────────────────────────────────────────

local BAR_X  = 86
local BAR_Y  = 76
local BAR_W  = 1108
local BAR_H  = 120

local EP_TW    = 26
local EP_TH    = 36
local EP_GAP   = 2
local EP_COLS  = 13
local EP_TILE_X = 820
local EP_TILE_Y = BAR_Y + math.floor((BAR_H - EP_TH) / 2)

local CTW, CTH, CTGAP = 26, 36, 3

-- ── Intent rendering ──────────────────────────────────────────────────────────

local function drawIntent(intent, x, y, e)
    love.graphics.setFont(FONT_UI)
    local t     = intent.type
    local bonus = (e and e.attackBonus) or 0
    if t == "attack" or t == "attack_single" then
        love.graphics.setColor(0.90, 0.28, 0.25)
        love.graphics.print("[ATK]  " .. (intent.damage + bonus) .. " dmg", x, y)
    elseif t == "attack_multi" then
        love.graphics.setColor(0.90, 0.28, 0.25)
        love.graphics.print("[ATK]  " .. intent.hits .. "×" .. (intent.damage + bonus) .. " dmg", x, y)
    elseif t == "block" then
        love.graphics.setColor(0.30, 0.55, 0.92)
        love.graphics.print("[BLK]  +" .. (intent.amount or 0) .. " shield", x, y)
    elseif t == "burst" then
        love.graphics.setColor(0.88, 0.72, 0.18)
        love.graphics.print("[BST]  Draw " .. (intent.count or 0) .. " tiles", x, y)
    elseif t == "buff" then
        love.graphics.setColor(0.78, 0.38, 0.92)
        love.graphics.print("[BUF]  +" .. (intent.amount or 0) .. " strength", x, y)
    elseif t == "draw_block" then
        love.graphics.setColor(0.30, 0.76, 0.46)
        love.graphics.print("[DRW]  Draw + 10 block", x, y)
    elseif t == "replace" then
        love.graphics.setColor(0.46, 0.76, 0.68)
        love.graphics.print("[REP]  Swap a tile", x, y)
    elseif t == "draw2" then
        love.graphics.setColor(0.30, 0.76, 0.46)
        love.graphics.print("[DRW]  Draw 2 tiles", x, y)
    else
        love.graphics.setColor(0.30, 0.76, 0.46)
        love.graphics.print("[DRW]  Draw tile", x, y)
    end
end

-- ── Enemy panel ───────────────────────────────────────────────────────────────

function drawCenterInfo(enemy)
    if not enemy then return end
    local cx = 870
    local bx = cx - 135
    local bw = 270
    local y  = 310

    if #enemy.revealedMelds > 0 then
        local totalW = 0
        for _, meld in ipairs(enemy.revealedMelds) do
            totalW = totalW + #meld.tiles * (CTW + CTGAP) + 6
        end
        totalW = totalW - 6
        local mx = cx - totalW / 2
        love.graphics.setFont(FONT_SMALL)
        love.graphics.setColor(0.76, 0.74, 0.46, 0.72)
        love.graphics.printf("Claimed", bx, y - 16, bw, "center")
        for _, meld in ipairs(enemy.revealedMelds) do
            for _, tile in ipairs(meld.tiles) do
                drawMahjongTile(tile, mx, y, CTW, CTH, false, false, false, false, 0)
                mx = mx + CTW + CTGAP
            end
            mx = mx + 6
        end
        y = y + CTH + 12
    end

    if #enemy.discards > 0 then
        local tile = enemy.discards[#enemy.discards]
        love.graphics.setFont(FONT_SMALL)
        love.graphics.setColor(0.50, 0.50, 0.50, 0.68)
        love.graphics.printf("Last discard", bx, y - 14, bw, "center")
        drawMahjongTile(tile, cx - CTW / 2, y, CTW, CTH, false, false, false, false, 0)
    end
end

function drawEnemyPanel(enemy, hideHand, revealHand)
    drawUIPanel(BAR_X, BAR_Y, BAR_W, BAR_H, 6)

    local lx   = BAR_X + 14
    local ly   = BAR_Y + 10
    local barW = 250
    local barH = 13

    love.graphics.setFont(FONT_TITLE)
    love.graphics.setColor(0.86, 0.70, 0.26)
    love.graphics.print(enemy.name, lx, ly)
    ly = ly + 22

    -- HP bar
    local hpFrac = math.max(0, enemy.hp / enemy.maxHp)
    love.graphics.setColor(0.12, 0.12, 0.12)
    love.graphics.rectangle("fill", lx, ly, barW, barH, 3, 3)
    love.graphics.setColor(0.68, 0.10, 0.09)
    love.graphics.rectangle("fill", lx, ly, barW * hpFrac, barH, 3, 3)
    love.graphics.setColor(1, 1, 1, 0.07)
    love.graphics.rectangle("fill", lx, ly, barW * hpFrac, barH / 2, 3, 3)
    love.graphics.setFont(FONT_SMALL)
    love.graphics.setColor(0.88, 0.88, 0.88)
    love.graphics.printf(enemy.hp .. " / " .. enemy.maxHp, lx, ly + 1, barW, "center")
    ly = ly + 18

    -- Shield bar (only shown when active)
    if (enemy.shield or 0) > 0 then
        love.graphics.setColor(0.30, 0.55, 0.92, 0.90)
        love.graphics.rectangle("fill", lx, ly, barW * math.min(1, enemy.shield / 50), barH, 3, 3)
        love.graphics.setColor(0.60, 0.80, 1.0, 0.50)
        love.graphics.rectangle("line", lx, ly, barW, barH, 3, 3)
        love.graphics.setColor(0.80, 0.92, 1.0)
        love.graphics.printf("Shield  " .. enemy.shield, lx, ly + 1, barW, "center")
        ly = ly + 18
    end

    if enemyIsDead(enemy) then
        love.graphics.setFont(FONT_UI)
        love.graphics.setColor(0.35, 0.86, 0.35)
        love.graphics.print("DEFEATED", lx, ly)
        return
    end

    -- Strength indicator
    if (enemy.strength or 0) > 0 then
        love.graphics.setFont(FONT_SMALL)
        love.graphics.setColor(0.78, 0.38, 0.92, 0.88)
        love.graphics.print("Strength  +" .. enemy.strength, lx, ly)
        ly = ly + 14
    end

    -- Rage indicator (Xi: grows with player draws, resets on set play)
    if (enemy.attackBonus or 0) > 0 then
        love.graphics.setFont(FONT_SMALL)
        love.graphics.setColor(0.92, 0.44, 0.18, 0.90)
        love.graphics.print("Rage  +" .. enemy.attackBonus .. " ATK", lx, ly)
        ly = ly + 14
    end

    -- Intents
    love.graphics.setFont(FONT_SMALL)
    love.graphics.setColor(0.58, 0.58, 0.58)
    love.graphics.print("Intent:", lx, ly)
    drawIntent(enemy.intent, lx + 56, ly, enemy)
    ly = ly + 18

    love.graphics.setColor(0.36, 0.36, 0.36)
    love.graphics.print("Next:", lx, ly)
    drawIntent(enemy.nextIntent, lx + 40, ly, enemy)

    -- Face-down hand
    if hideHand or enemyIsDead(enemy) then return end

    love.graphics.setFont(FONT_SMALL)
    love.graphics.setColor(0.42, 0.42, 0.42)
    love.graphics.print("Hand (" .. #enemy.hand .. ")", EP_TILE_X - 76, BAR_Y + 10)

    for i = 1, #enemy.hand do
        local col = (i - 1) % EP_COLS
        local row = math.floor((i - 1) / EP_COLS)
        local tx  = EP_TILE_X + col * (EP_TW + EP_GAP)
        local ty  = EP_TILE_Y + row * (EP_TH + 4)
        drawMahjongTile(enemy.hand[i], tx, ty, EP_TW, EP_TH,
                        false, false, false, not revealHand, 0)
    end
end

function drawSpringStealPanel(enemy, selected)
    if not enemy or #enemy.hand == 0 then return end
    local selCount = 0
    for _ in pairs(selected) do selCount = selCount + 1 end

    love.graphics.setFont(FONT_UI)
    love.graphics.setColor(0.35, 0.86, 0.35)
    love.graphics.printf(
        "Spring Steal — Select up to 4  [" .. selCount .. "/4]  ENTER confirm",
        0, BAR_Y + 8, 1280, "center")

    for i, tile in ipairs(enemy.hand) do
        local col = (i - 1) % EP_COLS
        local row = math.floor((i - 1) / EP_COLS)
        local tx  = EP_TILE_X + col * (EP_TW + EP_GAP)
        local ty  = EP_TILE_Y + row * (EP_TH + 4)
        drawMahjongTile(tile, tx, ty, EP_TW, EP_TH,
                        selected[i], false, false, false, 0)
    end
end

function getEnemyHandTileAt(enemy, mx, my)
    if not enemy then return nil end
    for i = 1, #enemy.hand do
        local col = (i - 1) % EP_COLS
        local row = math.floor((i - 1) / EP_COLS)
        local tx  = EP_TILE_X + col * (EP_TW + EP_GAP)
        local ty  = EP_TILE_Y + row * (EP_TH + 4)
        if mx >= tx and mx <= tx + EP_TW and my >= ty and my <= ty + EP_TH then
            return i
        end
    end
    return nil
end
