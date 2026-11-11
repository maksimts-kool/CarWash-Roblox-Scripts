local MainScreenModule = {}

local Players = game:GetService("Players")

local MainModule
local root = script.Parent.Parent
local GUI = root.Selections.Screen.SurfaceGui
local EFTTouch = root.Selections.EFTReader.Touchpart
local EFTScreen = root.Selections.EFTReader.Screen.SurfaceGui.Frame.LCD
local EFTSound = root.Selections.EFTReader.Screen.Contactless

local FRAMES = {
	Selection = GUI.Select,
	Process = GUI.Process,
	Confirm = GUI.Confirm
}

local WASH_TYPES = {
	Small = "Small Wash",
	Middle = "Middle Wash",
	Full = "Full Wash"
}

local WASH_PRICES = {
	Small = 5,
	Middle = 10,
	Full = 15
}

local IMAGE_STATES = {
	{"Tick", "Load", "Cross"},
	{"Tick", "Tick", "Load"},
	{"Tick", "Tick", "Tick"},
	{"Tick", "Cross", "Cross"} -- card declined
}

local IMAGES = {
	Tick = "rbxassetid://134007213543148",
	Load = "rbxassetid://2459243309",
	Cross = "rbxassetid://81435836476705"
}

local washTypeConf = ""
local EFTDB = false

local function formatPrice(price)
	return "€" .. price
end

-- Takes the price from the player's Cash. Returns false if the card is declined.
local function chargeCard(player, price)
	local stats = player:FindFirstChild("leaderstats")
	local cash = stats and stats:FindFirstChild("Cash")

	if not cash or cash.Value < price then
		return false
	end

	cash.Value -= price
	return true
end

function MainScreenModule:ShowFrame(frameName)
	for _, frame in pairs(FRAMES) do
		frame.Visible = false
	end
	FRAMES[frameName].Visible = true
	MainModule.values.MAIN_SCREEN = frameName
end

function MainScreenModule:SetProcessImages(step)
	local imageLabels = {
		FRAMES.Process.Frame.WSelected.ImageLabel,
		FRAMES.Process.Frame.WCard.ImageLabel,
		FRAMES.Process.Frame.PWash.ImageLabel
	}
	local state = IMAGE_STATES[step]

	for i, imageLabel in ipairs(imageLabels) do
		imageLabel.Image = IMAGES[state[i]]
	end
end

function MainScreenModule:ShowEFTMessage(title, message)
	EFTScreen.Message.Txt1.Text = title
	EFTScreen.Message.Txt2.Text = message
end

function MainScreenModule:AnimateLights(duration, callback)
	local lights = {EFTScreen.Ready.Light2, EFTScreen.Ready.Light3, EFTScreen.Ready.Light4}

	for _, light in ipairs(lights) do
		light.BackgroundColor3 = Color3.fromRGB(0, 200, 50)
		wait(.2)
	end

	wait(duration - 0.6)
	if callback then callback() end
end

function MainScreenModule:EFTProcess(action, player)
	if action == "init" then
		EFTScreen.Idle.Visible = false
		EFTScreen.Ready.Visible = true
		self:ShowEFTMessage("", "")
		EFTScreen.Ready.Amount.Text = string.format("%.2f", WASH_PRICES[washTypeConf])
		for _, light in ipairs({EFTScreen.Ready.Light2, EFTScreen.Ready.Light3, EFTScreen.Ready.Light4}) do
			light.BackgroundColor3 = Color3.fromRGB(0, 50, 25)
		end
		self:SetProcessImages(1)

	elseif action == "touch" and EFTScreen.Ready.Visible == true then
		EFTDB = true
		self:AnimateLights(0.6, function()
			EFTSound:Play()
		end)

		EFTScreen.Ready.Visible = false
		EFTScreen.Message.Visible = true

		local sequence = {
			{title = "Initializing", message = "Checking...", wait = 1},
			{title = "MasterCard", message = "Connecting...", wait = 1},
			{title = "MasterCard", message = "Sending...", wait = 1.8},
			{title = "MasterCard", message = "Reciving...", wait = 1.4}
		}

		EFTSound:Stop()

		for i, step in ipairs(sequence) do
			self:ShowEFTMessage(step.title, step.message)
			wait(step.wait)
		end

		if chargeCard(player, WASH_PRICES[washTypeConf]) then
			self:ShowEFTMessage("", "Accepted")
			self:SetProcessImages(2)
			task.spawn(function()self:ProceedCheck()end)
			wait(2)
		else
			self:ShowEFTMessage("Declined", "Insufficient funds")
			self:SetProcessImages(4)
			wait(3)
			self:ShowFrame("Selection")
		end

		EFTScreen.Message.Visible = false
		EFTScreen.Idle.Visible = true
		EFTDB = false
	end
end

function MainScreenModule:ProceedCheck()
	while MainModule.values.OCCUPIED do
		wait(0.1)
	end
	root.GateEN.Frame.MotorSupport.HingeConstraint.TargetAngle = -80
	wait(2)
	MainModule.values.MAIN_SCREEN_DONE = true
	MainModule.values.WASH = washTypeConf
	self:SetProcessImages(3)
end

function MainScreenModule:ResetFrame()
	FRAMES.Process.Visible = false
	FRAMES.Selection.Visible = true
end

function MainScreenModule:ChooseWash(washType)
	FRAMES.Confirm.WashSelected.Text = WASH_TYPES[washType]
	FRAMES.Confirm.Confirm.Text = "Pay " .. formatPrice(WASH_PRICES[washType])
	washTypeConf = washType
	self:ShowFrame("Confirm")
end

function MainScreenModule:ConnectWashButtons()
	for washType in pairs(WASH_TYPES) do
		local button = FRAMES.Selection.Selection[washType].Choose
		button.Text = formatPrice(WASH_PRICES[washType])
		button.MouseButton1Click:Connect(function()
			self:ChooseWash(washType)
		end)
	end
end

function MainScreenModule:ConnectConfirmButtons()
	FRAMES.Confirm.Confirm.MouseButton1Click:Connect(function()
		self:ShowFrame("Process")
		self:EFTProcess("init")
	end)

	FRAMES.Confirm.Cancel.MouseButton1Click:Connect(function()
		self:ShowFrame("Selection")
	end)
end

function MainScreenModule:ConnectEFTReader()
	local debounce = false
	EFTTouch.Touched:Connect(function(hit)
		if debounce or EFTDB or hit.Parent.Name ~= "Debit Card" then return end
		local player = Players:GetPlayerFromCharacter(hit.Parent.Parent)
		if not player then return end
		debounce = true
		self:EFTProcess("touch", player)
		wait(10)
		debounce = false
	end)
end

function MainScreenModule:ConnectEvents()
	self:ConnectWashButtons()
	self:ConnectConfirmButtons()
	self:ConnectEFTReader()
end

function MainScreenModule:Initialize(mainModule)
	MainModule = mainModule
	self:ShowFrame("Selection")
	self:ConnectEvents()
end

return MainScreenModule