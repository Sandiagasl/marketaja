
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local MarketStock = ReplicatedStorage.Modules.Util.Net.MarketStock

-- CONFIGURATION
local WEBHOOK_URL = "https://discord.com/api/webhooks/1484263811560116234/oS8bjLBQiqb--ivwjcRryIv_ksO7M_i57ypycnAmYwBZTJobjNttwKYvGBYER641g8ti"
local DISCORD_USER_ID = "1021078313260826695"
local CATEGORY = "Black"
local POLL_INTERVAL = 5

-- RARE ITEMS
local RARE_ITEMS = {
    ["Shady Seal"] = true,
    ["Crate"] = true,
}

local SEND_INITIAL_STOCK = true

-- HTTP REQUEST
local requestFunc =
    request or
    http_request or
    (syn and syn.request)

if not requestFunc then
    warn("HTTP request function unavailable!")
    return
end

local previousOffers = nil

-- CHECK RARITY
local function isRare(offer)
    local name = string.lower(tostring(offer.Name or ""))
    local rarity = string.lower(tostring(offer.Rarity or ""))

    return string.find(name, "crate", 1, true) ~= nil
        or rarity == "rare"
        or offer.Rare == true
end

-- SEND DISCORD
local function sendDiscord(offers, isInitial)
    if #offers == 0 then
        return
    end

    local lines = {}
    local foundRare = false

    for _, offer in ipairs(offers) do
        local rare = isRare(offer)

        if rare then
            foundRare = true
        end

        local tag = rare and " **[RARE]**" or ""

        table.insert(lines, string.format(
            "**%s**%s\nSlot: `%s` | Stock: `%d`",
            offer.Name,
            tag,
            tostring(offer.Slots),
            offer.Left
        ))
    end

    local payload = {
        username = "Market Stock Monitor",
        embeds = {
            {
                title = isInitial and "Current Market Stock"
                    or "Market Restock Detected",
                description = table.concat(lines, "\n\n"),
                color = foundRare and 16766720 or 5793266,
                footer = {
                    text = "Cobalt Market Monitor"
                },
                timestamp = DateTime.now():ToIsoDate()
            }
        },
        allowed_mentions = {
            parse = {}
        }
    }

    -- TAG DISCORD USER WHEN RARE ITEM APPEARS
    if foundRare
        and DISCORD_USER_ID ~= ""
        and DISCORD_USER_ID ~= "1021078313260826695" then

        payload.content = "<@" .. DISCORD_USER_ID .. ">"
        payload.allowed_mentions.users = { DISCORD_USER_ID }
    end

    local success, result = pcall(function()
        return requestFunc({
            Url = WEBHOOK_URL,
            Method = "POST",
            Headers = {
                ["Content-Type"] = "application/json"
            },
            Body = HttpService:JSONEncode(payload)
        })
    end)

    if not success then
        warn("Discord webhook error:", result)
    elseif type(result) == "table"
        and result.StatusCode
        and result.StatusCode >= 300 then

        warn("Discord returned HTTP status:", result.StatusCode)
    end
end

-- UNIQUE ITEM ID
local function makeOfferId(offer)
    if offer.Key ~= nil then
        return tostring(offer.Key)
    end

    return tostring(offer.Name or "Unknown")
        .. ":" .. tostring(offer.Slots or "?")
end

-- CHECK MARKET STOCK
local function checkStock()
    local success, response = pcall(function()
        return MarketStock:InvokeServer(CATEGORY)
    end)

    if not success then
        warn("Failed to retrieve market stock:", response)
        return
    end

    if type(response) ~= "table"
        or not response.Ok
        or type(response.Offers) ~= "table" then

        warn("Unexpected MarketStock response")
        return
    end

    local currentOffers = {}

    for _, offer in ipairs(response.Offers) do
        local remaining = tonumber(offer.Left) or 0

        if remaining > 0 then
            local item = {
                Name = tostring(offer.Name or "Unknown"),
                Slots = offer.Slots or "?",
                Key = tostring(offer.Key or ""),
                Left = remaining,
                Rarity = offer.Rarity,
                Rare = offer.Rare
            }

            currentOffers[makeOfferId(item)] = item
        end
    end

    -- FIRST CHECK
    if previousOffers == nil then
        previousOffers = currentOffers

        if SEND_INITIAL_STOCK then
            local initialList = {}

            for _, item in pairs(currentOffers) do
                table.insert(initialList, item)
            end

            table.sort(initialList, function(a, b)
                return a.Name < b.Name
            end)

            sendDiscord(initialList, true)
        end

        return
    end

    local notifications = {}

    -- ONLY NEW ITEMS OR INCREASED STOCK
    for id, current in pairs(currentOffers) do
        local previous = previousOffers[id]

        if previous == nil or current.Left > previous.Left then
            table.insert(notifications, current)
        end
    end

    -- UPDATE SNAPSHOT
    previousOffers = currentOffers

    table.sort(notifications, function(a, b)
        return a.Name < b.Name
    end)

    if #notifications > 0 then
        sendDiscord(notifications, false)
        print("New stock/restock detected!")
    end
end

-- MAIN LOOP
task.spawn(function()
    while true do
        checkStock()
        task.wait(POLL_INTERVAL)
    end
end)
