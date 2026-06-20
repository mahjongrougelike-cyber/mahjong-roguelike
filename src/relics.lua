-- Relic registry: always-active passive effects, auto-given (not chosen from a pool).
-- Relics are separate from items — they accumulate their own RELIC_FLAGS.
-- Add entries to M.RELICS and extend the default flags table in computeFlags as needed.

local M = {}

M.RELICS = {
    ancient_compendium = {
        id     = "ancient_compendium",
        name   = "Ancient Compendium",
        desc   = "Max hand size increased to 15. Gain 2 free draws at the start of each turn.",
        rarity = "starting",
        flags  = { handCapBonus = 2, extraFreeDraw = 2 },
    },
}

-- Merge all owned relic flags into a flat table.
-- Add new flag keys here as you create relics that use them.
function M.computeFlags(ownedIds)
    local f = {
        handCapBonus  = 0,
        extraFreeDraw = 0,
    }
    for _, id in ipairs(ownedIds) do
        local r = M.RELICS[id]
        if r then
            for k, v in pairs(r.flags or {}) do
                if     type(v) == "boolean" then f[k] = f[k] or v
                elseif type(v) == "number"  then f[k] = (f[k] or 0) + v end
            end
        end
    end
    return f
end

return M
