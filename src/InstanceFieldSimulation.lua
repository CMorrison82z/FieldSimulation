local FieldSimulation;

local CAST_TYPES = {
	None = 0,
	Box = 1,
	Sphere = 2,
	Part = 3,
}

local CAST_DEFAULTS = {
	DoRaycast = false, -- Fire raycasts on each update cycle. These are picked up bt .Hit 
	OverlapType = CAST_TYPES.None, -- Perform spacial queries
	FilterObjects = true, -- Whether objects in the same cache should be included in the filtered descendants for raycast and overlap params
	FilterType = Enum.RaycastFilterType.Blacklist,
	UpdateParticleOnRayHit = false -- whether to internally update particle.CFrame and particle.Distance on RaycastResults
}

local CACHE_FOLDER_NAME  = "_%sPartCache"

local INITIAL_CACHE_SIZE = 100

local ObjectCache = require(script.Parent.ObjectCache)
local Signal = require(script.Parent.Signal)

local t_insert = table.insert
local t_clone = table.clone

local hitSignal = Signal.new()
local overlappedSignal = Signal.new()
local simEndSignal = Signal.new()

local module = {}
module.Throttling = 0
module.Hit = hitSignal
module.Overlapped = overlappedSignal
module.SimulationEnded = simEndSignal -- callback function(ranSimulation)

local fieldSimulations = {}
local objectsCaches = {}

local runningSimulations = {}

function module:CreateField(name, func, funcParams)
	assert(not fieldSimulations[name], "Field with name " .. name .. " already exists")
	
	local newFs = FieldSimulation.new(func, funcParams)

	fieldSimulations[name] = newFs

	newFs.ParticleTerminated:Connect(function(particle)
		for index, value in ipairs(runningSimulations) do
			if value.Particle ~= particle then continue end

			module:EndSimulation(value)
		end
	end)

	return newFs
end

-- new object cache
function module:CreateObject(projectilePrefab)
	local cacheName = CACHE_FOLDER_NAME:format(projectilePrefab.Name)

	local cacheParent = Instance.new("Folder")
	cacheParent.Name = cacheName
	cacheParent.Parent = workspace

	local projectileTemplate = projectilePrefab:Clone()

	if projectileTemplate.ClassName == "Model" then
		for index, value in ipairs(projectileTemplate:GetDescendants()) do
			if not value:IsA("BasePart") then
				continue
			end

			value.CanCollide = false
			value.Anchored = true
			value.CanTouch = false
		end
	else
		projectileTemplate.CanCollide = false
		projectileTemplate.Anchored = true
		projectileTemplate.CanTouch = false
	end

	local pCache = ObjectCache.new(projectileTemplate, INITIAL_CACHE_SIZE, cacheParent)
	
	objectsCaches[projectilePrefab.Name] = pCache
	
	return pCache
end

local requiredParams = {
	"Field", "Particle"
}

function module:Cast(Params) --fieldName, objectName, particleInitialConditions)	
	for _, value in ipairs(requiredParams) do
		assert(Params[value], "Missing required parameter '" .. value .."'")
	end

	for name, val in pairs(CAST_DEFAULTS) do
		if (Params[name] == nil) then
			Params[name] = val
		end
	end

	local fieldName = Params.Field
	local particle = Params.Particle

	if not particle.CFrame then error"Missing CFrame" end

	local fs = fieldSimulations[fieldName]

	fs:Add(particle)

	local rcp = RaycastParams.new()
	local olp = OverlapParams.new()

	local filterInstances = Params.FilterDescendantsInstances or {}
	local filterType = Params.FilterType

	local instance;

	local _obj = Params.Object
	
	if _obj then
		if type(_obj) == "string" then
			instance = objectsCaches[_obj]:GetObject()
			
			if Params.FilterObjects then
				filterInstances[#filterInstances + 1] = objectsCaches[_obj].CurrentCacheParent
			end
		else
			instance = _obj
		end
	end

	rcp.FilterDescendantsInstances = filterInstances
	rcp.FilterType = filterType
	olp.FilterDescendantsInstances = filterInstances
	olp.FilterType = filterType
	
	particle._lastPoint = nil
	
	local runningSim = {
		Instance = instance,
		Particle = particle,

		Field = fieldName,

		RaycastParams = rcp,
		OverlapParams = olp,

		DoRaycast = Params.DoRaycast,
		UpdateParticleOnRayHit = Params.UpdateParticleOnRayHit,
		
		OverlapType = Params.OverlapType, -- {0 : Off, 1 : Sphere, 2 : Box. 3 : Part}

		UserData = Params.UserData or {},
	}
	runningSimulations[#runningSimulations + 1] = runningSim

	return runningSim
end

function module:CastN(amount, Params) --fieldName, objectName, particleInitialConditions)	
	
	for _, value in ipairs(requiredParams) do
		assert(Params[value], "Missing required parameter '" .. value .."'")
	end

	for name, val in pairs(CAST_DEFAULTS) do
		if (Params[name] == nil) then
			Params[name] = val
		end
	end

	local fieldName = Params.Field
	local particle = Params.Particle

	if type(particle) ~= "function" then error"Expected function for 'Particle'. (providing the same particle for N simulations is redundant. The function is expected to introduce randomness)" end
	
	local fs = fieldSimulations[fieldName]

	local _obj = Params.Object
	local objectCache;
	local currentCacheParent;
	
	if _obj then
		objectCache = objectsCaches[_obj]
		currentCacheParent = objectsCaches[_obj].CurrentCacheParent
	end
	
	local casts = {}
	
	for i = 1, amount do
		local particle_i = particle()
		
		fs:Add(particle_i)

		local rcp = RaycastParams.new()
		local olp = OverlapParams.new()

		local filterInstances = Params.FilterDescendantsInstances or {}
		local filterType = Params.FilterType
		
		local instance;
		
		if _obj then
			if Params.FilterObjects then
				filterInstances[#filterInstances + 1] = currentCacheParent
			end

			instance = objectCache:GetObject()
		end

		rcp.FilterDescendantsInstances = filterInstances
		rcp.FilterType = filterType
		olp.FilterDescendantsInstances = filterInstances
		olp.FilterType = filterType
		
		particle_i._lastPoint = nil
		
		local runningSim = {
			Instance = instance,
			Particle = particle_i,

			Field = fieldName,

			RaycastParams = rcp,
			OverlapParams = olp,

			DoRaycast = Params.DoRaycast,
			UpdateParticleOnRayHit = Params.UpdateParticleOnRayHit,
			OverlapType = Params.OverlapType, -- {0 : Off, 1 : Sphere, 2 : Box. 3 : Part}

			UserData = Params.UserData or {}
		}

		runningSimulations[#runningSimulations + 1] = runningSim
		casts[#casts + 1] = runningSim
	end
	
	return casts
end

-- * Note that when switching fieldSimulations, the current running simulation may be missing necessary properties to run in the new field
function module:UpdateSimulationField(runningSim, newField)
	local field = fieldSimulations[runningSim.Field]

	field:Remove(runningSim.Particle)

	runningSim.Field = newField

	fieldSimulations[newField]:Add(runningSim.Particle)
end

function module:EndSimulation(runningSim)
	local instance = runningSim.Instance

	if instance then
		local objectCache = objectsCaches[instance.Name]

		if objectCache then
			runningSim.Instance = instance:Clone()
			runningSim.Instance.Parent = workspace


			objectCache:ReturnObject(instance)
		end
	end

	local field = fieldSimulations[runningSim.Field]

	field:Remove(runningSim.Particle)

	local _index = table.find(runningSimulations, runningSim)

	runningSimulations[_index], runningSimulations[#runningSimulations] = runningSimulations[#runningSimulations], nil

	simEndSignal:Fire(runningSim)
end

function module:DestroyField(fieldName, switchToFieldName)
	local field = fieldSimulations[fieldName]
	
	if #field.Particles > 0 then
		assert(switchToFieldName, "Destroying field has particles. They must be transferred")
		
		local switchToField = fieldSimulations[switchToFieldName]
		
		for _, p in ipairs(field.Particles) do
			switchToField:Add(p)
		end
	end
	
	fieldSimulations[fieldName] = nil
	
	field:Destroy()
end

function module:GetCastFromInstance(instance : (BasePart | Model))
	for _, value in ipairs(runningSimulations) do
		if value.Instance == instance then return value end
	end
end


local bmt =  workspace.BulkMoveTo--(workspace, partList, cframeList, Enum.BulkMoveMode.FireCFrameChanged)

local _throttleCount = 0

game:GetService"RunService".Heartbeat:Connect(function(deltaTime)	
	local throttling = module.Throttling + 1
	local throttledDeltaTime = throttling * deltaTime

	_throttleCount = (_throttleCount + 1) % throttling

	local loadSize = math.floor(#runningSimulations / throttling)
	local remainder = #runningSimulations % throttling

	local i =  _throttleCount * loadSize + 1        

	-- ! This is wrong ! To throttle correctly, only the particles within the LOAD should be getting updated !
	for _, fs in pairs(fieldSimulations) do
		fs:Update(throttledDeltaTime)
	end

	local baseParts = {}
	local bpCFs = {}

	while i <=  (_throttleCount == 0 and loadSize or (_throttleCount + 1) * loadSize) do
		local runningSim = runningSimulations[i]
		
		local instance = runningSim.Instance
		local particle = runningSim.Particle

		local particleCF = particle.CFrame
		local lastPoint = particle._lastPoint or particleCF.Position
		local thisPoint = particleCF.Position

		if runningSim.DoRaycast then
			local rcr = workspace:Raycast(lastPoint, thisPoint - lastPoint, runningSim.RaycastParams)

			if rcr then
				-- If it hit's something, the point it hit will be closer than that of nextPoint.

				if runningSim.UpdateParticleOnRayHit then					
					particleCF = (particleCF - thisPoint) + rcr.Position + .0000025 * rcr.Normal
					particle.CFrame = particleCF
					
					if particle.Distance then
						local distanceCorrection = (rcr.Position - lastPoint).Magnitude

						particle.Distance -= distanceCorrection
					end
				end

				hitSignal:Fire(runningSim, rcr)
			end
		end

		local overlapType = runningSim.OverlapType

		if overlapType > 0 then
			if not instance then error("Overlap is non-zero without an instance") end

			local hitParts = {}

			if overlapType == 1 then
				if instance.ClassName == "Model" then
					local o, s = instance:GetBoundingBox()

					hitParts = workspace:GetPartBoundsInBox(o, s, runningSim.OverlapParams)
				else
					hitParts = workspace:GetPartBoundsInBox(instance.CFrame, instance.Size, runningSim.OverlapParams)
				end
			elseif overlapType == 2 then
				if instance.ClassName == "Model" then
					local ori, size = instance:GetBoundingBox()

					hitParts = workspace:GetPartBoundsInRadius(ori.Position, size.Magnitude, runningSim.OverlapParams)
				else
					hitParts = workspace:GetPartBoundsInRadius(instance.Position, instance.Size.Magnitude, runningSim.OverlapParams)
				end
			elseif overlapType == 3 then
				hitParts = workspace:GetPartsInPart(instance, runningSim.OverlapParams)
			end

			if #hitParts > 0 then
				overlappedSignal:Fire(runningSim, hitParts)
			end
		end

		if instance then
			if instance:IsA"BasePart" then
				baseParts[#baseParts + 1] = instance
				bpCFs[#bpCFs + 1] = particleCF
			else
				instance:PivotTo(particleCF)
			end
		end
		
		particle._lastPoint = particleCF.Position

		i += 1
	end

	bmt(workspace, baseParts, bpCFs, Enum.BulkMoveMode.FireCFrameChanged)
end)

FieldSimulation = {}

local simFuncs = {
	Add = function(self, particleProperties)
		local particles = self.Particles
		particles[#particles + 1] = particleProperties
	end,
	Remove = function(self, particleProperties, _fromIndex : number?)
		local particles = self.Particles

		_fromIndex = _fromIndex or table.find(particles, particleProperties)

		particles[_fromIndex], particles[#particles] = particles[#particles], nil
	end,
	Update = function (self, dt)
		local fieldFunction = self.Function
		local particles = self.Particles
		local terminationCondition = self.TerminationCondition

		local particleTerminated = self.ParticleTerminated

		for i = #particles, 1, -1 do
			local particle = particles[i]

			if terminationCondition(particle) then
				particleTerminated:Fire(particle)

				self:Remove(particle, i)

				particle = particles[i]
			end

			fieldFunction(particle, dt)
		end
	end,
	Destroy = function(self)
		table.clear(self.Particles)
		self.ParticleTerminated:Destroy()
		table.clear(self)
		self = nil
	end,
}
simFuncs.__index = simFuncs

-- Note that 'Params' are expected to be used within Function
function FieldSimulation.new(f, params)
	return setmetatable({
		Function = f,
		Parameters = params,
		Particles = {},
		TerminationCondition = function(particle)
			-- return particle.Position.Y > 10
		end,

		ParticleTerminated = Signal.new(),
	}, simFuncs)
end

do
	local GravityFieldParams = {
		G = - workspace.Gravity
	}

	module:CreateField("Gravity", function(particle, dt)
		local g = GravityFieldParams.G

		local c0 = particle.CFrame

		local v0 = particle.Velocity
		local x0 = c0.Position

		particle.Velocity = v0 + g * Vector3.yAxis * dt
		particle.CFrame = c0 + v0 * dt + g * Vector3.yAxis * (dt ^ 2 / 2)
	end, GravityFieldParams)
end

return module