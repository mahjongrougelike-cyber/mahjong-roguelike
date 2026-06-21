-- Map pathing system — Slay-the-Spire style horizontal scroll.
-- Each act has 10 content floors + 1 boss floor (11 total).
-- First 2 combat encounters per act use the easy pool; the rest use the hard pool.

local NR            = 20
local FLOOR_SPACING = 230
local WORLD_X0      = 60
local ROW_Y         = {190, 380, 570}

-- ── Visual config ─────────────────────────────────────────────────────────────

local NT = {
    start    = {label="Start",    r=0.26, g=0.26, b=0.26},
    combat   = {label="Combat",   r=0.68, g=0.12, b=0.12},
    elite    = {label="Elite",    r=0.50, g=0.10, b=0.58},
    rest     = {label="Rest",     r=0.10, g=0.46, b=0.16},
    shop     = {label="Shop",     r=0.54, g=0.44, b=0.08},
    boss     = {label="Boss",     r=0.82, g=0.14, b=0.08},
    jiangshi = {label="Jiangshi", r=0.72, g=0.08, b=0.28},
    tianshi  = {label="Tiānshǐ",  r=0.90, g=0.84, b=0.38},
}

-- ── Enemy pools ───────────────────────────────────────────────────────────────
-- Each act has easy (first 2 combats), hard (remaining combats), elite, and boss.

-- Enemy pools — add new enemies here as they are designed.
-- Unfinished slots use Wind Spirit as a stand-in.
local ACT_ENEMIES = {
    [1] = {
        easy = {
            { create = createWindSpirit },
            { create = createGaunxi },
            { create = createYinShen },
            { create = createWindSpirit },
            { create = createGaunxi },
            { create = createYinShen },
        },
        hard  = { { create = createTieNiu }, { create = createCan }, { create = createWindSpirit } },
        elite = { { create = createXi } },
        boss  =   { create = createWindSpirit },
    },
    [2] = {
        easy  = { { create = createWindSpirit } },
        hard  = { { create = createWindSpirit } },
        elite = { { create = createWindSpirit } },
        boss  =   { create = createWindSpirit },
    },
    [3] = {
        easy  = { { create = createWindSpirit } },
        hard  = { { create = createWindSpirit } },
        elite = { { create = createWindSpirit } },
        boss  =   { create = createWindSpirit },
    },
}

local MAX_ACTS    = 3
local MAX_CONTENT = 10  -- content floors per act; boss is floor 11

-- ── Map state ─────────────────────────────────────────────────────────────────

local mapGrid     = {}
local playerFloor = 0
local playerCol   = 1
local currentAct  = 1

-- ── Generation ────────────────────────────────────────────────────────────────

local function pickOne(pool) return pool[math.random(#pool)] end

local function pickOneAvoid(pool, last)
    if #pool <= 1 or last == nil then return pickOne(pool) end
    local filtered = {}
    for _, v in ipairs(pool) do
        if v ~= last then table.insert(filtered, v) end
    end
    return #filtered > 0 and filtered[math.random(#filtered)] or pickOne(pool)
end
local function worldX(floor) return WORLD_X0 + floor * FLOOR_SPACING end

local function shuffle(t)
    for i = #t, 2, -1 do
        local j = math.random(i)
        t[i], t[j] = t[j], t[i]
    end
end

local TEMPLATES = {
    [1]  = {"combat","combat","rest"},
    [2]  = {"combat","combat","shop"},
    [3]  = {"combat","elite","combat"},
    [4]  = {"combat","jiangshi","shop"},
    [5]  = {"elite","combat","combat"},
    [6]  = {"combat","shop","rest"},
    [7]  = {"combat","elite","combat"},
    [8]  = {"elite","combat","shop"},
    [9]  = {"combat","jiangshi","combat"},
    [10] = {"elite","combat","combat"},
}

local _cam          = {x = 220}
local companionGrid = {}   -- floor.."," ..col → hidden Tiānshǐ companion for each Jiangshi node

local function camTargetX()
    return math.min(220, 300 - worldX(playerFloor))
end

local function panMapCam()
    flux.to(_cam, 0.45, {x = camTargetX()}):ease("cubicout")
end

function generateMap()
    mapGrid       = {}
    companionGrid = {}
    playerFloor   = 0
    playerCol   = 1
    _cam.x      = camTargetX()

    local bossFloor = MAX_CONTENT + 1

    mapGrid[0] = {{
        type="start", x=worldX(0), y=380,
        connections={1,2,3}, visited=true, available=false, floor=0, col=1,
    }}
    mapGrid[bossFloor] = {{
        type="boss", x=worldX(bossFloor), y=380,
        connections={}, visited=false, available=false, floor=bossFloor, col=1,
    }}

    local act = ACT_ENEMIES[math.min(currentAct, MAX_ACTS)]
    local lastEasy, lastHard, lastElite = nil, nil, nil
    for f = 1, MAX_CONTENT do
        mapGrid[f] = {}
        local pool = {unpack(TEMPLATES[f] or {"combat","combat","rest"})}
        shuffle(pool)
        for c = 1, 3 do
            local jit = (math.random() - 0.5) * 80
            local nodeType = pool[c]
            local node = {
                type        = nodeType,
                x           = worldX(f),
                y           = ROW_Y[c] + jit,
                connections = {},
                visited     = false,
                available   = (f == 1),
                floor       = f,
                col         = c,
            }
            if nodeType == "combat" then
                if f <= 2 then
                    node.enemyDef = pickOneAvoid(act.easy, lastEasy)
                    lastEasy = node.enemyDef
                else
                    node.enemyDef = pickOneAvoid(act.hard, lastHard)
                    lastHard = node.enemyDef
                end
            elseif nodeType == "elite" then
                node.enemyDef = pickOneAvoid(act.elite, lastElite)
                lastElite = node.enemyDef
            end
            mapGrid[f][c] = node
            -- Companion Tiānshǐ node: hidden above each Jiangshi node; revealed on refuse
            if nodeType == "jiangshi" then
                companionGrid[f .. "," .. c] = {
                    type="tianshi", x=node.x, y=node.y - 56,
                    visited=false, available=false, floor=f, col=c,
                }
            end
        end
    end
    mapGrid[MAX_CONTENT + 1][1].enemyDef = act.boss

    for f = 1, MAX_CONTENT do
        local cur  = mapGrid[f]
        local next = mapGrid[f + 1]
        if not cur or not next then break end

        local maxNext = (f == MAX_CONTENT) and 1 or #next
        local reached = {}

        for c = 1, #cur do
            local node    = cur[c]
            local primary = math.max(1, math.min(maxNext, c + math.random(-1, 1)))
            table.insert(node.connections, primary)
            reached[primary] = true

            if math.random() < 0.35 then
                local delta = math.random() < 0.5 and -1 or 1
                local sec   = math.max(1, math.min(maxNext, primary + delta))
                if sec ~= primary then
                    table.insert(node.connections, sec)
                    reached[sec] = true
                end
            end
        end

        for nc = 1, maxNext do
            if not reached[nc] then
                local best = math.max(1, math.min(#cur, nc))
                table.insert(cur[best].connections, nc)
            end
        end
    end
end

function startNextAct()
    currentAct = currentAct + 1
    generateMap()
end

-- ── Public accessors ──────────────────────────────────────────────────────────

function getReachableNodes()
    local list = {}
    if playerFloor == 0 then
        for c = 1, #(mapGrid[1] or {}) do
            table.insert(list, {floor=1, col=c})
        end
        return list
    end
    local cur = mapGrid[playerFloor] and mapGrid[playerFloor][playerCol]
    if not cur then return list end
    local nf = playerFloor + 1
    if mapGrid[nf] then
        for _, nc in ipairs(cur.connections) do
            if mapGrid[nf][nc] then
                table.insert(list, {floor=nf, col=nc})
            end
        end
    end
    return list
end

function visitMapNode(floor, col)
    local node = mapGrid[floor] and mapGrid[floor][col]
    if not node then return nil end
    node.visited = true
    playerFloor  = floor
    playerCol    = col
    local nf = floor + 1
    if mapGrid[nf] then
        for _, nc in ipairs(node.connections) do
            if mapGrid[nf][nc] then mapGrid[nf][nc].available = true end
        end
    end
    panMapCam()
    return node
end

-- Enemy def is pre-assigned at map generation time for seed consistency.
function getNodeEnemyDef(node)
    return node.enemyDef
end

function isMapComplete()  return playerFloor == MAX_CONTENT + 1 end
function isRunComplete()  return currentAct > MAX_ACTS end
function getCurrentAct()  return currentAct end

-- Reveal the Tiānshǐ companion that sits above the Jiangshi node at (floor, col).
function revealTianshiCompanion(floor, col)
    local node = companionGrid[floor .. "," .. col]
    if node then node.available = true end
end

-- Returns {floor, col} if the player clicked an available Tiānshǐ companion node.
function getClickedTianshiNode(mx, my)
    local offX = _cam.x
    for _, node in pairs(companionGrid) do
        if node.available and not node.visited then
            local sx = node.x + offX
            local dx, dy = mx - sx, my - node.y
            if dx * dx + dy * dy < NR * NR then
                return { floor = node.floor, col = node.col }
            end
        end
    end
    return nil
end

-- Mark the companion visited (next-floor unlocking was already done by the Jiangshi visitMapNode).
function visitTianshiNode(floor, col)
    local node = companionGrid[floor .. "," .. col]
    if node then node.visited = true end
end

-- ── Icons ─────────────────────────────────────────────────────────────────────

local function drawIcon(ntype, x, y, alpha)
    alpha = alpha or 1
    if ntype == "combat" then
        love.graphics.setColor(1, 0.78, 0.78, alpha * 0.88)
        love.graphics.setLineWidth(2)
        love.graphics.line(x-7, y-7, x+7, y+7)
        love.graphics.line(x+7, y-7, x-7, y+7)
        love.graphics.setLineWidth(1.5)
        love.graphics.line(x-3, y-1, x-1, y-3)
        love.graphics.line(x+1, y+3, x+3, y+1)
        love.graphics.setLineWidth(1)

    elseif ntype == "elite" then
        love.graphics.setColor(0.90, 0.72, 1, alpha * 0.88)
        love.graphics.setLineWidth(1.5)
        local outerR, innerR = 9, 4
        local pts = {}
        for i = 0, 11 do
            local a = (i / 12) * math.pi * 2 - math.pi/2
            local r = (i % 2 == 0) and outerR or innerR
            table.insert(pts, x + math.cos(a)*r)
            table.insert(pts, y + math.sin(a)*r)
        end
        love.graphics.setColor(0.90, 0.72, 1, alpha * 0.26)
        love.graphics.polygon("fill", unpack(pts))
        love.graphics.setColor(0.90, 0.72, 1, alpha * 0.80)
        love.graphics.polygon("line", unpack(pts))
        love.graphics.setLineWidth(1)

    elseif ntype == "rest" then
        love.graphics.setColor(0.60, 0.38, 0.14, alpha * 0.85)
        love.graphics.setLineWidth(1.5)
        love.graphics.line(x-7, y+5, x,   y-1)
        love.graphics.line(x+7, y+5, x,   y-1)
        love.graphics.line(x-7, y+5, x+7, y+5)
        love.graphics.setLineWidth(1)
        love.graphics.setColor(0.96, 0.52, 0.10, alpha * 0.85)
        love.graphics.circle("fill", x, y-2, 5)
        love.graphics.setColor(1, 0.86, 0.28, alpha * 0.90)
        love.graphics.circle("fill", x, y-3, 3)

    elseif ntype == "shop" then
        love.graphics.setColor(0.80, 0.60, 0.08, alpha * 0.85)
        love.graphics.circle("fill", x, y, 8)
        love.graphics.setColor(0.96, 0.80, 0.22, alpha * 0.90)
        love.graphics.circle("fill", x, y, 6)
        love.graphics.setColor(0.76, 0.56, 0.06, alpha * 0.80)
        love.graphics.circle("fill", x, y, 3.5)
        love.graphics.setColor(0.98, 0.92, 0.60, alpha * 0.90)
        love.graphics.circle("fill", x, y, 1.5)

    elseif ntype == "boss" then
        love.graphics.setColor(0.88, 0.80, 0.80, alpha * 0.90)
        love.graphics.circle("fill", x, y-2, 8)
        love.graphics.rectangle("fill", x-5, y+4, 10, 5, 2, 2)
        love.graphics.setColor(0.12, 0.06, 0.06, alpha)
        love.graphics.circle("fill", x-3, y-2, 2.5)
        love.graphics.circle("fill", x+3, y-2, 2.5)
        love.graphics.circle("fill", x,   y+2, 1.2)
        love.graphics.rectangle("fill", x-4, y+5, 2, 3)
        love.graphics.rectangle("fill", x-1, y+5, 2, 3)
        love.graphics.rectangle("fill", x+2, y+5, 2, 3)

    elseif ntype == "start" then
        love.graphics.setColor(0.62, 0.92, 0.62, alpha * 0.80)
        love.graphics.circle("fill", x, y, 5)
        love.graphics.setColor(0.28, 0.72, 0.36, alpha)
        love.graphics.setLineWidth(1.5)
        love.graphics.circle("line", x, y, 5)
        love.graphics.setLineWidth(1)

    elseif ntype == "jiangshi" then
        -- Coffin cross
        love.graphics.setColor(0.82, 0.10, 0.30, alpha * 0.90)
        love.graphics.setLineWidth(2.5)
        love.graphics.line(x, y-9, x, y+8)
        love.graphics.line(x-6, y-3, x+6, y-3)
        love.graphics.setLineWidth(1)
        -- blood drops
        love.graphics.setColor(0.92, 0.18, 0.24, alpha * 0.72)
        love.graphics.circle("fill", x-2.5, y+10, 1.8)
        love.graphics.circle("fill", x+2.5, y+10, 1.8)

    elseif ntype == "tianshi" then
        -- Halo
        love.graphics.setColor(1.0, 0.90, 0.40, alpha * 0.80)
        love.graphics.setLineWidth(2)
        love.graphics.circle("line", x, y-6, 5)
        love.graphics.setLineWidth(1)
        -- Wings (left arc + right arc)
        love.graphics.setColor(0.96, 0.88, 0.56, alpha * 0.78)
        love.graphics.setLineWidth(1.5)
        love.graphics.arc("line", "open", x-4, y+2, 6, math.pi * 0.75, math.pi * 1.55)
        love.graphics.arc("line", "open", x+4, y+2, 6, math.pi * 1.45, math.pi * 2.25)
        love.graphics.setLineWidth(1)
        -- Body dot
        love.graphics.setColor(1.0, 0.94, 0.62, alpha * 0.90)
        love.graphics.circle("fill", x, y+1, 3)
    end
end

-- ── Dashed line helper ────────────────────────────────────────────────────────

local function dashedLine(x1, y1, x2, y2, dash, gap)
    local dx, dy = x2-x1, y2-y1
    local len    = math.sqrt(dx*dx + dy*dy)
    if len < 1 then return end
    local ux, uy = dx/len, dy/len
    local t, on  = 0, true
    while t < len do
        if on then
            local t2 = math.min(t + dash, len)
            love.graphics.line(x1+ux*t, y1+uy*t, x1+ux*t2, y1+uy*t2)
            t = t2
        else
            t = t + gap
        end
        on = not on
    end
end

-- ── Rendering ─────────────────────────────────────────────────────────────────

function drawMap(mx, my)
    love.graphics.setColor(0.06, 0.04, 0.01, 0.48)
    love.graphics.rectangle("fill", 0, 0, 1280, 720)

    love.graphics.setFont(FONT_TITLE)
    love.graphics.setColor(0.92, 0.76, 0.30)
    love.graphics.printf("Act " .. currentAct .. "  —  Choose Your Path", 0, 18, 1280, "center")

    local offX    = _cam.x
    local worldMX = mx - offX

    local reachSet = {}
    for _, r in ipairs(getReachableNodes()) do
        reachSet[r.floor .. "," .. r.col] = true
    end

    love.graphics.push()
    love.graphics.translate(offX, 0)

    local bossFloor = MAX_CONTENT + 1

    -- Connection lines
    local EDGE_MARGIN = 30
    for f = 0, bossFloor do
        local floor = mapGrid[f]
        if floor then
            for _, node in ipairs(floor) do
                local nf   = f + 1
                local next = mapGrid[nf]
                if next then
                    for _, nc in ipairs(node.connections) do
                        local dest = next[nc]
                        if dest then
                            local sx, dx = node.x + offX, dest.x + offX
                            if sx >= EDGE_MARGIN and sx <= 1280 - EDGE_MARGIN
                            and dx >= EDGE_MARGIN and dx <= 1280 - EDGE_MARGIN then
                                love.graphics.setColor(0.44, 0.38, 0.22, 0.55)
                                love.graphics.setLineWidth(1.5)
                                dashedLine(node.x, node.y, dest.x, dest.y, 6, 4)
                                love.graphics.setLineWidth(1)
                            end
                        end
                    end
                end
            end
        end
    end

    -- Nodes
    for f = 0, bossFloor do
        local floor = mapGrid[f]
        if floor then
            for c, node in ipairs(floor) do
                local key       = f .. "," .. c
                    local reachable = reachSet[key]
                    local nt        = NT[node.type] or NT.combat

                    local hovered = false
                    if reachable then
                        local dx, dy = worldMX - node.x, my - node.y
                        hovered = (dx*dx + dy*dy) < NR*NR
                    end
                    local R = hovered and NR + 3 or NR

                    love.graphics.setColor(0, 0, 0, 0.44)
                    love.graphics.circle("fill", node.x+2, node.y+3, R)

                    local dim = node.visited and 0.38 or 1.0
                    if not reachable and not node.visited then
                        love.graphics.setColor(0.12, 0.10, 0.08)
                    else
                        local m = hovered and 1.0 or dim * (reachable and 1.0 or 0.72)
                        love.graphics.setColor(nt.r*m, nt.g*m, nt.b*m)
                    end
                    love.graphics.circle("fill", node.x, node.y, R)

                    if reachable then
                        love.graphics.setColor(0.92, 0.76, 0.24, hovered and 1.0 or 0.68)
                        love.graphics.setLineWidth(hovered and 2.5 or 1.5)
                    elseif node.visited then
                        love.graphics.setColor(0.34, 0.28, 0.12, 0.50)
                        love.graphics.setLineWidth(1)
                    else
                        love.graphics.setColor(0.22, 0.20, 0.16, 0.42)
                        love.graphics.setLineWidth(1)
                    end
                    love.graphics.circle("line", node.x, node.y, R)
                    love.graphics.setLineWidth(1)

                    if f == playerFloor and c == playerCol then
                        love.graphics.setColor(0.32, 0.82, 0.44, 0.56)
                        love.graphics.setLineWidth(2)
                        love.graphics.circle("line", node.x, node.y, R + 7)
                        love.graphics.setLineWidth(1)
                    end

                    drawIcon(node.type, node.x, node.y,
                             node.visited and 0.45 or (reachable and 1.0 or 0.52))

                    love.graphics.setFont(FONT_SMALL)
                    if node.visited then
                        love.graphics.setColor(0.32, 0.30, 0.24)
                    elseif reachable then
                        love.graphics.setColor(hovered and 1.0 or 0.84,
                                               hovered and 0.90 or 0.74,
                                               hovered and 0.48 or 0.32)
                    else
                        love.graphics.setColor(0.36, 0.34, 0.28)
                    end
                    love.graphics.printf(nt.label, node.x-36, node.y+R+4, 72, "center")
            end
        end
    end

    -- Tiānshǐ companion nodes
    for _, cnode in pairs(companionGrid) do
        if cnode.available or cnode.visited then
            local nt  = NT.tianshi
            local dx  = worldMX - cnode.x
            local dy  = my - cnode.y
            local hovC = (not cnode.visited) and (dx*dx + dy*dy < NR*NR)
            local R   = hovC and NR + 3 or NR

            -- Dashed link from jiangshi to companion
            local ji = mapGrid[cnode.floor] and mapGrid[cnode.floor][cnode.col]
            if ji then
                love.graphics.setColor(nt.r, nt.g, nt.b, 0.22)
                love.graphics.setLineWidth(1)
                dashedLine(ji.x, ji.y - NR, cnode.x, cnode.y + R, 3, 5)
            end

            love.graphics.setColor(0, 0, 0, 0.44)
            love.graphics.circle("fill", cnode.x + 2, cnode.y + 3, R)

            local dim = cnode.visited and 0.38 or (hovC and 1.0 or 0.88)
            love.graphics.setColor(nt.r * dim, nt.g * dim, nt.b * dim)
            love.graphics.circle("fill", cnode.x, cnode.y, R)

            love.graphics.setColor(nt.r, nt.g, nt.b,
                hovC and 1.0 or (cnode.visited and 0.44 or 0.70))
            love.graphics.setLineWidth(hovC and 2.5 or 1.5)
            love.graphics.circle("line", cnode.x, cnode.y, R)
            love.graphics.setLineWidth(1)

            drawIcon("tianshi", cnode.x, cnode.y, cnode.visited and 0.40 or 1.0)

            love.graphics.setFont(FONT_SMALL)
            if cnode.visited then
                love.graphics.setColor(0.32, 0.30, 0.24)
            elseif hovC then
                love.graphics.setColor(1.0, 0.94, 0.56)
            else
                love.graphics.setColor(0.86, 0.76, 0.32)
            end
            love.graphics.printf(nt.label, cnode.x - 36, cnode.y + R + 4, 72, "center")
        end
    end

    love.graphics.pop()

    -- Tiānshǐ companion hover tooltip
    for _, cnode in pairs(companionGrid) do
        if cnode.available and not cnode.visited then
            local sx = cnode.x + offX
            local dx, dy = mx - sx, my - cnode.y
            if dx*dx + dy*dy < NR*NR then
                local tx = math.max(4, math.min(1280 - 134, sx - 65))
                local ty = cnode.y - NR - 30
                love.graphics.setColor(0.04, 0.03, 0.02, 0.88)
                love.graphics.rectangle("fill", tx, ty, 130, 22, 4, 4)
                love.graphics.setColor(NT.tianshi.r, NT.tianshi.g, NT.tianshi.b, 0.56)
                love.graphics.rectangle("line", tx, ty, 130, 22, 4, 4)
                love.graphics.setFont(FONT_SMALL)
                love.graphics.setColor(0.82, 0.80, 0.68)
                love.graphics.printf("Heaven's grace", tx, ty + 6, 130, "center")
                break
            end
        end
    end

    -- Hover tooltip
    local tips = {
        combat   = "Fight a random enemy",
        elite    = "Harder fight — greater reward",
        rest     = "Recover 25% max HP",
        shop     = "Spend gold on items",
        boss     = "Act " .. currentAct .. " boss",
        jiangshi = "Devil's bargain — items cost stats",
    }
    for _, r in ipairs(getReachableNodes()) do
        local node = mapGrid[r.floor] and mapGrid[r.floor][r.col]
        if node then
            local sx = node.x + offX
            local dx, dy = mx - sx, my - node.y
            if dx*dx + dy*dy < NR*NR then
                local tip = tips[node.type]
                if tip then
                    local tx = math.max(4, math.min(1280-124, sx-60))
                    local ty = node.y - NR - 30
                    love.graphics.setColor(0.04, 0.03, 0.02, 0.88)
                    love.graphics.rectangle("fill", tx, ty, 120, 22, 4, 4)
                    love.graphics.setColor(NT[node.type].r, NT[node.type].g, NT[node.type].b, 0.56)
                    love.graphics.rectangle("line", tx, ty, 120, 22, 4, 4)
                    love.graphics.setFont(FONT_SMALL)
                    love.graphics.setColor(0.82, 0.80, 0.68)
                    love.graphics.printf(tip, tx, ty+6, 120, "center")
                end
                break
            end
        end
    end

    -- Progress strip
    love.graphics.setFont(FONT_SMALL)
    love.graphics.setColor(0.36, 0.34, 0.26)
    love.graphics.printf(
        "Act " .. currentAct .. " / " .. MAX_ACTS
        .. "   ·   Floor " .. playerFloor .. " / " .. bossFloor
        .. "   ·   Click a highlighted node to travel",
        0, 696, 1280, "center")
end

function getClickedMapNode(mx, my)
    local offX = _cam.x
    for _, r in ipairs(getReachableNodes()) do
        local node = mapGrid[r.floor] and mapGrid[r.floor][r.col]
        if node then
            local sx = node.x + offX
            local dx, dy = mx - sx, my - node.y
            if dx*dx + dy*dy < NR*NR then return r end
        end
    end
    return nil
end
