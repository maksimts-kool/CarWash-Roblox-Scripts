-- Turns the wash's physics-driven machinery into scripted joints when the
-- server starts, so nothing in Workspace.CarWash is simulated any more.
--
-- The place is built with HingeConstraints (gate arms, brush swings and
-- spins), legacy Rotate joints spun by BodyAngularVelocities (the wheel
-- blaster heads), legacy surface motors (the dryer fans) and the odd rope /
-- spring / mover. Here, in one go before physics runs:
--
--   1. the moving models are welded into rigid assemblies (Welds);
--   2. every Rotate / RotateP / RotateV joint becomes a Motor6D "Joint" in the
--      same place, turning about the same axis (its C0's Z axis);
--   3. every HingeConstraint becomes a Motor6D in the same place, joining the
--      moving side to the side that holds it (anchored, or itself held by a
--      joint made earlier). Hinges named "HingeConstraint" become "Joint";
--      others keep their name;
--   4. every FanMotor gets a Motor6D "Joint" spinning it about its right face,
--      on a hidden anchored pivot, and its surface motor is removed;
--   5. every other constraint and body mover is removed (visible ropes, rods
--      and springs stay, as scenery), and anything left loose is anchored
--      where it is.
--
-- The moving parts all hang off anchored parts through these joints, so they
-- are anchored assemblies: no physics, no network ownership, nothing to fling
-- the car. The client (Joints.client) moves them every frame by setting each
-- joint's Transform from the attributes set here:
--
--   Mode   "Servo": swings to Target (degrees) at up to Speed (degrees/s)
--          "Motor": spins at Spin (degrees/s), easing between speeds
--   Rest   the hinge angle the joint was built at
--   Sign   1, or -1 when the hinge's attachments were the other way round
--
-- Angles are hinge angles, so the old TargetAngle values still apply.

local CollectionService = game:GetService("CollectionService")

local Welds = require(script.Parent.Welds)

local CarWash = workspace:WaitForChild("CarWash")

local TAG = "CarWashJoint"
local DEFAULT_SERVO_SPEED = 90 -- degrees per second, for hinges saved without an AngularSpeed
local MAX_SERVO_SPEED = 360
-- Parts moved by a joint stop colliding (they'd shove the car), except these
-- barrier arms, which still have to stop a car that hasn't paid.
local KEEP_COLLISION = { "GateEN", "GateEX" }
-- The legacy joints that turned a part (driven by a BodyAngularVelocity).
local ROTATE_CLASSES = { Rotate = true, RotateP = true, RotateV = true }

local Joints = {}
Joints.TAG = TAG

------------------------------------------------------------------------------
-- Driving the joints (server)

-- The joint that replaced the hinge (or fan motor) under `parent`.
function Joints.get(parent: Instance?, name: string?): Motor6D?
	local joint = parent and parent:FindFirstChild(name or "Joint")
	if joint and joint:IsA("Motor6D") and joint:HasTag(TAG) then
		return joint
	end
	return nil
end

-- Swings a servo joint to `angle` degrees, optionally at a new top speed (degrees/s).
function Joints.servo(joint: Motor6D?, angle: number, speed: number?)
	if not joint then
		return
	end
	joint:SetAttribute("Mode", "Servo")
	joint:SetAttribute("Target", angle)
	if speed then
		joint:SetAttribute("Speed", speed)
	end
end

-- Spins a motor joint at `speed` degrees per second (0 to stop).
function Joints.spin(joint: Motor6D?, speed: number)
	if not joint then
		return
	end
	joint:SetAttribute("Mode", "Motor")
	joint:SetAttribute("Spin", speed)
end

------------------------------------------------------------------------------
-- Building them (once, at startup)

-- Parts already hung off an anchored part by a joint made here.
local held: { [BasePart]: boolean } = {}

local function isHeld(part: BasePart): boolean
	if held[part] or part.Anchored then
		return true
	end
	local root = part.AssemblyRootPart
	return root ~= nil and root.Anchored
end

local function keepsCollision(part: BasePart): boolean
	for _, name in KEEP_COLLISION do
		local model = CarWash:FindFirstChild(name)
		if model and part:IsDescendantOf(model) then
			return true
		end
	end
	return false
end

-- Hangs `child`'s assembly off `parent` with a Motor6D whose axis is the X axis
-- of `pivot` (a CFrame relative to `parent`), keeping it exactly where it is.
local function makeJoint(parent: BasePart, child: BasePart, pivot: CFrame, name: string, where: Instance): Motor6D
	local moving = child:GetConnectedParts(true)
	for _, part in moving do
		held[part] = true
		if not keepsCollision(part) then
			part.CanCollide = false
		end
	end

	local joint = Instance.new("Motor6D")
	joint.Name = name
	joint.Part0 = parent
	joint.Part1 = child
	joint.C0 = pivot
	joint.C1 = child.CFrame:ToObjectSpace(parent.CFrame * pivot)
	joint.Parent = where
	joint:AddTag(TAG)
	return joint
end

-- The hinge angle (degrees) of attachment `b` relative to attachment `a`:
-- how far b's secondary (Y) axis is turned about a's primary (X) axis.
local function hingeAngle(a: Attachment, b: Attachment): number
	local up = a.WorldCFrame:VectorToObjectSpace(b.WorldCFrame.UpVector)
	return math.deg(math.atan2(up.Z, up.Y))
end

type HingeInfo = {
	name: string,
	parent: Instance,
	a0: Attachment,
	a1: Attachment,
	actuator: Enum.ActuatorType,
	target: number,
	speed: number,
	velocity: number,
}

local function readHinge(hinge: HingeConstraint): HingeInfo?
	local a0, a1 = hinge.Attachment0, hinge.Attachment1
	if not (a0 and a1 and a0.Parent and a1.Parent and a0.Parent:IsA("BasePart") and a1.Parent:IsA("BasePart")) then
		return nil
	end
	return {
		name = if hinge.Name == "HingeConstraint" then "Joint" else hinge.Name,
		parent = hinge.Parent :: Instance,
		a0 = a0,
		a1 = a1,
		actuator = hinge.ActuatorType,
		target = hinge.TargetAngle,
		speed = math.deg(hinge.AngularSpeed),
		velocity = math.deg(hinge.AngularVelocity),
	}
end

-- Builds the joint for one hinge, if one of its sides is held already.
-- Returns false to try again once more joints exist.
local function convertHinge(info: HingeInfo): boolean
	local p0, p1 = info.a0.Parent :: BasePart, info.a1.Parent :: BasePart
	local held0, held1 = isHeld(p0), isHeld(p1)
	if held0 and held1 then
		if info.actuator ~= Enum.ActuatorType.None then
			warn(`Joints: both sides of {info.parent:GetFullName()}.{info.name} are fixed (anchored?); it can't move`)
		end
		return true
	elseif not (held0 or held1) then
		return false
	end

	local rest = hingeAngle(info.a0, info.a1)
	local joint
	if held0 then
		joint = makeJoint(p0, p1, info.a0.CFrame, info.name, info.parent)
		joint:SetAttribute("Sign", 1)
	else
		-- the hinge's Attachment0 is on the moving side: drive it the other way
		joint = makeJoint(p1, p0, info.a1.CFrame, info.name, info.parent)
		joint:SetAttribute("Sign", -1)
	end
	joint:SetAttribute("Rest", rest)

	if info.actuator == Enum.ActuatorType.Motor then
		Joints.spin(joint, info.velocity)
	elseif info.actuator == Enum.ActuatorType.Servo then
		local speed = if info.speed > 0 then math.min(info.speed, MAX_SERVO_SPEED) else DEFAULT_SERVO_SPEED
		Joints.servo(joint, info.target, speed)
	else
		-- a free-swinging hinge: it now just stays put
		Joints.servo(joint, rest, DEFAULT_SERVO_SPEED)
	end
	return true
end

local function convertHinges(skip: (Instance) -> boolean)
	local pending: { HingeInfo } = {}
	for _, item in CarWash:GetDescendants() do
		if item:IsA("HingeConstraint") and not skip(item) then
			local info = readHinge(item)
			if info then
				table.insert(pending, info)
			else
				warn(`Joints: {item:GetFullName()} isn't attached to two parts; removed`)
			end
			item:Destroy()
		end
	end

	-- A hinge can only hang off a side that's already held, so a swing arm has
	-- to be jointed before the brush that spins on it. Repeat until stuck.
	local progress = true
	while progress and #pending > 0 do
		progress = false
		local index = 1
		while index <= #pending do
			if convertHinge(pending[index]) then
				table.remove(pending, index)
				progress = true
			else
				index += 1
			end
		end
	end
	for _, info in pending do
		warn(`Joints: nothing holds either side of {info.parent:GetFullName()}.{info.name}; it will be anchored`)
	end
end

-- The legacy Rotate joints turn their parts about the Z axis of C0 (in
-- Part0's space); each becomes a Motor6D turning about that same axis, hung
-- off whichever side is held. They start stopped.
local function convertRotates(skip: (Instance) -> boolean)
	for _, item in CarWash:GetDescendants() do
		if not (item:IsA("JointInstance") and ROTATE_CLASSES[item.ClassName]) or skip(item) then
			continue
		end
		local joint = item :: JointInstance
		local name = joint:GetFullName()
		local p0, p1, where = joint.Part0, joint.Part1, joint.Parent
		local axis = p0 and p0.CFrame * joint.C0
		joint:Destroy()
		if not (p0 and p1 and axis and where) then
			warn(`Joints: {name} isn't joining two parts; removed`)
			continue
		end

		local held0, held1 = isHeld(p0), isHeld(p1)
		if held0 == held1 then
			warn(`Joints: {name} can't spin: {if held0 then "both sides are" else "neither side is"} held`)
			continue
		end
		local holder, moving = if held0 then p0 else p1, if held0 then p1 else p0
		-- the joint turns about its pivot's X axis: put the Rotate's Z axis there
		local pivot = axis * CFrame.fromMatrix(Vector3.zero, Vector3.zAxis, Vector3.xAxis)
		local motor = makeJoint(holder, moving, holder.CFrame:ToObjectSpace(pivot), "Joint", where)
		motor:SetAttribute("Sign", 1)
		motor:SetAttribute("Rest", 0)
		Joints.spin(motor, 0)
	end
end

local function convertFans()
	for _, unit in CarWash:GetChildren() do
		if not unit.Name:match("^KWS Storm Dryer") then
			continue
		end
		-- the legacy joints the surface motors made (RotateV for a Motor surface);
		-- removed here so convertRotates doesn't give each fan a second joint
		for _, item in unit:GetDescendants() do
			if item.ClassName == "Motor" or ROTATE_CLASSES[item.ClassName] then
				item:Destroy()
			end
		end
		for _, motor in unit:GetDescendants() do
			if not (motor:IsA("BasePart") and motor.Name == "FanMotor") then
				continue
			end
			for _, face in Enum.NormalId:GetEnumItems() do
				motor[face.Name .. "Surface"] = Enum.SurfaceType.Smooth
			end
			if motor.Anchored then
				warn(`Joints: {motor:GetFullName()} is anchored, so its fan can't spin`)
				continue
			end

			local pivot = Instance.new("Part")
			pivot.Name = "FanPivot"
			pivot.Anchored = true
			pivot.CanCollide = false
			pivot.CanQuery = false
			pivot.CanTouch = false
			pivot.Transparency = 1
			pivot.Size = Vector3.one * 0.2
			pivot.CFrame = motor.CFrame
			pivot.Parent = motor.Parent

			-- a surface motor turns about the normal of the face it's on: X here
			makeJoint(pivot, motor, CFrame.identity, "Joint", motor)
		end
	end
end

-- Visible ropes, rods and springs are scenery (the building's cables, the
-- clearance bar's rods): they're kept, and once their parts are anchored they
-- just draw a line between them.
local function isScenery(item: Instance): boolean
	return (item:IsA("RopeConstraint") or item:IsA("RodConstraint") or item:IsA("SpringConstraint"))
		and (item :: Constraint).Visible
end

-- Constraints that aren't welds or scenery, and the old BodyMovers.
local function isPhysics(item: Instance): boolean
	return (item:IsA("Constraint") and not item:IsA("RigidConstraint") and not isScenery(item))
		or item:IsA("BodyMover")
end

-- Leaves alone anything that's meant to be physical: tools, and vehicles (or
-- characters) that happen to be inside CarWash.
local function makeSkip(): (Instance) -> boolean
	local roots = {}
	for _, item in CarWash:GetDescendants() do
		if item:IsA("Tool") then
			table.insert(roots, item)
		elseif item:IsA("Seat") or item:IsA("VehicleSeat") or item:IsA("Humanoid") then
			local top = item
			while top.Parent and top.Parent ~= CarWash do
				top = top.Parent
			end
			table.insert(roots, if item:IsA("Seat") then item else top)
		end
	end
	return function(item: Instance): boolean
		for _, root in roots do
			if item == root or item:IsDescendantOf(root) then
				return true
			end
		end
		return false
	end
end

function Joints.setup()
	local skip = makeSkip()

	-- Everything but the hinges goes first, so it can't tie parts together below.
	local removed = 0
	for _, item in CarWash:GetDescendants() do
		if isPhysics(item) and not item:IsA("HingeConstraint") and not skip(item) then
			item:Destroy()
			removed += 1
		end
	end

	Welds.weldAll()
	convertFans() -- before convertRotates: the fans' surface motors are RotateV joints too
	convertRotates(skip)
	convertHinges(skip)

	-- Whatever the removed constraints were holding up stays where it is.
	local anchored = 0
	for _, part in CarWash:GetDescendants() do
		if part:IsA("BasePart") and not isHeld(part) and not skip(part) then
			part.Anchored = true
			anchored += 1
		end
	end

	local count = #CollectionService:GetTagged(TAG)
	print(`Joints: {count} scripted joints; removed {removed} other constraints, anchored {anchored} loose parts`)
end

return Joints
