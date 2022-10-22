# Sample

The following code produces fluid simulation.
```lua
local fs = require(script.Parent.Folder.InstanceFieldSimulation)
fs.Throttling = 0

local SurfaceRestiution = .6

-- Here are a list of onHit callbacks. You could equally have OnHit callbacks based on the field they were in.
local OnHit = {
	Part = function(simulation, rcr)
		local particle = simulation.Particle

		particle.Velocity -= (1 + SurfaceRestiution) * rcr.Normal:Dot(particle.Velocity) * rcr.Normal
	end,
}
fs.Hit:Connect(function(simulation, rcr)
	local onHit = OnHit[simulation.Instance.Name] or OnHit[simulation.Field]

	onHit(simulation, rcr)
end)

fs.Overlapped:Connect(function(simulation, hitParts)
	
end)

fs.SimulationEnded:Connect(function(simulation)
	--simulation.Instance:Destroy()
end)

local p = Instance.new("Part")
p.CastShadow = false
p.Material = Enum.Material.Water
p.Size = Vector3.new(3,3,3)
p.Transparency = .5
p.Color = Color3.new(0,.5, 1)

local switchParams = {
	V = -1
}

local testField = fs:CreateField("Test", function(particle, dt)
	local c0 = particle.CFrame
	
	local x0 = c0.Position
	local v0 = particle.Velocity

	particle.Velocity = v0 + switchParams.V * Vector3.yAxis * dt
	particle.CFrame = (c0 + v0 * dt + switchParams.V * Vector3.yAxis * (dt ^ 2 / 2))
end)

-- If this condition is fulfilled, the particle is removed from simulation. FieldSimulation.SimulationEnded will be fired
testField.TerminationCondition = function(v)
	return v.CFrame.Position.Y < - 20
end

local pcache = fs:CreateObject(p)
for i = 1, 1e2 do
	pcache:Expand(1e2)
	
	wait()
end

for i = 1, 5e2 do
	fs:CastN(20, {
		Field = "Gravity",
		Object = "Part",
		Particle = function()
			return {
				CFrame = CFrame.identity + 3 * Vector3.new(math.random(), math.random(), math.random()),
				Velocity = Vector3.zero
			}
		end,
		DoRaycast = true,
		UpdateParticleOnRayHit = true,
		OverlapType = 0
	})
	wait()
end
```