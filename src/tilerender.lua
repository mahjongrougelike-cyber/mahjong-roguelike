-- Mahjong tile renderer.
-- Draws ivory tiles with a 3D bevel, suit symbols, and an optional golden flash.
-- Requires globals: SUIT, FONT_TILENUM, FONT_TITLE, FONT_UI, FONT_SMALL, FONT_CJK (set in love.load)
-- Sprites loaded by loadTileImages() from assets/tiles/ (FluffyStuff riichi-mahjong-tiles).
-- Falls back to procedural art if a sprite file is absent.

local BEVEL     = 5   -- depth offset in pixels for the 3D side-face
local TILE_IMGS = {}  -- keyed by sprite name, e.g. "Man1", "Pin3", "Ton"

-- ── Sprite mapping ────────────────────────────────────────────────────────────

local function getTileKey(tile)
    if not tile then return nil end
    local s = tile.suit
    if     s == SUIT.CIRCLE    then return "Pin" .. (tile.value or 1)
    elseif s == SUIT.BAMBOO    then return "Sou" .. (tile.value or 1)
    elseif s == SUIT.CHARACTER then return "Man" .. (tile.value or 1)
    elseif s == SUIT.WIND then
        local m = {East="Ton", South="Nan", West="Shaa", North="Pei"}
        return m[tile.label]
    elseif s == SUIT.DRAGON then
        local m = {White="Haku", Green="Hatsu", Red="Chun"}
        return m[tile.label]
    end
    return nil
end

function loadTileImages()
    -- SVG renderer (nanosvg via LuaJIT FFI) gives vector-quality tiles.
    -- Falls back to the 600×800 PNG exports if SVG loading fails.
    local svgr    = require("lib/svgrender")
    local srcDir  = love.filesystem.getSourceBaseDirectory()
    local svgDir  = srcDir .. "/assets/tiles/svg/"
    local usingSVG = svgr.available

    local function tryLoad(key)
        -- 1. Try SVG
        if usingSVG then
            local img = svgr.load(svgDir .. key .. ".svg")
            if img then TILE_IMGS[key] = img; return end
        end
        -- 2. Fallback: PNG
        local ok, img = pcall(love.graphics.newImage, "assets/tiles/" .. key .. ".png")
        if ok then TILE_IMGS[key] = img end
    end

    for i = 1, 9 do
        tryLoad("Man" .. i)
        tryLoad("Pin" .. i)
        tryLoad("Sou" .. i)
    end
    for _, w in ipairs({"Ton","Nan","Shaa","Pei"})  do tryLoad(w) end
    for _, d in ipairs({"Haku","Hatsu","Chun"})      do tryLoad(d) end
    tryLoad("Back")

    if usingSVG then
        love.graphics.setDefaultFilter("linear", "linear")
    end
end

-- ── Pip grid positions ────────────────────────────────────────────────────────
-- Normalised (0-1) within the tile's inner drawing area.
local PIP_GRIDS = {
    { {.50,.50} },
    { {.50,.28}, {.50,.72} },
    { {.50,.20}, {.50,.50}, {.50,.80} },
    { {.30,.26}, {.70,.26}, {.30,.74}, {.70,.74} },
    { {.30,.22}, {.70,.22}, {.50,.50}, {.30,.78}, {.70,.78} },
    { {.30,.18}, {.70,.18}, {.30,.50}, {.70,.50}, {.30,.82}, {.70,.82} },
    { {.30,.16}, {.70,.16}, {.30,.41}, {.70,.41}, {.50,.62}, {.30,.84}, {.70,.84} },
    { {.30,.13}, {.70,.13}, {.30,.37}, {.70,.37},
      {.30,.62}, {.70,.62}, {.30,.87}, {.70,.87} },
    { {.22,.14}, {.50,.14}, {.78,.14},
      {.22,.50}, {.50,.50}, {.78,.50},
      {.22,.86}, {.50,.86}, {.78,.86} },
}

-- ── Per-pip drawers ───────────────────────────────────────────────────────────

local function pip_ring(cx, cy, r)
    love.graphics.setColor(0.08, 0.18, 0.58)          -- deep navy outer
    love.graphics.circle("fill", cx, cy, r)
    love.graphics.setColor(0.944, 0.914, 0.788)        -- ivory gap matches tile face
    love.graphics.circle("fill", cx, cy, r * 0.66)
    love.graphics.setColor(0.72, 0.08, 0.08)           -- red inner disc
    love.graphics.circle("fill", cx, cy, r * 0.44)
    love.graphics.setColor(0.95, 0.45, 0.42, 0.65)    -- centre highlight
    love.graphics.circle("fill", cx, cy, r * 0.18)
end

local function pip_bamboo(cx, cy, sw, sh)
    love.graphics.setColor(0.07, 0.34, 0.10)
    love.graphics.rectangle("fill", cx - sw/2, cy - sh/2, sw, sh, 2, 2)
    love.graphics.setColor(0.20, 0.58, 0.26)
    love.graphics.rectangle("fill", cx - sw/2 + 1, cy - sh/2 + 2,
                                    math.max(2, sw * 0.30), sh - 4)
    love.graphics.setColor(0.04, 0.20, 0.06)
    love.graphics.rectangle("fill", cx - sw/2, cy - sh/2 + sh*0.28, sw, 2)
    love.graphics.rectangle("fill", cx - sw/2, cy - sh/2 + sh*0.64, sw, 2)
end

local CHN = {"一","二","三","四","五","六","七","八","九"}

-- ── Suit symbol drawers ───────────────────────────────────────────────────────

local function draw_circle_suit(ix, iy, iw, ih, val)
    local grid = PIP_GRIDS[math.min(val, 9)] or {}
    local r    = math.min(iw, ih) * 0.105
    for _, p in ipairs(grid) do
        pip_ring(ix + p[1] * iw, iy + p[2] * ih, r)
    end
end

local function draw_bamboo_suit(ix, iy, iw, ih, val)
    local grid = PIP_GRIDS[math.min(val, 9)] or {}
    local sw   = iw * 0.17
    local sh   = ih * 0.148
    for _, p in ipairs(grid) do
        pip_bamboo(ix + p[1] * iw, iy + p[2] * ih, sw, sh)
    end
end

local function draw_character_suit(ix, iy, iw, ih, val)
    local numStr = CHN[val] or tostring(val)
    love.graphics.setFont(FONT_CJK or FONT_TILENUM)
    love.graphics.setColor(0.78, 0.06, 0.06)
    love.graphics.printf(numStr, ix, iy + ih * 0.06, iw, "center")
end

local function draw_dragon_suit(ix, iy, iw, ih, label)
    local cx, cy = ix + iw * 0.5, iy + ih * 0.50
    if label == "White" then
        -- Blank / Haku: double border rectangle
        love.graphics.setColor(0.58, 0.56, 0.50)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", ix+iw*0.14, iy+ih*0.16, iw*0.72, ih*0.68, 3, 3)
        love.graphics.setLineWidth(1)
        love.graphics.rectangle("line", ix+iw*0.22, iy+ih*0.24, iw*0.56, ih*0.52, 2, 2)

    elseif label == "Red" then
        -- Chun (中): simplified — two verticals dropping from a top bar
        love.graphics.setColor(0.78, 0.07, 0.06)
        love.graphics.setLineWidth(2.5)
        local x1, x2 = ix + iw*0.24, ix + iw*0.76
        local y1, y3 = iy + ih*0.26, iy + ih*0.74
        love.graphics.line(x1, y1, x2, y1)
        love.graphics.line(ix+iw*0.37, y1, ix+iw*0.37, y3)
        love.graphics.line(ix+iw*0.63, y1, ix+iw*0.63, y3)
        love.graphics.line(x1+iw*0.04, y3, x2-iw*0.04, y3)
        love.graphics.setLineWidth(1)

    elseif label == "Green" then
        -- Hatsu (發): diamond outline + inner cross
        love.graphics.setColor(0.10, 0.56, 0.17)
        love.graphics.setLineWidth(2)
        local r = math.min(iw, ih) * 0.27
        love.graphics.polygon("line",
            cx, cy - r, cx + r*0.72, cy, cx, cy + r, cx - r*0.72, cy)
        love.graphics.setLineWidth(1)
        love.graphics.line(cx, cy - r*0.55, cx, cy + r*0.55)
        love.graphics.line(cx - r*0.38, cy, cx + r*0.38, cy)
    end
end

local WIND_DIR = {
    East  = { 1,  0},
    West  = {-1,  0},
    North = { 0, -1},
    South = { 0,  1},
}

local function draw_wind_suit(ix, iy, iw, ih, label)
    local d  = WIND_DIR[label] or {0, 0}
    local cx, cy = ix + iw * 0.5, iy + ih * 0.43
    local ar = math.min(iw, ih) * 0.22
    love.graphics.setColor(0.50, 0.54, 0.80)
    love.graphics.setLineWidth(2)
    love.graphics.line(cx - d[1]*ar, cy - d[2]*ar,
                       cx + d[1]*ar, cy + d[2]*ar)
    -- arrowhead
    local hx, hy = cx + d[1]*ar, cy + d[2]*ar
    local px, py = -d[2], d[1]
    local hs = ar * 0.48
    love.graphics.polygon("fill",
        hx,                               hy,
        hx - d[1]*hs + px*hs*0.55,  hy - d[2]*hs + py*hs*0.55,
        hx - d[1]*hs - px*hs*0.55,  hy - d[2]*hs - py*hs*0.55)
    love.graphics.setLineWidth(1)
end

local function draw_flower_suit(ix, iy, iw, ih, label)
    local cx, cy = ix + iw * 0.5, iy + ih * 0.41
    local isSeason = (label == "Spring" or label == "Summer"
                   or label == "Autumn" or label == "Winter")
    local r1 = math.min(iw, ih) * 0.145   -- petal offset
    local r2 = math.min(iw, ih) * 0.092   -- petal radius
    -- colour: plum/magenta for flowers, purple for seasons
    if isSeason then
        love.graphics.setColor(0.46, 0.28, 0.68)
    else
        love.graphics.setColor(0.70, 0.24, 0.50)
    end
    for i = 0, 5 do
        local a = (i / 6) * math.pi * 2
        love.graphics.circle("fill",
            cx + math.cos(a) * r1,
            cy + math.sin(a) * r1, r2)
    end
    -- bright centre
    if isSeason then
        love.graphics.setColor(0.80, 0.65, 0.18)
    else
        love.graphics.setColor(0.94, 0.76, 0.28)
    end
    love.graphics.circle("fill", cx, cy, r2 * 0.60)
end

-- Returns the short label to stamp on a tile's top-left corner.
local function getTileLabel(tile)
    local s = tile.suit
    if s == SUIT.CIRCLE or s == SUIT.BAMBOO or s == SUIT.CHARACTER then
        return tostring(tile.value or 1)
    end
    local l = tile.label or ""
    if s == SUIT.WIND then
        return l:sub(1, 1)          -- E / S / W / N
    elseif s == SUIT.DRAGON then
        return l:sub(1, 1)          -- W / G / R
    elseif s == SUIT.FLOWER then
        if     l == "Spring" then return "Sp"
        elseif l == "Summer" then return "Su"
        elseif l == "Autumn" then return "Au"
        elseif l == "Winter" then return "Wi"
        else   return l:sub(1, 1) end
    end
    return nil
end

local function draw_symbol(tile, ix, iy, iw, ih)
    local s = tile.suit
    local v = tile.value or 1
    if     s == SUIT.CIRCLE    then draw_circle_suit   (ix, iy, iw, ih, v)
    elseif s == SUIT.BAMBOO    then draw_bamboo_suit    (ix, iy, iw, ih, v)
    elseif s == SUIT.CHARACTER then draw_character_suit (ix, iy, iw, ih, v)
    elseif s == SUIT.DRAGON    then draw_dragon_suit    (ix, iy, iw, ih, tile.label)
    elseif s == SUIT.WIND      then draw_wind_suit      (ix, iy, iw, ih, tile.label)
    elseif s == SUIT.FLOWER    then draw_flower_suit    (ix, iy, iw, ih, tile.label)
    end
end

-- ── Tile base ────────────────────────────────────────────────────────────────

local function tile_base(x, y, w, h, selected, hovered, mustDiscard, faceDown, flashAmt, spriteImg)
    flashAmt = flashAmt or 0
    local fw = w - BEVEL   -- face width
    local fh = h - BEVEL   -- face height

    -- Two-layer drop shadow for soft look
    love.graphics.setColor(0, 0, 0, 0.36)
    love.graphics.rectangle("fill", x+4, y+6, fw, fh, 5, 5)
    love.graphics.setColor(0, 0, 0, 0.16)
    love.graphics.rectangle("fill", x+7, y+10, fw, fh, 5, 5)

    -- Right bevel face (shadow side — trapezoid)
    love.graphics.setColor(0.34, 0.26, 0.15)
    love.graphics.polygon("fill",
        x+fw,       y+2,
        x+fw+BEVEL, y+BEVEL,
        x+fw+BEVEL, y+fh+BEVEL-1,
        x+fw,       y+fh)

    -- Bottom bevel face (deepest shadow — trapezoid)
    love.graphics.setColor(0.24, 0.18, 0.10)
    love.graphics.polygon("fill",
        x+2,        y+fh,
        x+BEVEL,    y+fh+BEVEL,
        x+fw+BEVEL, y+fh+BEVEL,
        x+fw,       y+fh)

    if faceDown then
        -- Deep jade back
        love.graphics.setColor(0.058, 0.175, 0.090)
        love.graphics.rectangle("fill", x, y, fw, fh, 5, 5)

        -- Single centred diamond
        local cx2 = x + fw / 2
        local cy2 = y + fh / 2
        local ds  = math.min(fw, fh) * 0.26
        love.graphics.setColor(0.100, 0.265, 0.136, 0.65)
        love.graphics.polygon("fill",
            cx2, cy2-ds, cx2+ds*0.66, cy2, cx2, cy2+ds, cx2-ds*0.66, cy2)
        -- Diamond outline (slightly lighter)
        love.graphics.setColor(0.128, 0.325, 0.168, 0.55)
        love.graphics.setLineWidth(1)
        love.graphics.polygon("line",
            cx2, cy2-ds, cx2+ds*0.66, cy2, cx2, cy2+ds, cx2-ds*0.66, cy2)

        -- Outer border
        love.graphics.setColor(0.032, 0.098, 0.050, 0.92)
        love.graphics.rectangle("line", x, y, fw, fh, 5, 5)
        love.graphics.setLineWidth(1)
        return nil
    end

    -- Ivory base (always drawn — sprite transparency shows this, not the dark room)
    love.graphics.setColor(0.944, 0.914, 0.788)
    love.graphics.rectangle("fill", x, y, fw, fh, 5, 5)

    -- Sprite on top (if available); otherwise the ivory face is the tile
    if spriteImg then
        local iw2, ih2 = spriteImg:getDimensions()
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(spriteImg, x, y, 0, fw / iw2, fh / ih2)
    end

    -- Flash glow (newly drawn / played)
    if flashAmt > 0 then
        love.graphics.setColor(1, 0.86, 0.26, flashAmt * 0.50)
        love.graphics.rectangle("fill", x, y, fw, fh, 5, 5)
    end

    -- Selected: outer gold halo
    if selected then
        love.graphics.setColor(1, 0.82, 0.10, 0.14)
        love.graphics.rectangle("fill", x-3, y-3, fw+6, fh+6, 8, 8)
    end

    -- Single clean catchlight line along top edge only
    love.graphics.setColor(1, 0.96, 0.88, 0.50)
    love.graphics.setLineWidth(1)
    love.graphics.line(x+5, y+1.5, x+fw-5, y+1.5)
    love.graphics.setLineWidth(1)

    -- Outer border
    if selected then
        love.graphics.setColor(1.0, 0.82, 0.10)
        love.graphics.setLineWidth(2.5)
    elseif mustDiscard and hovered then
        love.graphics.setColor(0.95, 0.10, 0.06)
        love.graphics.setLineWidth(2.5)
    elseif hovered then
        love.graphics.setColor(0.90, 0.84, 0.68)
        love.graphics.setLineWidth(2)
    else
        love.graphics.setColor(0.38, 0.30, 0.18, 0.58)
        love.graphics.setLineWidth(1)
    end
    love.graphics.rectangle("line", x, y, fw, fh, 5, 5)
    love.graphics.setLineWidth(1)

    local pad = 5
    return x+pad, y+pad, fw-pad*2, fh-pad*2
end

-- ── Public API ────────────────────────────────────────────────────────────────

-- Draw a mahjong tile at (x, y) with dimensions (w, h).
--   selected    — lifted 20 px, gold border
--   hovered     — lifted 8 px, light border
--   mustDiscard — red border on hover
--   faceDown    — shows green back instead of face
--   flashAmt    — 0..1, golden glow intensity (newly drawn / played)
function drawMahjongTile(tile, x, y, w, h, selected, hovered, mustDiscard, faceDown, flashAmt)
    local lift = selected and 20 or (hovered and 8 or 0)
    local dy   = y - lift
    local key  = not faceDown and getTileKey(tile)
    local img  = key and TILE_IMGS[key]
    local ix, iy, iw, ih = tile_base(x, dy, w, h, selected, hovered, mustDiscard, faceDown, flashAmt, img)
    if ix then
        if not img then
            draw_symbol(tile, ix, iy, iw, ih)
        end
        -- Corner label: circle pips can overlap the corner so use white-on-dark there;
        -- all other suits have a clear ivory corner so black-on-white reads better.
        local lbl = getTileLabel(tile)
        if lbl then
            love.graphics.setFont(FONT_TITLE)
            local onDark = (tile.suit == SUIT.CIRCLE)
            local sr, sg, sb = onDark and 0.06 or 1, onDark and 0.04 or 1, onDark and 0.03 or 1
            local fr, fg, fb = onDark and 1   or 0, onDark and 1   or 0, onDark and 1   or 0
            love.graphics.setColor(sr, sg, sb, 0.88)
            love.graphics.print(lbl, ix + 1, iy - 1)
            love.graphics.print(lbl, ix + 3, iy - 1)
            love.graphics.print(lbl, ix + 1, iy + 1)
            love.graphics.print(lbl, ix + 3, iy + 1)
            love.graphics.setColor(fr, fg, fb, 1.0)
            love.graphics.print(lbl, ix + 2, iy)
        end
    end
end
