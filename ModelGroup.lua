--!strict

local LODGroup = {}

local Types = require(script.Parent.Parent.Parent.Types)

type Template = Types.Template
type ModelGroup = Types.ModelGroup
type ModelRegion = Types.ModelRegion

local LODModel = require(script.LODModel)

local Util = require(script.Parent.Parent.Util)


local function refreshScaleMultiplier(self : ModelGroup)
	-- added this so if a models scale is a lot different from the template then the chosen lod level will also be affected by this change
	local scale = 0

	for _, model in self.models do
		scale += model.model0:GetScale()
	end

	scale /= #self.models

	self.scaleMultiplier = 1 / (scale * self.template.scale)
end

local function destroyGroup(self : ModelGroup, timeout : number?)
	assert(timeout == nil or typeof(timeout) == "number", "timeout must be a number or nil!")

	-- deletion can be expensive sometimes so just in case we have a timeout to prevent too much lag
	local timeout = timeout or 5

	local penalty = 0
	
	for _, lodModel in self.models do
		penalty += 1

		if penalty > timeout then
			penalty = 0
			task.wait()
		end

		lodModel:Destroy()
	end

	self.models = {}
	self.selectedBillboard = false
	self.selectedLod = 0

	local index = table.find(self.parent.groups, self)

	if index then
		table.remove(self.parent.groups, index)
	end
end

local function parentGroupTo(self : ModelGroup, parent : ModelRegion)
	local index = table.find(self.parent.groups, self)

	if index then
		table.remove(self.parent.groups, index)
	end

	table.insert(parent.groups, self)
	-- the group is awaiting an update so the selectedLod is set to -1
	self.selectedLod = -1
	self.parent = parent
end

local function lodifyModel(self : ModelGroup, model0 : Model, autoPivot : boolean?, loadingPenaltyMultiplier : number?)
	
	assert(typeof(model0) == "Instance" and model0:IsA("Model"), "model0 must be a Model!")

	local camera = workspace.CurrentCamera

	if not camera then
		error("Could not LODify model because workspace.CurretCamera is nil!")
	end

	local camPos = camera.CFrame.Position
	
	local model = LODModel.new(self, model0, autoPivot, loadingPenaltyMultiplier)
	
	local t = tick()
	
	-- update the new element if needed
	if self.selectedLod == self.template.maxCellSize then
		-- out of render distance
		Util.hideModel(model0, 0)
	elseif self.selectedLod ~= 0 and self.selectedLod ~= -1 then
		-- this isnt really necessary considering we wont be moving many parts, but the functions are already made this way
		-- and i am not adding another 200 lines for basically no reason
		local partList, cframeList = {}, {}

		Util.hideModel(model0, 0)

		local pivot = model0:GetPivot()
		local scale = model0:GetScale() * self.template.scale
		local boundingBox = model0:GetBoundingBox().Position

		if self.selectedBillboard then
			local billboard = Util.createBillboardFromTemplate(self.template.billboards[self.selectedLod], pivot, boundingBox, scale, 
				self.selectedLod, cframeList, partList, model.loadingPenaltyMultiplier, t)

			model.selectedBillboard = billboard

			Util.updateBillboard(billboard, pivot.Position, camPos)

			table.insert(model.billboards, billboard)
		else
			local newModel, lines, count = Util.createMeshFromTemplate(self.template.lods[self.selectedLod], pivot, scale, cframeList, 
				partList)

			Util.updateLines(lines, camPos, cframeList, partList)

			model.lods[1] = {
				model = newModel,
				lines = lines,
				cellSize = self.selectedLod,
				loadingPenalty = (0.035 * count + 0.25) * model.loadingPenaltyMultiplier,
				lastUpdate = t
			}

			model.selectedLodIndex = 1
		end

		workspace:BulkMoveTo(partList, cframeList, Enum.BulkMoveMode.FireCFrameChanged)
	end

	table.insert(self.models, model)
	
	return model
end


function LODGroup.new(parent : ModelRegion, template : Template)
	local group : ModelGroup = {
		template = template,
		models = {},
		LODifyModel = lodifyModel,
		selectedLod = 0,
		selectedBillboard = false,
		parent = parent,
		scaleMultiplier = 1,
		Destroy = destroyGroup,
		ParentTo = parentGroupTo,
		RefreshScaleMultiplier = refreshScaleMultiplier
	}
	
	return group
end

return LODGroup
