-- MM2 Auto Trade Script with SupremeValues Integration
-- By Grok (for educational purposes only)
-- Требует HttpService или syn.request (для executors)

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Настройки
local AUTO_TRADE_ENABLED = false
local MONITOR_INTERVAL = 30 -- Секунды между проверками цен
local PRICE_CHANGE_THRESHOLD = 0.05 -- 5% изменение для сигнала
local itemsToMonitor = { -- Добавь предметы здесь (имена из MM2)
    "Fire Tiger",
    "Brush Knife",
    "Fang Blade"
}
local priceHistory = {} -- Хранение истории: {item = {prices = {}, times = {}}}

-- Функция для fetch цен с supremevalues.com (адаптировано; endpoint может быть /api/items?type=godly)
local function fetchItemValue(itemName)
    local success, response = pcall(function()
        -- Для executors используй syn.request; для Roblox - HttpService:GetAsync
        if syn then
            local res = syn.request({
                Url = "https://supremevalues.com/api/items?search=" .. HttpService:UrlEncode(itemName),
                Method = "GET"
            })
            if res.StatusCode == 200 then
                local data = HttpService:JSONDecode(res.Body)
                return data.value or data.price or 0 -- Адаптируй под структуру JSON (обычно {value: number})
            end
        else
            -- Fallback для HttpService (включи в Studio)
            local url = "https://supremevalues.com/api/items?search=" .. HttpService:UrlEncode(itemName)
            local data = HttpService:JSONDecode(HttpService:GetAsync(url))
            return data.value or 0
        end
        return 0
    end)
    if success then
        return response
    else
        warn("Ошибка fetch: " .. tostring(response))
        return 0
    end
end

-- Функция для анализа тренда (рост/падение)
local function analyzeTrend(itemName)
    if not priceHistory[itemName] or #priceHistory[itemName].prices < 2 then
        local currentPrice = fetchItemValue(itemName)
        if currentPrice > 0 then
            priceHistory[itemName] = {prices = {currentPrice}, times = {tick()}}
        end
        return "stable" -- Нет данных для тренда
    end
    
    local prices = priceHistory[itemName].prices
    local currentPrice = fetchItemValue(itemName)
    table.insert(prices, 1, currentPrice) -- Добавляем новую цену в начало
    if #prices > 10 then table.remove(prices) end -- Храним последние 10
    
    local oldPrice = prices[#prices]
    local change = (currentPrice - oldPrice) / oldPrice
    
    if change > PRICE_CHANGE_THRESHOLD then
        return "rising" -- Растёт, стоит трейдить
    elseif change < -PRICE_CHANGE_THRESHOLD then
        return "falling" -- Падает, не трейдить
    else
        return "stable"
    end
end

-- Функция для чата рекомендации (add/no)
local function chatRecommendation(itemName, trend)
    local message = ""
    if trend == "rising" then
        message = "add " .. itemName .. " (цена растёт!)"
    elseif trend == "falling" then
        message = "no " .. itemName .. " (цена падает!)"
    else
        message = "stable " .. itemName
    end
    game:GetService("ReplicatedStorage").DefaultChatSystemChatEvents.SayMessageRequest:FireServer(message, "All")
end

-- Симуляция авто-трейда (здесь логика для "win": сравни ценности в текущем трейде)
-- Предполагаем, что у тебя есть доступ к trade GUI; адаптируй под игру
local function autoTradeLogic()
    if not AUTO_TRADE_ENABLED then return end
    
    -- Пример: мониторим все предметы
    for _, itemName in ipairs(itemsToMonitor) do
        local trend = analyzeTrend(itemName)
        chatRecommendation(itemName, trend)
        
        -- Логика "win": если тренд rising и твоя сторона выигрывает (пример расчёта)
        -- В реальности: получи предметы из trade window via findFirstChild или RemoteEvents
        local myTradeValue = 0 -- Рассчитай ценность твоих предметов
        local theirTradeValue = 0 -- Их ценность
        for item in myTradeItems do -- Псевдокод
            myTradeValue += fetchItemValue(item.Name)
        end
        -- Аналогично для their
        if trend == "rising" and myTradeValue > theirTradeValue * 1.1 then
            -- Авто-accept (адаптируй: fire RemoteEvent для accept)
            -- game.ReplicatedStorage.TradeRemote:FireServer("accept")
            chatRecommendation("WIN TRADE!", "add")
        else
            chatRecommendation("NO WIN", "no")
        end
    end
end

-- GUI для toggle
local function createGUI()
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "AutoTradeGUI"
    screenGui.Parent = playerGui
    
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 200, 0, 100)
    frame.Position = UDim2.new(0, 10, 0, 10)
    frame.BackgroundColor3 = Color3.new(0, 0, 0)
    frame.Parent = screenGui
    
    local toggleButton = Instance.new("TextButton")
    toggleButton.Size = UDim2.new(1, 0, 0.5, 0)
    toggleButton.Position = UDim2.new(0, 0, 0, 0)
    toggleButton.Text = "Auto Trade: OFF"
    toggleButton.BackgroundColor3 = Color3.new(1, 0, 0)
    toggleButton.Parent = frame
    
    local statusLabel = Instance.new("TextLabel")
    statusLabel.Size = UDim2.new(1, 0, 0.5, 0)
    statusLabel.Position = UDim2.new(0, 0, 0.5, 0)
    statusLabel.Text = "Мониторинг: Запуск..."
    statusLabel.BackgroundTransparency = 1
    statusLabel.TextColor3 = Color3.new(1, 1, 1)
    statusLabel.Parent = frame
    
    toggleButton.MouseButton1Click:Connect(function()
        AUTO_TRADE_ENABLED = not AUTO_TRADE_ENABLED
        toggleButton.Text = "Auto Trade: " .. (AUTO_TRADE_ENABLED and "ON" or "OFF")
        toggleButton.BackgroundColor3 = AUTO_TRADE_ENABLED and Color3.new(0, 1, 0) or Color3.new(1, 0, 0)
        statusLabel.Text = AUTO_TRADE_ENABLED and "Авто-трейд включён" or "Авто-трейд выключён"
    end)
end

-- Основной loop
spawn(function()
    createGUI()
    while true do
        wait(MONITOR_INTERVAL)
        autoTradeLogic()
    end
end)

print("Скрипт загружен! Нажми кнопку в GUI для toggle.")
