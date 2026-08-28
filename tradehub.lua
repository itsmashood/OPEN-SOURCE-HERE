local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")
local API = ReplicatedStorage:WaitForChild("API")

if type(getconnections) ~= "function" then
    return
end

if type(getupvalues) ~= "function" then
    return
end

local ClientData = require(
    ReplicatedStorage
        :WaitForChild("ClientModules")
        :WaitForChild("Core")
        :WaitForChild("ClientData")
)

local okInventory, inventory = pcall(function()
    return ClientData.get("inventory")
end)

if not okInventory or type(inventory) ~= "table" then
    return
end

local toys = inventory.toys

if type(toys) ~= "table" then
    return
end

local phoneUnique

for key, item in pairs(toys) do
    if type(item) == "table"
        and (
            item.id == "trade_hub_2026_trade_phone"
            or item.kind == "trade_hub_2026_trade_phone"
        ) then
        phoneUnique = tostring(item.unique or key)
        break
    end
end

if not phoneUnique then
    return
end

local EquipRemote = API:WaitForChild("ToolAPI/Equip")

local function getEquippedPhone()
    local character = Player.Character

    if not character then
        return
    end

    for _, tool in ipairs(character:GetChildren()) do
        if tool:IsA("Tool") then
            local unique = tool:FindFirstChild("unique")

            if unique and tostring(unique.Value) == phoneUnique then
                return tool
            end
        end
    end
end

if not getEquippedPhone() then
    pcall(function()
        EquipRemote:InvokeServer(
            phoneUnique,
            {
                equip_as_last = false,
                use_sound_delay = false
            }
        )
    end)
end

local started = os.clock()

while not getEquippedPhone() and os.clock() - started < 6 do
    task.wait(0.1)
end

if not getEquippedPhone() then
    return
end

local Hotbar =
    PlayerGui
        :WaitForChild("ToolApp")
        :WaitForChild("Frame")
        :WaitForChild("Hotbar")

local function getActiveToolButton()
    for _, obj in ipairs(Hotbar:GetDescendants()) do
        if obj:IsA("GuiButton")
            and obj.Name == "Tool"
            and obj.AbsoluteSize.X >= 50
            and obj.AbsoluteSize.Y >= 50 then

            local connections = getconnections(obj.MouseButton1Down)

            if #connections > 0
                and type(connections[1].Function) == "function" then
                return obj
            end
        end
    end
end

local phoneButton

started = os.clock()

repeat
    phoneButton = getActiveToolButton()

    if phoneButton then
        break
    end

    task.wait(0.1)
until os.clock() - started > 6

if not phoneButton then
    return
end

local function getReadyPhoneApp()
    local app = PlayerGui:FindFirstChild("TradePhoneApp")

    if app and app:FindFirstChild("Frame") then
        return app
    end
end

local app = getReadyPhoneApp()

if not app then
    local attempts = 0

    while attempts < 3 and not app do
        attempts += 1

        local connections = getconnections(phoneButton.MouseButton1Down)
        local handler = connections[1] and connections[1].Function

        if type(handler) ~= "function" then
            return
        end

        local success = pcall(handler)

        if not success then
            return
        end

        local waitStarted = os.clock()

        repeat
            app = getReadyPhoneApp()

            if app then
                break
            end

            task.wait(0.05)
        until os.clock() - waitStarted > 1.5
    end
end

if not app then
    return
end

local travelButton

for _, obj in ipairs(app:GetDescendants()) do
    if obj:IsA("GuiButton") and obj.Parent then
        local parentName = tostring(obj.Parent.Name):upper()

        if parentName:find("TRAVEL", 1, true) then
            travelButton = obj
            break
        end
    end
end

if not travelButton then
    return
end

local travelConnections = getconnections(travelButton.MouseButton1Click)

if #travelConnections == 0 then
    return
end

local travelWrapper = travelConnections[1].Function

if type(travelWrapper) ~= "function" then
    return
end

local travelState

for _, value in pairs(getupvalues(travelWrapper)) do
    if type(value) == "table"
        and type(value.props) == "table"
        and type(value.props.mouse_button1_click) == "function" then
        travelState = value
        break
    end
end

if not travelState then
    return
end

local realTravelCallback

for _, value in pairs(getupvalues(travelState.props.mouse_button1_click)) do
    if type(value) == "table"
        and type(value.current) == "function" then
        realTravelCallback = value.current
        break
    end
end

if not realTravelCallback then
    return
end

local travelSuccess = pcall(realTravelCallback)

if not travelSuccess then
    return
end

local dialogButtons

started = os.clock()

repeat
    local dialogApp = PlayerGui:FindFirstChild("DialogApp")
    local dialog = dialogApp and dialogApp:FindFirstChild("Dialog")
    local normal = dialog and dialog:FindFirstChild("NormalDialog")

    dialogButtons = normal and normal:FindFirstChild("Buttons")

    if dialogButtons then
        break
    end

    task.wait(0.05)
until os.clock() - started > 5

if not dialogButtons then
    return
end

local function getButtonText(button)
    for _, obj in ipairs(button:GetDescendants()) do
        if obj:IsA("TextLabel") or obj:IsA("TextButton") then
            local text =
                tostring(obj.Text or "")
                    :gsub("^%s+", "")
                    :gsub("%s+$", "")

            if text ~= "" then
                return text
            end
        end
    end

    return ""
end

local yesButton

for _, button in ipairs(dialogButtons:GetChildren()) do
    if button:IsA("GuiButton") then
        if getButtonText(button):lower() == "yes" then
            yesButton = button
            break
        end
    end
end

if not yesButton then
    return
end

local yesConnections = getconnections(yesButton.MouseButton1Click)

if #yesConnections == 0 then
    return
end

local yesWrapper = yesConnections[1].Function

if type(yesWrapper) ~= "function" then
    return
end

local yesState

for _, value in pairs(getupvalues(yesWrapper)) do
    if type(value) == "table"
        and value.state == "normal"
        and type(value.mouse_button1_click) == "function" then
        yesState = value
        break
    end
end

if not yesState then
    return
end

pcall(yesState.mouse_button1_click)
