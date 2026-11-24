--[=[
    MinhDZ Hub | Blox Fruits Main
    Standalone, modular Farm Level based on the supplied KaitunBF source.

    Implemented independent features:
      * Farm Level
      * Bring Mob (shared farm-target controller)
      * Selectable weapon category + weapon lock
      * Smooth flight + persistent hover above the target
      * Auto Buso (Haki)
      * Auto Sea Travel (unlock requirements still apply)

    Notes:
      * The script waits for a Pirates/Marines team before creating any hub UI.
      * Farm Level is OFF by default.
      * Each feature has its own running flag/token.
      * Disabling Farm Level cancels its active flight and does not stop other features.
      * Bring Mob restores NPC state and does not force hidden SimulationRadius properties.
      * No global namecall hooks, hidden-property edits, anti-cheat bypass hooks,
        automatic server hopping, or unrelated Kaitun task orchestration are copied.
]=]

--// Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer

--// Environment / re-execution cleanup
local ENV = (type(getgenv) == "function" and getgenv()) or _G
if ENV.MinhDZBloxFruitsHub and type(ENV.MinhDZBloxFruitsHub.Unload) == "function" then
    pcall(ENV.MinhDZBloxFruitsHub.Unload)
end

--// Startup faction gate
-- The Fluent menu and floating button are not created until a real team is assigned.
-- Change ENV.MinhDZPreferredTeam to "Marines" before execution to prefer Marines.
local STARTUP_PREFERRED_TEAM = ENV.MinhDZPreferredTeam
if STARTUP_PREFERRED_TEAM ~= "Pirates" and STARTUP_PREFERRED_TEAM ~= "Marines" then
    STARTUP_PREFERRED_TEAM = "Pirates"
end
local STARTUP_AUTO_JOIN_TEAM = ENV.MinhDZAutoJoinTeam ~= false

local function getCurrentTeamName()
    local team = LocalPlayer.Team
    return team and team.Name or nil
end

local function hasSelectedTeam()
    local teamName = getCurrentTeamName()
    return teamName == "Pirates" or teamName == "Marines"
end

local function waitForInitialGameReady(timeout)
    local deadline = os.clock() + timeout
    while os.clock() < deadline do
        if game:IsLoaded() and LocalPlayer:FindFirstChild("DataLoaded") then
            return true
        end
        task.wait(0.2)
    end
    return false
end

print("[MinhDZ Hub] Waiting for Blox Fruits to load...")
if not waitForInitialGameReady(120) then
    warn("[MinhDZ Hub] Game data did not finish loading. Main menu was not opened.")
    return
end

local startupPlayerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
if startupPlayerGui then
    local loadingDeadline = os.clock() + 45
    while startupPlayerGui:FindFirstChild("LoadingScreen") and os.clock() < loadingDeadline do
        task.wait(0.2)
    end
end

if not hasSelectedTeam() then
    print("[MinhDZ Hub] Waiting for Pirates/Marines selection...")
    local startupCommF = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CommF_")
    local teamDeadline = os.clock() + 90
    local nextTeamRequest = 0
    local requestPending = false

    while not hasSelectedTeam() and os.clock() < teamDeadline do
        if STARTUP_AUTO_JOIN_TEAM and not requestPending and os.clock() >= nextTeamRequest then
            requestPending = true
            nextTeamRequest = os.clock() + 1.5
            task.spawn(function()
                local ok, result = pcall(function()
                    return startupCommF:InvokeServer("SetTeam", STARTUP_PREFERRED_TEAM)
                end)
                if not ok then
                    warn("[MinhDZ Hub] SetTeam request failed: " .. tostring(result))
                end
                requestPending = false
            end)
        end
        task.wait(0.15)
    end
end

if not hasSelectedTeam() then
    warn("[MinhDZ Hub] No faction was selected. Choose Pirates or Marines in the game, then execute MinhDZ Hub again. Main menu remains closed.")
    return
end

-- Wait briefly for the selected faction's character to finish spawning.
local characterDeadline = os.clock() + 45
while os.clock() < characterDeadline do
    local character = LocalPlayer.Character
    if character and character:FindFirstChild("HumanoidRootPart") then
        break
    end
    task.wait(0.2)
end

--// Fluent UI (created only after the team-selection gate has passed)
local FLUENT_URL = "https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"
local Fluent = loadstring(game:HttpGet(FLUENT_URL))()

local Window = Fluent:CreateWindow({
    Title = "MinhDZ Hub | Blox Fruits",
    SubTitle = "Modular Main",
    TabWidth = 150,
    Size = UDim2.fromOffset(610, 500),
    Acrylic = false,
    Theme = "Dark",
    -- Fluent's own minimize handler is the single source of truth.
    -- Unknown is unsafe here: mouse clicks also carry KeyCode.Unknown.
    MinimizeKey = Enum.KeyCode.RightControl
})

local Tabs = {
    Farming = Window:AddTab({ Title = "Farming", Icon = "swords" }),
    Utility = Window:AddTab({ Title = "Utility", Icon = "zap" }),
    Travel = Window:AddTab({ Title = "Travel", Icon = "map" }),
    Settings = Window:AddTab({ Title = "Settings", Icon = "settings" })
}

--// Independent floating menu control (keeps working while Fluent is hidden).
local FloatingGui = Instance.new("ScreenGui")
FloatingGui.Name = "MinhDZHubFloatingToggle"
FloatingGui.ResetOnSpawn = false
FloatingGui.IgnoreGuiInset = true
FloatingGui.DisplayOrder = 100000
FloatingGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local floatingParent
pcall(function()
    floatingParent = game:GetService("CoreGui")
end)
local parentedToCoreGui = false
if floatingParent then
    parentedToCoreGui = pcall(function()
        FloatingGui.Parent = floatingParent
    end)
end
if not parentedToCoreGui then
    FloatingGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
end

local ToggleButton = Instance.new("TextButton")
ToggleButton.Name = "MenuToggle"
ToggleButton.AnchorPoint = Vector2.new(0, 0.5)
ToggleButton.Position = UDim2.new(0, 16, 0.5, 0)
ToggleButton.Size = UDim2.fromOffset(116, 42)
ToggleButton.BackgroundColor3 = Color3.fromRGB(23, 18, 34)
ToggleButton.BackgroundTransparency = 0.08
ToggleButton.BorderSizePixel = 0
ToggleButton.AutoButtonColor = true
ToggleButton.Font = Enum.Font.GothamBold
ToggleButton.Text = "MZ  ·  HIDE"
ToggleButton.TextColor3 = Color3.fromRGB(205, 174, 255)
ToggleButton.TextSize = 12
ToggleButton.ZIndex = 10
ToggleButton.Parent = FloatingGui

local ToggleCorner = Instance.new("UICorner")
ToggleCorner.CornerRadius = UDim.new(0, 9)
ToggleCorner.Parent = ToggleButton

local ToggleStroke = Instance.new("UIStroke")
ToggleStroke.Color = Color3.fromRGB(157, 111, 225)
ToggleStroke.Thickness = 1.2
ToggleStroke.Transparency = 0.18
ToggleStroke.Parent = ToggleButton

local function syncMenuToggleLabel()
    local visible = Window.Root and Window.Root.Visible == true
    ToggleButton.Text = visible and "MZ  ·  HIDE" or "MZ  ·  OPEN"
    ToggleButton.TextColor3 = visible
        and Color3.fromRGB(205, 174, 255)
        or Color3.fromRGB(165, 245, 195)
end

local function setMenuVisible(visible)
    if not Window.Root then
        return
    end
    visible = visible == true
    if Window.Root.Visible ~= visible then
        -- Use Fluent's own method so Window.Minimized and Root.Visible stay in sync.
        Window:Minimize()
    end
    syncMenuToggleLabel()
end

-- Fluent handles RightControl itself. This listener only refreshes the floating label;
-- it deliberately does not toggle a second time.
local toggleInputConnection = UserInputService.InputBegan:Connect(function(input)
    if input.KeyCode == Enum.KeyCode.RightControl then
        task.defer(syncMenuToggleLabel)
    end
end)

ToggleButton.Activated:Connect(function()
    setMenuVisible(not (Window.Root and Window.Root.Visible == true))
end)

--// Game remotes / modules used by the source script
local RemotesFolder = ReplicatedStorage:WaitForChild("Remotes")
local CommF = RemotesFolder:WaitForChild("CommF_")
local NetFolder = ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Net")
local RegisterAttack = NetFolder:WaitForChild("RE/RegisterAttack")
local RegisterHit = NetFolder:WaitForChild("RE/RegisterHit")

local GlobalModule
local function getGlobalModule()
    if not GlobalModule then
        pcall(function()
            GlobalModule = require(ReplicatedStorage:WaitForChild("Global", 10))
        end)
    end
    return GlobalModule
end

local QuestModule
local GuideModule
local function getQuestModule()
    if not QuestModule then
        local ok, result = pcall(require, ReplicatedStorage:WaitForChild("Quests"))
        if ok and type(result) == "table" then
            QuestModule = result
        end
    end
    return QuestModule
end

local function getGuideModule()
    if not GuideModule then
        local ok, result = pcall(require, ReplicatedStorage:WaitForChild("GuideModule"))
        if ok and type(result) == "table" then
            GuideModule = result
        end
    end
    return GuideModule
end

--// State
local Hub = {
    Unloading = false,
    Features = {
        FarmLevel = { Enabled = false, Token = 0 },
        AutoEquipMelee = { Enabled = false, Token = 0 },
        AutoBuso = { Enabled = false, Token = 0 },
        AutoSeaTravel = { Enabled = false, Token = 0 }
    },
    Settings = {
        FlightSpeed = 75,
        AttackHeight = 18,
        AttackInterval = 0.18,
        WeaponCategory = "Melee",
        FruitSkill = "Z",
        BringRadius = 220,
        PreferredTeam = STARTUP_PREFERRED_TEAM,
        AutoJoinTeam = STARTUP_AUTO_JOIN_TEAM
    },
    Status = "Ready",
    LastFarmQuestStart = 0,
    LastSeaTravel = 0,
    LastSeaCheck = 0,
    LastBusoCheck = 0,
    LastEquipCheck = 0,
    MismatchCount = 0,
    MovementToken = 0,
    MovementObjects = {},
    SavedCollision = {},
    Hover = { Connection = nil, Position = nil, Gyro = nil, TargetRoot = nil, Character = nil, Humanoid = nil, AutoRotate = nil },
    FarmTarget = nil,
    SharedBring = { Enabled = false, Token = 0 },
    BroughtMobs = setmetatable({}, { __mode = "k" })
}

ENV.MinhDZBloxFruitsHub = Hub

local function notify(title, content, duration)
    pcall(function()
        Fluent:Notify({
            Title = title,
            Content = content,
            Duration = duration or 4
        })
    end)
end

local function setStatus(message)
    message = tostring(message)
    if Hub.Status ~= message then
        Hub.Status = message
        print("[MinhDZ Hub] " .. Hub.Status)
        local lower = message:lower()
        if lower:find("error", 1, true)
            or lower:find("unavailable", 1, true)
            or lower:find("not found", 1, true)
            or lower:find("no level quest", 1, true)
            or lower:find("rejected", 1, true) then
            notify("MinhDZ Hub diagnostics", message, 6)
        end
    end
end

local function isFeatureActive(name, token)
    local feature = Hub.Features[name]
    return feature ~= nil
        and feature.Enabled
        and feature.Token == token
        and not Hub.Unloading
        and not Fluent.Unloaded
end

--// Character helpers
local function getCharacter()
    return LocalPlayer.Character
end

local function getHumanoid()
    local character = getCharacter()
    return character and character:FindFirstChildOfClass("Humanoid")
end

local function getRoot()
    local character = getCharacter()
    return character and character:FindFirstChild("HumanoidRootPart")
end

local function getPlayerLevel()
    local data = LocalPlayer:FindFirstChild("Data")
    local level = data and data:FindFirstChild("Level")
    return level and tonumber(level.Value) or nil
end

local function getSeaIndex()
    local mapAttribute = workspace:GetAttribute("MAP")
    if mapAttribute == "Sea1" then
        return 1
    elseif mapAttribute == "Sea2" then
        return 2
    elseif mapAttribute == "Sea3" then
        return 3
    end

    -- Same PlaceId fallback table used by the supplied KaitunBF script.
    local placeMap = {
        [2753915549] = 1,
        [79091703265657] = 2,
        [4442272183] = 2,
        [100117331123089] = 3,
        [7449423635] = 3
    }
    return placeMap[game.PlaceId] or 1
end

local function stripLevelSuffix(name)
    local value = tostring(name or "")
    value = value:gsub("%s*%[Lv%.?%s*%d+%]%s*", "")
    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    return value
end

local function normalizeMobName(name)
    local value = stripLevelSuffix(name)
    value = value:gsub("^%s*[Dd][Ee][Ff][Ee][Aa][Tt]%s+%d+%s+", "")
    value = value:gsub("%s*%(%s*%d+%s*/%s*%d+%s*%)%s*$", "")
    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    if value == "Military Soldiers" then
        value = "Military Soldier"
    end
    return value
end

local function mobNamesMatch(left, right)
    if not left or not right then
        return false
    end
    local a = normalizeMobName(left):lower()
    local b = normalizeMobName(right):lower()
    if a == b then
        return true
    end
    if #a > 1 and a:sub(-1) == "s" and a:sub(-2) ~= "ss" then
        a = a:sub(1, -2)
    end
    if #b > 1 and b:sub(-1) == "s" and b:sub(-2) ~= "ss" then
        b = b:sub(1, -2)
    end
    return a == b
end

--// Quest selection: follows the level/quest selection pattern in KaitunBF.
local BLACKLISTED_QUESTS = {
    BartiloQuest = true,
    CitizenQuest = true,
    Trainees = true,
    MarineQuest = true
}

local function selectQuestForLevel(level, sea)
    local quests = getQuestModule()
    if not quests then
        return nil, "ReplicatedStorage.Quests is unavailable"
    end

    local effectiveLevel = level
    if sea == 1 and effectiveLevel >= 700 then
        effectiveLevel = 699
    elseif sea == 2 and effectiveLevel >= 1500 then
        effectiveLevel = 1499
    end

    local best = nil
    local bestRequirement = -1

    for questId, stages in pairs(quests) do
        if not BLACKLISTED_QUESTS[questId] and type(stages) == "table" then
            for stageId, stage in pairs(stages) do
                local requiredLevel = tonumber(stage.LevelReq)
                local tasks = type(stage.Task) == "table" and stage.Task or nil

                if requiredLevel and tasks and requiredLevel <= effectiveLevel and requiredLevel >= bestRequirement then
                    for mobName, amount in pairs(tasks) do
                        local numericAmount = tonumber(amount) or 0
                        local normalizedName = normalizeMobName(mobName)
                        if numericAmount > 1
                            and normalizedName ~= "Gladiator"
                            and normalizedName ~= "Factory Staff" then
                            bestRequirement = requiredLevel
                            best = {
                                QuestId = questId,
                                StageId = stageId,
                                MobName = normalizedName,
                                LevelReq = requiredLevel,
                                QuestName = stage.Name
                            }
                        end
                    end
                end
            end
        end
    end

    if not best then
        return nil, "No level quest found for the current sea/level"
    end
    return best
end

--// Resolve quest-giver CFrame from GuideModule.Data.NPCList (same source data as KaitunBF).
local function getObjectCFrame(object)
    if typeof(object) == "CFrame" then
        return object
    elseif typeof(object) == "Vector3" then
        return CFrame.new(object)
    end
    if typeof(object) ~= "Instance" then
        return nil
    end
    if object:IsA("BasePart") then
        return object.CFrame
    elseif object:IsA("Attachment") then
        return object.WorldCFrame
    elseif object:IsA("Model") then
        local ok, pivot = pcall(function()
            return object:GetPivot()
        end)
        if ok then
            return pivot
        end
    end
    local ok, cframe = pcall(function()
        return object.CFrame
    end)
    return ok and typeof(cframe) == "CFrame" and cframe or nil
end

local function getQuestGiverCFrame(requiredLevel)
    local guide = getGuideModule()
    local npcList = guide and guide.Data and guide.Data.NPCList
    if type(npcList) ~= "table" then
        return nil
    end

    for npcObject, npcInfo in pairs(npcList) do
        if type(npcInfo) == "table" and type(npcInfo.Levels) == "table" then
            for _, levelValue in ipairs(npcInfo.Levels) do
                if tonumber(levelValue) == tonumber(requiredLevel) then
                    local npcCFrame = getObjectCFrame(npcObject)
                    if not npcCFrame then
                        npcCFrame = getObjectCFrame(npcInfo.CFrame or npcInfo.NPC or npcInfo.Position)
                    end
                    if npcCFrame then
                        return npcCFrame
                    end
                end
            end
        end
    end
    return nil
end

--// Current quest parser. Mirrors KaitunBF's TrackedQuestFrame/Main.Quest
-- paths and includes a visible-label fallback for minor GUI layout changes.
local function parseQuestMob(text)
    if type(text) ~= "string" or text == "" then
        return nil
    end

    local value = text
    value = value:gsub("^%s*[Dd][Ee][Ff][Ee][Aa][Tt]%s*%d*%s*", "")
    value = value:gsub("%s*%(%s*%d+%s*/%s*%d+%s*%)%s*$", "")
    value = value:gsub("%s+%d+%s*/%s*%d+%s*$", "")
    value = value:gsub("^%s*%d+%s+", "")
    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    value = value:gsub("^[Mm]il%.?%s*[Ss]oldier.*", "Military Soldier")
    value = value:gsub("^[Mm]il%.?%s*[Ss]py.*", "Military Spy")

    if value == "" then
        return nil
    end
    return normalizeMobName(value)
end

local function readActiveQuest()
    local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
    if not playerGui then
        return nil, nil, 0, 0
    end

    local tracked = playerGui:FindFirstChild("TrackedQuestFrame")
    if tracked and tracked.Enabled then
        local frame = tracked:FindFirstChild("Frame")
        if frame then
            local header = frame:FindFirstChild("header")
            local headerLabel = header and header:FindFirstChild("textLabel")
            local description = frame:FindFirstChild("description")
            local progressLabel = frame:FindFirstChild("progress")
            local headerText = headerLabel and headerLabel.Text or ""
            local descriptionText = description and description.Text or ""
            local titleText = headerText:match("^%s*[Dd][Ee][Ff][Ee][Aa][Tt]%s+%d") and headerText or descriptionText
            local mob = parseQuestMob(titleText)
            local current, maximum = 0, 0
            if progressLabel and progressLabel.Text ~= "" then
                local cur, max = progressLabel.Text:match("(%d+)%s*/%s*(%d+)")
                current, maximum = tonumber(cur) or 0, tonumber(max) or 0
            end
            if mob then
                return mob, titleText, current, maximum
            end
        end
    end

    local main = playerGui:FindFirstChild("Main")
    local questFrame = main and main:FindFirstChild("Quest")
    if questFrame and questFrame.Visible then
        local container = questFrame:FindFirstChild("Container")
        local titleFolder = container and container:FindFirstChild("QuestTitle")
        local title = titleFolder and titleFolder:FindFirstChild("Title")
        local titleText = title and title.Text or ""
        local mob = parseQuestMob(titleText)
        local cur, max = titleText:match("%((%d+)%s*/%s*(%d+)%)")
        if mob then
            return mob, titleText, tonumber(cur) or 0, tonumber(max) or 0
        end
    end

    -- Deep fallback: KaitunBF also searches visible text labels when the
    -- tracked-quest GUI is temporarily rebuilt by the game.
    local function isVisible(element)
        local current = element
        while current and current:IsA("GuiObject") do
            if not current.Visible then
                return false
            end
            current = current.Parent
        end
        return true
    end

    local foundMob, foundTitle, foundCurrent, foundMaximum
    local function scan(node)
        if foundMob then
            return
        end
        if (node:IsA("TextLabel") or node:IsA("TextButton") or node:IsA("TextBox")) and isVisible(node) then
            local text = node.Text
            if type(text) == "string" and text:match("^%s*[Dd][Ee][Ff][Ee][Aa][Tt]%s+%d") then
                local mob = parseQuestMob(text)
                if mob then
                    local cur, max = text:match("%((%d+)%s*/%s*(%d+)%)")
                    if not cur then
                        cur, max = text:match("(%d+)%s*/%s*(%d+)")
                    end
                    foundMob, foundTitle = mob, text
                    foundCurrent, foundMaximum = tonumber(cur) or 0, tonumber(max) or 0
                    return
                end
            end
        end
        for _, child in ipairs(node:GetChildren()) do
            if foundMob then
                return
            end
            scan(child)
        end
    end
    scan(playerGui)

    return foundMob, foundTitle, foundCurrent or 0, foundMaximum or 0
end

--// Movement: smooth BodyPosition flight with a speed-limited moving target.
-- BodyPosition does not expose a MaxVelocity property; FlightSpeed is applied by
-- advancing its Position target in bounded Heartbeat steps instead.
local function restoreCollision()
    for part, originalValue in pairs(Hub.SavedCollision) do
        if part and part.Parent then
            pcall(function()
                part.CanCollide = originalValue
            end)
        end
    end
    table.clear(Hub.SavedCollision)
end

local function disableCollisionForCharacter(character)
    if not character then
        return
    end
    for _, descendant in ipairs(character:GetDescendants()) do
        if descendant:IsA("BasePart") then
            if Hub.SavedCollision[descendant] == nil then
                Hub.SavedCollision[descendant] = descendant.CanCollide
            end
            descendant.CanCollide = false
        end
    end
end

local function destroyMovementObjects()
    for _, object in pairs(Hub.MovementObjects) do
        if object and object.Parent then
            pcall(function() object:Destroy() end)
        end
    end
    table.clear(Hub.MovementObjects)
end

local function stopHover()
    local hover = Hub.Hover
    if hover.Connection then
        pcall(function() hover.Connection:Disconnect() end)
        hover.Connection = nil
    end
    for _, object in pairs({ hover.Position, hover.Gyro }) do
        if object and object.Parent then
            pcall(function() object:Destroy() end)
        end
    end
    if hover.Humanoid and hover.Humanoid.Parent and hover.AutoRotate ~= nil then
        pcall(function() hover.Humanoid.AutoRotate = hover.AutoRotate end)
    end
    hover.Position = nil
    hover.Gyro = nil
    hover.TargetRoot = nil
    hover.Character = nil
    hover.Humanoid = nil
    hover.AutoRotate = nil
end

local function stopMovement()
    Hub.MovementToken = Hub.MovementToken + 1
    destroyMovementObjects()
    restoreCollision()
    local root = getRoot()
    if root then
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end
end

local function moveTo(targetCFrame, farmToken)
    if typeof(targetCFrame) ~= "CFrame" then
        return false
    end

    stopHover()
    Hub.MovementToken = Hub.MovementToken + 1
    local movementToken = Hub.MovementToken
    local character = getCharacter()
    local humanoid = getHumanoid()
    local root = getRoot()
    if not character or not humanoid or humanoid.Health <= 0 or not root then
        return false
    end

    destroyMovementObjects()
    disableCollisionForCharacter(character)

    local flightSpeed = math.clamp(tonumber(Hub.Settings.FlightSpeed) or 75, 35, 180)
    local startPosition = root.Position
    local targetPosition = targetCFrame.Position
    local travelVector = targetPosition - startPosition
    local initialDistance = travelVector.Magnitude
    local travelDirection = initialDistance > 0.001 and travelVector.Unit or Vector3.zero
    local travelledDistance = 0

    local positionMover = Instance.new("BodyPosition")
    positionMover.Name = "MinhDZFlightPosition"
    positionMover.MaxForce = Vector3.new(1e9, 1e9, 1e9)
    positionMover.P = 10000
    positionMover.D = 1800
    -- Start at the current position. The target advances by FlightSpeed * dt
    -- below, keeping long flights smooth without assigning unsupported members.
    positionMover.Position = startPosition
    positionMover.Parent = root

    local orientationMover = Instance.new("BodyGyro")
    orientationMover.Name = "MinhDZFlightOrientation"
    orientationMover.MaxTorque = Vector3.new(1e9, 1e9, 1e9)
    orientationMover.P = 8500
    orientationMover.D = 1200
    orientationMover.CFrame = targetCFrame
    orientationMover.Parent = root

    Hub.MovementObjects.Position = positionMover
    Hub.MovementObjects.Gyro = orientationMover

    local previousAutoRotate = humanoid.AutoRotate
    humanoid.AutoRotate = false
    local movementHumanoid = humanoid
    local movementCharacter = character
    local settledFor = 0
    local moveTimeout = math.clamp(initialDistance / flightSpeed * 3.0 + 12, 15, 120)
    local moveStartedAt = os.clock()

    while true do
        if not isFeatureActive("FarmLevel", farmToken) or movementToken ~= Hub.MovementToken then
            break
        end
        if os.clock() - moveStartedAt > moveTimeout then
            setStatus("Flight timed out; check movement/physics and try a lower Flight Speed")
            break
        end

        character = getCharacter()
        humanoid = getHumanoid()
        root = getRoot()
        if not character or not humanoid or humanoid.Health <= 0 or not root then
            break
        end
        if character ~= movementCharacter then
            break
        end
        if not positionMover.Parent or not orientationMover.Parent then
            break
        end

        local dt = RunService.Heartbeat:Wait()
        dt = math.clamp(tonumber(dt) or 0, 0, 0.1)
        travelledDistance = math.min(initialDistance, travelledDistance + flightSpeed * dt)

        local steppedPosition = startPosition + travelDirection * travelledDistance
        if travelledDistance >= initialDistance then
            steppedPosition = targetPosition
        end
        positionMover.Position = steppedPosition
        orientationMover.CFrame = targetCFrame

        local distance = (targetPosition - root.Position).Magnitude
        local speed = root.AssemblyLinearVelocity.Magnitude
        if travelledDistance >= initialDistance and distance <= 4 and speed <= 9 then
            settledFor = settledFor + dt
            if settledFor >= 0.18 then
                break
            end
        else
            settledFor = 0
        end
    end

    destroyMovementObjects()
    if movementHumanoid and movementHumanoid.Parent then
        pcall(function() movementHumanoid.AutoRotate = previousAutoRotate end)
    end
    if movementToken == Hub.MovementToken then
        restoreCollision()
    end
    return isFeatureActive("FarmLevel", farmToken) and movementToken == Hub.MovementToken
end

local function startHoverAboveTarget(targetRoot, farmToken)
    local character = getCharacter()
    local humanoid = getHumanoid()
    local playerRoot = getRoot()
    if not targetRoot or not targetRoot.Parent or not character or not humanoid or humanoid.Health <= 0 or not playerRoot then
        stopHover()
        return false
    end

    local hover = Hub.Hover
    if hover.TargetRoot == targetRoot and hover.Character == character and hover.Connection then
        return true
    end

    stopHover()
    local positionMover = Instance.new("BodyPosition")
    positionMover.Name = "MinhDZFarmHoverPosition"
    positionMover.MaxForce = Vector3.new(1e9, 1e9, 1e9)
    positionMover.P = 18000
    positionMover.D = 1800
    positionMover.Position = targetRoot.Position + Vector3.new(0, Hub.Settings.AttackHeight, 0)
    positionMover.Parent = playerRoot

    local gyro = Instance.new("BodyGyro")
    gyro.Name = "MinhDZFarmHoverOrientation"
    gyro.MaxTorque = Vector3.new(1e9, 1e9, 1e9)
    gyro.P = 15000
    gyro.D = 1400
    gyro.CFrame = CFrame.lookAt(playerRoot.Position, targetRoot.Position)
    gyro.Parent = playerRoot

    hover.Position = positionMover
    hover.Gyro = gyro
    hover.TargetRoot = targetRoot
    hover.Character = character
    hover.Humanoid = humanoid
    hover.AutoRotate = humanoid.AutoRotate
    humanoid.AutoRotate = false

    hover.Connection = RunService.Heartbeat:Connect(function()
        if not isFeatureActive("FarmLevel", farmToken)
            or not targetRoot.Parent
            or not targetRoot:IsDescendantOf(workspace)
            or not positionMover.Parent
            or not gyro.Parent then
            stopHover()
            return
        end

        local liveCharacter = getCharacter()
        local liveRoot = getRoot()
        local liveHumanoid = getHumanoid()
        local targetHumanoid = targetRoot.Parent:FindFirstChildOfClass("Humanoid")
        if liveCharacter ~= character or not liveRoot or not liveHumanoid or liveHumanoid.Health <= 0
            or not targetHumanoid or targetHumanoid.Health <= 0 then
            stopHover()
            return
        end

        local height = math.clamp(tonumber(Hub.Settings.AttackHeight) or 18, 8, 60)
        positionMover.Position = targetRoot.Position + Vector3.new(0, height, 0)
        gyro.CFrame = CFrame.lookAt(liveRoot.Position, targetRoot.Position)
    end)
    return true
end

--// Enemy helpers
local function findNearestQuestMob(mobName)
    local enemies = workspace:FindFirstChild("Enemies")
    local playerRoot = getRoot()
    if not enemies or not playerRoot then
        return nil
    end

    local closest, closestDistance = nil, math.huge
    for _, model in ipairs(enemies:GetChildren()) do
        if mobNamesMatch(model.Name, mobName) then
            local humanoid = model:FindFirstChildOfClass("Humanoid")
            local root = model:FindFirstChild("HumanoidRootPart")
            if humanoid and root and humanoid.Health > 0 then
                local distance = (root.Position - playerRoot.Position).Magnitude
                if distance < closestDistance then
                    closest = model
                    closestDistance = distance
                end
            end
        end
    end
    return closest
end

local function findMobSpawnCFrame(mobName)
    local spawnFolder = ReplicatedStorage:FindFirstChild("FortBuilderReplicatedSpawnPositionsFolder")
    if not spawnFolder then
        return nil
    end

    for _, spawnObject in ipairs(spawnFolder:GetChildren()) do
        local candidates = { spawnObject.Name, tostring(spawnObject) }
        if spawnObject:IsA("StringValue") then
            table.insert(candidates, spawnObject.Value)
        end
        for _, candidate in ipairs(candidates) do
            if mobNamesMatch(candidate, mobName) then
                local spawnCFrame = getObjectCFrame(spawnObject)
                if spawnCFrame then
                    return spawnCFrame
                end
            end
        end
    end
    return nil
end

--// Shared farm context + Bring Mob controller.
-- Bring Mob is deliberately not a separate UI feature: its worker starts and
-- stops with Farm Level and future farm modules can reuse this controller.
function Hub.SetFarmTarget(mobName, anchorPosition)
    if type(mobName) ~= "string" or mobName == "" then
        Hub.FarmTarget = nil
        return
    end
    Hub.FarmTarget = {
        Name = normalizeMobName(mobName),
        Anchor = typeof(anchorPosition) == "Vector3" and anchorPosition or nil,
        UpdatedAt = os.clock()
    }
end

function Hub.ClearFarmTarget()
    Hub.FarmTarget = nil
end

local BRING_EXCLUDED_MOBS = {
    ["Ice Admiral"] = true,
    ["Awakened Ice Admiral"] = true,
    ["Saber Expert"] = true,
    ["The Gorilla King"] = true,
    Bobby = true,
    ["Mob Leader"] = true,
    ["Vice Admiral"] = true,
    Swan = true,
    ["Magma Admiral"] = true,
    ["Fishman Lord"] = true,
    Wysper = true,
    ["Thunder God"] = true,
    Cyborg = true,
    ["Don Swan"] = true,
    Greybeard = true,
    ["The Saw"] = true,
    Core = true,
    ["Cake Prince"] = true,
    ["Dough King"] = true
}

local function saveAndPrepareMob(model, humanoid, root)
    local original = Hub.BroughtMobs[model]
    if not original then
        original = {
            WalkSpeed = humanoid.WalkSpeed,
            JumpPower = humanoid.JumpPower,
            UseJumpPower = humanoid.UseJumpPower,
            PlatformStand = humanoid.PlatformStand,
            AutoRotate = humanoid.AutoRotate,
            OriginalPosition = root.Position,
            Parts = {}
        }
        Hub.BroughtMobs[model] = original
    end

    pcall(function()
        humanoid.PlatformStand = false
        humanoid.WalkSpeed = 0
        humanoid.JumpPower = 0
        humanoid.AutoRotate = false
    end)

    for _, part in ipairs(model:GetDescendants()) do
        if part:IsA("BasePart") then
            if original.Parts[part] == nil then
                original.Parts[part] = part.CanCollide
            end
            part.CanCollide = false
        end
    end

    local mover = root:FindFirstChild("MinhDZBringPosition")
    if not mover then
        mover = Instance.new("BodyPosition")
        mover.Name = "MinhDZBringPosition"
        mover.MaxForce = Vector3.new(1e6, 1e6, 1e6)
        mover.P = 20000
        mover.D = 1250
        mover.Parent = root
    end
    return mover, original
end

local function restoreBroughtMob(model)
    local original = Hub.BroughtMobs[model]
    if not original then
        return
    end

    local humanoid = model and model.Parent and model:FindFirstChildOfClass("Humanoid")
    if humanoid then
        pcall(function()
            humanoid.WalkSpeed = original.WalkSpeed
            humanoid.JumpPower = original.JumpPower
            humanoid.UseJumpPower = original.UseJumpPower
            humanoid.PlatformStand = original.PlatformStand
            humanoid.AutoRotate = original.AutoRotate
        end)
    end

    for part, canCollide in pairs(original.Parts) do
        if part and part.Parent then
            pcall(function()
                part.CanCollide = canCollide
            end)
        end
    end

    local root = model and model.Parent and model:FindFirstChild("HumanoidRootPart")
    local mover = root and root:FindFirstChild("MinhDZBringPosition")
    if mover then
        pcall(function() mover:Destroy() end)
    end
    Hub.BroughtMobs[model] = nil
end

local function restoreAllBroughtMobs()
    local models = {}
    for model in pairs(Hub.BroughtMobs) do
        table.insert(models, model)
    end
    for _, model in ipairs(models) do
        restoreBroughtMob(model)
    end
end

local BringLastTick = 0
local SimulationLastUpdate = 0
local function refreshLocalSimulationRadius()
    if os.clock() - SimulationLastUpdate < 2 then
        return
    end
    SimulationLastUpdate = os.clock()

    -- KaitunBF uses these executor-supported hidden properties for client NPC
    -- physics ownership. Keep this optional so unsupported executors do not crash.
    local setter = ENV.sethiddenproperty or sethiddenproperty
    if type(setter) == "function" then
        pcall(setter, LocalPlayer, "SimulationRadius", math.huge)
        pcall(setter, LocalPlayer, "MaxSimulationRadius", math.huge)
    end
end

local function bringMobStep(sharedToken)
    local shared = Hub.SharedBring
    if not shared.Enabled or shared.Token ~= sharedToken or Hub.Unloading then
        return
    end
    if os.clock() - BringLastTick < 0.10 then
        return
    end
    BringLastTick = os.clock()
    refreshLocalSimulationRadius()

    local farmTarget = Hub.FarmTarget
    local playerRoot = getRoot()
    local enemies = workspace:FindFirstChild("Enemies")
    if not farmTarget or not playerRoot or not enemies then
        restoreAllBroughtMobs()
        return
    end

    local anchor = farmTarget.Anchor
    if not anchor then
        anchor = playerRoot.Position - Vector3.new(0, Hub.Settings.AttackHeight, 0)
    end

    local updated = {}
    local radius = math.clamp(tonumber(Hub.Settings.BringRadius) or 220, 50, 300)

    for _, model in ipairs(enemies:GetChildren()) do
        if not Hub.SharedBring.Enabled or Hub.SharedBring.Token ~= sharedToken or Hub.Unloading then
            break
        end
        if mobNamesMatch(model.Name, farmTarget.Name) and not BRING_EXCLUDED_MOBS[model.Name] then
            local humanoid = model:FindFirstChildOfClass("Humanoid")
            local root = model:FindFirstChild("HumanoidRootPart")
            if humanoid and root and humanoid.Health > 0 then
                local original = Hub.BroughtMobs[model]
                local originalPosition = original and original.OriginalPosition or root.Position
                local nearFarmAnchor = (originalPosition - anchor).Magnitude <= radius + 50
                local nearPlayer = (root.Position - playerRoot.Position).Magnitude <= 360
                if nearFarmAnchor and nearPlayer then
                    local mover = saveAndPrepareMob(model, humanoid, root)
                    mover.Position = anchor
                    root.AssemblyLinearVelocity = Vector3.zero
                    root.AssemblyAngularVelocity = Vector3.zero

                    -- The original Kaitun bring routine snaps mobs that drift far
                    -- from the cluster, then uses BodyPosition to keep them grouped.
                    local horizontalDistance = (Vector2.new(root.Position.X, root.Position.Z)
                        - Vector2.new(anchor.X, anchor.Z)).Magnitude
                    if horizontalDistance > 18 then
                        root.CFrame = CFrame.new(anchor)
                        root.AssemblyLinearVelocity = Vector3.zero
                    end
                    updated[model] = true
                end
            end
        end
    end

    local stale = {}
    for model in pairs(Hub.BroughtMobs) do
        if not updated[model] then
            table.insert(stale, model)
        end
    end
    for _, model in ipairs(stale) do
        restoreBroughtMob(model)
    end
end

-- Shared API for Farm Level now and future farm modules later. Bring Mob is
-- automatic inside Farm Level, but the controller itself remains reusable.
function Hub.StartSharedBring()
    local shared = Hub.SharedBring
    if shared.Enabled or Hub.Unloading then
        return
    end

    shared.Enabled = true
    shared.Token = shared.Token + 1
    local token = shared.Token
    task.spawn(function()
        while Hub.SharedBring.Enabled and Hub.SharedBring.Token == token and not Hub.Unloading do
            local ok, err = pcall(bringMobStep, token)
            if not ok then
                warn("[MinhDZ Hub] Bring Mob error: " .. tostring(err))
                setStatus("Bring Mob error: " .. tostring(err))
                task.wait(0.5)
            else
                task.wait(0.10)
            end
        end
        restoreAllBroughtMobs()
    end)
end

function Hub.StopSharedBring()
    local shared = Hub.SharedBring
    if not shared.Enabled then
        restoreAllBroughtMobs()
        return
    end
    shared.Enabled = false
    shared.Token = shared.Token + 1
    restoreAllBroughtMobs()
end

--// Weapon helpers: lock the selected category and re-equip it if another tool is selected.
local VALID_WEAPON_CATEGORIES = { "Melee", "Sword", "Gun", "Blox Fruit" }

local function getToolCategory(tool)
    if not tool or not tool:IsA("Tool") then
        return nil
    end
    if tool.Name == "Combat" then
        return "Melee"
    end
    local tip = tostring(tool.ToolTip or "")
    for _, category in ipairs(VALID_WEAPON_CATEGORIES) do
        if tip == category then
            return category
        end
    end
    return nil
end

local function findToolForCategory(category)
    local character = getCharacter()
    if character then
        for _, tool in ipairs(character:GetChildren()) do
            if getToolCategory(tool) == category then
                return tool, true
            end
        end
    end

    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
    if backpack then
        for _, tool in ipairs(backpack:GetChildren()) do
            if getToolCategory(tool) == category and tool.Name ~= "Tool" then
                return tool, false
            end
        end
    end
    return nil, false
end

local function equipSelectedWeapon()
    local category = Hub.Settings.WeaponCategory
    if not table.find(VALID_WEAPON_CATEGORIES, category) then
        category = "Melee"
        Hub.Settings.WeaponCategory = category
    end

    local tool, alreadyEquipped = findToolForCategory(category)
    if alreadyEquipped then
        return tool
    end
    if not tool then
        return nil
    end

    local humanoid = getHumanoid()
    if not humanoid or humanoid.Health <= 0 then
        return nil
    end
    local ok = pcall(function()
        humanoid:EquipTool(tool)
    end)
    if not ok then
        return nil
    end
    return tool
end

local function hasBuso()
    local ok, result = pcall(function()
        return LocalPlayer:HasTag("Buso")
    end)
    return ok and result == true
end

--// Combat: melee/sword use the source hit pipeline; guns activate their Tool;
-- Blox Fruit uses the selected fruit skill key (same VirtualInputManager pattern as KaitunBF).
local LastAttackAt = 0
local LastFruitSkillAt = 0
local function pressFruitSkill()
    local skillName = tostring(Hub.Settings.FruitSkill or "Z")
    local validSkills = { Z = true, X = true, C = true, V = true }
    if not validSkills[skillName] then
        skillName = "Z"
    end
    local keyCode = Enum.KeyCode[skillName]
    if not keyCode then
        return false
    end

    local ok, err = pcall(function()
        local inputManager = game:GetService("VirtualInputManager")
        inputManager:SendKeyEvent(true, keyCode, false, game)
        task.wait(0.12)
        inputManager:SendKeyEvent(false, keyCode, false, game)
    end)
    if not ok then
        warn("[MinhDZ Hub] Fruit skill input unavailable: " .. tostring(err))
    end
    return ok
end

local function attackNearbyQuestMobs(primaryTarget, mobName, selectedTool)
    local category = Hub.Settings.WeaponCategory
    local interval = Hub.Settings.AttackInterval
    if category == "Blox Fruit" then
        interval = math.max(0.8, interval)
        if os.clock() - LastFruitSkillAt < interval then
            return
        end
        if not selectedTool then
            return
        end
        LastFruitSkillAt = os.clock()
        pressFruitSkill()
        return
    elseif category == "Gun" then
        interval = math.max(0.35, interval)
        if os.clock() - LastAttackAt < interval then
            return
        end
        if not selectedTool then
            return
        end
        LastAttackAt = os.clock()
        local ok, err = pcall(function()
            selectedTool:Activate()
        end)
        if not ok then
            warn("[MinhDZ Hub] Gun activation failed: " .. tostring(err))
        end
        return
    end

    if os.clock() - LastAttackAt < interval then
        return
    end

    local playerRoot = getRoot()
    local enemies = workspace:FindFirstChild("Enemies")
    if not playerRoot or not enemies then
        return
    end

    local hitTargets = {}
    local hitPart = nil
    for _, model in ipairs(enemies:GetChildren()) do
        if mobNamesMatch(model.Name, mobName) then
            local humanoid = model:FindFirstChildOfClass("Humanoid")
            local root = model:FindFirstChild("HumanoidRootPart")
            if humanoid and root and humanoid.Health > 0
                and (root.Position - playerRoot.Position).Magnitude <= 60 then
                local candidatePart = model:FindFirstChild("Head") or model.PrimaryPart or root
                hitPart = hitPart or candidatePart
                table.insert(hitTargets, { model, root })
                if #hitTargets >= 3 then
                    break
                end
            end
        end
    end

    if #hitTargets == 0 or not hitPart then
        return
    end

    LastAttackAt = os.clock()
    local ok, err = pcall(function()
        RegisterAttack:FireServer(0.16, 1)
        local global = getGlobalModule()
        if global and type(global.SendHitsToServer) == "function" then
            global.SendHitsToServer(hitPart, hitTargets)
        else
            RegisterHit:FireServer(hitPart, hitTargets)
        end
    end)
    if not ok then
        warn("[MinhDZ Hub] Attack remote error: " .. tostring(err))
    end
end

--// Farm Level feature step
local function farmLevelStep(token)
    if not isFeatureActive("FarmLevel", token) then
        return
    end

    local level = getPlayerLevel()
    if not level then
        Hub.ClearFarmTarget()
        stopHover()
        setStatus("Waiting for player level data...")
        task.wait(1)
        return
    end

    local sea = getSeaIndex()
    local quest, questError = selectQuestForLevel(level, sea)
    if not quest then
        Hub.ClearFarmTarget()
        stopHover()
        setStatus(questError)
        task.wait(2)
        return
    end

    local activeMob, activeTitle, activeProgress, activeMaximum = readActiveQuest()
    local hasProgress = (tonumber(activeProgress) or 0) > 0
    if activeMob and not mobNamesMatch(activeMob, quest.MobName) and not hasProgress then
        Hub.MismatchCount = Hub.MismatchCount + 1
        if Hub.MismatchCount >= 3 then
            setStatus("Different quest detected; abandoning it before level farm...")
            pcall(function()
                CommF:InvokeServer("AbandonQuest")
            end)
            Hub.MismatchCount = 0
            Hub.LastFarmQuestStart = os.clock()
            task.wait(0.8)
        end
        return
    end

    if not activeMob then
        Hub.ClearFarmTarget()
        stopHover()
        Hub.MismatchCount = 0
        if os.clock() - Hub.LastFarmQuestStart < 3 then
            return
        end

        local questGiver = getQuestGiverCFrame(quest.LevelReq)
        if questGiver then
            local root = getRoot()
            if root and (root.Position - questGiver.Position).Magnitude > 14 then
                setStatus(string.format("Travelling to quest giver | %s | Lv. %d", tostring(quest.QuestId), quest.LevelReq))
                moveTo(questGiver * CFrame.new(0, 4, 4), token)
                return
            end
        end

        if not isFeatureActive("FarmLevel", token) then
            return
        end

        setStatus(string.format("Accepting quest | %s | %s", tostring(quest.QuestId), quest.MobName))
        Hub.LastFarmQuestStart = os.clock()
        local ok, result = pcall(function()
            return CommF:InvokeServer("StartQuest", quest.QuestId, quest.StageId)
        end)
        if not ok then
            setStatus("StartQuest failed: " .. tostring(result))
        end
        task.wait(0.8)
        return
    end

    Hub.MismatchCount = 0
    local farmMobName = (activeMob and hasProgress) and activeMob or quest.MobName
    local target = findNearestQuestMob(farmMobName)
    if not target then
        stopHover()
        local spawnCFrame = findMobSpawnCFrame(farmMobName)
        if spawnCFrame then
            Hub.SetFarmTarget(farmMobName, spawnCFrame.Position)
            local root = getRoot()
            if root and (root.Position - spawnCFrame.Position).Magnitude > 25 then
                setStatus("Searching mob spawn | " .. farmMobName)
                moveTo(spawnCFrame * CFrame.new(0, Hub.Settings.AttackHeight, 0), token)
                return
            end
        else
            Hub.ClearFarmTarget()
        end
        setStatus("Waiting for mob spawn | " .. farmMobName)
        task.wait(1)
        return
    end

    local targetRoot = target:FindFirstChild("HumanoidRootPart")
    local targetHumanoid = target:FindFirstChildOfClass("Humanoid")
    local playerRoot = getRoot()
    if not targetRoot or not targetHumanoid or targetHumanoid.Health <= 0 or not playerRoot then
        return
    end

    local attackPosition = targetRoot.Position + Vector3.new(0, Hub.Settings.AttackHeight, 0)
    local attackCFrame = CFrame.lookAt(attackPosition, targetRoot.Position)
    local distance = (playerRoot.Position - attackPosition).Magnitude
    Hub.SetFarmTarget(farmMobName, targetRoot.Position)

    if distance > 18 then
        stopHover()
        setStatus(string.format("Farm Level | %s | smooth flight to mob", farmMobName))
        moveTo(attackCFrame, token)
        return
    end

    if not startHoverAboveTarget(targetRoot, token) then
        return
    end

    if (playerRoot.Position - attackPosition).Magnitude > 7 then
        setStatus(string.format("Farm Level | %s | stabilizing hover", farmMobName))
        task.wait(0.08)
        return
    end

    local selectedTool = equipSelectedWeapon()
    if not selectedTool then
        setStatus("Selected weapon not found: " .. tostring(Hub.Settings.WeaponCategory) .. ". Check Backpack tools.")
        task.wait(1)
        return
    end

    setStatus(string.format("Farm Level | %s | %s | Lv. %d", farmMobName, selectedTool.Name, level))
    attackNearbyQuestMobs(target, farmMobName, selectedTool)
    task.wait(0.06)
end

--// Auto Equip Selected Weapon is a separate utility feature.
local function autoEquipMeleeStep()
    if os.clock() - Hub.LastEquipCheck < 0.75 then
        return
    end
    Hub.LastEquipCheck = os.clock()
    local tool = equipSelectedWeapon()
    if not tool then
        setStatus("Auto Equip Selected Weapon: no " .. tostring(Hub.Settings.WeaponCategory) .. " tool found")
    else
        setStatus("Auto Equip Selected Weapon: " .. tool.Name)
    end
end

--// Auto Buso is a separate feature.
local function autoBusoStep()
    if os.clock() - Hub.LastBusoCheck < 5 then
        return
    end
    Hub.LastBusoCheck = os.clock()
    if hasBuso() then
        setStatus("Auto Buso: active")
        return
    end

    local ok, result = pcall(function()
        return CommF:InvokeServer("Buso")
    end)
    if not ok then
        warn("[MinhDZ Hub] Auto Buso error: " .. tostring(result))
        setStatus("Auto Buso error: " .. tostring(result))
    else
        setStatus("Auto Buso activation requested")
    end
end

--// Auto Sea Travel: keeps the unlock checks visible and conservative.
local function getServerMeleeMastery(styleName)
    local highest = 0
    pcall(function()
        local itemServiceModule = ReplicatedStorage:FindFirstChild("ItemReplicationService")
        local itemConfigModule = ReplicatedStorage:FindFirstChild("ItemConfig")
        if not itemServiceModule or not itemConfigModule then
            return
        end

        local itemService = require(itemServiceModule)
        local itemConfig = require(itemConfigModule)
        local userCache = itemService._UserCache and itemService._UserCache[LocalPlayer.UserId]
        local masteryItems = userCache and userCache:GetItems("Mastery")
        if type(masteryItems) ~= "table" then
            return
        end

        local wanted = tostring(styleName):lower():gsub("[^%w]", "")
        for _, entry in pairs(masteryItems) do
            if entry and entry.ItemId then
                local ok, item = pcall(function()
                    return itemConfig.match(entry.ItemId):unwrap()
                end)
                local debugLabel = ok and item and item.Index and item.Index.DebugLabel
                if debugLabel then
                    local label = tostring(debugLabel):lower():gsub("[^%w]", "")
                    local matches = label == wanted or (wanted == "dragonclaw" and label == "dragonbreath")
                    if matches then
                        highest = math.max(highest, tonumber(entry.Value) or 0)
                    end
                end
            end
        end
    end)
    return highest
end

local function findDragonClawMastery()
    local mastery = getServerMeleeMastery("Dragon Claw")
    local owned = mastery > 0
    local containers = { LocalPlayer.Character, LocalPlayer:FindFirstChildOfClass("Backpack") }
    for _, container in ipairs(containers) do
        if container then
            for _, tool in ipairs(container:GetChildren()) do
                if tool:IsA("Tool") and (tool.Name:lower():find("dragon claw", 1, true) or tool.Name:lower():find("dragon breath", 1, true)) then
                    owned = true
                    local masteryValue = tool:FindFirstChild("Level", true)
                    mastery = math.max(mastery, masteryValue and tonumber(masteryValue.Value) or 0)
                end
            end
        end
    end
    return mastery, owned
end

local function autoSeaTravelStep(token)
    if not isFeatureActive("AutoSeaTravel", token) then
        return
    end
    local level = getPlayerLevel()
    if not level then
        return
    end

    local sea = getSeaIndex()
    if sea == 1 and level < 700 then
        setStatus("Auto Sea Travel: Sea 1 requires level 700")
        return
    elseif sea == 2 and level < 1500 then
        setStatus("Auto Sea Travel: Sea 2 requires level 1500")
        return
    elseif sea >= 3 then
        setStatus("Auto Sea Travel: already in Sea 3")
        return
    end

    if os.clock() - Hub.LastSeaCheck < 10 then
        return
    end
    Hub.LastSeaCheck = os.clock()
    if os.clock() - Hub.LastSeaTravel < 60 then
        return
    end

    if sea == 1 and level >= 700 then
        Hub.LastSeaTravel = os.clock()
        setStatus("Checking Second Sea access...")
        pcall(function()
            CommF:InvokeServer("DressrosaQuestProgress", "Detective")
        end)
        task.wait(1)
        if not isFeatureActive("AutoSeaTravel", token) then
            return
        end
        local ok, result = pcall(function()
            return CommF:InvokeServer("TravelDressrosa")
        end)
        if ok then
            notify("MinhDZ Hub", "Second Sea travel request sent. Server unlock requirements still apply.", 5)
            setStatus("Second Sea travel requested | " .. tostring(result))
        else
            setStatus("Second Sea travel failed: " .. tostring(result))
        end
        return
    end

    if sea == 2 and level >= 1500 then
        local mastery, hasDragonClaw = findDragonClawMastery()
        if not hasDragonClaw or mastery < 400 then
            setStatus("Third Sea: Dragon Claw mastery 400 is still required by the source logic")
            return
        end

        local phoeyuDoorExists = false
        pcall(function()
            local map = workspace:FindFirstChild("Map")
            local iceCastle = map and map:FindFirstChild("IceCastle")
            local hall = iceCastle and iceCastle:FindFirstChild("Hall")
            local libraryDoor = hall and hall:FindFirstChild("LibraryDoor")
            phoeyuDoorExists = libraryDoor and libraryDoor:FindFirstChild("PhoeyuDoor") ~= nil
        end)

        if not phoeyuDoorExists then
            if not isFeatureActive("AutoSeaTravel", token) then
                return
            end
            Hub.LastSeaTravel = os.clock()
            setStatus("Checking Third Sea access...")
            local ok, result = pcall(function()
                return CommF:InvokeServer("TravelZou")
            end)
            if ok then
                notify("MinhDZ Hub", "Third Sea travel request sent. Server unlock requirements still apply.", 5)
                setStatus("Third Sea travel requested | " .. tostring(result))
            else
                setStatus("Third Sea travel failed: " .. tostring(result))
            end
        end
    end
end

--// Independent feature runner
local function startFeature(name, worker)
    local feature = Hub.Features[name]
    if not feature or feature.Enabled then
        return
    end

    feature.Enabled = true
    feature.Token = feature.Token + 1
    local token = feature.Token

    if name == "FarmLevel" then
        Hub.StartSharedBring()
    end

    task.spawn(function()
        while isFeatureActive(name, token) do
            local ok, err = pcall(worker, token)
            if not ok then
                warn("[MinhDZ Hub] " .. name .. " error: " .. tostring(err))
                setStatus(name .. " error: " .. tostring(err))
                task.wait(1)
            else
                task.wait(0.12)
            end
        end
    end)

    notify("MinhDZ Hub", name .. " enabled", 3)
end

local function stopFeature(name)
    local feature = Hub.Features[name]
    if not feature or not feature.Enabled then
        return
    end

    feature.Enabled = false
    feature.Token = feature.Token + 1
    if name == "FarmLevel" then
        stopMovement()
        stopHover()
        Hub.ClearFarmTarget()
        Hub.StopSharedBring()
        Hub.MismatchCount = 0
        setStatus("Farm Level stopped; movement and hover cancelled")
    end
    notify("MinhDZ Hub", name .. " disabled", 3)
end

local function setFeature(name, enabled, worker)
    if enabled then
        startFeature(name, worker)
    else
        stopFeature(name)
    end
end

--// UI: each toggle starts/stops only its own module.
Tabs.Farming:AddParagraph({
    Title = "Farm Level",
    Content = "Select a level-appropriate quest, travel to its quest giver, accept it, then keep a stable hover above matching mobs while attacking with the selected weapon category."
})

Tabs.Farming:AddToggle("FarmLevel", {
    Title = "Farm Level",
    Description = "Auto travel, accept quest, hover above the target and automatically bring matching mobs.",
    Default = false,
    Callback = function(value)
        setFeature("FarmLevel", value, farmLevelStep)
    end
})

Tabs.Farming:AddParagraph({
    Title = "Integrated Bring Mob",
    Content = "Bring Mob starts automatically with Farm Level. Turning Farm Level off stops the shared controller and restores saved NPC properties. Future farm modules can reuse Hub.SetFarmTarget(), Hub.StartSharedBring() and Hub.StopSharedBring()."
})

Tabs.Farming:AddParagraph({
    Title = "Farm Status",
    Content = "Runtime status and errors are printed with the [MinhDZ Hub] prefix in the executor console."
})

Tabs.Farming:AddButton({
    Title = "Stop Farm Level",
    Description = "Cancels Farm Level movement and attack loop only.",
    Callback = function()
        local option = Fluent.Options.FarmLevel
        if option then
            option:SetValue(false)
        else
            stopFeature("FarmLevel")
        end
    end
})

Tabs.Utility:AddParagraph({
    Title = "Independent utilities",
    Content = "These utilities have their own toggles. They do not start Farm Level."
})

Tabs.Utility:AddToggle("AutoEquipMelee", {
    Title = "Auto Equip Selected Weapon",
    Description = "Keep the selected weapon category equipped, even when Farm Level is off.",
    Default = false,
    Callback = function(value)
        setFeature("AutoEquipMelee", value, autoEquipMeleeStep)
    end
})

Tabs.Utility:AddToggle("AutoBuso", {
    Title = "Auto Buso (Haki)",
    Description = "Enable Buso when it is not active.",
    Default = false,
    Callback = function(value)
        setFeature("AutoBuso", value, autoBusoStep)
    end
})

Tabs.Travel:AddParagraph({
    Title = "Sea Travel",
    Content = "Uses the travel calls and unlock checks found in the supplied KaitunBF source. It cannot complete missing story/puzzle requirements by itself."
})

Tabs.Travel:AddToggle("AutoSeaTravel", {
    Title = "Auto Sea Travel",
    Description = "Request Second Sea at Lv. 700; request Third Sea when Dragon Claw mastery conditions are met.",
    Default = false,
    Callback = function(value)
        setFeature("AutoSeaTravel", value, autoSeaTravelStep)
    end
})

Tabs.Settings:AddParagraph({
    Title = "Menu Visibility",
    Content = "Use the floating MZ button to hide or reopen the menu. RightControl is also a visibility shortcut; hiding the menu does not stop enabled features."
})

Tabs.Settings:AddParagraph({
    Title = "Team Selection",
    Content = "MinhDZ waits for Pirates/Marines selection before creating this menu. Preferred Team is remembered for the next execution; it never switches your live team."
})

Tabs.Settings:AddDropdown("PreferredTeam", {
    Title = "Preferred Team",
    Description = "Preferred faction for the next execution. The current live team is never changed.",
    Values = { "Pirates", "Marines" },
    Default = Hub.Settings.PreferredTeam,
    Callback = function(value)
        if value == "Pirates" or value == "Marines" then
            Hub.Settings.PreferredTeam = value
            ENV.MinhDZPreferredTeam = value
        end
    end
})

Tabs.Settings:AddToggle("AutoJoinTeam", {
    Title = "Auto Join Team on Startup",
    Description = "Automatically requests the preferred team before the main menu is created on the next execution.",
    Default = Hub.Settings.AutoJoinTeam,
    Callback = function(value)
        Hub.Settings.AutoJoinTeam = value == true
        ENV.MinhDZAutoJoinTeam = Hub.Settings.AutoJoinTeam
    end
})

Tabs.Settings:AddDropdown("WeaponCategory", {
    Title = "Farm Weapon Category",
    Description = "The selected category is kept equipped during farming. Switching this dropdown changes the locked weapon category.",
    Values = { "Melee", "Sword", "Gun", "Blox Fruit" },
    Default = Hub.Settings.WeaponCategory,
    Callback = function(value)
        if table.find(VALID_WEAPON_CATEGORIES, value) then
            Hub.Settings.WeaponCategory = value
            if Hub.Features.FarmLevel.Enabled or Hub.Features.AutoEquipMelee.Enabled then
                task.defer(equipSelectedWeapon)
            end
            setStatus("Weapon category locked: " .. value)
        end
    end
})

Tabs.Settings:AddDropdown("FruitSkill", {
    Title = "Blox Fruit Skill",
    Description = "Skill key used while Blox Fruit is selected. Only available/unlocked skills will work.",
    Values = { "Z", "X", "C", "V" },
    Default = Hub.Settings.FruitSkill,
    Callback = function(value)
        if value == "Z" or value == "X" or value == "C" or value == "V" then
            Hub.Settings.FruitSkill = value
        end
    end
})

Tabs.Settings:AddSlider("BringRadius", {
    Title = "Bring Mob Radius",
    Description = "Maximum distance from the farm anchor for matching mobs to be gathered.",
    Default = Hub.Settings.BringRadius,
    Min = 50,
    Max = 300,
    Rounding = 0,
    Callback = function(value)
        Hub.Settings.BringRadius = math.clamp(tonumber(value) or 220, 50, 300)
    end
})

Tabs.Settings:AddSlider("FlightSpeed", {
    Title = "Flight Speed",
    Description = "Travel speed in studs/second. The BodyPosition target advances smoothly each frame; lower is steadier.",
    Default = 75,
    Min = 35,
    Max = 180,
    Rounding = 0,
    Callback = function(value)
        Hub.Settings.FlightSpeed = math.clamp(tonumber(value) or 75, 35, 180)
    end
})

Tabs.Settings:AddSlider("AttackHeight", {
    Title = "Attack Height",
    Description = "Continuous hover height above the target mob; maintained even while attacks are cooling down.",
    Default = 18,
    Min = 8,
    Max = 60,
    Rounding = 0,
    Callback = function(value)
        Hub.Settings.AttackHeight = math.clamp(tonumber(value) or 18, 8, 60)
    end
})

Tabs.Settings:AddSlider("AttackInterval", {
    Title = "Attack Interval",
    Description = "Cooldown for melee/sword hits; Gun and Blox Fruit use their own minimum cooldowns.",
    Default = 0.18,
    Min = 0.12,
    Max = 0.6,
    Rounding = 2,
    Callback = function(value)
        Hub.Settings.AttackInterval = math.clamp(tonumber(value) or 0.18, 0.12, 0.6)
    end
})

Tabs.Settings:AddButton({
    Title = "Stop All Features",
    Description = "Stops every enabled feature and cancels active movement.",
    Callback = function()
        local optionNames = {
            FarmLevel = "FarmLevel",
            AutoEquipMelee = "AutoEquipMelee",
            AutoBuso = "AutoBuso",
            AutoSeaTravel = "AutoSeaTravel"
        }
        for featureName, optionName in pairs(optionNames) do
            local option = Fluent.Options[optionName]
            if option and Hub.Features[featureName].Enabled then
                option:SetValue(false)
            else
                stopFeature(featureName)
            end
        end
        stopMovement()
        stopHover()
        Hub.ClearFarmTarget()
        Hub.StopSharedBring()
        notify("MinhDZ Hub", "All features stopped", 4)
    end
})

Tabs.Settings:AddButton({
    Title = "Unload Hub",
    Description = "Stops all loops, restores collisions and removes the Fluent UI.",
    Callback = function()
        Hub.Unload()
    end
})

function Hub.Unload()
    if Hub.Unloading then
        return
    end
    Hub.Unloading = true
    for _, feature in pairs(Hub.Features) do
        feature.Enabled = false
        feature.Token = feature.Token + 1
    end
    stopMovement()
    stopHover()
    Hub.ClearFarmTarget()
    Hub.StopSharedBring()
    if toggleInputConnection then
        pcall(function()
            toggleInputConnection:Disconnect()
        end)
        toggleInputConnection = nil
    end
    pcall(function()
        FloatingGui:Destroy()
    end)
    pcall(function()
        Fluent:Destroy()
    end)
end

Window:SelectTab(1)

-- Team selection has already completed before the Fluent window was constructed.
-- No background SetTeam worker runs after the menu becomes available.

Fluent:Notify({
    Title = "MinhDZ Hub",
    Content = "Loaded. Farm Level is OFF by default; Bring Mob starts automatically with Farm Level. Choose a weapon category in Settings.",
    Duration = 6
})

print("[MinhDZ Hub] Loaded | Farm Level (integrated Bring Mob), Weapon Lock, Smooth Flight, Auto Buso, Auto Sea Travel")
