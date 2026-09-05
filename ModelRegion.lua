--!strict

local LODRegion = {}


local Types = require(script.Parent.Parent.Types)

type ModelRegion = Types.ModelRegion

local ModelGroup = require(script.ModelGroup)


local function destroyRegion(self : ModelRegion, timeout : number?)
	assert(timeout == nil or typeof(timeout) == "number", "timeout must be a number or nil!")

	for _, group in self.groups do
		group:Destroy(timeout)
	end

	self.groups = {}

	local index = table.find(_G.regions, self)

	if index then
		table.remove(_G.regions, index)
	end
end

local function createGroup(self : ModelRegion, template : Types.Template)
	local group = ModelGroup.new(self, template)

	table.insert(self.groups, group)

	return group
end


-- pivot: Basically the center of the region which will be used when determining the level of the LOD
function LODRegion.new(pivot : Vector3)
	assert(typeof(pivot) == "Vector3", "pivot must be a Vector3!")

	local region : ModelRegion = {
		pivot = pivot,
		groups = {},
		lastDir = Vector3.zAxis,
		CreateGroup = createGroup,
		Destroy = destroyRegion
	}

	return region
end


return LODRegion