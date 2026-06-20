-- lib/svgrender.lua
-- LuaJIT FFI wrapper around svgrender.dll (nanosvg + nanosvgrast).
-- Use M.load(absPath, scale) -> Love2D Image | nil

-- ffi is unavailable in web/Emscripten builds; wrap both require and load defensively
local ffi
local ffiOk = pcall(function() ffi = require("ffi") end)

local srcDir  = love.filesystem.getSourceBaseDirectory()
local dllPath = srcDir .. "/svgrender.dll"

local svglib
local loaded = ffiOk and pcall(function()
    svglib = ffi.load(dllPath)
end)

if not loaded or not svglib then
    -- DLL unavailable — return a no-op module so callers get nil gracefully
    return { load = function() return nil end, available = false }
end

ffi.cdef[[
    typedef struct SvgrHandle SvgrHandle;
    SvgrHandle*    svgr_load       (const char* path, float dpi);
    unsigned char* svgr_rasterize  (SvgrHandle* h, float scale, int* out_w, int* out_h);
    void           svgr_free_pixels(unsigned char* ptr);
    void           svgr_close      (SvgrHandle* h);
]]

local M = { available = true }

-- Returns a Love2D Image rasterised from an SVG file, or nil on failure.
-- absPath : OS absolute path to the .svg file
-- scale   : rasterisation scale (1.0 = native SVG pixel size)
function M.load(absPath, scale)
    scale = scale or 1.0
    local h = svglib.svgr_load(absPath, 96.0)
    if h == nil then return nil end

    local ow = ffi.new("int[1]")
    local oh = ffi.new("int[1]")
    local px = svglib.svgr_rasterize(h, scale, ow, oh)
    svglib.svgr_close(h)
    if px == nil or ow[0] <= 0 or oh[0] <= 0 then return nil end

    local w, ht = ow[0], oh[0]
    local imgData = love.image.newImageData(w, ht, "rgba8",
                        ffi.string(px, w * ht * 4))
    svglib.svgr_free_pixels(px)

    local img = love.graphics.newImage(imgData)
    img:setFilter("linear", "linear")
    return img
end

return M
