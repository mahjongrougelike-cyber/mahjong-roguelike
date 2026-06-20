--
-- anim8
--
-- Copyright (c) 2011-2013 Enrique García Cota
-- MIT license: see LICENSE for details.
-- v2.3.1
--

local anim8 = {}
anim8.__index = anim8

-- ── Grid ──────────────────────────────────────────────────────────────────────

local Grid = {}
Grid.__index = Grid

local function parseSpec(spec, maxVal)
    if type(spec) == "number" then return {spec} end
    local a, b = spec:match("^(%d+)-(%d+)$")
    if not a then error("invalid frame range: " .. tostring(spec)) end
    a, b = tonumber(a), tonumber(b)
    local result, step = {}, a <= b and 1 or -1
    for i = a, b, step do result[#result+1] = i end
    return result
end

function Grid:_quad(col, row)
    if not self._quads[col] then self._quads[col] = {} end
    if not self._quads[col][row] then
        self._quads[col][row] = love.graphics.newQuad(
            self.left + (col - 1) * (self.fw + self.border),
            self.top  + (row - 1) * (self.fh + self.border),
            self.fw, self.fh,
            self.iw, self.ih
        )
    end
    return self._quads[col][row]
end

function Grid:frames(...)
    local args   = {...}
    local result = {}
    for i = 1, #args, 2 do
        local cols = parseSpec(args[i])
        local rows = parseSpec(args[i + 1])
        for _, row in ipairs(rows) do
            for _, col in ipairs(cols) do
                result[#result + 1] = self:_quad(col, row)
            end
        end
    end
    return result
end

Grid.__call = function(self, ...) return self:frames(...) end

function anim8.newGrid(fw, fh, iw, ih, left, top, border)
    return setmetatable({
        fw = fw, fh = fh, iw = iw, ih = ih,
        left = left or 0, top = top or 0, border = border or 0,
        _quads = {},
    }, Grid)
end

-- ── Animation ─────────────────────────────────────────────────────────────────

local Animation = {}
Animation.__index = Animation

function anim8.newAnimation(frames, durations, onLoop)
    local self = setmetatable({
        frames    = frames,
        timer     = 0,
        position  = 1,
        status    = "playing",
        flippedH  = false,
        flippedV  = false,
        onLoop    = onLoop or "loop",
        _durations = {},
        _totalDuration = 0,
    }, Animation)

    if type(durations) == "number" then
        for i = 1, #frames do self._durations[i] = durations end
    else
        for i, d in ipairs(durations) do self._durations[i] = d end
    end

    for _, d in ipairs(self._durations) do
        self._totalDuration = self._totalDuration + d
    end
    return self
end

function Animation:update(dt)
    if self.status ~= "playing" then return end
    self.timer = self.timer + dt
    while self.timer >= self._durations[self.position] do
        self.timer = self.timer - self._durations[self.position]
        self.position = self.position + 1
        if self.position > #self.frames then
            local ol = self.onLoop
            if ol == "loop" then
                self.position = 1
            elseif ol == "pauseAtEnd" then
                self.position = #self.frames
                self.timer    = 0
                self:pause()
                return
            elseif ol == "pauseAtStart" then
                self.position = 1
                self.timer    = 0
                self:pause()
                return
            elseif type(ol) == "function" then
                self.position = 1
                ol(self)
            else
                self.position = 1
            end
        end
    end
end

function Animation:draw(image, x, y, r, sx, sy, ox, oy)
    local frame = self.frames[self.position]
    if not frame then return end
    local _, _, fw, fh = frame:getViewport()
    sx, sy = sx or 1, sy or 1
    ox, oy = ox or 0, oy or 0
    if self.flippedH then sx = -sx; ox = ox + fw end
    if self.flippedV then sy = -sy; oy = oy + fh end
    love.graphics.draw(image, frame, x, y, r or 0, sx, sy, ox, oy)
end

function Animation:gotoFrame(n)
    self.position = ((n - 1) % #self.frames) + 1
    self.timer    = 0
end

function Animation:pause()  self.status = "paused"   end
function Animation:resume() self.status = "playing"  end

function Animation:pauseAtStart()
    self:gotoFrame(1)
    self:pause()
end

function Animation:pauseAtEnd()
    self:gotoFrame(#self.frames)
    self:pause()
end

function Animation:flipH()
    self.flippedH = not self.flippedH
    return self
end

function Animation:flipV()
    self.flippedV = not self.flippedV
    return self
end

function Animation:clone()
    local c = setmetatable({}, Animation)
    for k, v in pairs(self) do c[k] = v end
    c._durations = {}
    for i, v in ipairs(self._durations) do c._durations[i] = v end
    return c
end

function Animation:getFramesCount()   return #self.frames end
function Animation:getDuration()      return self._totalDuration end
function Animation:getCurrentFrame()
    return self.position, self.timer, self._durations[self.position]
end

anim8.Grid      = Grid
anim8.Animation = Animation

return anim8
