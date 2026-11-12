-- Shows the "Emergency" frame on the tunnel's screens (TimerWash,
-- TimerWashScreen2, TimerDryer) and the entrance ProgressScreen while the
-- emergency stop is on (CarWash WashPhase "Stopped", set by the ControlPanel),
-- on each player's client.
--
-- The frames are saved in the place, one in each screen's SurfaceGui, on top
-- of its Body: edit their look and wording there. This script only shows them
-- and animates them: the badge pulses and the hazard stripes slide.

local TweenService = game:GetService("TweenService")

local CarWash = workspace:WaitForChild("CarWash")

local SCREENS = { "TimerWash", "TimerWashScreen2", "TimerDryer", "ProgressScreen" }
local PULSE = TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
local SLIDE = TweenInfo.new(1.5, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1)
local STRIPE_SPACING = 70 -- px between the saved stripes

type Screen = { frame: Frame, tweens: { Tween } }
local screens: { Screen } = {}

local function show(screen: Screen, on: boolean)
	local frame = screen.frame
	for _, tween in screen.tweens do
		tween:Cancel()
	end
	table.clear(screen.tweens)
	frame.Visible = on
	if not on then
		return
	end

	local badge = frame:FindFirstChild("Badge")
	local scale = badge and badge:FindFirstChildOfClass("UIScale")
	if scale then
		scale.Scale = 1
		local tween = TweenService:Create(scale, PULSE, { Scale = 1.1 })
		tween:Play()
		table.insert(screen.tweens, tween)
	end
	local stripes = frame:FindFirstChild("Stripes", true)
	if stripes and stripes:IsA("GuiObject") then
		stripes.Position = UDim2.fromOffset(0, 0)
		local tween = TweenService:Create(stripes, SLIDE, { Position = UDim2.fromOffset(STRIPE_SPACING, 0) })
		tween:Play()
		table.insert(screen.tweens, tween)
	end
end

local function update()
	local stopped = CarWash:GetAttribute("WashPhase") == "Stopped"
	for _, screen in screens do
		if screen.frame.Visible ~= stopped then
			show(screen, stopped)
		end
	end
end

for _, name in SCREENS do
	task.spawn(function()
		local model = CarWash:WaitForChild(name)
		local gui = model:FindFirstChildWhichIsA("SurfaceGui", true)
		while not (gui and gui:FindFirstChild("Emergency")) do
			task.wait(0.5)
			gui = model:FindFirstChildWhichIsA("SurfaceGui", true)
		end
		local screen = { frame = gui.Emergency :: Frame, tweens = {} }
		screen.frame.Visible = false
		table.insert(screens, screen)
		update()
	end)
end

CarWash:GetAttributeChangedSignal("WashPhase"):Connect(update)
