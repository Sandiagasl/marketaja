
local env = getgenv()

-- STOP PREVIOUS NOTIFIER
if env.MarketNotifier then
    env.MarketNotifier.Running = false

    if env.MarketNotifier.Thread then
        pcall(task.cancel, env.MarketNotifier.Thread)
    end
end

local state = {
    Running = true,
    Thread = nil
}

env.MarketNotifier = state

-- SERVICES
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

-- RARE KEYWORDS
-- Semua nama item yang mengandung keyword akan dianggap rare.
local RARE_ITEMS = {
    "seal",
    "trophy",
    "greg",
    "coffer",
    "voucher",
    "maja",
    "30m",
    "1h",
    "12h",
    "market",
    "crate crate",
    "puffer",
    "lockbox"
}

local SEND_INITIAL_STOCK = true

-- RARE DETECTION
local function isRare(offer)
    local name = string.lower(
        tostring(offer.Name or offer.Id or "")
    )

    for _, keyword in ipairs(RARE_ITEMS) do
        keyword = string.lower(keyword)

        if string.find(name, keyword, 1, true) then
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

-- SEND COMBINED DISCORD NOTIFICATION
local function sendDiscord(allMarkets, initial)
    local lines = {}
    local foundRare = false

    for _, market in ipairs(MARKETS) do
        local offers = allMarkets[market]

        if offers and #offers > 0 then
            table.insert(
                lines,
                "**" .. string.upper(market) .. " MARKET**"
            )

            for _, offer in ipairs(offers) do
                local rare = isRare(offer)

                if rare then
                    foundRare = true
                end

                table.insert(lines, string.format(
                    "%s **%s** %s\nStock: `%s` | Price: `%s`",
                    rare and "💎" or "•",
                    tostring(offer.Name or "Unknown"),
                    rare and "**{ Exclsuive }**" or "",
                    tostring(offer.Left or "?"),
                    tostring(offer.Price or "?")
                ))
            end

            table.insert(lines, "")
        end
    end

    if #lines == 0 then
        return
    end

    local payload = {
        username = "Market Stock Monitor",
        embeds = {
            {
                title = "Market Stock Update",
                description = table.concat(lines, "\n"),
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
        and DISCORD_USER_ID ~= ""
        and DISCORD_USER_ID ~= "YOUR_DISCORD_USER_ID" then

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
    )
end

-- CHECK ONE MARKET
local function checkMarket(market)
    local success, response = pcall(function()
        return MarketStock:InvokeServer(market)
    end)

    if not success then
        warn("Failed to check " .. market, response)
        return nil
    end

    if type(response) ~= "table"
        or not response.Ok
        or type(response.Offers) ~= "table" then

        warn("Invalid response:", market)
        return nil
    end

    local current = {}

    for _, offer in ipairs(response.Offers) do
        local remaining = tonumber(offer.Left) or 0

        if remaining > 0 then
            local item = {
                Name = tostring(offer.Name or offer.Id or "Unknown"),
                Key = offer.Key,
                Id = offer.Id,
                Left = remaining,
                Price = offer.Price
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

            return list
        end

        print(market .. " initial stock loaded")
        return nil
    end

    local notifications = {}

    -- NEW ITEMS OR INCREASED STOCK
    for id, item in pairs(current) do
        local old = previousStock[market][id]

        if old == nil or item.Left > old.Left then
            table.insert(notifications, item)
        end
    end

    previousStock[market] = current

    table.sort(notifications, function(a, b)
        return a.Name < b.Name
    end)

    if #notifications > 0 then
        print(market .. " stock updated!")
        return notifications
    end

    return nil
end

-- MAIN LOOP
state.Thread = task.spawn(function()
    while state.Running do
        local allMarkets = {}

        for _, market in ipairs(MARKETS) do
            if not state.Running then
                break
            end

            local changedOffers = checkMarket(market)

            if changedOffers and #changedOffers > 0 then
                allMarkets[market] = changedOffers
            end
        end

        if state.Running and next(allMarkets) then
            sendDiscord(allMarkets, false)
        end

        task.wait(POLL_INTERVAL)
    end

    if env.MarketNotifier == state then
        env.MarketNotifier = nil
    end
end)

print("Market Stock Monitor started!")
