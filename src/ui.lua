-- Room renderer — clean, flat casino aesthetic. No glows, no vignettes.

function initAtmosphere() end   -- nothing to precompute
function updateAtmosphere(dt)   end

-- ── Room ──────────────────────────────────────────────────────────────────────

function drawRoom()
    -- ── Flat dark background ─────────────────────────────────────────────────
    love.graphics.setColor(0.08, 0.09, 0.11)   -- clean dark charcoal-navy
    love.graphics.rectangle("fill", 0, 0, 1280, 720)

    -- ── Mahogany table border ─────────────────────────────────────────────────
    love.graphics.setColor(0.30, 0.18, 0.09)
    love.graphics.rectangle("fill", 50, 40, 1180, 662, 12, 12)

    -- Subtle grain bands (3 horizontal sweeps)
    for i, alpha in ipairs({0.10, 0.07, 0.05}) do
        love.graphics.setColor(0.40, 0.24, 0.11, alpha)
        love.graphics.rectangle("fill", 52, 40 + i * 185, 1176, 58, 4, 4)
    end

    -- Clean top edge highlight
    love.graphics.setColor(0.48, 0.30, 0.14, 0.55)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", 50, 40, 1180, 662, 12, 12)
    love.graphics.setLineWidth(1)

    -- ── Casino felt ───────────────────────────────────────────────────────────
    local FX, FY, FW, FH = 86, 76, 1108, 588
    love.graphics.setColor(0.14, 0.38, 0.18)   -- clean vivid casino green
    love.graphics.rectangle("fill", FX, FY, FW, FH, 8, 8)

    -- Woven diagonal grain (very subtle — just texture, not mood)
    love.graphics.setColor(0.17, 0.44, 0.21, 0.07)
    love.graphics.setLineWidth(0.8)
    for d = -FH, FW, 18 do
        local x1 = FX + math.max(0, d)
        local y1 = FY + math.max(0, -d)
        local x2 = FX + math.min(FW, d + FH)
        local y2 = FY + math.min(FH, FH - d)
        if x1 <= FX+FW and y1 <= FY+FH then
            love.graphics.line(x1, y1, x2, y2)
        end
    end
    love.graphics.setLineWidth(1)

    -- Wall guide (subtle inset)
    love.graphics.setColor(0.20, 0.50, 0.24, 0.22)
    love.graphics.rectangle("line", 442, 217, 276, 276, 5, 5)

    -- Corner diamond emblems
    love.graphics.setColor(0.22, 0.54, 0.26, 0.40)
    for _, co in ipairs({
        {FX+26, FY+26}, {FX+FW-26, FY+26},
        {FX+26, FY+FH-26}, {FX+FW-26, FY+FH-26},
    }) do
        local s = 9
        love.graphics.polygon("line",
            co[1], co[2]-s, co[1]+s, co[2], co[1], co[2]+s, co[1]-s, co[2])
    end

    -- Felt border (clean single line)
    love.graphics.setColor(0.22, 0.56, 0.26, 0.70)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", FX, FY, FW, FH, 8, 8)
    love.graphics.setLineWidth(1)
end

-- ── Lighting ──────────────────────────────────────────────────────────────────

function drawLighting()
    -- Intentionally empty — no glows, no vignettes
end

-- ── UI Panel ─────────────────────────────────────────────────────────────────

function drawUIPanel(x, y, w, h, r)
    r = r or 6
    love.graphics.setColor(0.06, 0.07, 0.09, 0.88)
    love.graphics.rectangle("fill", x, y, w, h, r, r)
    love.graphics.setColor(1, 1, 1, 0.05)
    love.graphics.rectangle("fill", x+1, y+1, w-2, math.min(h*0.35, 20), r, r)
    love.graphics.setColor(0.30, 0.50, 0.34, 0.55)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", x, y, w, h, r, r)
    love.graphics.setLineWidth(1)
end
