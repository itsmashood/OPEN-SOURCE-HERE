antiLagEnabled = antiLagEnabled == true
antiLagLevel = antiLagEnabled and 100 or 0
antiLagConnectionStarted = antiLagConnectionStarted or false
antiLagLoopRunning = antiLagLoopRunning or false





antiLagCleanRadius = antiLagCleanRadius or 220
antiLagScanDelay = antiLagScanDelay or 3
antiLagMaxPartsPerScan = antiLagMaxPartsPerScan or 220
antiLagCleanedInstances = antiLagCleanedInstances or setmetatable({}, {__mode = "k"})

antiLagRemovedPlayersPets = antiLagRemovedPlayersPets or setmetatable({}, {__mode = "k"})
antiLagPlayerPetScanRunning = antiLagPlayerPetScanRunning or false

function xyneriaAntiLagSafeText(value)
    local ok, result = pcall(function()
        return tostring(value)
    end)

    if ok then
        return result
    end

    return ""
end

function xyneriaAntiLagLowerClean(value)
    return xyneriaAntiLagSafeText(value):lower()
end

function xyneriaAntiLagIsMyAsset(object)
    if not object then
        return true
    end

    if player and player.Character and object == player.Character then
        return true
    end

    if player and player.Character and object:IsDescendantOf(player.Character) then
        return true
    end

    local objectName = xyneriaAntiLagLowerClean(object.Name)
    local playerName = player and xyneriaAntiLagLowerClean(player.Name) or ""

    if playerName ~= "" and objectName:find(playerName, 1, true) then
        return true
    end

    local ownerTag = nil
    pcall(function()
        ownerTag = object:FindFirstChild("Owner") or object:FindFirstChild("Player") or object:FindFirstChild("Creator")
    end)

    if ownerTag and ownerTag.Value ~= nil and player then
        local ownerValue = ownerTag.Value
        if ownerValue == player or ownerValue == player.Name or ownerValue == player.UserId then
            return true
        end
    end

    local ownerAttribute = nil
    local creatorAttribute = nil

    pcall(function()
        ownerAttribute = object:GetAttribute("Owner")
        creatorAttribute = object:GetAttribute("Creator")
    end)

    if player and (ownerAttribute == player.UserId or creatorAttribute == player.Name) then
        return true
    end

    return false
end

function xyneriaAntiLagObliterateModel(object)
    if not antiLagEnabled then
        return false
    end

    if not object or not object.Parent then
        return false
    end

    if antiLagRemovedPlayersPets[object] then
        return false
    end

    if xyneriaAntiLagIsGuiOrInventory(object) then
        return false
    end

    if xyneriaAntiLagIsMyAsset(object) then
        return false
    end

    antiLagRemovedPlayersPets[object] = true

    task.defer(function()
        pcall(function()
            if object and object.Parent then
                object:ClearAllChildren()
                object:Destroy()
            end
        end)
    end)

    return true
end

function xyneriaAntiLagIsOtherPlayerCharacter(model)
    if not model or not model:IsA("Model") then
        return false
    end

    for _, otherPlayer in ipairs(Players:GetPlayers()) do
        if otherPlayer ~= player and otherPlayer.Character == model then
            return true
        end
    end

    return false
end

function xyneriaAntiLagLooksLikePetModel(model)
    if not model or not model:IsA("Model") then
        return false
    end

    if xyneriaAntiLagIsMyAsset(model) then
        return false
    end

    if model:FindFirstChildOfClass("Humanoid") and not xyneriaAntiLagNameHasAny(model, {"pet", "animal"}) then
        return false
    end

    local hasPetMarker = false

    pcall(function()
        hasPetMarker = model:FindFirstChild("Pet") ~= nil
            or model:FindFirstChild("Animal") ~= nil
            or model:GetAttribute("Pet") ~= nil
            or model:GetAttribute("pet") ~= nil
            or model:GetAttribute("Animal") ~= nil
            or model:GetAttribute("Owner") ~= nil
    end)

    if hasPetMarker then
        return true
    end

    local nameLower = xyneriaAntiLagLowerClean(model.Name)

    if nameLower:find("pet", 1, true) or nameLower:find("animal", 1, true) then
        return true
    end

    return false
end

function xyneriaAntiLagRemoveOtherPlayers()
    if not antiLagEnabled then
        return
    end

    for _, otherPlayer in ipairs(Players:GetPlayers()) do
        if otherPlayer ~= player and otherPlayer.Character then
            xyneriaAntiLagObliterateModel(otherPlayer.Character)
        end
    end

    local altCharacterFolder = workspace:FindFirstChild("PlayerCharacters")
    if altCharacterFolder then
        for _, child in ipairs(altCharacterFolder:GetChildren()) do
            if child.Name ~= tostring(player and player.Name or "") then
                xyneriaAntiLagObliterateModel(child)
            end
        end
    end
end

function xyneriaAntiLagMaybeRemovePlayerOrPet(instance)
    if not antiLagEnabled or not instance then
        return false
    end

    local current = instance

    while current and current ~= workspace do
        if current:IsA("Model") then
            if xyneriaAntiLagIsOtherPlayerCharacter(current) or xyneriaAntiLagLooksLikePetModel(current) then
                return xyneriaAntiLagObliterateModel(current)
            end
        end

        current = current.Parent
    end

    return false
end

function xyneriaAntiLagRemovePetsBatch()
    if not antiLagEnabled or antiLagPlayerPetScanRunning then
        return
    end

    antiLagPlayerPetScanRunning = true

    task.spawn(function()
        local scanned = 0

        for _, instance in ipairs(workspace:GetDescendants()) do
            if not antiLagEnabled then
                break
            end

            if instance:IsA("Model") then
                xyneriaAntiLagMaybeRemovePlayerOrPet(instance)
                scanned += 1

                if scanned % 50 == 0 then
                    task.wait()
                end
            end
        end

        antiLagPlayerPetScanRunning = false
    end)
end

function xyneriaAntiLagRemovePlayersAndPets()
    if not antiLagEnabled then
        return
    end

    xyneriaAntiLagRemoveOtherPlayers()
    xyneriaAntiLagRemovePetsBatch()
end


function xyneriaAntiLagGetRoot()
    local character = player and player.Character

    if not character then
        return nil
    end

    return character:FindFirstChild("HumanoidRootPart")
end

function xyneriaAntiLagIsOwnCharacter(instance)
    local character = player and player.Character

    return character and instance and instance:IsDescendantOf(character)
end

function xyneriaAntiLagIsGuiOrInventory(instance)
    if not instance then
        return true
    end

    local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
    local backpack = player and player:FindFirstChildOfClass("Backpack")

    if playerGui and instance:IsDescendantOf(playerGui) then
        return true
    end

    if backpack and instance:IsDescendantOf(backpack) then
        return true
    end

    local coreGui = nil
    pcall(function()
        coreGui = game:GetService("CoreGui")
    end)

    if coreGui and instance:IsDescendantOf(coreGui) then
        return true
    end

    return false
end

function xyneriaAntiLagIsCharacterModel(instance)
    local current = instance

    while current and current ~= workspace do
        if current:IsA("Model") and current:FindFirstChildOfClass("Humanoid") then
            return true
        end

        current = current.Parent
    end

    return false
end

function xyneriaAntiLagIsToolOrVehicle(instance)
    local current = instance

    while current and current ~= workspace do
        if current:IsA("Tool") then
            return true
        end

        local name = tostring(current.Name or ""):lower()

        if name:find("vehicle", 1, true)
            or name:find("car", 1, true)
            or name:find("bike", 1, true)
            or name:find("scooter", 1, true)
            or name:find("stroller", 1, true)
            or name:find("pet", 1, true) then
            return true
        end

        current = current.Parent
    end

    return false
end

function xyneriaAntiLagGetWorldPosition(instance)
    if not instance then
        return nil
    end

    if instance:IsA("BasePart") then
        return instance.Position
    end

    if instance:IsA("Attachment") then
        return instance.WorldPosition
    end

    local current = instance.Parent

    while current do
        if current:IsA("BasePart") then
            return current.Position
        elseif current:IsA("Attachment") then
            return current.WorldPosition
        end

        current = current.Parent
    end

    return nil
end

function xyneriaAntiLagIsNearPlayer(instance)
    local root = xyneriaAntiLagGetRoot()
    local position = xyneriaAntiLagGetWorldPosition(instance)

    if not root or not position then
        return false
    end

    return (position - root.Position).Magnitude <= antiLagCleanRadius
end

function xyneriaAntiLagCanTouch(instance)
    if not antiLagEnabled then
        return false
    end

    if not instance or not instance:IsDescendantOf(workspace) then
        return false
    end

    if xyneriaAntiLagIsGuiOrInventory(instance) then
        return false
    end

    if xyneriaAntiLagIsOwnCharacter(instance) then
        return false
    end

    if xyneriaAntiLagIsCharacterModel(instance) then
        return false
    end

    if xyneriaAntiLagIsToolOrVehicle(instance) then
        return false
    end

    if not xyneriaAntiLagIsNearPlayer(instance) then
        return false
    end

    return true
end

function xyneriaAntiLagSafeSet(object, property, value)
    pcall(function()
        object[property] = value
    end)
end

function xyneriaAntiLagDestroy(instance)
    pcall(function()
        instance:Destroy()
    end)
end

function xyneriaAntiLagNameHasAny(instance, words)
    local text = ""

    pcall(function()
        text = tostring(instance.Name or "") .. " " .. tostring(instance:GetFullName() or "")
    end)

    text = text:lower()

    for _, word in ipairs(words) do
        if text:find(word, 1, true) then
            return true
        end
    end

    return false
end

function xyneriaAntiLagIsProtectedGround(instance)
    return xyneriaAntiLagNameHasAny(instance, {
        "floor",
        "ground",
        "road",
        "path",
        "baseplate",
        "spawn",
        "platform",
        "bridge",
        "terrain",
        "sidewalk"
    })
end

function xyneriaAntiLagLooksLikeBuilding(instance)
    return xyneriaAntiLagNameHasAny(instance, {
        "building",
        "house",
        "home",
        "wall",
        "roof",
        "ceiling",
        "window",
        "door",
        "pillar",
        "column",
        "fence",
        "arch",
        "shop",
        "store",
        "mall",
        "tower",
        "sign",
        "billboard",
        "poster",
        "banner",
        "bench",
        "tree",
        "bush",
        "plant",
        "flower",
        "grass",
        "decor",
        "decoration",
        "prop",
        "mesh",
        "statue",
        "fountain",
        "ship",
        "boat",
        "vessel",
        "dock",
        "harbor",
        "tradehub",
        "trade_hub",
        "trade hub"
    })
end

function xyneriaAntiLagOptimizeLighting()
    local lighting = game:GetService("Lighting")

    xyneriaAntiLagSafeSet(lighting, "GlobalShadows", false)
    xyneriaAntiLagSafeSet(lighting, "EnvironmentDiffuseScale", 0)
    xyneriaAntiLagSafeSet(lighting, "EnvironmentSpecularScale", 0)
    xyneriaAntiLagSafeSet(lighting, "ShadowSoftness", 0)
    xyneriaAntiLagSafeSet(lighting, "Brightness", 1)

    for _, effect in ipairs(lighting:GetChildren()) do
        if effect:IsA("PostEffect") then
            xyneriaAntiLagSafeSet(effect, "Enabled", false)
        elseif effect:IsA("Atmosphere") or effect:IsA("Clouds") then
            xyneriaAntiLagDestroy(effect)
        end
    end

    local terrain = workspace:FindFirstChildOfClass("Terrain")

    if terrain then
        xyneriaAntiLagSafeSet(terrain, "WaterReflectance", 0)
        xyneriaAntiLagSafeSet(terrain, "WaterWaveSize", 0)
        xyneriaAntiLagSafeSet(terrain, "WaterWaveSpeed", 0)
        xyneriaAntiLagSafeSet(terrain, "WaterTransparency", 1)
    end
end

function xyneriaAntiLagCleanVisual(instance)
    if not xyneriaAntiLagCanTouch(instance) then
        return
    end

    if antiLagCleanedInstances[instance] then
        return
    end

    antiLagCleanedInstances[instance] = true

    
    if instance:IsA("Decal")
        or instance:IsA("Texture")
        or instance:IsA("SurfaceAppearance")
        or instance:IsA("ParticleEmitter")
        or instance:IsA("Trail")
        or instance:IsA("Beam")
        or instance:IsA("Smoke")
        or instance:IsA("Fire")
        or instance:IsA("Sparkles")
        or instance:IsA("Highlight") then

        xyneriaAntiLagDestroy(instance)
        return
    end

    
    if instance:IsA("PointLight")
        or instance:IsA("SpotLight")
        or instance:IsA("SurfaceLight") then

        xyneriaAntiLagSafeSet(instance, "Enabled", false)
        return
    end

    
    
    if instance:IsA("Model") and xyneriaAntiLagLooksLikeBuilding(instance) then
        return
    end

    if instance:IsA("BasePart") then
        
        
        if xyneriaAntiLagLooksLikeBuilding(instance) and not xyneriaAntiLagIsProtectedGround(instance) then
            xyneriaAntiLagSafeSet(instance, "CastShadow", false)
            xyneriaAntiLagSafeSet(instance, "Reflectance", 0)
        end

        
        xyneriaAntiLagSafeSet(instance, "CastShadow", false)
        xyneriaAntiLagSafeSet(instance, "Reflectance", 0)

        if instance:IsA("MeshPart") then
            xyneriaAntiLagSafeSet(instance, "TextureID", "")
            xyneriaAntiLagSafeSet(instance, "TextureId", "")
        end

        pcall(function()
            if instance.Material ~= Enum.Material.SmoothPlastic then
                instance.Material = Enum.Material.SmoothPlastic
            end
        end)

        return
    end

    if instance:IsA("SpecialMesh") then
        xyneriaAntiLagSafeSet(instance, "TextureId", "")
    end
end

function xyneriaAntiLagCleanPartTree(part)
    if not part or not xyneriaAntiLagCanTouch(part) then
        return
    end

    xyneriaAntiLagCleanVisual(part)

    if part and part.Parent then
        for _, descendant in ipairs(part:GetDescendants()) do
            xyneriaAntiLagCleanVisual(descendant)
        end
    end

    local parent = part.Parent

    if parent and parent ~= workspace and parent:IsA("Model") and xyneriaAntiLagCanTouch(parent) and xyneriaAntiLagLooksLikeBuilding(parent) then
        xyneriaAntiLagCleanVisual(parent)
    end
end

function xyneriaAntiLagGetNearbyParts()
    local root = xyneriaAntiLagGetRoot()

    if not root then
        return {}
    end

    local overlapParams = OverlapParams.new()
    overlapParams.FilterType = Enum.RaycastFilterType.Blacklist
    overlapParams.MaxParts = antiLagMaxPartsPerScan

    if player and player.Character then
        overlapParams.FilterDescendantsInstances = {player.Character}
    end

    local parts = {}

    local ok = pcall(function()
        parts = workspace:GetPartBoundsInRadius(root.Position, antiLagCleanRadius, overlapParams)
    end)

    if not ok or type(parts) ~= "table" then
        return {}
    end

    return parts
end

function xyneriaAntiLagCleanNearby()
    if not antiLagEnabled then
        return
    end

    pcall(function()
        xyneriaAntiLagOptimizeLighting()
    end)

    pcall(function()
        xyneriaAntiLagRemovePlayersAndPets()
    end)

    local processed = 0

    for _, part in ipairs(xyneriaAntiLagGetNearbyParts()) do
        if not antiLagEnabled then
            break
        end

        xyneriaAntiLagCleanPartTree(part)

        processed += 1
        if processed % 15 == 0 then
            task.wait()
        end
    end
end

function xyneriaApplyAntiLag()
    antiLagEnabled = antiLagEnabled == true
    antiLagLevel = antiLagEnabled and 100 or 0

    if not antiLagEnabled then
        return
    end

    xyneriaAntiLagCleanNearby()

    if not antiLagConnectionStarted then
        antiLagConnectionStarted = true

        workspace.DescendantAdded:Connect(function(instance)
            task.wait(0.1)

            if antiLagEnabled then
                if not xyneriaAntiLagMaybeRemovePlayerOrPet(instance) then
                    xyneriaAntiLagCleanVisual(instance)
                end
            end
        end)
    end

    if not antiLagLoopRunning then
        antiLagLoopRunning = true

        task.spawn(function()
            while antiLagEnabled do
                xyneriaAntiLagCleanNearby()
                task.wait(antiLagScanDelay)
            end

            antiLagLoopRunning = false
        end)
    end

    print("[Xyneria Anti-Lag] Strong cleanup enabled. Radius:", tostring(antiLagCleanRadius))
end
