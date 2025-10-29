-- MM2 Auto Trade Script v2 - Full Automation with SupremeValues (2025 Update)
-- By Grok (educational only - use at own risk)
-- Требует executor с syn.request или HttpService

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Настройки
local AUTO_TRADE_ENABLED = false
local AUTO_ADD_ENABLED = false
local AUTO_ADD_ITEM = "Fire Tiger" -- Предмет для авто-добавления (измени на свой)
local MONITOR_INTERVAL = 30 -- Секунды для цен
local TRADE_CHECK_INTERVAL = 2 -- Секунды для проверки трейда
local PRICE_CHANGE_THRESHOLD = 0.05 -- 5% для тренда
local WIN_THRESHOLD = 1.1 -- Твоя ценность > их * 1.1 для "win"
local itemsToMonitor = {"Fire Tiger", "Brush Knife", "Fang Blade"} -- Мониторь эти
local priceHistory = {}

-- Fetch цен с supremevalues (актуальный API 2025)
local function fetchItemValue(itemName)
    local success, response = pcall(function()
        local url = "https://api.supremevalues.xyz/items?search=" .. HttpService:UrlEncode(itemName)
        if syn and syn.request then
            local res = syn.request({Url = url, Method = "GET"})
            if res.StatusCode == 200 then
                local data = HttpService:JSONDecode(res.Body)
                return data[1] and data[1].value or 0 -- Структура: [{name, value, ...}]
            end
        else
            -- Fallback (для Studio)
            local data = HttpService:JSONDecode(HttpService:GetAsync(url))
            return data[1] and data[1].value or 0
        end
        return 0
    end)
    if not success then
        warn("Fetch error: " .. tostring(response))
        return 0
    end
    return response
end

-- Анализ тренда
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
    ReplicatedStorage.DefaultChatSystemChatEvents.SayMessageRequest:FireServer(msg, "All")
end

-- Расчёт ценности стороны трейда (Left = твоя, Right = их)
local function calculateTradeValue(sideFrame) -- sideFrame = LeftFrame.ScrollingFrame
    local totalValue = 0
    if not sideFrame then return 0 end
    for _, child in pairs(sideFrame:GetChildren()) do
        if child:IsA("Frame") and child:FindFirstChild("ItemName") then
            local itemName = child.ItemName.Text
            totalValue = totalValue + fetchItemValue(itemName)
        end
    end
    return totalValue
end

-- Авто-логика трейда
local function autoTradeCheck()
    if not AUTO_TRADE_ENABLED then return end
    
    local tradingFrame = playerGui:FindFirstChild("TradingFrame")
    if not tradingFrame or not tradingFrame.Visible then return end
    
    -- Мониторь тренды и чать
    for _, item in ipairs(itemsToMonitor) do
        local trend = analyzeTrend(item)
        local msg = trend == "rising" and "add " .. item .. " (рост!)" or (trend == "falling" and "no " .. item .. " (падение!)" or "stable " .. item)
        chatMessage(msg)
    end
    
    -- Расчёт win
    local leftValue = calculateTradeValue(tradingFrame.LeftFrame and tradingFrame.LeftFrame.ScrollingFrame)
    local rightValue = calculateTradeValue(tradingFrame.RightFrame and tradingFrame.RightFrame.ScrollingFrame)
    
    local isWin = leftValue > rightValue * WIN_THRESHOLD
    local acceptBtn = tradingFrame:FindFirstChild("AcceptButton") or tradingFrame:FindFirstChildOfClass("TextButton") -- Адаптируй если имя другое
    local declineBtn = tradingFrame:FindFirstChild("DeclineButton") or tradingFrame:FindFirstChildOfClass("TextButton", true) -- Decline
    
    if isWin then
        if acceptBtn then acceptBtn.MouseButton1Click:Fire() end
        chatMessage("add WIN TRADE! (твоя ценность: " .. leftValue .. ", их: " .. rightValue .. ")")
    else
        if declineBtn then declineBtn.MouseButton1Click:Fire() end
        chatMessage("no LOSE TRADE! (твоя: " .. leftValue .. ", их: " .. rightValue .. ")")
    end
end

-- Авто-добавление предмета (клик по инвентарю)
local function autoAddItemToTrade()
    if not AUTO_ADD_ENABLED or not AUTO_TRADE_ENABLED then return end
    local tradingFrame = playerGui:FindFirstChild("TradingFrame")
    if not tradingFrame or not tradingFrame.Visible then return end
    
    local trend = analyzeTrend(AUTO_ADD_ITEM)
    if trend == "rising" then
        -- Найди кнопку предмета в инвентаре (предполагаем в Backpack GUI или Trade Add buttons)
        local backpack = player:FindFirstChild("Backpack")
        if backpack then
            for _, tool in pairs(backpack:GetChildren()) do
                if tool.Name == AUTO_ADD_ITEM then
                    -- Симулируем клик (fire event или mouse)
                    tool.MouseButton1Click:Fire() -- Если это button; иначе используй firesignal
                    chatMessage("add " .. AUTO_ADD_ITEM .. " to trade!")
                    break
                end
            end
        end
    end
end

-- Основной loop для трейда
spawn(function()
    while true do
        wait(TRADE_CHECK_INTERVAL)
        autoTradeCheck()
        autoAddItemToTrade()
    end
end)

-- Loop для мониторинга цен (фон)
spawn(function()
    while true do
        wait(MONITOR_INTERVAL)
        for _, item in ipairs(itemsToMonitor) do
            analyzeTrend(item) -- Обновляем историю
        end
    end
end)

-- GUI
local function createGUI()
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "AutoTradeGUI"
    screenGui.Parent = playerGui
    
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 250, 0, 150)
    frame.Position = UDim2.new(0, 10, 0, 10)
    frame.BackgroundColor3 = Color3.new(0, 0, 0)
    frame.Parent = screenGui
    
    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0, 30)
    title.Text = "MM2 Auto Trade v2"
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
    toggleAdd.Text = "Auto Add Item: OFF (" .. AUTO_ADD_ITEM .. ")"
    toggleAdd.BackgroundColor3 = Color3.new(1, 0, 0)
    toggleAdd.Parent = frame
    toggleAdd.MouseButton1Click:Connect(function()
        AUTO_ADD_ENABLED = not AUTO_ADD_ENABLED
        toggleAdd.Text = "Auto Add Item: " .. (AUTO_ADD_ENABLED and "ON" or "OFF") .. " (" .. AUTO_ADD_ITEM .. ")"
        toggleAdd.BackgroundColor3 = AUTO_ADD_ENABLED and Color3.new(0, 1, 0) or Color3.new(1, 0, 0)
    end)
    
    local status = Instance.new("TextLabel")
    status.Size = UDim2.new(1, 0, 0, 30)
    status.Position = UDim2.new(0, 0, 0, 90)
    status.Text = "Статус: Готов"
    status.BackgroundTransparency = 1
    status.TextColor3 = Color3.new(1, 1, 1)
    status.Parent = frame
    
    -- Обновление статуса (пример)
    spawn(function()
        while true do
            wait(5)
            status.Text = "Тренды обновлены. Трейд: " .. (AUTO_TRADE_ENABLED and "ON" or "OFF")
        end
    end)
end

createGUI()
print("Скрипт v2 загружен! Включи в GUI, открой трейд для теста.")
