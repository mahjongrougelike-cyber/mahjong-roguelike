-- Renders the draw pile as a top-down mahjong wall.
-- Total 144 tiles arranged in 4 sides of 18 positions, each stacked 2 high.
-- Tiles are consumed from the top-left of the top wall going clockwise.

local N    = 18    -- tiles per side
local TW   = 13   -- tile size along wall
local TD   = 17   -- tile depth (perpendicular to wall)
local CX   = 580  -- wall center x (horizontally centered between panels)
local CY   = 355  -- wall center y
local HALF = N * TW / 2   -- 117

-- Bottom tile peeks out behind the top tile to show stacking
local SOX = -2
local SOY = -4

local COL_TOP  = { 0.918, 0.868, 0.728 }  -- warm ivory face
local COL_BOT  = { 0.600, 0.498, 0.332 }  -- tan bottom tile
local COL_LINE = { 0.225, 0.172, 0.095 }  -- dark border

local function drawOneTile(x, y, w, h, col)
    -- Face
    love.graphics.setColor(col)
    love.graphics.rectangle("fill", x, y, w, h, 2, 2)
    -- Top catchlight
    love.graphics.setColor(1, 0.96, 0.88, 0.22)
    love.graphics.rectangle("fill", x, y, w, 2)
    love.graphics.rectangle("fill", x, y, 2, h)
    -- Right / bottom shadow edge
    love.graphics.setColor(0, 0, 0, 0.18)
    love.graphics.rectangle("fill", x+w-2, y, 2, h)
    love.graphics.rectangle("fill", x, y+h-2, w, 2)
    -- Border
    love.graphics.setColor(COL_LINE)
    love.graphics.setLineWidth(0.75)
    love.graphics.rectangle("line", x, y, w, h, 2, 2)
    love.graphics.setLineWidth(1)
end

local function drawStack(x, y, w, h, count)
    if count >= 2 then
        drawOneTile(x + SOX, y + SOY, w, h, COL_BOT)
    end
    if count >= 1 then
        drawOneTile(x, y, w, h, COL_TOP)
    end
end

-- pileSize = current #drawPile
function drawWallDisplay(pileSize)
    local drawn        = math.max(0, 144 - pileSize)
    local emptyPos     = math.floor(drawn / 2)
    local halfAtEmpty  = drawn % 2 == 1

    local function stackCount(pos)
        if pos < emptyPos then return 0 end
        if pos == emptyPos and halfAtEmpty then return 1 end
        return 2
    end

    -- Top wall: positions 0..N-1, left to right
    for i = 0, N - 1 do
        local c = stackCount(i)
        if c > 0 then
            drawStack(CX - HALF + i * TW, CY - HALF - TD, TW, TD, c)
        end
    end

    -- Right wall: positions N..2N-1, top to bottom
    for i = 0, N - 1 do
        local c = stackCount(N + i)
        if c > 0 then
            drawStack(CX + HALF, CY - HALF + i * TW, TD, TW, c)
        end
    end

    -- Bottom wall: positions 2N..3N-1, right to left
    for i = 0, N - 1 do
        local c = stackCount(2 * N + i)
        if c > 0 then
            drawStack(CX + HALF - (i + 1) * TW, CY + HALF, TW, TD, c)
        end
    end

    -- Left wall: positions 3N..4N-1, bottom to top
    for i = 0, N - 1 do
        local c = stackCount(3 * N + i)
        if c > 0 then
            drawStack(CX - HALF - TD, CY + HALF - (i + 1) * TW, TD, TW, c)
        end
    end
end
