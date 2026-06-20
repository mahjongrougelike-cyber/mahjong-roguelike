-- Animation state: tile draw fly-in, play-set flash, and screen shake.
-- All state is module-local; accessed through the public API below.

local _drawAnim   = nil   -- active fly-in: { tile, x,y, cx,cy, destX,destY, t, dur, idx }
local _flashIdx   = nil   -- hand index of the just-arrived tile
local _flashT     = 0     -- 1 → 0 over 0.55 s
local _playFlash  = 0     -- 1 → 0 over ~0.28 s (set-played glow)

-- Screen shake: trauma decays, magnitude scales with trauma^2
local _shakeTrauma = 0
local _shakePhase  = 0    -- phase accumulator for oscillation
local _shakeX      = 0
local _shakeY      = 0
local SHAKE_MAX    = 14   -- max pixel offset at full trauma
local SHAKE_DECAY  = 2.8  -- trauma units per second

function initAnim()
    _drawAnim     = nil
    _flashIdx     = nil
    _flashT       = 0
    _playFlash    = 0
    _shakeTrauma  = 0
    _shakePhase   = 0
    _shakeX       = 0
    _shakeY       = 0
end

function updateAnim(dt)
    -- Tile fly-in
    if _drawAnim then
        _drawAnim.t = math.min(1, _drawAnim.t + dt / _drawAnim.dur)
        local p = 1 - (1 - _drawAnim.t) ^ 3   -- ease-out cubic
        _drawAnim.cx = _drawAnim.x + (_drawAnim.destX - _drawAnim.x) * p
        _drawAnim.cy = _drawAnim.y + (_drawAnim.destY - _drawAnim.y) * p
        if _drawAnim.t >= 1 then
            _flashIdx = _drawAnim.idx
            _flashT   = 1.0
            _drawAnim = nil
        end
    end

    -- Golden arrival flash
    if _flashIdx then
        _flashT = math.max(0, _flashT - dt * 1.9)
        if _flashT <= 0 then _flashIdx = nil end
    end

    -- Play-set flash
    _playFlash = math.max(0, _playFlash - dt * 3.6)

    -- Screen shake: decay trauma, compute offsets via layered sine waves
    if _shakeTrauma > 0 then
        _shakeTrauma = math.max(0, _shakeTrauma - dt * SHAKE_DECAY)
        _shakePhase  = _shakePhase + dt * 38
        local mag = _shakeTrauma * _shakeTrauma * SHAKE_MAX
        _shakeX = (math.sin(_shakePhase) * 0.55 + math.sin(_shakePhase * 2.1) * 0.45) * mag
        _shakeY = (math.cos(_shakePhase * 1.8) * 0.55 + math.cos(_shakePhase * 0.7) * 0.45) * mag
    else
        _shakeX = 0
        _shakeY = 0
    end
end

-- Queue a fly-in animation for a tile being drawn into the hand.
--   tile     — the tile object
--   handIdx  — its index in playerHand
--   destX/Y  — pixel destination (top-left corner of its slot)
--   wallCX/Y — wall center (animation origin)
function queueDrawAnim(tile, handIdx, destX, destY, wallCX, wallCY, tileW, tileH)
    _drawAnim = {
        tile  = tile,
        x     = wallCX - tileW / 2,
        y     = wallCY - tileH / 2,
        cx    = wallCX - tileW / 2,
        cy    = wallCY - tileH / 2,
        destX = destX,
        destY = destY,
        t     = 0,
        dur   = 0.36,
        idx   = handIdx,
    }
end

-- Trigger a brief flash over the played-set area.
function triggerPlayFlash()
    _playFlash = 1.0
end

-- Trigger screen shake. trauma: 0..1 (1 = max hit feel, ~0.35 for a block).
function triggerShake(trauma)
    _shakeTrauma = math.min(1, _shakeTrauma + trauma)
end

-- ── Accessors ─────────────────────────────────────────────────────────────────
function getDrawAnim()   return _drawAnim        end
function getFlashIdx()   return _flashIdx        end
function getFlashT()     return _flashT          end
function getPlayFlash()  return _playFlash       end
function getShakeOffset() return _shakeX, _shakeY end
