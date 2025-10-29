-- MM2 Auto Trade Script v5 - Enhanced Version
-- ВНИМАНИЕ: Использование может привести к бану! Только для образовательных целей.

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Настройки
local AUTO_TRADE_ENABLED = false
local AUTO_ADD_ENABLED = false
local AUTO_ADD_ITEM = "Fire Tiger"
local MONITOR_INTERVAL = 30
local TRADE_CHECK_INTERVAL = 3
local PRICE_CHANGE_THRESHOLD = 0.05
local WIN_THRESHOLD = 1.1
local itemsToMonitor = {"Fire Tiger", "Brush Knife", "Fang Blade", "Icebreaker", "Luger"}
local priceHistory = {}
local itemValues = {}
local lastCacheUpdate = 0
local CACHE_DURATION = 300

-- Улучшенная функция получения цен с mm2values
local function fetchItemValue(itemName)
    local now = tick()
    local cachedName = itemName:lower():gsub("%s+", " "):gsub("[^%w%s]", "")
    
    -- Используем кэш если он свежий
    if itemValues[cachedName] and (now - lastCacheUpdate) < CACHE_DURATION then
        return itemValues[cachedName] or 0
    end
    
    local success, result = pcall(function()
        -- Основной источник: mm2values
        local url = "https://www.mm2values.com/?p=godly"
        local response
        
        if syn and syn.request then
            response = syn.request({
                Url = url,
                Method = "GET",
                Headers = {
                    ["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
                }
            })
        else
            response = game:HttpGetAsync(url)
        end
        
        if response and response.StatusCode == 200 then
            local html = response.Body
            
            -- Улучшенный парсинг таблицы цен
            for itemRow in html:gmatch('<tr[^>]*>(.-)</tr>') do
                local itemNameMatch = itemRow:match('<td[^>]*>([^<]+)</td>')
                local valueMatch = itemRow:match('<td[^>]*class="value"[^>]*>([^<]+)</td>') or 
                                 itemRow:match('<td[^>]*>%s*(%d+)%s*</td>')
                
                if itemNameMatch and valueMatch then
                    local cleanName = itemNameMatch:lower():gsub("%s+", " "):gsub("[^%w%s]", "")
                    local value = tonumber(valueMatch:gsub(",", ""):gsub("%$", ""))
                    
                    if value and cleanName ~= "" then
                        itemValues[cleanName] = value
                    end
                end
            end
            
            lastCacheUpdate = now
            return itemValues[cachedName] or 0
        end
        
        return 0
    end)
    
    if not success then
        warn("Ошибка получения цены для " .. itemName .. ": " .. tostring(result))
        return 0
    end
    
    return result or 0
end

-- Анализ тренда цен
local function analyzeTrend(itemName)
    local currentPrice = fetchItemValue(itemName)
    if currentPrice == 0 then return "unknown" end
    
    local cachedName = itemName:lower():gsub("%s+", " "):gsub("[^%w%s]", "")
    
    if not priceHistory[cachedName] then
        priceHistory[cachedName] = {prices = {currentPrice}, timestamps = {tick()}}
        return "stable"
    end
    
    local history = priceHistory[cachedName]
    table.insert(history.prices, 1, currentPrice)
    table.insert(history.timestamps, 1, tick())
    
    -- Храним только последние 20 значений
    if #history.prices > 20 then
        table.remove(history.prices)
        table.remove(history.timestamps)
    end
    
    -- Анализ изменения цены
    if #history.prices >= 2 then
        local oldestPrice = history.prices[#history.prices]
        if oldestPrice > 0 then
            local change = (currentPrice - oldestPrice) / oldestPrice
            
            if change > PRICE_CHANGE_THRESHOLD then 
                return "rising", change
            elseif change < -PRICE_CHANGE_THRESHOLD then 
                return "falling", change
            else 
                return "stable", change
            end
        end
    end
    
    return "stable", 0
end

-- Отправка сообщений в чат
local function chatMessage(msg)
    pcall(function()
        ReplicatedStorage.DefaultChatSystemChatEvents.SayMessageRequest:FireServer(msg, "All")
    end)
end

-- Поиск элементов интерфейса
local function findTradeElement(namePattern, className)
    className = className or "TextButton"
    
    -- Ищем в основном GUI торговли
    local tradeGuis = {
        playerGui:FindFirstChild("TradeGui"),
        playerGui:FindFirstChild("TradingGui"),
        playerGui:FindFirstChild("TradeWindow"),
        playerGui:FindFirstChild("TradeFrame")
    }
    
    for _, tradeGui in pairs(tradeGuis) do
        if tradeGui and tradeGui.Visible then
            for _, descendant in pairs(tradeGui:GetDescendants()) do
                if descendant:IsA(className) then
                    local text = descendant.Text or descendant.Name or ""
                    if text:lower():find(namePattern:lower()) then
                        return descendant
                    end
                end
            end
        end
    end
    
    return nil
end

-- Расчет стоимости предметов в торговле
local function calculateTradeValue(side)
    local total = 0
    local itemCount = 0
    
    if side then
        for _, element in pairs(side:GetDescendants()) do
            if element:IsA("TextLabel") or element:IsA("TextButton") then
                local text = element.Text
                if text and text ~= "" and not text:match("^%d+$") then
                    local value = fetchItemValue(text)
                    if value > 0 then
                        total = total + value
                        itemCount = itemCount + 1
                    end
                end
            end
        end
    end
    
    return total, itemCount
end

-- Основная функция автоматической торговли
local function autoTradeCheck()
    if not AUTO_TRADE_ENABLED then return end
    
    -- Проверяем активна ли торговля
    local tradeGui = playerGui:FindFirstChild("TradeGui") or 
                    playerGui:FindFirstChild("TradingGui") or 
                    playerGui:FindFirstChild("TradeWindow")
    
    if not tradeGui or not tradeGui.Visible then
        return
    end
    
    -- Анализ трендов и отчет в чат
    for _, item in ipairs(itemsToMonitor) do
        local trend, change = analyzeTrend(item)
        if trend ~= "unknown" then
            local changePercent = math.floor((change or 0) * 100)
            local message = string.format("%s: %s (%d%%)", item, trend, changePercent)
            chatMessage(message)
        end
    end
    
    -- Находим стороны торговли
    local mySide = findTradeElement("my", "Frame") or findTradeElement("left", "Frame")
    local otherSide = findTradeElement("other", "Frame") or findTradeElement("right", "Frame")
    
    local myValue, myItems = calculateTradeValue(mySide)
    local otherValue, otherItems = calculateTradeValue(otherSide)
    
    -- Логируем значения
    print(string.format("Мои предметы: %d (стоимость: %d)", myItems, myValue))
    print(string.format("Предметы оппонента: %d (стоимость: %d)", otherItems, otherValue))
    
    -- Принимаем решение о торговле
    local shouldAccept = false
    local reason = ""
    
    if myValue > 0 and otherValue > 0 then
        local ratio = otherValue / myValue
        
        if ratio >= WIN_THRESHOLD then
            shouldAccept = true
            reason = string.format("WIN - выгода: +%d%%", math.floor((ratio - 1) * 100))
        else
            reason = string.format("LOSE - проигрыш: -%d%%", math.floor((1 - ratio) * 100))
        end
        
        -- Отправляем сообщение в чат
        chatMessage(string.format("Трейд: Я=%d, Он=%d - %s", myValue, otherValue, reason))
        
        -- Нажимаем соответствующие кнопки
        if shouldAccept then
            local acceptBtn = findTradeElement("accept") or findTradeElement("confirm")
            if acceptBtn then
                pcall(function()
                    if firesignal then
                        firesignal(acceptBtn.Activated)
                    else
                        acceptBtn:Fire("Activated")
                    end
                end)
                chatMessage("add Принимаю трейд!")
            end
        else
            local declineBtn = findTradeElement("decline") or findTradeElement("cancel")
            if declineBtn then
                pcall(function()
                    if firesignal then
                        firesignal(declineBtn.Activated)
                    else
                        declineBtn:Fire("Activated")
                    end
                end)
                chatMessage("no Отказываюсь от трейда")
            end
        end
    end
end

-- Автоматическое добавление предметов
local function autoAddItemToTrade()
    if not AUTO_ADD_ENABLED or not AUTO_TRADE_ENABLED then return end
    
    local tradeGui = playerGui:FindFirstChild("TradeGui") or playerGui:FindFirstChild("TradingGui")
    if not tradeGui or not tradeGui.Visible then return end
    
    -- Проверяем тренд предмета
    local trend = analyzeTrend(AUTO_ADD_ITEM)
    if trend == "falling" then
        chatMessage("no " .. AUTO_ADD_ITEM .. " - цена падает!")
        return
    end
    
    -- Ищем предмет в инвентаре
    local backpack = player:FindFirstChild("Backpack")
    if backpack then
        for _, item in pairs(backpack:GetChildren()) do
            if item.Name:lower() == AUTO_ADD_ITEM:lower() then
                -- Пытаемся добавить предмет в торговлю
                pcall(function()
                    -- Попытка через remote events
                    local tradeRemote = ReplicatedStorage:FindFirstChild("TradeItem") or 
                                      ReplicatedStorage:FindFirstChild("AddItemToTrade")
                    if tradeRemote then
                        tradeRemote:FireServer(item)
                        chatMessage("add " .. AUTO_ADD_ITEM .. " - добавляю в трейд!")
                    end
                end)
                break
            end
        end
    end
end

-- Создание интерфейса
local function createGUI()
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "MM2AutoTradeV5"
    screenGui.Parent = playerGui
    
    local mainFrame = Instance.new("Frame")
    mainFrame.Size = UDim2.new(0, 300, 0, 350)
    mainFrame.Position = UDim2.new(0, 10, 0, 10)
    mainFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
    mainFrame.BorderSizePixel = 0
    mainFrame.Parent = screenGui
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = mainFrame
    
    -- Заголовок
    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0, 40)
    title.Position = UDim2.new(0, 0, 0, 0)
    title.Text = "MM2 Auto Trade v5"
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
    title.TextSize = 16
    title.Font = Enum.Font.GothamBold
    title.Parent = mainFrame
    
    local titleCorner = Instance.new("UICorner")
    titleCorner.CornerRadius = UDim.new(0, 8)
    titleCorner.Parent = title
    
    -- Кнопка включения/выключения автотрейда
    local toggleTradeBtn = Instance.new("TextButton")
    toggleTradeBtn.Size = UDim2.new(0.9, 0, 0, 40)
    toggleTradeBtn.Position = UDim2.new(0.05, 0, 0, 50)
    toggleTradeBtn.Text = "Автотрейд: ВЫКЛ"
    toggleTradeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    toggleTradeBtn.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
    toggleTradeBtn.TextSize = 14
    toggleTradeBtn.Font = Enum.Font.Gotham
    toggleTradeBtn.Parent = mainFrame
    
    local btnCorner = Instance.new("UICorner")
    btnCorner.CornerRadius = UDim.new(0, 6)
    btnCorner.Parent = toggleTradeBtn
    
    toggleTradeBtn.MouseButton1Click:Connect(function()
        AUTO_TRADE_ENABLED = not AUTO_TRADE_ENABLED
        if AUTO_TRADE_ENABLED then
            toggleTradeBtn.Text = "Автотрейд: ВКЛ"
            toggleTradeBtn.BackgroundColor3 = Color3.fromRGB(60, 200, 80)
            chatMessage("Автотрейд активирован!")
        else
            toggleTradeBtn.Text = "Автотрейд: ВЫКЛ"
            toggleTradeBtn.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
            chatMessage("Автотрейд деактивирован!")
        end
    end)
    
    -- Кнопка авто-добавления
    local toggleAddBtn = Instance.new("TextButton")
    toggleAddBtn.Size = UDim2.new(0.9, 0, 0, 40)
    toggleAddBtn.Position = UDim2.new(0.05, 0, 0, 100)
    toggleAddBtn.Text = "Авто-добавление: ВЫКЛ"
    toggleAddBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    toggleAddBtn.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
    toggleAddBtn.TextSize = 14
    toggleAddBtn.Font = Enum.Font.Gotham
    toggleAddBtn.Parent = mainFrame
    btnCorner:Clone().Parent = toggleAddBtn
    
    toggleAddBtn.MouseButton1Click:Connect(function()
        AUTO_ADD_ENABLED = not AUTO_ADD_ENABLED
        if AUTO_ADD_ENABLED then
            toggleAddBtn.Text = "Авто-добавление: ВКЛ"
            toggleAddBtn.BackgroundColor3 = Color3.fromRGB(60, 200, 80)
        else
            toggleAddBtn.Text = "Авто-добавление: ВЫКЛ"
            toggleAddBtn.BackgroundColor3 = Color3.fromRGB(200, 60, 60)
        end
    end)
    
    -- Статус
    local statusLabel = Instance.new("TextLabel")
    statusLabel.Size = UDim2.new(0.9, 0, 0, 60)
    statusLabel.Position = UDim2.new(0.05, 0, 0, 150)
    statusLabel.Text = "Статус: Ожидание...\nКэш: 0 предметов"
    statusLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
    statusLabel.BackgroundTransparency = 1
    statusLabel.TextSize = 12
    statusLabel.TextWrapped = true
    statusLabel.Font = Enum.Font.Gotham
    statusLabel.Parent = mainFrame
    
    -- Кнопка обновления цен
    local refreshBtn = Instance.new("TextButton")
    refreshBtn.Size = UDim2.new(0.9, 0, 0, 35)
    refreshBtn.Position = UDim2.new(0.05, 0, 0, 220)
    refreshBtn.Text = "Обновить цены"
    refreshBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    refreshBtn.BackgroundColor3 = Color3.fromRGB(80, 120, 200)
    refreshBtn.TextSize = 14
    refreshBtn.Font = Enum.Font.Gotham
    refreshBtn.Parent = mainFrame
    btnCorner:Clone().Parent = refreshBtn
    
    refreshBtn.MouseButton1Click:Connect(function()
        lastCacheUpdate = 0
        chatMessage("Обновляю цены...")
    end)
    
    -- Дебаг кнопка
    local debugBtn = Instance.new("TextButton")
    debugBtn.Size = UDim2.new(0.9, 0, 0, 35)
    debugBtn.Position = UDim2.new(0.05, 0, 0, 265)
    debugBtn.Text = "Дебаг интерфейса"
    debugBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    debugBtn.BackgroundColor3 = Color3.fromRGB(120, 80, 160)
    debugBtn.TextSize = 14
    debugBtn.Font = Enum.Font.Gotham
    debugBtn.Parent = mainFrame
    btnCorner:Clone().Parent = debugBtn
    
    debugBtn.MouseButton1Click:Connect(function()
        print("=== ДЕБАГ ИНТЕРФЕЙСА ===")
        for _, gui in pairs(playerGui:GetChildren()) do
            print("GUI: " .. gui.Name .. " (Visible: " .. tostring(gui.Visible) .. ")")
        end
        chatMessage("Дебаг завершен - проверьте F9")
    end)
    
    -- Обновление статуса
    spawn(function()
        while true do
            wait(5)
            local statusText = string.format("Статус: %s\nКэш: %d предметов", 
                AUTO_TRADE_ENABLED and "Активен" or "Неактивен",
                table.count(itemValues))
            statusLabel.Text = statusText
        end
    end)
end

-- Запуск основных циклов
spawn(function()
    while true do
        wait(TRADE_CHECK_INTERVAL)
        pcall(autoTradeCheck)
    end
end)

spawn(function()
    while true do
        wait(MONITOR_INTERVAL)
        pcall(function()
            for _, item in ipairs(itemsToMonitor) do
                analyzeTrend(item)
            end
        end)
    end
end)

-- Инициализация
createGUI()
print("MM2 Auto Trade v5 загружен! Используйте интерфейс для управления.")

-- Предупреждение
warn("ВНИМАНИЕ: Использование автотрейда может привести к бану! Используйте на свой страх и риск.")
