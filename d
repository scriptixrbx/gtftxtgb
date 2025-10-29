-- MM2 Auto Trade Script v3 - MM2Values Integration + Fixed Trade Logic (2025)
-- By Grok (educational only - ban risk!)
-- Требует syn.request и firesignal (Delta/Synapse)

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Настройки
local AUTO_TRADE_ENABLED = false
local AUTO_ADD_ENABLED = false
local AUTO_ADD_ITEM = "Fire Tiger" -- Измени на свой godly
local MONITOR_INTERVAL = 30
local TRADE_CHECK_INTERVAL = 2
local PRICE_CHANGE_THRESHOLD = 0.05
local WIN_THRESHOLD = 1.1
local itemsToMonitor = {"Fire Tiger", "Brush Knife", "Fang Blade"} -- Godly для mm2values
local priceHistory = {}
local itemValues = {} -- Кэш цен с mm2values

-- Fetch и парсинг с mm2values.com (godly page)
local function fetchItemValue(itemName)
    if itemValues[itemName] then return itemValues[itemName] end -- Кэш
    
    local success, response = pcall(function()
        local url = "https://www.mm2values.com/?p=godly"
        if syn and syn.request then
            local res = syn.request({Url = url, Method = "GET"})
            if res.StatusCode == 200 then
                local html = res.Body
                -- Парсинг таблицы: <tr><td><a>Item Name</a></td><td>Value</td>...</tr>
                -- Паттерн для godly (адаптировано под структуру сайта 2025)
                for match in html:gmatch('<tr[^>]*>.*?<td[^>]*>([^<]+)</td>.*?<td[^>]*>(%d+)</td>') do
                    local name, value = match:match("([^|]+)|(%d+)")
                    if name and value then
                        name = name:lower():gsub("%s+", " "):gsub("[^%w%s]", "") -- Нормализация
                        itemValues[name] = tonumber(value) or 0
                    end
                end
                return itemValues[itemName:lower():gsub("%s+", " "):gsub("[^%w%s]", "")] or 0
            end
        end
        return 0
    end)
    if not success then
        warn("Fetch/parse error: " .. tostring(response))
        return 0
    end
    return response
end

-- Анализ тренда (fetch обновляет кэш)
local function analyzeTrend(itemName)
    local currentPrice = fetchItemValue(itemName)
    if not priceHistory[itemName] then
        priceHistory[itemName] = {prices = {currentPrice}}
        return "stable"
    end
    local prices = priceHistory[itemName].prices
    table.insert(prices, 1, currentPrice)
    if #prices > 10 then table.remove(prices) end
    
    local oldPrice = prices[#prices]
    if oldPrice == 0 then return "stable" end
    local change = (currentPrice - oldPrice) / oldPrice
    
    if change > PRICE_CHANGE_THRESHOLD then return "rising"
    elseif change < -PRICE_CHANGE_THRESHOLD then return "falling"
    else return "stable" end
end

-- Чат
local function chatMessage(msg)
    pcall(function()
        ReplicatedStorage.DefaultChatSystemChatEvents.SayMessageRequest:FireServer(msg, "All")
    end)
end

-- Расчёт ценности стороны (ScrollingFrame с ItemFrames)
local function calculateTradeValue(sideScrollingFrame)
    local totalValue = 0
    if not sideScrollingFrame then return 0 end
    for _, child in pairs(sideScrollingFrame:GetChildren()) do
        if child:IsA("Frame") and (child:FindFirstChild("NameLabel") or child:FindFirstChild("TextLabel")) then
            local itemLabel = child:FindFirstChild("NameLabel") or child:FindFirstChild("TextLabel")
            if itemLabel then
                local itemName = itemLabel.Text
                totalValue += fetchItemValue(itemName)
            end
        end
    end
    return totalValue
end

-- Авто-логика трейда (fixed paths 2025)
local function autoTradeCheck()
    if not AUTO_TRADE_ENABLED then return end
    
    local tradingGui = playerGui:FindFirstChild("TradingGui") or playerGui:FindFirstChild("TradeGui") or playerGui:FindFirstChild("TradingFrame")
    if not tradingGui or not tradingGui.Visible then 
        print("No trading GUI found or not visible")
        return 
    end
    print("Trading GUI found: " .. tradingGui.Name)
    
    -- Тренды и чат
    for _, item in ipairs(itemsToMonitor) do
        local trend = analyzeTrend(item)
        local msg = trend == "rising" and "add " .. item .. " (рост!)" or (trend == "falling" and "no " .. item .. " (падение!)" or "stable " .. item)
        chatMessage(msg)
    end
    
    -- Стороны: Your/Left = твоя, Their/Right = их
    local yourScrolling = tradingGui:FindFirstChild("YourInventory") and tradingGui.YourInventory.ScrollingFrame or 
                          tradingGui:FindFirstChild("LeftFrame") and tradingGui.LeftFrame.ScrollingFrame
    local theirScrolling = tradingGui:FindFirstChild("TheirInventory") and tradingGui.TheirInventory.ScrollingFrame or 
                           tradingGui:FindFirstChild("RightFrame") and tradingGui.RightFrame.ScrollingFrame
    
    local yourValue = calculateTradeValue(yourScrolling)
    local theirValue = calculateTradeValue(theirScrolling)
    print("Your value: " .. yourValue .. ", Their: " .. theirValue) -- Debug
    
    -- Кнопки (Accept/Decline in frames)
    local acceptFrame = tradingGui:FindFirstChild("AcceptFrame") or tradingGui:FindFirstChild("MainFrame")
    local acceptBtn = acceptFrame and (acceptFrame:FindFirstChild("AcceptButton") or acceptFrame:FindFirstChildOfClass("TextButton"))
    local declineFrame = tradingGui:FindFirstChild("DeclineFrame") or tradingGui:FindFirstChild("MainFrame")
    local declineBtn = declineFrame and (declineFrame:FindFirstChild("DeclineButton") or declineFrame:FindFirstChildOfClass("TextButton"))
    
    local isWin = yourValue > theirValue * WIN_THRESHOLD
    
    if isWin and acceptBtn then
        firesignal(acceptBtn.Activated) -- Надёжный клик для executor
        chatMessage("add WIN TRADE! (твоя: " .. yourValue .. ", их: " .. theirValue .. ")")
        print("Auto-accepted trade")
    elseif declineBtn then
        firesignal(declineBtn.Activated)
        chatMessage("no LOSE TRADE! (твоя: " .. yourValue .. ", их: " .. theirValue .. ")")
        print("Auto-declined trade")
    end
end

-- Авто-добавление (ищет в YourInventory или Backpack)
local function autoAddItemToTrade()
    if not AUTO_ADD_ENABLED or not AUTO_TRADE_ENABLED then return end
    local tradingGui = playerGui:FindFirstChild("TradingGui") or playerGui:FindFirstChild("TradeGui") or playerGui:FindFirstChild("TradingFrame")
    if not tradingGui or not tradingGui.Visible then return end
    
    local trend = analyzeTrend(AUTO_ADD_ITEM)
    if trend ~= "rising" then return end
    
    -- Ищи в YourInventory ScrollingFrame
    local yourScrolling = tradingGui:FindFirstChild("YourInventory") and tradingGui.YourInventory.ScrollingFrame or 
                          tradingGui:FindFirstChild("LeftFrame") and tradingGui.LeftFrame.ScrollingFrame
    if yourScrolling then
        for _, slot in pairs(yourScrolling:GetChildren()) do
            if slot:IsA("Frame") and (slot.Name == AUTO_ADD_ITEM or slot:FindFirstChild("NameLabel") and slot.NameLabel.Text == AUTO_ADD_ITEM) then
                local addBtn = slot:FindFirstChild("AddButton") or slot
                if addBtn then
                    firesignal(addBtn.Activated)
                    chatMessage("add " .. AUTO_ADD_ITEM .. " to trade!")
                    print("Auto-added " .. AUTO_ADD_ITEM)
                    break
                end
            end
        end
    end
    
    -- Fallback: Backpack tools (если инвентарь tools)
    local backpack = player:FindFirstChildOfClass("Backpack")
    if backpack then
        for _, tool in pairs(backpack:GetChildren()) do
            if tool.Name == AUTO_ADD_ITEM and tool:IsA("Tool") then
                -- Fire add remote if exists, or simulate equip/add
                pcall(function() ReplicatedStorage.Remotes["AddToTrade"]:FireServer(tool) end) -- Адаптируй remote name
                chatMessage("add " .. AUTO_ADD_ITEM .. " from backpack!")
                break
            end
        end
    end
end

-- Loops
spawn(function()
    while true do
        wait(TRADE_CHECK_INTERVAL)
        autoTradeCheck()
        autoAddItemToTrade()
    end
end)

spawn(function()
    while true do
        wait(MONITOR_INTERVAL)
        for _, item in ipairs(itemsToMonitor) do
            analyzeTrend(item) -- Обновляет кэш
        end
        print("Prices updated from mm2values")
    end
end)

-- GUI (расширенное)
local function createGUI()
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "AutoTradeGUI"
    screenGui.Parent = playerGui
    
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 250, 0, 200)
    frame.Position = UDim2.new(0, 10, 0, 10)
    frame.BackgroundColor3 = Color3.new(0, 0, 0)
    frame.Parent = screenGui
    
    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0, 30)
    title.Text = "MM2 Auto Trade v3 (MM2Values)"
    title.BackgroundTransparency = 1
    title.TextColor3 = Color3.new(1, 1, 1)
    title.Parent = frame
    
    local toggleTrade = Instance.new("TextButton")
    toggleTrade.Size = UDim2.new(1, 0, 0, 30)
    toggleTrade.Position = UDim2.new(0, 0, 0, 30)
    toggleTrade.Text = "Auto Trade: OFF"
    toggleTrade.BackgroundColor3 = Color3.new(1, 0, 0)
    toggleTrade.Parent = frame
    toggleTrade.MouseButton1Click:Connect(function()
        AUTO_TRADE_ENABLED = not AUTO_TRADE_ENABLED
        toggleTrade.Text = "Auto Trade: " .. (AUTO_TRADE_ENABLED and "ON" or "OFF")
        toggleTrade.BackgroundColor3 = AUTO_TRADE_ENABLED and Color3.new(0, 1, 0) or Color3.new(1, 0, 0)
    end)
    
    local toggleAdd = Instance.new("TextButton")
    toggleAdd.Size = UDim2.new(1, 0, 0, 30)
    toggleAdd.Position = UDim2.new(0, 0, 0, 60)
    toggleAdd.Text = "Auto Add (" .. AUTO_ADD_ITEM .. "): OFF"
    toggleAdd.BackgroundColor3 = Color3.new(1, 0, 0)
    toggleAdd.Parent = frame
    toggleAdd.MouseButton1Click:Connect(function()
        AUTO_ADD_ENABLED = not AUTO_ADD_ENABLED
        toggleAdd.Text = "Auto Add (" .. AUTO_ADD_ITEM .. "): " .. (AUTO_ADD_ENABLED and "ON" or "OFF")
        toggleAdd.BackgroundColor3 = AUTO_ADD_ENABLED and Color3.new(0, 1, 0) or Color3.new(1, 0, 0)
    end)
    
    local status = Instance.new("TextLabel")
    status.Size = UDim2.new(1, 0, 0, 30)
    status.Position = UDim2.new(0, 0, 0, 90)
    status.Text = "Статус: Готов (проверь консоль)"
    status.BackgroundTransparency = 1
    status.TextColor3 = Color3.new(1, 1, 1)
    status.Parent = frame
    
    local debugBtn = Instance.new("TextButton")
    debugBtn.Size = UDim2.new(1, 0, 0, 30)
    debugBtn.Position = UDim2.new(0, 0, 0, 120)
    debugBtn.Text = "Print GUI Hierarchy"
    debugBtn.BackgroundColor3 = Color3.new(0.5, 0.5, 0.5)
    debugBtn.Parent = frame
    debugBtn.MouseButton1Click:Connect(function()
        print("=== PlayerGui Children ===")
        for _, v in pairs(playerGui:GetChildren()) do print(v.Name) end
        if tradingGui then
            print("=== Trading Children ===")
            for _, v in pairs(tradingGui:GetChildren()) do print(v.Name) end
        end
    end)
    
    -- Обновление статуса
    spawn(function()
        while true do
            wait(5)
            status.Text = "Цены: " .. (#itemValues > 0 and tostring(#itemValues) .. " items" or "fetch...") .. " | Trade: " .. (AUTO_TRADE_ENABLED and "ON" or "OFF")
        end
    end)
end

createGUI()
print("v3 загружен! Включи в GUI, открой трейд. Проверь консоль (F9) на debug.")
