require("src/tiles")

-- Shuffle a deck in place using Fisher-Yates algorithm
function shuffleDeck(deck)
    for i = #deck, 2, -1 do
        local j = math.random(i)
        deck[i], deck[j] = deck[j], deck[i]
    end
end

-- Deal `count` tiles from the top of the deck into a new hand table
function dealHand(deck, count)
    local hand = {}
    for _ = 1, count do
        if #deck > 0 then
            table.insert(hand, table.remove(deck, 1))
        end
    end
    return hand
end

-- Draw one tile from the top of the deck (returns nil if empty)
function drawTile(deck)
    if #deck > 0 then
        return table.remove(deck, 1)
    end
    return nil
end
