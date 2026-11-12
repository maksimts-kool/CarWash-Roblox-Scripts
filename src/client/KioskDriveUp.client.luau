-- Drive-up kiosk: when the player stops their car next to the pay kiosk, the
-- camera swings to the kiosk screen so they can choose a wash with the mouse
-- (or a tap), and "Pay" sends their card to the reader from the driver's seat.
--
-- The buttons are StarterGui.KioskDriveUp; this script only shows them, moves
-- the camera and plays the card animation. The server (CarWash.Kiosk) checks
-- the player is really parked there before it takes the payment.
--
-- While the kiosk view is open the screen is the only thing giving
-- instructions: the HUD's objective and job panel hide (player attribute
-- "KioskUi"), the hotbar hides, and the card the customer asked for gets
-- its "Wanted" badge on the screen instead of the job panel naming it.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local Selections = workspace:WaitForChild("CarWash"):WaitForChild("Selections")
local screenPart = Selections:WaitForChild("Screen") :: BasePart
local reader = Selections:WaitForChild("EFTReader")
local touchpart = reader:WaitForChild("Touchpart") :: BasePart
local pages = screenPart:WaitForChild("SurfaceGui"):WaitForChild("Pages")
local selectPage = pages:WaitForChild("Select")
local confirmPage = pages:WaitForChild("Confirm")
local processPage = pages:WaitForChild("Process")
local cards = selectPage:WaitForChild("Cards")

local TapCardRemote = ReplicatedStorage:WaitForChild("CarWashRemotes"):WaitForChild("KioskTapCard")

local gui = player:WaitForChild("PlayerGui"):WaitForChild("KioskDriveUp")
local bar = gui:WaitForChild("Bar")
local barScale = bar:WaitForChild("Scale")
local payButton = bar:WaitForChild("TapCard")
local payGlow = payButton:WaitForChild("Glow")
local leaveButton = bar:WaitForChild("Leave")
local openButton = gui:WaitForChild("OpenKiosk")
local openScale = openButton:WaitForChild("Scale")

local RANGE = 9 -- studs (flat) from the driver's seat to the kiosk screen
local STOPPED_SPEED = 2.5
local LEAVE_SPEED = 5
local SETTLE_SECONDS = 0.4 -- stopped this long before the camera swings over
local CARD_TOOL = "Debit Card"

local VIEW_TWEEN = TweenInfo.new(0.6, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

-- where the camera sits: close on the screen while choosing, pulled back to
-- show the card reader too while paying
local function viewCFrame(): CFrame
	local normal = screenPart.CFrame.RightVector -- the SurfaceGui is on the Right face
	local focus, distance
	if processPage.Visible then
		focus = Vector3.new(screenPart.Position.X, (screenPart.Position.Y + touchpart.Position.Y) / 2, screenPart.Position.Z)
		distance = 1.9
	else
		focus = screenPart.Position
		distance = 1.35
	end
	return CFrame.lookAt(focus + normal * distance, focus)
end

---------------------------------------------------------------- state
local viewing = false
local dismissed = false -- the player closed the view; don't swing back until they drive off
local stoppedSince: number? = nil
local savedType: Enum.CameraType? = nil
local savedSubject: Instance? = nil
local savedBackpack = true
local tapping = false

local function driverSeat(): VehicleSeat?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local seat = humanoid and humanoid.SeatPart
	if seat and seat:IsA("VehicleSeat") then
		return seat
	end
	return nil
end

local function nearKiosk(seat: BasePart): boolean
	local offset = seat.Position - screenPart.Position
	return Vector3.new(offset.X, 0, offset.Z).Magnitude <= RANGE
end

local function speedOf(seat: BasePart): number
	return seat.AssemblyLinearVelocity.Magnitude
end

local function cardTool(): Tool?
	local backpack = player:FindFirstChildOfClass("Backpack")
	local tool = (backpack and backpack:FindFirstChild(CARD_TOOL))
		or (player.Character and player.Character:FindFirstChild(CARD_TOOL))
	return if tool and tool:IsA("Tool") then tool else nil
end

local function setKioskUi()
	player:SetAttribute("AtKiosk", viewing)
	player:SetAttribute("KioskUi", viewing or openButton.Visible)
end

---------------------------------------------------------------- see through the car
-- Parked beside the kiosk, the car's own door and mirror sit between the
-- camera and the screen. While the kiosk view is open the car and the
-- driver are hidden on this client only, and the car's non-solid parts stop
-- catching the mouse so clicks reach the screen. Solid parts are left alone,
-- so the car's physics never changes.
local hiddenParts: { BasePart } = {}
local unqueried: { BasePart } = {}

local function carModel(seat: BasePart): Instance
	local model: Instance = seat
	while model.Parent and model.Parent ~= workspace do
		model = model.Parent
	end
	return model
end

local function hideCar(seat: BasePart)
	for _, root in { carModel(seat), player.Character } do
		for _, part in (root :: Instance):GetDescendants() do
			if part:IsA("BasePart") then
				table.insert(hiddenParts, part)
				if part.CanQuery and not part.CanCollide then
					part.CanQuery = false
					table.insert(unqueried, part)
				end
			end
		end
	end
end

local function showCar()
	for _, part in hiddenParts do
		part.LocalTransparencyModifier = 0
	end
	for _, part in unqueried do
		if part.Parent then
			part.CanQuery = true
		end
	end
	table.clear(hiddenParts)
	table.clear(unqueried)
end

---------------------------------------------------------------- the customer's pick
-- Badges the card the customer asked for (this client only). The "most
-- popular" ribbon steps aside when it's on the same card.
local function showWanted(on: boolean)
	local wants = if on and player:GetAttribute("JobActive") then player:GetAttribute("JobWants") else nil
	for _, slot in cards:GetChildren() do
		local badge = slot:FindFirstChild("Wanted")
		if badge then
			badge.Visible = slot.Name == wants
		end
		local ribbon = slot:FindFirstChild("Ribbon")
		if ribbon then
			ribbon.Visible = slot.Name ~= wants
		end
	end
end

---------------------------------------------------------------- buttons
local pulse: Tween? = nil
local function refreshBar()
	local canPay = viewing
		and processPage.Visible
		and processPage:GetAttribute("State") == "WaitingForCard"
		and not tapping
		and cardTool() ~= nil
	payButton.Visible = canPay
	if canPay and not pulse then
		payGlow.Size = UDim2.fromScale(1, 1)
		payGlow.BackgroundTransparency = 0.4
		pulse = TweenService:Create(payGlow, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, -1), {
			Size = UDim2.new(1, 22, 1, 22),
			BackgroundTransparency = 1,
		})
		pulse:Play()
	elseif not canPay and pulse then
		pulse:Cancel()
		pulse = nil
		payGlow.BackgroundTransparency = 1
	end
end

local function fitButtons()
	local width = camera.ViewportSize.X
	barScale.Scale = math.clamp((width - 24) / bar.Size.X.Offset, 0.6, 1)
	openScale.Scale = math.clamp((width - 24) / 400, 0.7, 1)
end
camera:GetPropertyChangedSignal("ViewportSize"):Connect(fitButtons)
fitButtons()

---------------------------------------------------------------- camera
local function enterView()
	if viewing then
		return
	end
	viewing = true
	local seat = driverSeat()
	if seat then
		hideCar(seat)
	end
	savedType = camera.CameraType
	savedSubject = camera.CameraSubject
	camera.CameraType = Enum.CameraType.Scriptable
	TweenService:Create(camera, VIEW_TWEEN, { CFrame = viewCFrame() }):Play()

	savedBackpack = StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.Backpack)
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	openButton.Visible = false
	showWanted(true)
	setKioskUi()
	refreshBar()
	bar.Visible = true
	local scale = barScale.Scale
	barScale.Scale = scale * 0.9
	TweenService:Create(barScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = scale }):Play()
end

local function exitView()
	if not viewing then
		return
	end
	viewing = false
	dismissed = true
	showCar()
	showWanted(false)
	bar.Visible = false
	refreshBar()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, savedBackpack)
	setKioskUi()
	camera.CameraType = savedType or Enum.CameraType.Custom
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	camera.CameraSubject = if savedSubject and savedSubject.Parent then savedSubject else humanoid
end

-- keep the camera on the kiosk (eases between the screen and the reader view),
-- and keep the mouse free so the screen can be clicked
RunService:BindToRenderStep("KioskDriveUp", Enum.RenderPriority.Camera.Value + 1, function(dt)
	if not viewing then
		return
	end
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable
	end
	local target = viewCFrame()
	if (camera.CFrame.Position - target.Position).Magnitude > 0.005 then
		camera.CFrame = camera.CFrame:Lerp(target, math.min(1, dt * 8))
	end
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true
	-- the default camera scripts reset the driver's transparency every frame
	for _, part in hiddenParts do
		part.LocalTransparencyModifier = 1
	end
end)

---------------------------------------------------------------- the card
-- A copy of the player's Debit Card flies from the car window to the reader.
local function playCardTap(onTouch: () -> ())
	local tool = cardTool()
	local handle = tool and tool:FindFirstChild("Handle")
	if not handle or not handle:IsA("BasePart") then
		onTouch()
		return
	end
	local card = handle:Clone()
	for _, child in card:GetChildren() do
		if not child:IsA("SurfaceGui") and not child:IsA("Decal") and not child:IsA("SpecialMesh") then
			child:Destroy()
		end
	end
	card.Name = "DriveUpCard"
	card.Anchored = true
	card.CanCollide = false
	card.CanTouch = false
	card.CanQuery = false
	card.CastShadow = false

	local normal = screenPart.CFrame.RightVector -- the kiosk faces the lane this way
	local function standing(position: Vector3): CFrame
		-- card face towards the reader, long side upright
		return CFrame.fromMatrix(position, normal:Cross(Vector3.yAxis).Unit, normal)
	end
	local readerFront = touchpart.Position + normal * 0.1 + Vector3.new(0, 0.12, 0)
	local start = camera.CFrame * CFrame.new(0.35, -0.55, -0.6)
	card.CFrame = standing(start.Position) * CFrame.Angles(0, 0, math.rad(-35))
	card.Parent = workspace

	local toReader = TweenService:Create(card, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = standing(readerFront) })
	toReader:Play()
	toReader.Completed:Wait()
	onTouch()
	task.wait(0.6)
	local back = TweenService:Create(card, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		CFrame = standing(start.Position) * CFrame.Angles(0, 0, math.rad(-35)),
		Transparency = 1,
	})
	back:Play()
	back.Completed:Wait()
	card:Destroy()
end

payButton.MouseButton1Click:Connect(function()
	if not payButton.Visible or tapping then
		return
	end
	tapping = true
	refreshBar()
	playCardTap(function()
		TapCardRemote:FireServer()
	end)
	tapping = false
	refreshBar()
end)

leaveButton.MouseButton1Click:Connect(exitView)
openButton.MouseButton1Click:Connect(function()
	dismissed = false
	enterView()
end)

for _, page in { selectPage, confirmPage, processPage } do
	page:GetPropertyChangedSignal("Visible"):Connect(refreshBar)
end
processPage:GetAttributeChangedSignal("State"):Connect(function()
	refreshBar()
	if viewing and processPage:GetAttribute("State") == "Proceed" then
		-- paid and the gate is open: give the player their driving camera back
		task.delay(1.5, exitView)
	end
end)

---------------------------------------------------------------- watch the driver
local function setOpenButton(visible: boolean)
	if openButton.Visible ~= visible then
		openButton.Visible = visible
		setKioskUi()
	end
end

RunService.Heartbeat:Connect(function()
	local seat = driverSeat()
	local near = seat ~= nil and nearKiosk(seat)

	if viewing then
		if not near or speedOf(seat :: BasePart) > LEAVE_SPEED then
			exitView()
		end
		return
	end

	if not near then
		dismissed = false
		stoppedSince = nil
		setOpenButton(false)
		return
	end

	if speedOf(seat :: BasePart) >= STOPPED_SPEED then
		stoppedSince = nil
		setOpenButton(false)
		return
	end
	stoppedSince = stoppedSince or os.clock()
	if dismissed then
		-- already paid and the gate is opening: nothing left to do at the kiosk
		local state = processPage:GetAttribute("State")
		setOpenButton(not (processPage.Visible and (state == "Paid" or state == "Proceed")))
	elseif os.clock() - (stoppedSince :: number) >= SETTLE_SECONDS then
		enterView()
	end
end)

player.CharacterRemoving:Connect(function()
	if viewing then
		exitView()
	end
end)
