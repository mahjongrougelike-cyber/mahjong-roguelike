-- Hand and discard-pile rendering.
-- Delegates tile drawing to drawMahjongTile (src/tilerender.lua).

local TILE_W   = 64
local TILE_H   = 88
local TILE_GAP = 6

-- ── Layout ────────────────────────────────────────────────────────────────────

local function handLayout(hand)
    local totalW = #hand * (TILE_W + TILE_GAP) - TILE_GAP
    return (1280 - totalW) / 2, 720 - TILE_H - 30
end

-- Exported so main.lua can compute animation destinations.
function getHandLayout(handSize)
    local totalW = handSize * (TILE_W + TILE_GAP) - TILE_GAP
    local startX = (1280 - totalW) / 2
    local y      = 720 - TILE_H - 30
    return startX, y, TILE_W, TILE_H, TILE_GAP
end

-- ── Player hand ───────────────────────────────────────────────────────────────

-- flashIdx / flashT  — index + brightness (1→0) for newly drawn tile glow
-- animIdx            — index currently flying in (rendered by main.lua, skipped here)
function drawHand(hand, hoveredIndex, selectedIndices, mustDiscard, flashIdx, flashT, animIdx)
    local startX, y = handLayout(hand)

    for i, tile in ipairs(hand) do
        if i ~= animIdx then
            local x       = startX + (i - 1) * (TILE_W + TILE_GAP)
            local hovered = i == hoveredIndex
            local sel     = selectedIndices[i] == true
            local flash   = (flashIdx == i) and (flashT or 0) or 0
            drawMahjongTile(tile, x, y, TILE_W, TILE_H, sel, hovered, mustDiscard, false, flash)
        end
    end

    if mustDiscard then
        -- Pulse alpha between 0.72 and 1.0 so the banner catches the eye
        local pulse = 0.86 + 0.14 * math.sin(love.timer.getTime() * 5)
        love.graphics.setColor(0.55, 0.04, 0.02, 0.88 * pulse)
        love.graphics.rectangle("fill", 0, y - 30, 1280, 26)
        -- Subtle top/bottom border lines
        love.graphics.setColor(0.85, 0.18, 0.12, 0.70 * pulse)
        love.graphics.rectangle("fill", 0, y - 30, 1280, 2)
        love.graphics.rectangle("fill", 0, y - 6,  1280, 2)
        love.graphics.setFont(FONT_UI)
        love.graphics.setColor(1, 0.80, 0.76, pulse)
        love.graphics.printf("✦  Hand full — discard a tile  ✦", 0, y - 27, 1280, "center")
    end
end

-- ── Hit-testing ───────────────────────────────────────────────────────────────

function getHoveredTileIndex(hand, mx, my, selectedIndices)
    local startX, baseY = handLayout(hand)
    for i = 1, #hand do
        local x    = startX + (i - 1) * (TILE_W + TILE_GAP)
        local lift = (selectedIndices and selectedIndices[i]) and 20 or 0
        local y    = baseY - lift
        if mx >= x and mx <= x + TILE_W and my >= y and my <= y + TILE_H then
            return i
        end
    end
    return nil
end
