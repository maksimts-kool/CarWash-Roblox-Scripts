-- The pay terminal (CarWash.Selections): pick a wash on the screen, confirm,
-- then tap a "Debit Card" tool on the EFT reader to pay from leaderstats.Cash.
--
-- The server owns what the screen says; client/KioskScreen animates it:
--   Pages.Select / Confirm / Process   which page is visible
--   Pages.Process attribute "State"    "WaitingForCard" | "Processing" | "Paid"
--                                      | "Proceed" | "Declined"
--   Pages.Process.Status Title/Message what the payment is doing

local Players = game:GetService("Players")

local Cash = require(script.Parent.Cash)
local Config = require(script.Parent.Config)

local Selections = workspace:WaitForChild("CarWash"):WaitForChild("Selections")
local GUI = Selections.Screen.SurfaceGui
local Reader = Selections.EFTReader
local LCD = Reader.Screen.SurfaceGui.Frame.LCD
local ContactlessSound = Reader.Screen.Contactless

local Pages = GUI.Pages
local PAGES = {
	Select = Pages.Select,
	Confirm = Pages.Confirm,
	Process = Pages.Process,
}
local Cards = Pages.Select.Cards -- one slot per program, with an "Accent" attribute
local Summary = Pages.Confirm.Summary.Card
local Side = Pages.Confirm.Side
local Steps = Pages.Process.Steps.Card
local Status = Pages.Process.Status.Card

local INK = Color3.fromRGB(22, 32, 52)
local MUTED = Color3.fromRGB(110, 122, 140)
local NOT_INCLUDED = Color3.fromRGB(185, 194, 208)

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

local function formatAmount(price: number): string
	return Config.Currency .. string.format("%.2f", price)
end

local function showPage(name: string)
	for pageName, page in PAGES do
		page.Visible = pageName == name
	end
end

local function showPayment(state: string, title: string, message: string)
	Status.Title.Text = title
	Status.Message.Text = message
	Pages.Process:SetAttribute("State", state)
end

local function showReaderMessage(title: string, message: string)
	LCD.Message.Txt1.Text = title
	LCD.Message.Txt2.Text = message
end

local function includes(program: string, stage: string): boolean
	return table.find(Config.Programs[program].arches, stage) ~= nil
end

-- One line of a wash's stage list: a ticked dot, or a dash when the wash skips it.
local function showFeature(row: Instance, stage: string, included: boolean, accent: Color3)
	row.Label.Text = Config.StageNames[stage]
	row.Label.TextColor3 = if included then INK else MUTED
	row.Label.TextTransparency = if included then 0 else 0.25
	row.Icon.BackgroundColor3 = if included then accent else NOT_INCLUDED
	row.Icon.Check.Visible = included
	row.Icon.Dash.Visible = not included
end

-- Fills each menu card from Config: name, price and the stages it runs.
local function fillMenu()
	for program, info in Config.Programs do
		local slot = Cards[program]
		local accent = slot:GetAttribute("Accent")
		slot.Card.WashName.Text = info.name
		slot.Card.Price.Text = formatPrice(info.price)
		for index, stage in Config.StageOrder do
			local row = slot.Card.Features:FindFirstChild("Feature" .. index)
			if row then
				showFeature(row, stage, includes(program, stage), accent)
			end
		end
	end
end

-- The Confirm page takes the chosen card's colour, name and stage list.
local function fillSummary(program: string)
	local info = Config.Programs[program]
	local slot = Cards[program]
	local accent = slot:GetAttribute("Accent")

	local band = Summary.Band
	band.BackgroundColor3 = accent
	band.Square.BackgroundColor3 = accent
	-- the car's windows, lights and wheel rims are cut-outs in the band colour
	for _, item in band.Art.Car:GetDescendants() do
		if item:GetAttribute("Hole") then
			if item:IsA("UIStroke") then
				item.Color = accent
			elseif item:IsA("GuiObject") then
				item.BackgroundColor3 = accent
			end
		end
	end
	-- as many drops as the menu card shows, centred over the car
	local tier = #slot.Card.Band.Art.Drops:GetChildren()
	for _, dropFrame in band.Art.Drops:GetChildren() do
		local index = tonumber(dropFrame.Name:match("%d+"))
		dropFrame.Visible = index ~= nil and index <= tier
		if index then
			local x = math.round((index - (tier + 1) / 2) * 22)
			dropFrame.Position = UDim2.new(0.5, x - 7, 0, 0)
		end
	end
	band.WashName.Text = info.name
	band.Tag.Text = `{#info.arches} wash stages`

	local rows = Summary.Features
	local index = 0
	for _, stage in Config.StageOrder do
		if includes(program, stage) then
			index += 1
			local row = rows:FindFirstChild("Feature" .. index)
			if row then
				row.Visible = true
				row.Icon.BackgroundColor3 = accent
				row.Label.Text = Config.StageNames[stage]
			end
		end
	end
	for _, row in rows:GetChildren() do
		local rowIndex = tonumber(row.Name:match("^Feature(%d+)$"))
		if rowIndex and rowIndex > index then
			row.Visible = false
		end
	end

	Side.Total.Card.Price.Text = formatAmount(info.price)
	Side.Confirm.Label.Text = "Pay " .. formatPrice(info.price)
	Steps.Selected.Sub.Text = `{info.name} · {formatPrice(info.price)}`
	Status.Amount.Text = formatAmount(info.price)
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
	Steps.Drive.Sub.Text = "Wait for the gate to open"
	showPayment("WaitingForCard", "Tap your card", "Hold your Debit Card to the reader below")
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
		showPayment("Processing", "Processing", step.message)
		task.wait(step.seconds)
	end

	if Cash.charge(player, Config.Programs[program].price) then
		showReaderMessage("", "Accepted")
		showPayment("Paid", "Payment accepted", "The gate opens as soon as the wash is free")
		task.spawn(function()
			onPaid(program)
			Steps.Drive.Sub.Text = "The gate is open"
			showPayment("Proceed", "Drive in", "Drive forward onto the conveyor")
		end)
		task.wait(2)
	else
		showReaderMessage("Declined", "Insufficient funds")
		showPayment("Declined", "Card declined", "Insufficient funds")
		task.wait(3)
		showPage("Select")
	end

	LCD.Message.Visible = false
	LCD.Idle.Visible = true
	paying = false
end

local function choose(program: string)
	selectedProgram = program
	fillSummary(program)
	showPage("Confirm")
end

local function connectButtons()
	for program in Config.Programs do
		local card = Cards[program].Card
		card.MouseButton1Click:Connect(function()
			choose(program)
		end)
		card.Choose.MouseButton1Click:Connect(function()
			choose(program)
		end)
	end

	Side.Confirm.MouseButton1Click:Connect(function()
		if selectedProgram then
			showPage("Process")
			armReader(Config.Programs[selectedProgram].price)
		end
	end)
	Side.Cancel.MouseButton1Click:Connect(function()
		showPage("Select")
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
	showPage("Select")
end

-- paidCallback(program) runs after a successful payment. It may yield until
-- the customer is let in; the terminal shows "proceed" once it returns.
function Kiosk.start(paidCallback: (program: string) -> ())
	onPaid = paidCallback
	fillMenu()
	showPage("Select")
	connectButtons()
	connectReader()
end

return Kiosk
