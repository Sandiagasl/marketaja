
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local MarketStock =
    ReplicatedStorage.Modules.Util.Net.MarketStock

-- CONFIGURATION
local WEBHOOK_URL = "https://discord.com/api/webhooks/1484263811560116234/oS8bjLBQiqb--ivwjcRryIv_ksO7M_i57ypycnAmYwBZTJobjNttwKYvGBYER641g8ti"
local DISCORD_USER_ID = "1021078313260826695"

local POLL_INTERVAL = 5

local MARKETS = {
    "Black",
    "Forest"
}

-- RARE ITEMS
local RARE_ITEMS = {
    "seal",
    "trophy",
    "greg",
    "coffin",
    "voucher",
    "maja",
}

local SEND_INITIAL_STOCK = true

-- All names containing "crate" are rare.
local function isRare(offer)
    local name = string.lower(tostring(offer.Name or offer.Id or ""))

    for _, keyword in ipairs(RARE_ITEMS) do
        if string.find(name, string.lower(keyword), 1, true) then
            return true
        end
    end

    return false
end

-- HTTP REQUEST
local requestFunc =
    request or http_request or (syn and syn.request)

if not requestFunc then
    warn("HTTP request unavailable!")
    return
end

-- STOCK SNAPSHOTS
local previousStock = {}

-- SEND DISCORD
local function sendDiscord(market, offers, initial)
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

        table.insert(lines, string.format(
            "**%s** %s\nSlot: `%s` | Stock: `%d` | Price: `%s`",
            offer.Name,
            rare and "💎 **{ Exclusive }** " or "",
            tostring(offer.Slot),
            offer.Left,
            tostring(offer.Price or "?")
        ))
    end

    local payload = {
        username = "Market Stock Monitor",
        embeds = {
            {
                title = market .. " Market",
                description = table.concat(lines, "\n\n"),
                color = foundRare and 16766720 or 5793266,
                footer = {
                    text = initial
                        and "Initial Stock"
                        or "Stock Update"
                },
                timestamp = DateTime.now():ToIsoDate()
            }
        },
        allowed_mentions = {
            parse = {}
        }
    }

    if foundRare
        and DISCORD_USER_ID ~= "" then

        payload.content = "<@" .. DISCORD_USER_ID .. ">"
        payload.allowed_mentions.users = {
            DISCORD_USER_ID
        }
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
        warn("Discord error:", result)
    elseif type(result) == "table"
        and result.StatusCode
        and result.StatusCode >= 300 then

        warn("Discord HTTP error:", result.StatusCode)
    end
end

-- UNIQUE ITEM ID
local function getItemId(offer)
    return tostring(
        offer.Key
        or offer.Id
        or offer.Name
        or "Unknown"
    ) .. ":" .. tostring(offer.Slot or offer.Slots or "?")
end

-- CHECK ONE MARKET
local function checkMarket(market)
    local success, response = pcall(function()
        return MarketStock:InvokeServer(market)
    end)

    if not success then
        warn("Failed to check " .. market, response)
        return
    end

    if type(response) ~= "table"
        or not response.Ok
        or type(response.Offers) ~= "table" then
        warn("Invalid response:", market)
        return
    end

    local current = {}

    for _, offer in ipairs(response.Offers) do
        local remaining = tonumber(offer.Left) or 0

        if remaining > 0 then
            local item = {
                Name = tostring(offer.Name or "Unknown"),
                Slot = offer.Slot or offer.Slots or "?",
                Key = offer.Key,
                Id = offer.Id,
                Left = remaining,
                Price = offer.Price,
                Rarity = offer.Rarity,
                Rare = offer.Rare,
                Kind = offer.Kind,
                Tier = offer.Tier
            }

            current[getItemId(item)] = item
        end
    end

    -- FIRST CHECK
    if previousStock[market] == nil then
        previousStock[market] = current

        if SEND_INITIAL_STOCK then
            local list = {}

            for _, item in pairs(current) do
                table.insert(list, item)
            end

            table.sort(list, function(a, b)
                return a.Name < b.Name
            end)

            sendDiscord(market, list, true)
        end

        print(market .. " initial stock loaded")
        return
    end

    local notifications = {}

    -- NEW ITEMS OR INCREASED STOCK ONLY
    for id, item in pairs(current) do
        local old = previousStock[market][id]

        if old == nil or item.Left > old.Left then
            table.insert(notifications, item)
        end
    end

    -- UPDATE SNAPSHOT
    previousStock[market] = current

    table.sort(notifications, function(a, b)
        return a.Name < b.Name
    end)

    if #notifications > 0 then
        sendDiscord(market, notifications, false)
        print(market .. " stock updated!")
    end
end

-- MAIN LOOP
task.spawn(function()
    while true do
        for _, market in ipairs(MARKETS) do
            checkMarket(market)
        end

        task.wait(POLL_INTERVAL)
    end
end)
