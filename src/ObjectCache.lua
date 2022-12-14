--[=[
    @class ObjectCache
]=]
local ObjectCache = {}
ObjectCache.__index = ObjectCache

--[=[
    @type Object BasePart | Model
    @within ObjectCache

    Generalization for things that are base parts or models.
]=]
export type Object = BasePart | Model

--[=[
    @interface OCache
    .Open {Object}
    .InUse: {Object},
    .CurrentCacheParent: Folder,
    .Template: Object,
    .ExpansionSize: number
    @within ObjectCache

    Description
]=]
export type OCache = {
	Open: {Object},
	InUse: {Object},
	CurrentCacheParent: Folder,
	Template: Object,
	ExpansionSize: number
}

local objectProperties = {
	"Transparency",
	"Size",
	"Material",
	"Color",
	"Reflectance"
}	

-- A CFrame that's really far away. Ideally. You are free to change this as needed.
local CF_REALLY_FAR_AWAY = CFrame.new(0, 10e8, 0)

local DEFAULT_CACHE_NAME = "_%sObjectCache"

-- Format params: methodName, ctorName
local ERR_NOT_INSTANCE = "Cannot statically invoke method '%s' - It is an instance method. Call it on an instance of this class created via %s"

-- Format params: paramName, expectedType, actualType
local ERR_INVALID_TYPE = "Invalid type for parameter '%s' (Expected %s, got %s)"

--Similar to assert but warns instead of errors.
local function wassert(requirement: boolean, messageIfNotMet: string)
	if requirement == false then
		warn(messageIfNotMet)
	end
end

local function FullWipe(t)
	if not t then return end

	for i, v in pairs(t) do
		if typeof(v) == "Instance" then
			if v:IsA("Player") then
				continue
			end
			v:Destroy()
		elseif typeof(v) == "RBXScriptConnection" then
			v:Disconnect()
		elseif type(v) == "table" then
			if type(v.Destroy) == "function" then
				v:Destroy()
			else
				FullWipe(v)
			end
		end
	end

	table.clear(t)

	t = nil
end

--[=[
    @param template Object
    @param numPrecreatedObjects number?
    @param currentCacheParent Folder?
    @return OCache

    ObjectCache constructor.
]=]
function ObjectCache.new(template: Object, numPrecreatedObjects: number?, currentCacheParent: Folder?): OCache
	numPrecreatedObjects = numPrecreatedObjects or 5

	if not currentCacheParent then
		currentCacheParent = Instance.new("Folder")
		currentCacheParent.Name = DEFAULT_CACHE_NAME:format(template.Name)
		currentCacheParent.Parent = workspace
	else
		wassert(currentCacheParent.Parent == workspace, "Cache parent is not a member of workspace")
	end

	--PrecreatedParts value.
	--Same thing. Ensure it's a number, ensure it's not negative, warn if it's really huge or 0.
	assert(numPrecreatedObjects > 0, "PrecreatedObjects can not be negative!")
	wassert(numPrecreatedObjects ~= 0, "PrecreatedObjects is 0! This may have adverse effects when initially using the cache.")
	wassert(template.Archivable, "The template's Archivable property has been set to false, which prevents it from being cloned. It will temporarily be set to true.")

	local oldArchivable = template.Archivable
	template.Archivable = true
	local newTemplate: Object = template:Clone()

	template.Archivable = oldArchivable
	template = newTemplate
	newTemplate:PivotTo(CF_REALLY_FAR_AWAY)
	template.Anchored = true

	local oCache: OCache = {
		Open = {},
		InUse = {},
		CurrentCacheParent = currentCacheParent,
		Template = template,
		ExpansionSize = 10,
		_selfTemplate = {}, -- To reset a returned object to its original properties
		_objectType = template:IsA("BasePart") and "BasePart" or "Model"
	}
	
	if oCache._objectType == "BasePart" then
		local selfTemplate = {}

		for _, propName in ipairs(objectProperties) do
			selfTemplate[propName] = template[propName]
		end

		oCache._selfTemplate = selfTemplate
	else
		local selfTemplate = {}

		for _, bp in ipairs(template:GetDescendants()) do
			if not bp:IsA("BasePart") then continue end

			local bpTemplate = {}

			for _, propName in ipairs(objectProperties) do
				bpTemplate[propName] = bp[propName]
			end

			selfTemplate[bp] = bpTemplate
		end

		oCache._selfTemplate = selfTemplate
	end

	setmetatable(oCache, ObjectCache)

	-- Below: Ignore type mismatch nil | number and the nil | Instance mismatch on the table.insert line.
	for _ = 1, numPrecreatedObjects do
		local nObject: Object = template:Clone()

		nObject.Parent = currentCacheParent
		
		table.insert(oCache.Open, nObject)
	end
	oCache.Template.Parent = nil

	return oCache
end

--[=[
    @return Object

    Retrieve an object from the cache
]=]
function ObjectCache:GetObject(): Object
	assert(getmetatable(self) == ObjectCache, ERR_NOT_INSTANCE:format("GetObject", "ObjectCache.new"))

	if #self.Open == 0 then
		warn("No objects available in the cache! Creating [" .. self.ExpansionSize .. "] new object instance(s) - this amount can be edited by changing the ExpansionSize property of the ObjectCache instance... (This cache now contains a grand total of " .. tostring(#self.Open + #self.InUse + self.ExpansionSize) .. " objects.)")
		
		local template = self.Template
		local cParent = self.CurrentCacheParent
		local _open = self.Open
		
		for i = 1, self.ExpansionSize, 1 do
			local nObject: Object = template:Clone()

			nObject.Parent = cParent
			
			table.insert(_open, nObject)
		end
	end
	local object = self.Open[#self.Open]
	self.Open[#self.Open] = nil
	table.insert(self.InUse, object)
	return object
end

--[=[
    @param object Object

    Return object to cache. ObjectCache will attempt to reset important properties back to the template's properties.
]=]
function ObjectCache:ReturnObject(object: Object)
	assert(getmetatable(self) == ObjectCache, ERR_NOT_INSTANCE:format("ReturnObject", "ObjectCache.new"))

	local index = table.find(self.InUse, object)

	if index ~= nil then
		table.remove(self.InUse, index)
		table.insert(self.Open, object)
		object:PivotTo(CF_REALLY_FAR_AWAY)
	else
		error("Attempted to return object \"" .. object.Name .. "\" (" .. object:GetFullName() .. ") to the cache, but it's not in-use! Did you call this on the wrong object?")
	end
end

--[=[
    @param object Object

    Reset important properties back to the template's properties.
]=]
function ObjectCache:ResetObject(object: Object)
	if self._objectType == "BasePart" then
		for propName, propVal in pairs(self._selfTemplate) do
			object[propName] = propVal
		end
	else
		for objectDescendant, descProperties in pairs(self._selfTemplate) do
			for propName, propVal in pairs(descProperties) do
				objectDescendant[propName] = propVal
			end
		end
	end
end


--[=[
   Expands the size of the cache.
]=]
function ObjectCache:Expand(amount: number?)
	assert(getmetatable(self) == ObjectCache, ERR_NOT_INSTANCE:format("Expand", "ObjectCache.new"))

	amount = amount or self.ExpansionSize

	local template = self.Template
	local cParent = self.CurrentCacheParent
	local _open = self.Open

	for i = 1, amount do
		local nObject: Object = template:Clone()

		nObject.Parent = cParent
		
		table.insert(_open, nObject)
	end
end

--[=[
   Destroys the object cache.

   :::caution
    This will _also_ destroy all parts it is responsible for.
]=]
function ObjectCache:Destroy()
	assert(getmetatable(self) == ObjectCache, ERR_NOT_INSTANCE:format("Dispose", "ObjectCache.new"))

	FullWipe(self)
end

return ObjectCache