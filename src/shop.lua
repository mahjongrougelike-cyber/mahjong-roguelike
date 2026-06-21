-- Shop / reward screen UI.
-- Used for both shop nodes (mode="shop") and elite combat rewards (mode="reward").
-- No pricing system yet — items are taken freely; gold costs to be added later.

local M = {}

local CARD_W, CARD_H = 280, 180
local CARD_Y         = 185
local CARD_GAP       = 28

local RARITY_COLOR = {
    rare     = { 0.90, 0.62, 0.10 },
    uncommon = { 0.32, 0.62, 0.90 },
    common   = { 0.60, 0.60, 0.60 },
}

-- Pick up to `count` items from `sourceIds` not already owned, shuffled.
-- sourceIds should already be filtered to the correct source via Items.bySource().
function M.generateOffer(ownedIds, sourceIds, count)
    count = count or 3
    local owned = {}
    for _, id in ipairs(ownedIds) do owned[id] = true end
    local pool = {}
    for _, id in ipairs(sourceIds) do
        if not owned[id] then table.insert(pool, id) end
    end
    for i = #pool, 2, -1 do
        local j  = math.random(i)
        pool[i], pool[j] = pool[j], pool[i]
    end
    local offer = {}
    for i = 1, math.min(count, #pool) do
        table.insert(offer, pool[i])
    end
    return offer
end

-- Draw the item selection screen and return hit-test data.
-- mode: "shop"      → title "SHOP",                    exit button "Leave"
--       "reward"   → title "CHOOSE A REWARD",          exit button "Skip"
--       "run_start"→ title "CHOOSE YOUR STARTING ITEM",exit button "Skip"
-- Returns: itemRects (list of {x,y,w,h,id}), exitBtn {x,y,w,h}
function M.draw(offer, ITEMS, playerItems, mode)
    mode = mode or "shop"

    local TITLES = {
        shop      = "SHOP",
        reward    = "CHOOSE A REWARD",
        run_start = "CHOOSE YOUR STARTING ITEM",
        jiangshi  = "JIANGSHI BARGAIN",
        tianshi   = "HEAVEN'S GRACE",
    }
    local EXIT_LABELS = {
        shop      = "Leave",
        reward    = "Skip",
        run_start = "Skip",
        jiangshi  = "Refuse",
        tianshi   = "Depart",
    }

    -- Dark overlay
    if mode == "jiangshi" then
        love.graphics.setColor(0.10, 0, 0, 0.88)
        love.graphics.rectangle("fill", 0, 0, 1280, 720)
        love.graphics.setColor(0.50, 0.04, 0.12, 0.28)
        love.graphics.rectangle("fill", 0, 0, 1280, 720)
    elseif mode == "tianshi" then
        love.graphics.setColor(0.02, 0.02, 0.05, 0.88)
        love.graphics.rectangle("fill", 0, 0, 1280, 720)
        love.graphics.setColor(0.44, 0.38, 0.04, 0.18)
        love.graphics.rectangle("fill", 0, 0, 1280, 720)
    else
        love.graphics.setColor(0, 0, 0, 0.82)
        love.graphics.rectangle("fill", 0, 0, 1280, 720)
    end

    -- Title
    love.graphics.setFont(FONT_TITLE)
    if mode == "jiangshi" then
        love.graphics.setColor(0.90, 0.20, 0.30)
    elseif mode == "tianshi" then
        love.graphics.setColor(0.98, 0.88, 0.42)
    else
        love.graphics.setColor(0.92, 0.78, 0.22)
    end
    love.graphics.printf(TITLES[mode] or "SHOP", 0, 60, 1280, "center")

    -- Tianshi subtitle
    if mode == "tianshi" then
        love.graphics.setFont(FONT_SMALL)
        love.graphics.setColor(0.72, 0.66, 0.40, 0.78)
        love.graphics.printf("A blessing for your restraint — choose freely.", 0, 96, 1280, "center")
    end

    -- Owned items summary
    if #playerItems > 0 then
        local names = {}
        for _, id in ipairs(playerItems) do
            local it = ITEMS[id]
            if it then table.insert(names, it.name) end
        end
        love.graphics.setFont(FONT_SMALL)
        love.graphics.setColor(0.46, 0.44, 0.34)
        love.graphics.printf("Owned: " .. table.concat(names, "  •  "), 60, 88, 1160, "center")
    end

    -- Item cards
    local totalW = #offer * CARD_W + math.max(0, #offer - 1) * CARD_GAP
    local startX = (1280 - totalW) / 2
    local itemRects = {}

    for i, id in ipairs(offer) do
        local it  = ITEMS[id]
        local ix  = startX + (i - 1) * (CARD_W + CARD_GAP)
        local rc  = RARITY_COLOR[it.rarity] or RARITY_COLOR.common

        -- Card background
        love.graphics.setColor(0.09, 0.11, 0.14, 0.97)
        love.graphics.rectangle("fill", ix, CARD_Y, CARD_W, CARD_H, 8, 8)

        -- Subtle rarity tint
        love.graphics.setColor(rc[1] * 0.10, rc[2] * 0.10, rc[3] * 0.10, 0.60)
        love.graphics.rectangle("fill", ix, CARD_Y, CARD_W, CARD_H, 8, 8)

        -- Rarity strip at top
        love.graphics.setColor(rc[1], rc[2], rc[3], 0.80)
        love.graphics.rectangle("fill", ix, CARD_Y, CARD_W, 4, 4, 0)

        -- Border
        love.graphics.setColor(rc[1] * 0.7, rc[2] * 0.7, rc[3] * 0.7, 0.80)
        love.graphics.setLineWidth(1.5)
        love.graphics.rectangle("line", ix, CARD_Y, CARD_W, CARD_H, 8, 8)
        love.graphics.setLineWidth(1)

        -- Item name
        love.graphics.setFont(FONT_TITLE)
        love.graphics.setColor(0.96, 0.90, 0.72)
        love.graphics.printf(it.name, ix + 10, CARD_Y + 14, CARD_W - 20, "left")

        -- Rarity label
        love.graphics.setFont(FONT_SMALL)
        love.graphics.setColor(rc[1], rc[2], rc[3], 0.80)
        love.graphics.printf(it.rarity:upper(), ix + 10, CARD_Y + 34, CARD_W - 20, "left")

        -- Description
        love.graphics.setFont(FONT_SMALL)
        love.graphics.setColor(0.78, 0.74, 0.60)
        love.graphics.printf(it.desc, ix + 10, CARD_Y + 52, CARD_W - 20, "left")

        -- Cost (jiangshi items)
        if it.cost_desc then
            love.graphics.setColor(0.90, 0.22, 0.28, 0.90)
            love.graphics.printf("Cost: " .. it.cost_desc, ix + 10, CARD_Y + CARD_H - 44, CARD_W - 20, "left")
        end

        -- Source badge (bottom right)
        love.graphics.setColor(0.40, 0.38, 0.28)
        love.graphics.printf(it.source:upper(), ix, CARD_Y + CARD_H - 22, CARD_W - 10, "right")

        table.insert(itemRects, { x = ix, y = CARD_Y, w = CARD_W, h = CARD_H, id = id })
    end

    if #offer == 0 then
        love.graphics.setFont(FONT_TITLE)
        love.graphics.setColor(0.46, 0.42, 0.32)
        love.graphics.printf("Nothing available.", 0, CARD_Y + 70, 1280, "center")
    end

    -- Exit button
    local exitLabel = EXIT_LABELS[mode] or "Leave"
    local EBX, EBY, EBW, EBH = 590, 420, 100, 34
    love.graphics.setColor(0.10, 0.12, 0.14, 0.92)
    love.graphics.rectangle("fill", EBX, EBY, EBW, EBH, 5, 5)
    love.graphics.setColor(0.36, 0.34, 0.26, 0.75)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", EBX, EBY, EBW, EBH, 5, 5)
    love.graphics.setFont(FONT_UI)
    love.graphics.setColor(0.72, 0.68, 0.52)
    love.graphics.printf(exitLabel, EBX, EBY + 9, EBW, "center")

    love.graphics.setFont(FONT_SMALL)
    love.graphics.setColor(0.34, 0.32, 0.24)
    love.graphics.printf("ESC to " .. exitLabel:lower(), 0, EBY + 44, 1280, "center")

    return itemRects, { x = EBX, y = EBY, w = EBW, h = EBH }
end

return M
