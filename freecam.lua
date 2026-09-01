local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")

if not UserInputService.TouchEnabled then
	return
end

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

local GuiParent = CoreGui
pcall(function()
	if gethui then
		GuiParent = gethui()
	end
end)

local oldGui = GuiParent:FindFirstChild("MobileFreecamMinimal")
if oldGui then
	oldGui:Destroy()
end

local Gui = Instance.new("ScreenGui")
Gui.Name = "MobileFreecamMinimal"
Gui.ResetOnSpawn = false
Gui.IgnoreGuiInset = true
Gui.Parent = GuiParent

local Toggle = Instance.new("TextButton")
Toggle.Name = "Toggle"
Toggle.AnchorPoint = Vector2.new(1, 0)
Toggle.Position = UDim2.new(1, -14, 0, 14)
Toggle.Size = UDim2.fromOffset(54, 54)
Toggle.BackgroundColor3 = Color3.fromRGB(78, 29, 92)
Toggle.BackgroundTransparency = 0.08
Toggle.Text = "FC"
Toggle.TextColor3 = Color3.fromRGB(255, 255, 255)
Toggle.TextScaled = true
Toggle.Font = Enum.Font.GothamBold
Toggle.AutoButtonColor = true
Toggle.Parent = Gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 16)
corner.Parent = Toggle

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(255, 135, 205)
stroke.Thickness = 2
stroke.Transparency = 0.1
stroke.Parent = Toggle

local grad = Instance.new("UIGradient")
grad.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(92, 38, 110)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(176, 65, 145))
})
grad.Rotation = 45
grad.Parent = Toggle

local Enabled = false
local MoveSpeed = 2.2
local LookSensitivity = 0.16

local CamPosition
local CamPitch = 0
local CamYaw = 0

local SavedCameraType
local SavedCameraSubject
local SavedCameraCFrame

local SavedWalkSpeed
local SavedJumpPower
local SavedAutoRotate
local SavedUseJumpPower

local Humanoid
local Character

local lookTouch = nil
local lastLookPos = nil

local function getCharacterData()
	Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
	Humanoid = Character:FindFirstChildOfClass("Humanoid")
	return Character, Humanoid
end

local function isPointInToggle(pos)
	local absPos = Toggle.AbsolutePosition
	local absSize = Toggle.AbsoluteSize

	return pos.X >= absPos.X
		and pos.X <= absPos.X + absSize.X
		and pos.Y >= absPos.Y
		and pos.Y <= absPos.Y + absSize.Y
end

local function enableFreecam()
	if Enabled then
		return
	end

	Camera = workspace.CurrentCamera
	if not Camera then
		return
	end

	getCharacterData()
	if not Humanoid then
		return
	end

	Enabled = true

	SavedCameraType = Camera.CameraType
	SavedCameraSubject = Camera.CameraSubject
	SavedCameraCFrame = Camera.CFrame

	SavedWalkSpeed = Humanoid.WalkSpeed
	SavedJumpPower = Humanoid.JumpPower
	SavedUseJumpPower = Humanoid.UseJumpPower
	SavedAutoRotate = Humanoid.AutoRotate

	CamPosition = Camera.CFrame.Position

	local x, y = Camera.CFrame:ToOrientation()
	CamPitch = math.deg(x)
	CamYaw = math.deg(y)

	Humanoid.WalkSpeed = 0
	Humanoid.JumpPower = 0
	Humanoid.AutoRotate = false

	Camera.CameraType = Enum.CameraType.Scriptable

	Toggle.Text = "ON"
	Toggle.BackgroundColor3 = Color3.fromRGB(125, 46, 116)
	stroke.Color = Color3.fromRGB(255, 188, 232)
end

local function disableFreecam()
	if not Enabled then
		return
	end

	Enabled = false

	Camera = workspace.CurrentCamera
	if Camera then
		Camera.CameraType = SavedCameraType or Enum.CameraType.Custom
		Camera.CameraSubject = SavedCameraSubject

		if SavedCameraCFrame then
			Camera.CFrame = SavedCameraCFrame
		end
	end

	getCharacterData()
	if Humanoid then
		if SavedWalkSpeed ~= nil then
			Humanoid.WalkSpeed = SavedWalkSpeed
		end

		if SavedJumpPower ~= nil then
			Humanoid.JumpPower = SavedJumpPower
		end

		if SavedAutoRotate ~= nil then
			Humanoid.AutoRotate = SavedAutoRotate
		end

		if SavedUseJumpPower ~= nil then
			Humanoid.UseJumpPower = SavedUseJumpPower
		end
	end

	lookTouch = nil
	lastLookPos = nil

	Toggle.Text = "FC"
	Toggle.BackgroundColor3 = Color3.fromRGB(78, 29, 92)
	stroke.Color = Color3.fromRGB(255, 135, 205)
end

Toggle.MouseButton1Click:Connect(function()
	if Enabled then
		disableFreecam()
	else
		enableFreecam()
	end
end)

UserInputService.TouchStarted:Connect(function(input, processed)
	if not Enabled then
		return
	end

	if processed then
		return
	end

	if isPointInToggle(input.Position) then
		return
	end

	local screenSize = Camera.ViewportSize

	if input.Position.X >= screenSize.X * 0.45 then
		lookTouch = input
		lastLookPos = input.Position
	end
end)

UserInputService.TouchMoved:Connect(function(input)
	if not Enabled then
		return
	end

	if input == lookTouch and lastLookPos then
		local delta = input.Position - lastLookPos

		CamYaw -= delta.X * LookSensitivity
		CamPitch -= delta.Y * LookSensitivity
		CamPitch = math.clamp(CamPitch, -89, 89)

		lastLookPos = input.Position
	end
end)

UserInputService.TouchEnded:Connect(function(input)
	if input == lookTouch then
		lookTouch = nil
		lastLookPos = nil
	end
end)

LocalPlayer.CharacterAdded:Connect(function()
	task.wait(1)

	if Enabled then
		getCharacterData()

		if Humanoid then
			Humanoid.WalkSpeed = 0
			Humanoid.JumpPower = 0
			Humanoid.AutoRotate = false
		end
	end
end)

RunService.RenderStepped:Connect(function(dt)
	if not Enabled then
		return
	end

	Camera = workspace.CurrentCamera
	if not Camera then
		return
	end

	getCharacterData()
	if not Humanoid then
		return
	end

	Camera.CameraType = Enum.CameraType.Scriptable

	local rotation =
		CFrame.Angles(0, math.rad(CamYaw), 0) *
		CFrame.Angles(math.rad(CamPitch), 0, 0)

	local inputMove = Humanoid.MoveDirection

	if inputMove.Magnitude > 0 then
		local move = Vector3.new(
			inputMove.X,
			0,
			inputMove.Z
		)

		if move.Magnitude > 0 then
			CamPosition += move.Unit * MoveSpeed * 35 * dt
		end
	end

	Camera.CFrame = CFrame.new(CamPosition) * rotation
end)
