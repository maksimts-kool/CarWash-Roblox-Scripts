-- Moving Gradient Hexagons In Sequence by Rows and Groups (No texture)
-- Author: T3 Chat
-- Date: 11 Dec 2025

local Workspace = game:GetService("Workspace")
local rootFolder = script.Parent

-- Define color gradient palette
local gradientColors = {
	Color3.fromRGB(69, 126, 170),
	Color3.fromRGB(150, 0, 152),
}

-- Settings
local gradientSpeed = 0.2   -- speed of gradient movement
local groupDelay = 0.6      -- delay between each HexagonsGroup
local rowDelay = 0.2        -- delay between each Row inside a group
local colorSpread = 50      -- spatial width of color transition
local updateRate = 0.02     -- update step time

-- Utility: lerp between two colors
local function lerpColor(c1, c2, t)
	return Color3.new(
		c1.R + (c2.R - c1.R) * t,
		c1.G + (c2.G - c1.G) * t,
		c1.B + (c2.B - c1.B) * t
	)
end

-- Utility: compute gradient color based on spatial phase
local function sampleGradient(x, timeNow)
	local phase = (x / colorSpread + timeNow * gradientSpeed) % #gradientColors
	local idx1 = math.floor(phase) + 1
	local idx2 = (idx1 % #gradientColors) + 1
	local t = phase - math.floor(phase)
	return lerpColor(gradientColors[idx1], gradientColors[idx2], t)
end

-- Gather all groups, rows, and their parts named "Color"
local allGroups = {}
for g = 1, 9 do
	local group = rootFolder:WaitForChild("HexagonsGroup" .. g)
	local rows = { "Row11", "Row12", "Row21", "Row22" }
	local rowList = {}

	for _, rowName in ipairs(rows) do
		local row = group:WaitForChild(rowName)
		local rowParts = {}

		for _, part in ipairs(row:GetChildren()) do
			if part:IsA("BasePart") and part.Name == "Color" then
				table.insert(rowParts, part)
			end
		end

		table.insert(rowList, rowParts)
	end

	table.insert(allGroups, rowList)
end

-- Main animation loop
task.spawn(function()
	while true do
		local timeNow = tick()
		for groupIndex, rowList in ipairs(allGroups) do
			for rowIndex, parts in ipairs(rowList) do
				-- Add delay based on the group and row
				local phaseOffset = (groupIndex - 1) * groupDelay + (rowIndex - 1) * rowDelay
				local effectiveTime = timeNow - phaseOffset

				for _, part in ipairs(parts) do
					local posX = part.Position.X
					local c = sampleGradient(posX, effectiveTime)
					part.Color = c
				end
			end
		end
		task.wait(updateRate)
	end
end)