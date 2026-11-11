-- The pay terminal (CarWash.Selections): pick a wash on the screen, confirm,
-- then tap a "Debit Card" tool on the EFT reader to pay from leaderstats.Cash.

local Players = game:GetService("Players")

local Cash = require(script.Parent.Cash)
local Config = require(script.Parent.Config)

local Selections = workspace:WaitForChild("CarWash"):WaitForChild("Selections")
local GUI = Selections.Screen.SurfaceGui
local Reader = Selections.EFTReader
local LCD = Reader.Screen.SurfaceGui.Frame.LCD
local ContactlessSound = Reader.Screen.Contactless

local FRAMES = {
	Selection = GUI.Select,
	Process = GUI.Process,
	Confirm = GUI.Confirm,
}

-- The three status icons on the Process frame: wash selected, card, proceed.
local PROCESS_ICONS = {
	GUI.Process.Frame.WSelected.ImageLabel,
	GUI.Process.Frame.WCard.ImageLabel,
	GUI.Process.Frame.PWash.ImageLabel,
}
local PROCESS_STEPS = {
	WaitingForCard = { "Tick", "Load", "Cross" },
	Paid = { "Tick", "Tick", "Load" },
	Proceed = { "Tick", "Tick", "Tick" },
	Declined = { "Tick", "Cross", "Cross" },
}
local IMAGES = {
	Tick = "rbxassetid://134007213543148",
	Load = "rbxassetid://2459243309",
	Cross = "rbxassetid://81435836476705",
}

local READER_LIGHTS = { LCD.Ready.Light2, LCD.Ready.Light3, LCD.Ready.Light4 }
local LIGHT_OFF = Color3.fromRGB(0, 50, 25)
local LIGHT_ON = Color3.fromRGB(0, 200, 50)

-- What the reader shows while it "talks to the bank".
local PAYMENT_SEQUENCE = {
	{ title = "Initializing", message = "Checking...", seconds = 1 },
	{ title = "MasterCard", message = "Connecting...", seconds = 1 },
	{ title = "MasterCard", message = "Sending...", seconds = 1.8 },
	{ title = "MasterCard", message = "Receiving...", seconds = 1.4 },
}

local CARD_TOOL = "Debit Card"
local READER_COOLDOWN = 10

local Kiosk = {}

local selectedProgram: string? = nil
local paying = false
local onPaid: (program: string) -> ()

local function formatPrice(price: number): string
	return Config.Currency .. price
end

local function showFrame(name: string)
	for frameName, frame in FRAMES do
		frame.Visible = frameName == name
	end
end

local function showStep(step: string)
	for index, icon in PROCESS_ICONS do
		icon.Image = IMAGES[PROCESS_STEPS[step][index]]
	end
end

local function showReaderMessage(title: string, message: string)
	LCD.Message.Txt1.Text = title
	LCD.Message.Txt2.Text = message
end

-- The reader wakes up and asks for the card.
local function armReader(price: number)
	LCD.Idle.Visible = false
	LCD.Ready.Visible = true
	showReaderMessage("", "")
	LCD.Ready.Amount.Text = string.format("%.2f", price)
	for _, light in READER_LIGHTS do
		light.BackgroundColor3 = LIGHT_OFF
	end
	showStep("WaitingForCard")
end

local function pay(player: Player)
	local program = selectedProgram
	if not program or not LCD.Ready.Visible then
		return
	end
	paying = true

	for _, light in READER_LIGHTS do
		light.BackgroundColor3 = LIGHT_ON
		task.wait(0.2)
	end
	ContactlessSound:Play()

	LCD.Ready.Visible = false
	LCD.Message.Visible = true
	for _, step in PAYMENT_SEQUENCE do
		showReaderMessage(step.title, step.message)
		task.wait(step.seconds)
	end

	if Cash.charge(player, Config.Programs[program].price) then
		showReaderMessage("", "Accepted")
		showStep("Paid")
		task.spawn(function()
			onPaid(program)
			showStep("Proceed")
		end)
		task.wait(2)
	else
		showReaderMessage("Declined", "Insufficient funds")
		showStep("Declined")
		task.wait(3)
		showFrame("Selection")
	end

	LCD.Message.Visible = false
	LCD.Idle.Visible = true
	paying = false
end

local function choose(program: string)
	local info = Config.Programs[program]
	FRAMES.Confirm.WashSelected.Text = info.name
	FRAMES.Confirm.Confirm.Text = "Pay " .. formatPrice(info.price)
	selectedProgram = program
	showFrame("Confirm")
end

local function connectButtons()
	for program, info in Config.Programs do
		local button = FRAMES.Selection.Selection[program].Choose
		button.Text = formatPrice(info.price)
		button.MouseButton1Click:Connect(function()
			choose(program)
		end)
	end

	FRAMES.Confirm.Confirm.MouseButton1Click:Connect(function()
		if selectedProgram then
			showFrame("Process")
			armReader(Config.Programs[selectedProgram].price)
		end
	end)
	FRAMES.Confirm.Cancel.MouseButton1Click:Connect(function()
		showFrame("Selection")
	end)
end

local function connectReader()
	local coolingDown = false
	Reader.Touchpart.Touched:Connect(function(hit)
		if coolingDown or paying or hit.Parent.Name ~= CARD_TOOL then
			return
		end
		local player = Players:GetPlayerFromCharacter(hit.Parent.Parent)
		if not player then
			return
		end
		coolingDown = true
		pay(player)
		task.wait(READER_COOLDOWN)
		coolingDown = false
	end)
end

-- Back to the wash menu, ready for the next customer.
function Kiosk.reset()
	showFrame("Selection")
end

-- paidCallback(program) runs after a successful payment. It may yield until
-- the customer is let in; the terminal shows "proceed" once it returns.
function Kiosk.start(paidCallback: (program: string) -> ())
	onPaid = paidCallback
	showFrame("Selection")
	connectButtons()
	connectReader()
end

return Kiosk
