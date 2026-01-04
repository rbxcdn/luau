-- AnimationPlayer: Minimal module to play animation data on a character

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local AnimationPlayer = {}
AnimationPlayer._state = {
	character = nil,
	data = nil,
	isPlaying = false,
	time = 0,
	speed = 1,
	boneCache = {}, -- motorName → Motor6D instance
	keyframeTimes = {}, -- Sorted array of keyframe timestamps
	flattenedKeyframes = {} -- timestamp → {motorName → CFrame}
}

-- Maps parent-child part names to Motor6D names
local function getMotorName(parentName: string, childName: string): string?
	-- R6 Rig mappings
	if parentName == "HumanoidRootPart" and childName == "Torso" then
		return "RootJoint"
	elseif parentName == "Torso" then
		local r6Map = {
			["Left Arm"] = "Left Shoulder",
			["Right Arm"] = "Right Shoulder", 
			["Left Leg"] = "Left Hip",
			["Right Leg"] = "Right Hip",
			["Head"] = "Neck"
		}
		return r6Map[childName]
	end
	-- R15 Rig mappings (optional)
	if parentName == "HumanoidRootPart" and childName == "LowerTorso" then
		return "Root"
	elseif parentName == "LowerTorso" and childName == "UpperTorso" then
		return "Waist"
	elseif parentName == "UpperTorso" then
		local r15Map = {
			["Head"] = "Neck",
			["LeftUpperArm"] = "LeftShoulder",
			["RightUpperArm"] = "RightShoulder"
		}
		return r15Map[childName]
	elseif parentName == "LowerTorso" then
		local r15Map = {
			["LeftUpperLeg"] = "LeftHip",
			["RightUpperLeg"] = "RightHip"
		}
		return r15Map[childName]
	end
	return nil
end

-- Flattens a keyframe hierarchy into motorName → CFrame pairs
local function flattenKeyframeHierarchy(hierarchy, parentName: string, result)
	for partName, data in pairs(hierarchy) do
		if type(data) ~= "table" then continue end

		local motorName = getMotorName(parentName, partName)
		if motorName and data.CFrame then
			result[motorName] = data.CFrame
		end

		-- Process children recursively
		for childName, childData in pairs(data) do
			if childName ~= "CFrame" and type(childData) == "table" then
				flattenKeyframeHierarchy({[childName] = childData}, partName, result)
			end
		end
	end
	return result
end

function AnimationPlayer:Play(animationData, targetCharacter: Model)
	self:Stop()

	self._state.character = targetCharacter
	self._state.data = animationData
	self._state.isPlaying = true
	self._state.time = 0
	self._state.speed = animationData.Properties and animationData.Properties.Speed or 1

	self:_disableDefaultAnimation()
	self:_processKeyframes()
	self:_cacheMotors()
	self:_startLoop()
end

function AnimationPlayer:Stop()
	self._state.isPlaying = false
	self._state.character = nil
	self._state.data = nil
	self._state.boneCache = {}
	self._state.keyframeTimes = {}
	self._state.flattenedKeyframes = {}
end

function AnimationPlayer:_disableDefaultAnimation()
	local humanoid = self._state.character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local animator = humanoid:FindFirstChild("Animator")
		if animator then animator:Destroy() end
	end

	local animateScript = self._state.character:FindFirstChild("Animate")
	if animateScript then animateScript:Destroy() end
end

function AnimationPlayer:_processKeyframes()
	self._state.keyframeTimes = {}
	self._state.flattenedKeyframes = {}

	-- Process and flatten all keyframes
	for timestamp, keyframeData in pairs(self._state.data.Keyframes) do
		if type(timestamp) == "number" then
			self._state.flattenedKeyframes[timestamp] = flattenKeyframeHierarchy(keyframeData, "", {})
			table.insert(self._state.keyframeTimes, timestamp)
		end
	end

	-- Sort keyframe times
	table.sort(self._state.keyframeTimes)
end

function AnimationPlayer:_cacheMotors()
	self._state.boneCache = {}

	-- Get motor names from the first keyframe
	if not self._state.keyframeTimes[1] then return end

	local firstKeyframe = self._state.flattenedKeyframes[self._state.keyframeTimes[1]]
	for motorName in pairs(firstKeyframe) do
		local motor = self._state.character:FindFirstChild(motorName, true)
		if motor and motor:IsA("Motor6D") then
			self._state.boneCache[motorName] = motor
		end
	end
end

function AnimationPlayer:_startLoop()
	local connection
	connection = RunService.RenderStepped:Connect(function(deltaTime)
		if not self._state.isPlaying then
			connection:Disconnect()
			return
		end

		-- Update time
		local animationLength = self._state.keyframeTimes[#self._state.keyframeTimes]
		self._state.time = (self._state.time + deltaTime * self._state.speed) % animationLength

		-- Find keyframes to interpolate between
		local currentKeyframeTime, nextKeyframeTime, alpha = self:_getKeyframeInterval()

		-- Apply animation
		self:_animateMotors(currentKeyframeTime, nextKeyframeTime, alpha)
	end)
end

function AnimationPlayer:_getKeyframeInterval()
	local times = self._state.keyframeTimes
	local currentTime = self._state.time

	-- Find the current keyframe
	for i = 1, #times - 1 do
		if currentTime >= times[i] and currentTime < times[i + 1] then
			local currentKeyframe = times[i]
			local nextKeyframe = times[i + 1]
			local alpha = (currentTime - currentKeyframe) / (nextKeyframe - currentKeyframe)
			return currentKeyframe, nextKeyframe, alpha
		end
	end

	-- Handle wrap-around (last to first)
	local lastTime = times[#times]
	local firstTime = times[1]
	if currentTime >= lastTime then
		return lastTime, firstTime, 0
	end

	return times[1], times[2], 0
end

function AnimationPlayer:_animateMotors(currentTime: number, nextTime: number, alpha: number)
	local currentKeyframes = self._state.flattenedKeyframes[currentTime]
	local nextKeyframes = self._state.flattenedKeyframes[nextTime]

	for motorName, motor in pairs(self._state.boneCache) do
		local currentCFrame = currentKeyframes[motorName]
		local nextCFrame = nextKeyframes[motorName]

		if currentCFrame and nextCFrame then
			-- Interpolate and apply transform
			motor.Transform = currentCFrame:Lerp(nextCFrame, alpha)
		end
	end
end

return AnimationPlayer
