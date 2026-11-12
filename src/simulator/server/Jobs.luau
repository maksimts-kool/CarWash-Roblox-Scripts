-- Customer jobs: the core loop of the simulator.
--
--   1. Hold E at the Job Board: a customer's dirty car appears in a free bay
--      of the Drop-Off lot. Only you can drive it.
--   2. The customer hands over the money for the wash they want (the player's
--      WashBudget attribute). It isn't yours: Cash.charge spends it at the
--      kiosk, and whatever's left goes back to the customer when the job ends.
--      Drive to the kiosk, pay, and run it through the wash. Wash marks the
--      car with LastWashProgram as it leaves the tunnel.
--   3. Stop it on the Customer Pickup pad: the customer rates how clean it
--      is and pays you (base + tip), you get XP, and you're sent back to the
--      Job Board for the next one.
--
-- The player's current job is mirrored for the HUD: attributes JobActive,
-- JobCustomer, JobCarName, JobWants, JobVip, JobPay, JobLine, JobEndsAt and an
-- ObjectValue "JobCar" under the player.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local SimConfig = require(ReplicatedStorage:WaitForChild("SimConfig"))
local PlayerData = require(script.Parent.PlayerData)
local WashConfig = require(game:GetService("ServerScriptService"):WaitForChild("CarWash"):WaitForChild("Config"))

local World = workspace:WaitForChild("Simulator")
local Bays = World:WaitForChild("DropOff"):WaitForChild("Bays")
local PickupZone: BasePart = World:WaitForChild("Pickup"):WaitForChild("Zone")
local ReturnPoint: BasePart = World:WaitForChild("ReturnPoint")
local TakeJobPrompt: ProximityPrompt = World:WaitForChild("JobBoard"):WaitForChild("Panel"):WaitForChild("PromptAttachment"):WaitForChild("TakeJob")
local Templates = ServerStorage:WaitForChild("SimCars")
local TagTemplate: BillboardGui = ServerStorage:WaitForChild("SimGui"):WaitForChild("JobTag")

local Jobs = {}

type Job = {
	player: Player,
	model: Model,
	seat: VehicleSeat,
	bay: BasePart,
	customer: string,
	carName: string,
	wants: string,
	vip: boolean,
	pay: number,
	xp: number,
	endsAt: number,
	done: boolean,
	lastNag: number,
	connections: { RBXScriptConnection },
}

local jobs: { [Player]: Job } = {}
local notify: RemoteEvent
local reward: RemoteEvent

local jobCars = Instance.new("Folder")
jobCars.Name = "JobCars"
jobCars.Parent = World

local rng = Random.new()

local function pick(list)
	return list[rng:NextInteger(1, #list)]
end

local function money(n: number): string
	return SimConfig.Currency .. tostring(math.floor(n + 0.5))
end

---------------------------------------------------------------- HUD mirror
local function publish(player: Player, job: Job?)
	player:SetAttribute("JobActive", job ~= nil)
	player:SetAttribute("JobCustomer", job and job.customer)
	player:SetAttribute("JobCarName", job and job.carName)
	player:SetAttribute("JobWants", job and job.wants)
	player:SetAttribute("JobVip", job and job.vip)
	player:SetAttribute("JobPay", job and job.pay)
	player:SetAttribute("JobEndsAt", job and job.endsAt)
	if not job then
		-- unspent wash money goes back to the customer
		player:SetAttribute("WashBudget", nil)
	end
	local value = player:FindFirstChild("JobCar")
	if not value then
		local created = Instance.new("ObjectValue")
		created.Name = "JobCar"
		created.Parent = player
		value = created
	end
	local objectValue = value :: ObjectValue
	objectValue.Value = if job then job.model else nil
end

---------------------------------------------------------------- cars
local function seatOf(model: Instance): VehicleSeat?
	return model:FindFirstChildWhichIsA("VehicleSeat", true)
end

-- A bay with no car parked on it.
local function freeBay(): BasePart?
	local bays = Bays:GetChildren()
	table.sort(bays, function(a, b)
		return a.Name < b.Name
	end)
	for _, bay in bays do
		if not bay:IsA("BasePart") then
			continue
		end
		local taken = false
		for _, job in jobs do
			if job.bay == bay and job.seat:IsDescendantOf(workspace) then
				local flat = (job.seat.Position - bay.Position) * Vector3.new(1, 0, 1)
				if flat.Magnitude < 16 then
					taken = true
				end
			end
		end
		for _, model in CollectionService:GetTagged("WashableCar") do
			local seat = seatOf(model)
			if seat and ((seat.Position - bay.Position) * Vector3.new(1, 0, 1)).Magnitude < 12 then
				taken = true
			end
		end
		if not taken then
			return bay
		end
	end
	return nil
end

local function eject(seat: VehicleSeat)
	local humanoid = seat.Occupant
	if humanoid then
		local weld = seat:FindFirstChild("SeatWeld")
		if weld then
			weld:Destroy()
		end
		humanoid.Sit = false
		humanoid.Jump = true
	end
end

-- The name tag above a customer's car: a copy of ServerStorage.SimGui.JobTag
-- (edit its look there), filled in for this job and gold for a VIP. Only
-- other players see it: the owner's job panel already says all of this.
local function tag(seat: VehicleSeat, job: Job)
	local gui = TagTemplate:Clone()
	local frame = gui.Frame
	frame.Badge.Image = SimConfig.Icons[if job.vip then "Crown" else "Customer"]
	frame.Title.Text = (if job.vip then "VIP " else "") .. job.customer .. " • " .. SimConfig.ProgramNames[job.wants]
	frame.Subtitle.Text = "Job for " .. job.player.DisplayName
	if job.vip then
		frame.BackgroundColor3 = Color3.fromRGB(60, 45, 10)
		frame.UIStroke.Color = Color3.fromRGB(255, 205, 60)
		frame.Title.TextColor3 = Color3.fromRGB(255, 220, 100)
	end
	gui.PlayerToHideFrom = job.player
	gui.Parent = seat
end

---------------------------------------------------------------- job lifecycle
local function finish(job: Job, removeCarAfter: number?)
	if jobs[job.player] == job then
		jobs[job.player] = nil
		publish(job.player, nil)
	end
	job.done = true
	for _, connection in job.connections do
		connection:Disconnect()
	end
	local model = job.model
	task.delay(removeCarAfter or 0, function()
		if job.seat.Parent then
			eject(job.seat)
		end
		model:Destroy()
	end)
end

local function chooseCustomer(player: Player)
	local level = player:GetAttribute("Level") or 1
	local pool, total = {}, 0
	for index, def in SimConfig.Customers do
		if def.unlock <= level then
			-- newer unlocks turn up more often
			total += index
			table.insert(pool, { def = def, weight = index })
		end
	end
	local roll = rng:NextNumber(0, total)
	for _, entry in pool do
		roll -= entry.weight
		if roll <= 0 then
			return entry.def
		end
	end
	return pool[#pool].def
end

local function startJob(player: Player)
	if not player:GetAttribute("DataLoaded") then
		notify:FireClient(player, "Still loading your save, try again in a second.", "warn")
		return
	end
	local current = jobs[player]
	if current then
		notify:FireClient(player, "Finish this one first, or cancel it.", "warn")
		return
	end
	local bay = freeBay()
	if not bay then
		notify:FireClient(player, "The Drop-Off lot is full. Wait for a bay to free up!", "warn")
		return
	end

	local def = chooseCustomer(player)
	local template = Templates:FindFirstChild(def.car)
	if not template then
		warn("Simulator: missing car template", def.car)
		return
	end

	local billboards = PlayerData.upgradeLevel(player, "Billboard")
	local vip = rng:NextNumber() < SimConfig.VipChanceBase + 0.08 * billboards
	local wants = if vip then "Full" else pick(def.wants)
	local pay = def.pay * (if vip then SimConfig.VipPayMultiplier else 1)

	local model = template:Clone() :: Model
	model.Name = def.car .. "_" .. player.UserId
	local offset = template:GetAttribute("SpawnOffset") or CFrame.identity
	model:PivotTo(CFrame.new(bay.Position.X, bay.Position.Y + 0.4, bay.Position.Z) * offset)
	model:SetAttribute("SpawnOffset", nil)
	model:SetAttribute("Dirt", rng:NextNumber(SimConfig.StartDirt[1], SimConfig.StartDirt[2]))
	model:SetAttribute("JobOwner", player.UserId)

	local seat = seatOf(model) :: VehicleSeat
	local job: Job = {
		player = player,
		model = model,
		seat = seat,
		bay = bay,
		customer = pick(SimConfig.CustomerNames),
		carName = def.carName,
		wants = wants,
		vip = vip,
		pay = pay,
		xp = def.xp * (if vip then 1.5 else 1),
		endsAt = workspace:GetServerTimeNow() + SimConfig.JobTimeoutSeconds,
		done = false,
		lastNag = 0,
		connections = {},
	}
	tag(seat, job)
	model.Parent = jobCars
	jobs[player] = job
	publish(player, job)

	-- the customer pays for their own wash
	local program = WashConfig.Programs[wants]
	local washPrice = if program then program.price else 0
	player:SetAttribute("WashBudget", washPrice)

	-- only the job's owner may drive it
	table.insert(job.connections, seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		local humanoid = seat.Occupant
		if not humanoid then
			return
		end
		local driver = Players:GetPlayerFromCharacter(humanoid.Parent)
		if driver ~= player then
			task.defer(eject, seat)
			if driver then
				notify:FireClient(driver, "That car belongs to another washer.", "warn")
			end
		end
	end))
	table.insert(job.connections, model:GetAttributeChangedSignal("LastWashProgram"):Connect(function()
		local program = model:GetAttribute("LastWashProgram")
		if program then
			-- the objective switches to delivering; this is just the cheer
			notify:FireClient(player, "Sparkling!", "good")
		end
	end))
	table.insert(job.connections, model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(workspace) and not job.done then
			finish(job)
			notify:FireClient(player, "Your customer's car is gone. Job cancelled.", "warn")
		end
	end))

	-- the job panel shows who, what and how much; the toast is only their voice
	notify:FireClient(player, `"{pick(SimConfig.CustomerLines)}"`, "job")
end

-- How the customer rates the car they get back.
local function evaluate(job: Job)
	local model = job.model
	local dirt = model:GetAttribute("Dirt") or 1
	local soap = model:GetAttribute("Soap") or 0
	local wet = model:GetAttribute("Wet") or 0
	local shine = model:GetAttribute("Shine") or 0
	local condition = model:GetAttribute("Condition") or "?"
	local washed = model:GetAttribute("LastWashProgram")

	local score = (1 - dirt) * 70 + shine * 20 + (if soap < 0.1 and wet < 0.25 then 10 else 0)
	score += SimConfig.DetailKitScore * PlayerData.upgradeLevel(job.player, "DetailKit")
	score = math.clamp(math.floor(score + 0.5), 0, 100)
	local stars = 1
	for i, threshold in SimConfig.StarThresholds do
		if score >= threshold then
			stars = 6 - i
			break
		end
	end

	local notes = {}
	local wantedRank = SimConfig.ProgramRank[job.wants] or 1
	local gotRank = SimConfig.ProgramRank[washed] or 0
	if gotRank < wantedRank then
		stars = math.max(1, stars - SimConfig.WrongProgramStars)
		table.insert(notes, `I asked for the {SimConfig.ProgramNames[job.wants]}...`)
	elseif gotRank > wantedRank then
		table.insert(notes, "Ooh, you upgraded my wash!")
	end
	if wet >= 0.25 then
		table.insert(notes, "Still dripping wet.")
	end

	local player = job.player
	local level = player:GetAttribute("Level") or 1
	local soapLevel = PlayerData.upgradeLevel(player, "PremiumSoap")
	local tipLevel = PlayerData.upgradeLevel(player, "TipJar")

	local base = job.pay * (1 + 0.10 * soapLevel) * (1 + SimConfig.LevelPayBonus * (level - 1))
	local tipRate = if stars >= 3 then SimConfig.TipPerStar * (stars - 2) else 0
	if condition == "Showroom Shine" then
		tipRate += SimConfig.ShowroomBonus
	end
	if job.vip and stars < 4 then
		tipRate = 0
		table.insert(notes, "A VIP expects better than that.")
	end
	if gotRank > wantedRank then
		tipRate += 0.1
	end
	local tip = base * tipRate * (1 + 0.15 * tipLevel)
	local xp = math.floor(job.xp * (0.6 + 0.1 * stars) + 0.5)

	local comments = {
		"Is this even the same car?!",
		"Hmm. It'll do.",
		"Nice job, thanks!",
		"Wow, it looks brand new!",
		"Absolutely spotless. You're the best!",
	}
	return {
		customer = job.customer,
		carName = job.carName,
		vip = job.vip,
		wants = job.wants,
		washed = washed,
		condition = condition,
		score = score,
		stars = stars,
		base = math.floor(base + 0.5),
		tip = math.floor(tip + 0.5),
		xp = xp,
		comment = comments[stars],
		notes = notes,
	}
end

local function deliver(job: Job)
	local player = job.player
	local result = evaluate(job)
	local total = result.base + result.tip
	result.total = total

	PlayerData.addCash(player, total)
	PlayerData.recordJob(player, result.stars, total)
	result.levelUp = PlayerData.addXP(player, result.xp)
	if result.levelUp then
		local unlocked = {}
		for _, def in SimConfig.Customers do
			if def.unlock == result.levelUp then
				table.insert(unlocked, def.carName)
			end
		end
		result.unlocked = unlocked
	end
	reward:FireClient(player, result)
	print(`Simulator: {player.Name} delivered {result.customer}'s {result.carName}: {result.stars}* score {result.score}, {money(total)}`)

	finish(job, 2.5)

	-- back to the Job Board for the next customer
	task.delay(1.2, function()
		local character = player.Character
		if character and character.Parent then
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.SeatPart then
				humanoid.Sit = false
				task.wait(0.2)
			end
			character:PivotTo(ReturnPoint.CFrame * CFrame.Angles(0, math.pi, 0) + Vector3.new(0, 3, 0))
		end
	end)
end

local function onPad(seat: BasePart): boolean
	local rel = PickupZone.CFrame:PointToObjectSpace(seat.Position)
	return math.abs(rel.X) <= PickupZone.Size.X / 2 and math.abs(rel.Z) <= PickupZone.Size.Z / 2 and math.abs(rel.Y) < 12
end

local function watch()
	while true do
		task.wait(0.25)
		local now = workspace:GetServerTimeNow()
		for player, job in jobs do
			if job.done then
				continue
			end
			if now > job.endsAt then
				notify:FireClient(player, `{job.customer} got tired of waiting and took their car back.`, "warn")
				finish(job)
				continue
			end
			local seat = job.seat
			if not seat:IsDescendantOf(workspace) or not onPad(seat) then
				continue
			end
			if not job.model:GetAttribute("LastWashProgram") then
				if os.clock() - job.lastNag > 6 then
					job.lastNag = os.clock()
					notify:FireClient(player, `"It's still filthy! Run it through the wash first."`, "warn")
				end
				continue
			end
			if seat.AssemblyLinearVelocity.Magnitude <= SimConfig.DeliverMaxSpeed then
				deliver(job)
			end
		end
	end
end

function Jobs.cancel(player: Player)
	local job = jobs[player]
	if job then
		finish(job)
		notify:FireClient(player, `Job cancelled. {job.customer} drove off.`, "info")
	end
end

function Jobs.start(notifyRemote: RemoteEvent, rewardRemote: RemoteEvent, cancelRemote: RemoteEvent)
	notify, reward = notifyRemote, rewardRemote
	TakeJobPrompt.Triggered:Connect(startJob)
	cancelRemote.OnServerEvent:Connect(Jobs.cancel)
	Players.PlayerAdded:Connect(function(player)
		publish(player, nil)
	end)
	for _, player in Players:GetPlayers() do
		publish(player, nil)
	end
	Players.PlayerRemoving:Connect(function(player)
		local job = jobs[player]
		if job then
			finish(job)
		end
	end)
	task.spawn(watch)
end

return Jobs
