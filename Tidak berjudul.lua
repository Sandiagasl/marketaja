
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local Net = ReplicatedStorage.Modules.Util.Net
local MarketStock = Net.MarketStock
local MarketBuy = Net.MarketBuy

-- CONFIGURATION
local WEBHOOK_URL = "https://discord.com/api/webhooks/1484263811560116234/oS8bjLBQiqb--ivwjcRryIv_ksO7M_i57ypycnAmYwBZTJobjNttwKYvGBYER641g8ti"
local DISCORD_USER_ID = "1021078313260826695"

local POLL_INTERVAL = 5

local MARKETS = {
    "Black",
    "Forest"
}

-- AUTO BUY SETTINGS
local AUTO_BUY = true

-- false = hanya membeli item yang muncul setelah pengecekan pertama
-- true = juga mencoba membeli item langka yang sudah tersedia saat script mulai
local AUTO_BUY_INITIAL_STOCK = false

-- RARE ITEMS
local RARE_ITEMS = {
    "seal",
    "trophy",
    "greg",
    "coffin",
    "voucher",
    "maja",
    "warp",
    "crate"
}

local SEND_INITIAL_STOCK = true

-- HTTP REQUEST
local requestFunc =
    request or http_request or (syn and syn.request)

if not requestFunc then
    warn("HTTP request unavailable!")
    return
end

-- CHECK RARITY USING KEYWORDS
local function isRare(offer)
    local name = string.lower(
        tostring(offer.Name or offer.Id or "")
    )

    for _, keyword in ipairs(RARE_ITEMS) do
        if string.find(name, string.lower(keyword), 1, true) then
            return true
        end
    end

    return false
end

-- STOCK SNAPSHOTS
local previousStock = {}

-- PURCHASE HISTORY
local boughtItems = {}

-- DISCORD REQUEST
local function sendDiscordPayload(payload)
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
        return false
    end

    if type(result) == "table"
        and result.StatusCode
        and result.StatusCode >= 300 then

        warn("Discord HTTP error:", result.StatusCode)
        return false
    end

    return true
end

-- STOCK NOTIFICATION
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
            rare and "💎 **{ Exclusive }**" or "",
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
                    text = initial and "Initial Stock" or "Stock Update"
                },
                timestamp = DateTime.now():ToIsoDate()
            }
        },
        allowed_mentions = {
            parse = {}
        }
    }

    if foundRare and DISCORD_USER_ID ~= "" then
        payload.content = "<@" .. DISCORD_USER_ID .. ">"
        payload.allowed_mentions.users = {
            DISCORD_USER_ID
        }
    end

    sendDiscordPayload(payload)
end

-- PURCHASE NOTIFICATION
local function sendBuyNotification(market, offer)
    local payload = {
        username = "Market Auto Buyer",
        embeds = {
            {
                title = "🛒 Purchase Request Sent",
                description = string.format(
                    "**Item:** %s\n**Market:** %s\n**Slot:** %s\n**Price:** %s",
                    tostring(offer.Name),
                    tostring(market),
                    tostring(offer.Slot),
                    tostring(offer.Price or "?")
                ),
                color = 5793266,
                footer = {
                    text = "Market Auto Buy"
                },
                timestamp = DateTime.now():ToIsoDate()
            }
        },
        allowed_mentions = {
            parse = {}
        }
    }

    sendDiscordPayload(payload)
end

-- UNIQUE ITEM ID
local function getItemId(offer)
    return tostring(
        offer.Key
        or offer.Id
        or offer.Name
        or "Unknown"
    ) .. ":" .. tostring(offer.Slot or "?")
end

-- AUTO BUY
local function autoBuy(market, offer)
    if not AUTO_BUY then
        return
    end

    if not isRare(offer) then
        return
    end

    local slot = tonumber(offer.Slot)

    if not slot then
        warn("Invalid slot for:", offer.Name)
        return
    end

    local buyId = market .. ":" .. getItemId(offer)

    if boughtItems[buyId] then
        return
    end

    -- Mark before invoking to prevent duplicate attempts
    boughtItems[buyId] = true

    local success, result = pcall(function()
        return MarketBuy:InvokeServer(market, slot)
    end)

    if not success then
        boughtItems[buyId] = nil
        warn("Auto Buy error:", result)
        return
    end

    -- InvokeServer may return nil.
    -- This confirms only that the request did not error.
    sendBuyNotification(market, offer)

    print("Purchase request sent:", market, offer.Name, "Slot:", slot)
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
                Slot = offer.Slot or "?",
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

        local list = {}

        for _, item in pairs(current) do
            table.insert(list, item)

            if AUTO_BUY_INITIAL_STOCK then
                autoBuy(market, item)
            end
        end

        table.sort(list, function(a, b)
            return a.Name < b.Name
        end)

        if SEND_INITIAL_STOCK then
            sendDiscord(market, list, true)
        end

        print(market .. " initial stock loaded")
        return
    end

    local notifications = {}

    -- NEW ITEMS OR INCREASED STOCK
    for id, item in pairs(current) do
        local old = previousStock[market][id]

        if old == nil or item.Left > old.Left then
            table.insert(notifications, item)

            -- AUTO BUY MATCHING ITEMS
            autoBuy(market, item)
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
