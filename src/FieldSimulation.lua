local Signal = require(script.Parent.Signal)

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

return FieldSimulation