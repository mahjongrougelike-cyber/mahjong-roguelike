-- Tile suit constants
SUIT = {
    CHARACTER = "character",  -- attack damage
    BAMBOO    = "bamboo",     -- block / defense
    CIRCLE    = "circle",     -- mana generation
    DRAGON    = "dragon",     -- Red=damage mult, Green=block mult, White=mana mult
    WIND      = "wind",       -- skip enemy turn + pick a stat
    FLOWER    = "flower",     -- block + mana
}

-- Color associated with each suit (for rendering)
SUIT_COLOR = {
    [SUIT.CHARACTER] = {0.85, 0.2,  0.2 },
    [SUIT.BAMBOO]    = {0.2,  0.7,  0.3 },
    [SUIT.CIRCLE]    = {0.2,  0.4,  0.85},
    [SUIT.DRAGON]    = {0.9,  0.75, 0.1 },
    [SUIT.WIND]      = {0.8,  0.8,  0.9 },
    [SUIT.FLOWER]    = {0.85, 0.4,  0.75},
}

local function addTiles(deck, suit, names, value, copies)
    for _, name in ipairs(names) do
        for _ = 1, copies do
            table.insert(deck, { suit = suit, value = value, label = name })
        end
    end
end

-- Build the full 144-tile standard Mahjong deck
function buildFullDeck()
    local deck = {}

    for _, suit in ipairs({ SUIT.CHARACTER, SUIT.BAMBOO, SUIT.CIRCLE }) do
        for num = 1, 9 do
            addTiles(deck, suit, { tostring(num) }, num, 4)
        end
    end

    addTiles(deck, SUIT.DRAGON, { "Red", "Green", "White" },                              10, 4)
    addTiles(deck, SUIT.WIND,   { "East", "South", "West", "North" },                     8,  4)
    addTiles(deck, SUIT.FLOWER, { "Plum", "Orchid", "Chrys", "Bam", "Spring", "Summer", "Autumn", "Winter" }, 15, 1)

    return deck  -- 144 tiles total
end
