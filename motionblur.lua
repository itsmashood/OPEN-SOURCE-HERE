local v1 = game:GetService("Players")
local v2 = game:GetService("RunService")
local v3 = game:GetService("UserInputService")
local v134 = game:GetService("ReplicatedStorage")
local v144 = game:GetService("Lighting")

local v4 = v1.LocalPlayer
local v5 = v4:WaitForChild("PlayerGui")

local v135
pcall(function()
	local v136 = require(v134:WaitForChild("Fsys"))
	v135 = v136.load("ClientData")
end)

local v6 = {
	Title = "Sprayhub lol",

	BlurStrength = 10.5,
	CharacterBlur = 1,

	ScanInterval = 0.5,
	PetSearchRadius = 22,
	MaxPets = 6,
	PetMaxModelSize = 18,

	GuiTransparency = 0.08,

	Window = {
		Width = 270,
		Height = 200,
		MinWidth = 230,
		MinHeight = 180,
		MaxWidth = 420,
		MaxHeight = 520,
		CornerRadius = 14
	},

	Theme = {
		Main = Color3.fromRGB(255, 255, 255),
		Secondary = Color3.fromRGB(255, 255, 255),
		Accent = Color3.fromRGB(255, 105, 180),
		AccentDark = Color3.fromRGB(255, 182, 213),
		Text = Color3.fromRGB(40, 40, 40),
		SliderBack = Color3.fromRGB(255, 215, 230),
		Knob = Color3.fromRGB(255, 255, 255)
	}
}

local function v7(v106)
	local v8 = v5:FindFirstChild(v106)
	if v8 then
		v8:Destroy()
	end
end

v7("v202")
v7("v203")

pcall(function()
	v2:UnbindFromRenderStep("v204")
end)

for v125, v8 in ipairs(workspace:GetDescendants()) do
	if v8:IsA("BasePart") then
		v8.LocalTransparencyModifier = 0
	end
end

local v9 = workspace.CurrentCamera
if v9 then
	local v10 = v9:FindFirstChild("v201")
	if v10 then
		v10:Destroy()
	end
end

local v11 = {
	BlurStrength = v6.BlurStrength,
	CharacterBlur = v6.CharacterBlur,
}

local v12 = Instance.new("BlurEffect")
v12.Name = "v201"
v12.Size = v11.BlurStrength
v12.Enabled = true
if workspace.CurrentCamera then
	v12.Parent = workspace.CurrentCamera
end

local v13 = Instance.new("ScreenGui")
v13.Name = "v202"
v13.ResetOnSpawn = false
v13.IgnoreGuiInset = true
v13.DisplayOrder = 999999
v13.Parent = v5

local v14 = Instance.new("ScreenGui")
v14.Name = "v203"
v14.ResetOnSpawn = false
v14.IgnoreGuiInset = true
v14.DisplayOrder = -1
v14.Parent = v5

local function v15(v107, v108)
	local v16 = 10 ^ (v108 or 0)
	return math.floor(v107 * v16 + 0.5) / v16
end

local function v17(v109, v110)
	local v18 = Instance.new("UICorner")
	v18.CornerRadius = UDim.new(0, v110)
	v18.Parent = v109
	return v18
end

local v19 = Instance.new("Frame")
v19.Name = "Main"
v19.Size = UDim2.fromOffset(v6.Window.Width, v6.Window.Height)
v19.Position = UDim2.new(0.5, -v6.Window.Width / 2, 0.5, -v6.Window.Height / 2)
v19.BackgroundColor3 = v6.Theme.Main
v19.BackgroundTransparency = v6.GuiTransparency
v19.BorderSizePixel = 0
v19.ClipsDescendants = true
v19.Parent = v13
v17(v19, v6.Window.CornerRadius)

local v20 = Instance.new("UIStroke")
v20.Color = v6.Theme.Accent
v20.Transparency = 0.35
v20.Thickness = 1
v20.Parent = v19

local v21 = Instance.new("Frame")
v21.Name = "Header"
v21.Size = UDim2.new(1, 0, 0, 56)
v21.BackgroundColor3 = v6.Theme.Secondary
v21.BackgroundTransparency = v6.GuiTransparency
v21.BorderSizePixel = 0
v21.Active = true
v21.Parent = v19
v17(v21, v6.Window.CornerRadius)

local v22 = Instance.new("Frame")
v22.Size = UDim2.new(1, 0, 0, 18)
v22.Position = UDim2.new(0, 0, 1, -18)
v22.BackgroundColor3 = v6.Theme.Secondary
v22.BackgroundTransparency = v6.GuiTransparency
v22.BorderSizePixel = 0
v22.Parent = v21

local v23 = Instance.new("ImageButton")
v23.Name = "GuiToggle"
v23.Size = UDim2.fromOffset(38, 38)
v23.Position = UDim2.new(0, 8, 0.5, -19)
v23.BackgroundColor3 = v6.Theme.AccentDark
v23.BorderSizePixel = 0
v23.AutoButtonColor = false
v23.ClipsDescendants = true
v23.Parent = v21
v17(v23, 9)

local v24 = Instance.new("ImageLabel")
v24.Size = UDim2.fromOffset(32, 32)
v24.AnchorPoint = Vector2.new(0.5, 0.5)
v24.Position = UDim2.fromScale(0.5, 0.5)
v24.BackgroundTransparency = 1
v24.Image = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(v4.UserId) .. "&w=180&h=180"
v24.Parent = v23

local v25 = Instance.new("TextLabel")
v25.Size = UDim2.new(1, -58, 0, 56)
v25.Position = UDim2.fromOffset(54, 0)
v25.BackgroundTransparency = 1
v25.Text = v6.Title
v25.TextColor3 = v6.Theme.Text
v25.TextSize = 18
v25.Font = Enum.Font.GothamBold
v25.TextXAlignment = Enum.TextXAlignment.Left
v25.Parent = v21

local v26 = Instance.new("ScrollingFrame")
v26.Name = "Content"
v26.Position = UDim2.fromOffset(10, 62)
v26.Size = UDim2.new(1, -20, 1, -72)
v26.BackgroundTransparency = 1
v26.BorderSizePixel = 0
v26.ScrollBarThickness = 4
v26.ScrollBarImageColor3 = v6.Theme.Accent
v26.CanvasSize = UDim2.new(0, 0, 0, 0)
v26.Parent = v19

local v27 = Instance.new("UIListLayout")
v27.Padding = UDim.new(0, 10)
v27.Parent = v26

v27:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	v26.CanvasSize = UDim2.new(0, 0, 0, v27.AbsoluteContentSize.Y + 12)
end)

local function v28(v111, v112, v113, v114, v115, v116)
	local v29 = Instance.new("Frame")
	v29.Size = UDim2.new(1, -4, 0, 66)
	v29.BackgroundColor3 = v6.Theme.Secondary
	v29.BackgroundTransparency = v6.GuiTransparency
	v29.BorderSizePixel = 0
	v29.Parent = v26
	v17(v29, 12)

	local v30 = Instance.new("TextLabel")
	v30.Size = UDim2.new(1, -88, 0, 26)
	v30.Position = UDim2.fromOffset(12, 5)
	v30.BackgroundTransparency = 1
	v30.Text = v111
	v30.TextColor3 = v6.Theme.Text
	v30.TextSize = 14
	v30.Font = Enum.Font.GothamMedium
	v30.TextXAlignment = Enum.TextXAlignment.Left
	v30.Parent = v29

	local v31 = Instance.new("TextLabel")
	v31.Size = UDim2.fromOffset(70, 26)
	v31.Position = UDim2.new(1, -76, 0, 5)
	v31.BackgroundTransparency = 1
	v31.TextColor3 = v6.Theme.Accent
	v31.TextSize = 14
	v31.Font = Enum.Font.GothamBold
	v31.TextXAlignment = Enum.TextXAlignment.Right
	v31.Parent = v29

	local v32 = Instance.new("Frame")
	v32.Size = UDim2.new(1, -24, 0, 8)
	v32.Position = UDim2.new(0, 12, 0, 43)
	v32.BackgroundColor3 = v6.Theme.SliderBack
	v32.BorderSizePixel = 0
	v32.Active = true
	v32.Parent = v29
	v17(v32, 999)

	local v33 = Instance.new("Frame")
	v33.Size = UDim2.new(0, 0, 1, 0)
	v33.BackgroundColor3 = v6.Theme.Accent
	v33.BorderSizePixel = 0
	v33.Parent = v32
	v17(v33, 999)

	local v34 = Instance.new("Frame")
	v34.Size = UDim2.fromOffset(20, 20)
	v34.AnchorPoint = Vector2.new(0.5, 0.5)
	v34.Position = UDim2.new(0, 0, 0.5, 0)
	v34.BackgroundColor3 = v6.Theme.Knob
	v34.BorderSizePixel = 0
	v34.Parent = v32
	v17(v34, 999)

	local v35 = false

	local function v36(v39)
		v39 = math.clamp(v39, 0, 1)

		local v37 = v112 + (v113 - v112) * v39
		v37 = v15(v37, v115)

		v33.Size = UDim2.new(v39, 0, 1, 0)
		v34.Position = UDim2.new(v39, 0, 0.5, 0)
		v31.Text = tostring(v37)

		v116(v37)
	end

	local function v38(v117)
		local v39 = (v117 - v32.AbsolutePosition.X) / v32.AbsoluteSize.X
		v36(v39)
	end

	v36((v114 - v112) / (v113 - v112))

	v32.InputBegan:Connect(function(v118)
		if v118.UserInputType == Enum.UserInputType.MouseButton1
			or v118.UserInputType == Enum.UserInputType.Touch then
			v35 = true
			v38(v118.Position.X)
		end
	end)

	v3.InputChanged:Connect(function(v118)
		if v35 and (v118.UserInputType == Enum.UserInputType.MouseMovement or v118.UserInputType == Enum.UserInputType.Touch) then
			v38(v118.Position.X)
		end
	end)

	v3.InputEnded:Connect(function(v118)
		if v118.UserInputType == Enum.UserInputType.MouseButton1
			or v118.UserInputType == Enum.UserInputType.Touch then
			v35 = false
		end
	end)

	return v29
end

v28("Blur Strength", 0, 56, v11.BlurStrength, 1, function(v119)
	v11.BlurStrength = v119
end)

v28("Character Blur", 0, 1, v11.CharacterBlur, 2, function(v119)
	v11.CharacterBlur = v119
end)


local v40 = Instance.new("ImageButton")
v40.Name = "FloatingPFP"
v40.Size = UDim2.fromOffset(44, 44)
v40.Position = UDim2.new(0, 14, 0.5, -22)
v40.BackgroundColor3 = v6.Theme.AccentDark
v40.BorderSizePixel = 0
v40.AutoButtonColor = false
v40.Image = "rbxthumb://type=AvatarHeadShot&id=" .. tostring(v4.UserId) .. "&w=180&h=180"
v40.Visible = false
v40.Parent = v13
v17(v40, 10)

local v41 = Instance.new("UIStroke")
v41.Color = v6.Theme.Accent
v41.Transparency = 0.1
v41.Parent = v40

local function v42()
	v19.Visible = false
	v40.Visible = true
end

local function v43()
	v19.Visible = true
	v40.Visible = false
end

v23.Activated:Connect(v42)
v40.Activated:Connect(v43)

do
	local v35 = false
	local v44
	local v45

	v40.InputBegan:Connect(function(v118)
		if v118.UserInputType == Enum.UserInputType.MouseButton1
			or v118.UserInputType == Enum.UserInputType.Touch then
			v35 = true
			v44 = v118.Position
			v45 = v40.Position
		end
	end)

	v3.InputChanged:Connect(function(v118)
		if v35 and (
			v118.UserInputType == Enum.UserInputType.MouseMovement
			or v118.UserInputType == Enum.UserInputType.Touch
		) then
			local v46 = v118.Position - v44
			v40.Position = UDim2.new(
				v45.X.Scale,
				v45.X.Offset + v46.X,
				v45.Y.Scale,
				v45.Y.Offset + v46.Y
			)
		end
	end)

	v3.InputEnded:Connect(function(v118)
		if v118.UserInputType == Enum.UserInputType.MouseButton1
			or v118.UserInputType == Enum.UserInputType.Touch then
			v35 = false
		end
	end)
end

do
	local v35 = false
	local v44
	local v45
	local v47

	v21.InputBegan:Connect(function(v118)
		if v118.UserInputType == Enum.UserInputType.MouseButton1
			or v118.UserInputType == Enum.UserInputType.Touch then
			v35 = true
			v44 = v118.Position
			v45 = v19.Position

			v118.Changed:Connect(function()
				if v118.UserInputState == Enum.UserInputState.End then
					v35 = false
				end
			end)
		end
	end)

	v21.InputChanged:Connect(function(v118)
		if v118.UserInputType == Enum.UserInputType.MouseMovement
			or v118.UserInputType == Enum.UserInputType.Touch then
			v47 = v118
		end
	end)

	v3.InputChanged:Connect(function(v118)
		if v35 and v118 == v47 then
			local v46 = v118.Position - v44
			v19.Position = UDim2.new(
				v45.X.Scale,
				v45.X.Offset + v46.X,
				v45.Y.Scale,
				v45.Y.Offset + v46.Y
			)
		end
	end)
end

local v48 = Instance.new("TextButton")
v48.Size = UDim2.fromOffset(24, 24)
v48.AnchorPoint = Vector2.new(1, 1)
v48.Position = UDim2.new(1, -4, 1, -4)
v48.BackgroundTransparency = 1
v48.Text = "◢"
v48.TextColor3 = v6.Theme.Accent
v48.TextSize = 18
v48.Font = Enum.Font.GothamBold
v48.Parent = v19

do
	local v49 = false
	local v50
	local v51

	v48.InputBegan:Connect(function(v118)
		if v118.UserInputType == Enum.UserInputType.MouseButton1
			or v118.UserInputType == Enum.UserInputType.Touch then
			v49 = true
			v50 = v118.Position
			v51 = v19.AbsoluteSize
		end
	end)

	v3.InputChanged:Connect(function(v118)
		if v49 and (v118.UserInputType == Enum.UserInputType.MouseMovement or v118.UserInputType == Enum.UserInputType.Touch) then
			local v46 = v118.Position - v50

			local v52 = math.clamp(v51.X + v46.X, v6.Window.MinWidth, v6.Window.MaxWidth)
			local v53 = math.clamp(v51.Y + v46.Y, v6.Window.MinHeight, v6.Window.MaxHeight)

			v19.Size = UDim2.fromOffset(v52, v53)
		end
	end)

	v3.InputEnded:Connect(function(v118)
		if v118.UserInputType == Enum.UserInputType.MouseButton1
			or v118.UserInputType == Enum.UserInputType.Touch then
			v49 = false
		end
	end)
end

local v54 = Instance.new("ViewportFrame")
v54.Size = UDim2.fromScale(1, 1)
v54.Position = UDim2.fromScale(0, 0)
v54.BackgroundTransparency = 1
v54.BorderSizePixel = 0
v54.Visible = false

v54.Active = false
v54.Selectable = false
pcall(function()
	v54.Interactable = false
end)

v54.Parent = v14

local v55 = Instance.new("Camera")
v55.Parent = v54
v54.CurrentCamera = v55

local v56 = Instance.new("WorldModel")
v56.Parent = v54

local v57 = v4.Character
local v58 = 0
local v59 = {}

local function v60()
	v58 += 1
	return "v206_" .. tostring(v58)
end

local function v61(v87)
	if not v87 or not v87:IsA("Model") then
		return nil
	end

	if v87.PrimaryPart then
		return v87.PrimaryPart
	end

	local v62 = v87:FindFirstChild("HumanoidRootPart", true)
	if v62 and v62:IsA("BasePart") then
		return v62
	end

	for v125, v8 in ipairs(v87:GetDescendants()) do
		if v8:IsA("BasePart") then
			return v8
		end
	end

	return nil
end

local function v63(v87)
	for v125, v126 in ipairs(v1:GetPlayers()) do
		if v126.Character == v87 then
			return true
		end
	end
	return false
end

local function v64(v87)
	for v125, v8 in ipairs(v87:GetDescendants()) do
		if v8:IsA("BasePart") then
			return true
		end
	end
	return false
end

local function v65(v87)
	for v125, v8 in ipairs(v87:GetDescendants()) do
		if v8:IsA("BasePart") and not v8.Anchored then
			return true
		end
	end
	return false
end

local function v66(v87)
	if not v87 then
		return
	end
	for v125, v8 in ipairs(v87:GetDescendants()) do
		if v8:IsA("BasePart") then
			v8.LocalTransparencyModifier = 0
		end
	end
end

local function v67(v87)
	local v68 = v59[v87]
	if not v68 then
		return
	end

	v66(v87)

	if v68.clone then
		v68.clone:Destroy()
	end

	v59[v87] = nil
end

local function v145(v8)
	return v8:IsA("BasePart")
		or v8:IsA("Bone")
		or v8:IsA("Motor6D")
		or v8:IsA("Attachment")
		or v8:IsA("Decal")
		or v8:IsA("Texture")
		or v8:IsA("SurfaceAppearance")
		or v8:IsA("SpecialMesh")
		or v8:IsA("ParticleEmitter")
		or v8:IsA("Trail")
		or v8:IsA("Beam")
		or v8:IsA("Light")
		or v8:IsA("Highlight")
end

local function v146(v147, v148)
	if not v147 or not v148 or not v147.Parent or not v148.Parent then
		return
	end

	if v147:IsA("BasePart") and v148:IsA("BasePart") then
		v148.Color = v147.Color
		v148.Material = v147.Material
		v148.MaterialVariant = v147.MaterialVariant
		v148.Reflectance = v147.Reflectance

		if v147:IsA("MeshPart") and v148:IsA("MeshPart") then
			v148.TextureID = v147.TextureID
		end

	elseif v147:IsA("Attachment") and v148:IsA("Attachment")
		and not v147:IsA("Bone") then

		v148.CFrame = v147.CFrame

	elseif v147:IsA("Decal") and v148:IsA("Decal") then
		v148.Texture = v147.Texture
		v148.Color3 = v147.Color3
		v148.Transparency = v147.Transparency

	elseif v147:IsA("Texture") and v148:IsA("Texture") then
		v148.Texture = v147.Texture
		v148.Color3 = v147.Color3
		v148.Transparency = v147.Transparency
		v148.OffsetStudsU = v147.OffsetStudsU
		v148.OffsetStudsV = v147.OffsetStudsV
		v148.StudsPerTileU = v147.StudsPerTileU
		v148.StudsPerTileV = v147.StudsPerTileV

	elseif v147:IsA("SurfaceAppearance") and v148:IsA("SurfaceAppearance") then
		v148.ColorMap = v147.ColorMap
		v148.MetalnessMap = v147.MetalnessMap
		v148.NormalMap = v147.NormalMap
		v148.RoughnessMap = v147.RoughnessMap
		v148.AlphaMode = v147.AlphaMode

	elseif v147:IsA("SpecialMesh") and v148:IsA("SpecialMesh") then
		v148.MeshId = v147.MeshId
		v148.TextureId = v147.TextureId
		v148.Scale = v147.Scale
		v148.Offset = v147.Offset
		v148.VertexColor = v147.VertexColor

	elseif v147:IsA("ParticleEmitter") and v148:IsA("ParticleEmitter") then
		v148.Enabled = v147.Enabled
		v148.Color = v147.Color
		v148.Transparency = v147.Transparency
		v148.LightEmission = v147.LightEmission
		v148.LightInfluence = v147.LightInfluence
		v148.Brightness = v147.Brightness
		v148.Texture = v147.Texture
		v148.Rate = v147.Rate
		v148.Speed = v147.Speed
		v148.Size = v147.Size
		v148.Lifetime = v147.Lifetime

	elseif v147:IsA("Trail") and v148:IsA("Trail") then
		v148.Enabled = v147.Enabled
		v148.Color = v147.Color
		v148.Transparency = v147.Transparency
		v148.LightEmission = v147.LightEmission
		v148.LightInfluence = v147.LightInfluence
		v148.Texture = v147.Texture
		v148.Lifetime = v147.Lifetime

	elseif v147:IsA("Beam") and v148:IsA("Beam") then
		v148.Enabled = v147.Enabled
		v148.Color = v147.Color
		v148.Transparency = v147.Transparency
		v148.LightEmission = v147.LightEmission
		v148.LightInfluence = v147.LightInfluence
		v148.Texture = v147.Texture
		v148.Width0 = v147.Width0
		v148.Width1 = v147.Width1

	elseif v147:IsA("Light") and v148:IsA("Light") then
		v148.Enabled = v147.Enabled
		v148.Color = v147.Color
		v148.Brightness = v147.Brightness
		v148.Range = v147.Range
		v148.Shadows = v147.Shadows

	elseif v147:IsA("Highlight") and v148:IsA("Highlight") then
		v148.Enabled = v147.Enabled
		v148.FillColor = v147.FillColor
		v148.FillTransparency = v147.FillTransparency
		v148.OutlineColor = v147.OutlineColor
		v148.OutlineTransparency = v147.OutlineTransparency
	end
end

local function v69(v87, v120)
	if not v87 or not v87.Parent then
		return nil
	end

	local v70 = {}

	for v125, v8 in ipairs(v87:GetDescendants()) do
		if v145(v8) then
			local v71 = v60()
			v8:SetAttribute("v205", v71)
			v70[v71] = v8
		end
	end

	local v72 = v87.Archivable
	v87.Archivable = true

	local v73, v74 = pcall(function()
		return v87:Clone()
	end)

	v87.Archivable = v72

	for v125, v8 in ipairs(v87:GetDescendants()) do
		if v145(v8) then
			v8:SetAttribute("v205", nil)
		end
	end

	if not v73 or not v74 then
		return nil
	end

	local v75 = {}
	local v76 = {}
	local v77 = {}
	local v149 = {}

	for v125, v8 in ipairs(v74:GetDescendants()) do
		if v8:IsA("Script") or v8:IsA("LocalScript") then
			v8:Destroy()
		elseif v145(v8) then
			local v71 = v8:GetAttribute("v205")
			local v78 = v71 and v70[v71]

			if v78 then
				if v8:IsA("BasePart") and v78:IsA("BasePart") then
					v75[v78] = v8
					v8.Anchored = true
					v8.CanCollide = false
					v8.CanTouch = false
					v8.CanQuery = false

				elseif v8:IsA("Bone") and v78:IsA("Bone") then
					v76[v78] = v8

				elseif v8:IsA("Motor6D") and v78:IsA("Motor6D") then
					v77[v78] = v8

				else
					v149[v78] = v8
				end
			end

			v8:SetAttribute("v205", nil)
		end
	end

	v74.Name = "v206_" .. v120 .. "_Clone"
	v74.Parent = v56

	return {
		kind = v120,
		clone = v74,
		partMap = v75,
		boneMap = v76,
		motorMap = v77,
		visualMap = v149,
		descendantCount = #v87:GetDescendants()
	}
end

local function v79(v87, v120)
	if not v87 or not v87.Parent then
		return
	end

	local v80 = v59[v87]
	if v80 then
		v80.kind = v120

		local v150 = #v87:GetDescendants()
		if v80.descendantCount ~= v150 then
			if v80.clone then
				v80.clone:Destroy()
			end

			local v81 = v69(v87, v120)
			if v81 then
				v59[v87] = v81
			else
				v59[v87] = nil
			end
		end

		return
	end

	local v81 = v69(v87, v120)
	if v81 then
		v59[v87] = v81
	end
end

local function v82(v87, v68)
	if not v87 or not v87.Parent or not v68 or not v68.clone or not v68.clone.Parent then
		v67(v87)
		return false
	end

	local v83 = v68.kind == "character"
	local v84 = v83 and v11.CharacterBlur or 1

	for v78, v127 in pairs(v68.partMap or {}) do
		if v78 and v78.Parent and v127 and v127.Parent then
			v127.CFrame = v78.CFrame

			if v127.Size ~= v78.Size then
				v127.Size = v78.Size
			end

			v146(v78, v127)

			v127.Transparency = math.max(
				v78.Transparency,
				1 - v84
			)

			if v83 then
				v78.LocalTransparencyModifier = 0
			else
				v78.LocalTransparencyModifier = 1
			end
		end
	end

	for v128, v129 in pairs(v68.boneMap or {}) do
		if v128
			and v128.Parent
			and v129
			and v129.Parent then

			if v129.CFrame ~= v128.CFrame then
				v129.CFrame = v128.CFrame
			end

			v129.Transform = v128.Transform
		end
	end

	for v130, v131 in pairs(v68.motorMap or {}) do
		if v130
			and v130.Parent
			and v131
			and v131.Parent then

			if v131.C0 ~= v130.C0 then
				v131.C0 = v130.C0
			end

			if v131.C1 ~= v130.C1 then
				v131.C1 = v130.C1
			end

			v131.Transform = v130.Transform
		end
	end

	for v147, v148 in pairs(v68.visualMap or {}) do
		v146(v147, v148)
	end

	return true
end

local v85 = OverlapParams.new()
v85.FilterType = Enum.RaycastFilterType.Exclude
v85.FilterDescendantsInstances = {}

local function v86(v121)
	local v87 = v121:FindFirstAncestorOfClass("Model")
	if not v87 then
		return nil
	end

	while v87.Parent and v87.Parent:IsA("Model") do
		v87 = v87.Parent
	end

	return v87
end

local function v88(v87, v95)
	if not v87 or v87 == v57 then
		return false
	end

	if v63(v87) then
		return false
	end

	if not v64(v87) then
		return false
	end

	if not v65(v87) then
		return false
	end

	local v89 = v61(v87)
	if not v89 then
		return false
	end

	local v90 = (v89.Position - v95.Position).Magnitude
	if v90 > v6.PetSearchRadius then
		return false
	end

	local v73, v91 = pcall(function()
		return v87:GetExtentsSize()
	end)

	if not v73 or not v91 then
		return false
	end

	local v92 = math.max(v91.X, v91.Y, v91.Z)
	if v92 > v6.PetMaxModelSize then
		return false
	end

	return true
end

local function v137()
	local v138 = {}

	if not v135 then
		return v138
	end

	local v139, v140 = pcall(function()
		return v135.get("pet_char_wrappers")
	end)

	if not v139 or type(v140) ~= "table" then
		return v138
	end

	for v141, v142 in pairs(v140) do
		local v143 = v142 and v142.char
		if v142
			and v142.controller == v4
			and typeof(v143) == "Instance"
			and v143:IsA("Model")
			and v143:IsDescendantOf(workspace) then

			table.insert(v138, v143)
		end
	end

	return v138
end

local function v93()
	local v94 = {}

	if not v57 then
		return v94
	end

	local v95 = v61(v57)
	if not v95 then
		return v94
	end

	v85.FilterDescendantsInstances = {v57}

	local v96 = workspace:GetPartBoundsInRadius(v95.Position, v6.PetSearchRadius, v85)
	local v97 = {}

	for v125, v121 in ipairs(v96) do
		local v87 = v86(v121)

		if v87 and not v97[v87] and v88(v87, v95) then
			v97[v87] = true

			local v89 = v61(v87)
			if v89 then
				table.insert(v94, {
					model = v87,
					dist = (v89.Position - v95.Position).Magnitude
				})
			end
		end
	end

	table.sort(v94, function(v122, v123)
		return v122.dist < v123.dist
	end)

	local v98 = {}
	for v132 = 1, math.min(#v94, v6.MaxPets) do
		table.insert(v98, v94[v132].model)
	end

	return v98
end

local function v99()
	local v100 = {}

	if v57 and v57.Parent then
		v100[v57] = "character"
	end

	if v57 and v57.Parent then
		for v141, v143 in ipairs(v137()) do
			if v143 ~= v57 then
				v100[v143] = "pet"
			end
		end
	end

	for v87, v120 in pairs(v100) do
		v79(v87, v120)
	end

	for v87, v125 in pairs(v59) do
		if not v100[v87] then
			v67(v87)
		end
	end
end

local function v101(v124)
	v57 = v124
	task.wait(1)
	v99()
end

if v57 then
	task.spawn(function()
		task.wait(1)
		v99()
	end)
end

v4.CharacterAdded:Connect(v101)

task.spawn(function()
	while v13.Parent do
		pcall(v99)
		task.wait(v6.ScanInterval)
	end
end)

v2:BindToRenderStep("v204", Enum.RenderPriority.Last.Value, function()
	local v102 = workspace.CurrentCamera
	if not v102 then
		return
	end

	if v12.Parent ~= v102 then
		v12.Parent = v102
	end

	v12.Enabled = true
	v12.Size = v11.BlurStrength

	v55.CFrame = v102.CFrame
	v55.FieldOfView = v102.FieldOfView

	v54.Ambient = v144.Ambient

	local v151 = math.clamp(v144.Brightness / 3, 0, 1)
	v54.LightColor = v144.OutdoorAmbient:Lerp(Color3.new(1, 1, 1), v151)

	local v152 = v144:GetSunDirection()
	v54.LightDirection = Vector3.new(-v152.X, -v152.Y, -v152.Z)

	local v104 = false

	for v87, v68 in pairs(v59) do
		local v105 = v82(v87, v68)
		if v105 then
			v104 = true
		end
	end

	v54.Visible = v104
end)
