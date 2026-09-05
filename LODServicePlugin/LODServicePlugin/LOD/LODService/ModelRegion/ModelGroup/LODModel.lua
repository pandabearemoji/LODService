--!strict

local LODModel = {}

local Types = require(script.Parent.Parent.Parent.Parent.Types)

type BillboardPlane = Types.BillboardPlane
type Billboard = Types.Billboard
type MeshModel = Types.MeshModel
type LODModel = Types.LODModel
type ModelGroup = Types.ModelGroup

local Util = require(script.Parent.Parent.Parent.Util)


local function destroy(self : LODModel)
	-- destroy the lods, disconnect events and remove all references for the gc
	
	Util.loadModel(self.model0)

	for _, model in self.lods do
		model.model:Destroy()
	end

	self.lods = {}

	for _, billboard in self.billboards do
		billboard.yPlane.part:Destroy()

		for _, plane in billboard.planes do
			plane.part:Destroy()
		end
	end

	self.billboards = {}
	self.selectedBillboard = nil

	if self.pivotConnection then
		self.pivotConnection:Disconnect()
	end
	
	if self.destroyConnection then
		self.destroyConnection:Disconnect()
	end

	local index = table.find(self.parent.models, self)

	if index then
		table.remove(self.parent.models, index)
	end
end

local function pivotTo(self : LODModel, pivot : CFrame, ignore0 : boolean?)
	assert(typeof(pivot) == "CFrame", "pivot must be a CFrame!")

	local camera = workspace.CurrentCamera

	-- needed for pixel lines and billboards
	if not camera then
		error("Could not pivot model because workspace.CurretCamera is nil!")
	end
	
	local t = tick()
	self.pivot = pivot

	local camPos = camera.CFrame.Position
	
	local boundingBox = self.model0:GetBoundingBox().Position

	-- needed for pixel lines
	local scale = self.model0:GetScale() * self.parent.template.scale

	-- optimization cuz we might move a ton of parts
	local partList, cframeList = {}, {}

	local billboard = self.selectedBillboard
	
	if billboard then
		billboard.lastUpdate = t
		
		for _, plane in billboard.planes do
			table.insert(partList, plane.part)
			table.insert(cframeList, Util.pivotPlane(plane, pivot, boundingBox))
		end

		table.insert(partList, billboard.yPlane.part)
		table.insert(cframeList, Util.pivotPlane(billboard.yPlane, pivot, boundingBox))

		Util.updateBillboard(billboard, pivot.Position, camPos)
	elseif self.selectedLodIndex then
		local model = self.lods[self.selectedLodIndex]
		
		model.lastUpdate = t
		
		for _, v in model.model:GetChildren() do
			-- pretty naive but i cannot be bothered tbh
			if v.Name ~= "plane" and v:IsA("BasePart") then
				table.insert(partList, v)
				table.insert(cframeList, pivot)
			end
		end

		if #model.lines > 0 then
			for _, line in model.lines do
				local v1 = pivot:PointToWorldSpace(line.origv1 * scale)
				local v2 = pivot:PointToWorldSpace(line.origv2 * scale)
				local rightVector = v2 - v1

				line.pos = v1:Lerp(v2, 0.5)
				line.v1 = v1
				line.v2 = v2
				line.rightVector = rightVector

				-- done as per [1] '3.3.2 Dynamic Normal'
				local normal = (v1 - camPos):Cross(v2 - camPos):Cross(rightVector)

				table.insert(partList, line.plane)
				table.insert(cframeList, CFrame.lookAlong(line.pos, normal, rightVector:Cross(normal)))
			end
		end
	elseif self.parent.selectedLod and not ignore0 then
		-- yeahh im too lazy to get all parts and allat
		self.model0:PivotTo(pivot)
	end

	workspace:BulkMoveTo(partList, cframeList, Enum.BulkMoveMode.FireCFrameChanged)
	
	self.lastPivoted = t
end


local function nonAutoPivotTo(self : LODModel, pivot : CFrame)
	-- needed because strict mode doesnt like the extra argument lol
	pivotTo(self, pivot)
end

local function autoPivotTo(self : LODModel, pivot : CFrame)
	self.model0:PivotTo(pivot)
end


local function connectPivotingEvent(self : LODModel)
	if self.pivotConnection then
		self.pivotConnection:Disconnect()
	end

	self.pivotConnection = self.model0:GetPropertyChangedSignal("WorldPivot"):Connect(function()
		pivotTo(self, self.model0.WorldPivot, true)
	end)
end


local function preloadAll(self : LODModel)
	local camera = workspace.CurrentCamera
	
	if not camera then
		error("Could not preload model because workspace.CurretCamera is nil!")
		return
	end
	
	local position = camera.CFrame.Position
	
	local parentTemplate = self.parent.template
	local pivot, scale, boundingBox = self.model0:GetPivot(), self.model0:GetScale(), self.model0:GetBoundingBox().Position
	
	local cframeList, partList = {}, {}
	
	local t = tick()
	
	for cellSize, template in pairs(parentTemplate.lods) do
		if cellSize ~= self.parent.selectedLod then
			local model, lines, count = Util.createMeshFromTemplate(template, pivot, scale * parentTemplate.scale, cframeList, partList)
			Util.hideModel(model, 0)

			Util.updateLines(lines, position, cframeList, partList)
			
			table.insert(self.lods, {
				model = model,
				lines = lines,
				cellSize = cellSize,
				loadingPenalty = 0.035 * count + 0.25,
				lastUpdate = t
			})
		end
	end
	
	for cellSize, template in pairs(parentTemplate.billboards) do
		local billboard = Util.createBillboardFromTemplate(template, pivot, boundingBox, scale * parentTemplate.scale, cellSize, cframeList, 
			partList, self.loadingPenaltyMultiplier, t)
		Util.hideModel(billboard.model, 0)

		table.insert(self.billboards, billboard)
	end
	
	workspace:BulkMoveTo(partList, cframeList, Enum.BulkMoveMode.FireCFrameChanged)
end


function LODModel.new(parent : ModelGroup, model0 : Model, autoPivot : boolean?, loadingPenaltyMultiplier : number?)
	
	local count = 0
	local loadingPenaltyMultiplier = loadingPenaltyMultiplier or 1
	
	for _, v in model0:GetDescendants() do
		if v:IsA("BasePart") then
			count += 1
		end
	end
	
	local t = tick()
	
	local model : LODModel = {
		lods = {},
		model0 = model0,
		loadingPenalty0 = (0.035 * count + 0.25) * loadingPenaltyMultiplier,
		lastPivoted = t,
		lastUpdate0 = t,
		parent = parent,
		billboards = {},
		Destroy = destroy,
		PivotTo = autoPivot and autoPivotTo or nonAutoPivotTo,
		PreloadAll = preloadAll,
		loadingPenaltyMultiplier = loadingPenaltyMultiplier,
		pivot = model0:GetPivot()
	}
	
	model.destroyConnection = model0.Destroying:Connect(function()
		model:Destroy()
	end)
	
	if autoPivot then
		connectPivotingEvent(model)
	end

	return model
end


return LODModel