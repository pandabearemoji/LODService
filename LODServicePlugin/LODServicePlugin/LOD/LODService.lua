--!strict
--!native

local LODService = {}
LODService.loadedLods = 0
-- need to use globals cuz modelregion needs access to this
-- and requiring would lead to recursive requires
_G.regions = {} :: {ModelRegion}
LODService.enabled = false
LODService.viewportSizeConnection = nil :: RBXScriptConnection?
LODService.fovConnection = nil :: RBXScriptConnection?
LODService.cameraConnection = nil :: RBXScriptConnection?

LODService.X = 5
LODService.RScreenComponent = 0.0005 * LODService.X

-- Maximum loaded models before the script starts destroying unloaded models
LODService.MaxMemoryUsage = 5000
-- The penalty needed for a heartbeat timeout
LODService.PenaltyTimeout = 30
-- The amount of time the thread times out (in seconds)
LODService.Timeout = 0.1
-- The amount of billboard rendering instructions before a hearbeat timeout
LODService.BillboardTimeout = 15
-- The cosine of the minimum difference in angle needed for a billboard update
LODService.BillboardUpdateDot = 0.997

local Types = require(script.Parent.Types)

type BillboardTemplate = Types.BillboardTemplate
type MeshTemplate = Types.MeshTemplate
type Template = Types.Template
type Billboard = Types.Billboard
type MeshModel = Types.MeshModel
type LODModel = Types.LODModel
type ModelGroup = Types.ModelGroup
type ModelRegion = Types.ModelRegion

type ModelUnloader = (model : Model, loaded : number, models : {any}, i : number) -> (number)

local DynamicallyGenerated = script.Parent.DynamicallyGenerated

local Util = require(script.Util)
Util.folder = Instance.new("Folder", workspace)
Util.folder.Name = "LODs"

local ModelRegion = require(script.ModelRegion)

local LODGenerator = require(script.LODGenerator)
LODService.lodGenerator = LODGenerator.new(false, 0, 1, false, false, false)
local VertexClustering = require(script.LODGenerator.MeshSimplification.VertexClustering)

local RunS = game:GetService("RunService")
local AS = game:GetService("AssetService")


-- pivot: The center of the region which will be used for determining the lod level for a given distance from it
function LODService:CreateRegion(pivot : Vector3)
	local region = ModelRegion.new(pivot)
	table.insert(_G.regions, region)
	return region
end

--[[ X: 'render distance' constant usually a number between 5-10 but it can be anything you want (defaults to 5)
the higher this number is the lower the quality of the selected lod will get]]
function LODService:SetX(X : number)
	assert(typeof(X) == "number", "X must be a number!")

	local camera = workspace.CurrentCamera

	if not camera then
		warn("Could not set X because workspace.CurrentCamera is nil!")
		return
	end

	LODService.X = X
	LODService.RScreenComponent = X * 2 * math.tan(math.rad(camera.FieldOfView) * 0.5) / camera.ViewportSize.Y
end

-- Starts LODService's rendering
function LODService:Run()
	if not LODService.enabled then
		LODService.enabled = true

		local camera = workspace.CurrentCamera

		if camera then
			LODService.connectCameraListeners(camera)

			LODService.cameraConnection = workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
				if workspace.CurrentCamera then
					LODService.connectCameraListeners(workspace.CurrentCamera)
				else
					warn("Could not find camera, this may break LODService!")
				end
			end)
		else
			warn("Could not find camera, this may break LODService!")
		end

		task.spawn(function()
			while LODService.enabled do
				RunS.RenderStepped:Wait()

				LODService.step()
			end
		end)

		task.spawn(function()
			while LODService.enabled do
				RunS.RenderStepped:Wait()

				LODService.stepBillboards()
			end
		end)
	end
end

-- Stops LODService's rendering
function LODService:Pause()
	if LODService.enabled then
		LODService.enabled = false

		if LODService.cameraConnection then
			LODService.cameraConnection:Disconnect()
		end

		if LODService.viewportSizeConnection then
			LODService.viewportSizeConnection:Disconnect()
		end

		if LODService.fovConnection then
			LODService.fovConnection:Disconnect()
		end
	end
end

-- Stops and clears (resets all models to their original states and deletes the generated lods) LODService
function LODService:Clear()
	LODService:Pause()

	for _, region in _G.regions do
		region:Destroy()
	end
end


function LODService.updateR(camera : Camera)
	-- refer to [1] - 4 IMPLEMENTATION - LOD determination
	LODService.RScreenComponent = LODService.X * 2 * math.tan(math.rad(camera.FieldOfView) * 0.5) / camera.ViewportSize.Y
end


function LODService.connectCameraListeners(camera : Camera)
	if LODService.viewportSizeConnection then
		LODService.viewportSizeConnection:Disconnect()
	end

	if LODService.fovConnection then
		LODService.fovConnection:Disconnect()
	end

	-- automatically update the constant for R calculation
	LODService.viewportSizeConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
		LODService.updateR(camera)
	end)

	LODService.fovConnection = camera:GetPropertyChangedSignal("FieldOfView"):Connect(function()
		LODService.updateR(camera)
	end)

	LODService.updateR(camera)
end


function LODService.destroyModel(model : Model, loaded : number, models : {any}, i : number)
	model:Destroy()
	models[i] = nil

	return loaded - 1
end

function LODService.unloadPreviousModel(previous : number, penalty : number, loaded : number, lodModel : LODModel, 
	modelUnloader : ModelUnloader)

	if previous == 0 then
		Util.hideModel(lodModel.model0, 0)
		penalty += lodModel.loadingPenalty0
	elseif lodModel.selectedLodIndex then
		local model = lodModel.lods[lodModel.selectedLodIndex]

		loaded = modelUnloader(model.model, loaded, lodModel.lods, lodModel.selectedLodIndex)
		penalty += model.loadingPenalty
	else
		-- this case is almost guaranteed not to happen but just in case
		for i, model in pairs(lodModel.lods) do
			if model.cellSize == previous then
				loaded = modelUnloader(model.model, loaded, lodModel.lods, i)
				penalty += model.loadingPenalty
				break
			end
		end
	end

	lodModel.selectedLodIndex = nil

	return penalty, loaded
end

function LODService.loadModelIntoLOD(lodModel : LODModel, i : number, position : Vector3, cframeList : {CFrame}, partList : {Instance}, 
	t : number, camPos : Vector3)
	
	local model = lodModel.lods[i]
	lodModel.selectedLodIndex = i
	Util.loadModel(model.model)
	
	if model.lastUpdate < lodModel.lastPivoted then
		local pivot = lodModel.pivot
		local scale = lodModel.model0:GetScale()
		
		model.lastUpdate = t
		
		local cframeList2, partList2 = {}, {}

		for _, v in model.model:GetChildren() do
			-- pretty naive but i cannot be bothered tbh
			if v.Name ~= "plane" and v:IsA("BasePart") then
				table.insert(partList2, v)
				table.insert(cframeList2, pivot)
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

				table.insert(partList2, line.plane)
				table.insert(cframeList2, CFrame.lookAlong(line.pos, normal, rightVector:Cross(normal)))
			end
		end
		
		workspace:BulkMoveTo(partList2, cframeList2, Enum.BulkMoveMode.FireCFrameChanged)
	else
		Util.updateLines(model.lines, position, cframeList, partList)
	end
end


-- soo i originally used localtransparencymodifier for unloading
-- but it turns out roblox considers transparent parts for gpu instancing
-- meaning reparenting is realistically the only option
-- (cframing far is actually quite expensive and mehh)

function LODService.step()
	local camera = workspace.CurrentCamera

	if not camera then
		warn("Could not step because workspace.CurretCamera is nil!")
		return
	end

	local penalty = 0
	local upd = false
	
	local t = tick()

	local loaded = LODService.loadedLods

	local deleteUnused = loaded > LODService.MaxMemoryUsage

	-- store the unloader functions because i guess its cleaner and faster this way? (i am not sure whether this is faster than 
	-- spamming ifs pls tell me in the devforum thread if ur sure that this is slow)
	local modelUnloader : ModelUnloader = deleteUnused and LODService.destroyModel or Util.hideModel

	local position = camera.CFrame.Position

	local cframeList, partList = {}, {}

	for _, region in _G.regions do
		local updateBillboards = false

		penalty += 1

		if penalty > LODService.PenaltyTimeout then
			task.wait(LODService.Timeout)
			penalty = math.max(penalty - LODService.PenaltyTimeout, 0)
		end

		-- refer to [1] - 4 IMPLEMENTATION - LOD determination
		local unscaledR = LODService.RScreenComponent * (region.pivot - position).Magnitude

		for _, group in region.groups do
			penalty += 1

			if penalty > LODService.PenaltyTimeout then
				task.wait(LODService.Timeout)
				penalty = math.max(penalty - LODService.PenaltyTimeout, 0)
			end

			local R = unscaledR * group.scaleMultiplier

			if R > group.template.maxCellSize then
				-- model is out of 'render distance'
				penalty, loaded = LODService.unloadGroup(group, penalty, loaded, deleteUnused, modelUnloader)	
			else
				local mesh : MeshTemplate?, billboard : BillboardTemplate?, meshCellSize, billboardCellSize = nil, nil, nil, nil
				local meshCellSizeDiff, billboardCellSizeDiff = math.huge, math.huge

				-- again refer to [1] - 4 IMPLEMENTATION - LOD determination
				-- choosing the largest cellSize lod that's smaller than R
				for i, model in pairs(group.template.lods) do
					if i < R then
						local diff = R - i

						if diff < meshCellSizeDiff then
							mesh = model
							meshCellSizeDiff = diff
							meshCellSize = i
						end
					end
				end

				for i, pBillboard in pairs(group.template.billboards) do
					if i < R  then
						local diff = R - i

						if diff < billboardCellSizeDiff then
							billboard = pBillboard
							billboardCellSizeDiff = diff
							billboardCellSize = i
						end
					end
				end

				if not meshCellSize and not billboardCellSize then
					-- fall back to lod0
					meshCellSize = 0
					meshCellSizeDiff = 0
					billboardCellSize = 1
				end

				if billboardCellSizeDiff < meshCellSizeDiff and billboardCellSize then
					penalty, loaded, upd = LODService.loadBillboard(group, billboardCellSize, billboard, penalty, loaded, modelUnloader,
						cframeList, partList, position, t)
				else
					penalty, loaded, upd = LODService.loadMesh(group, meshCellSize, penalty, loaded, mesh, modelUnloader, 
						position, cframeList, partList, t)
				end

				if upd then
					updateBillboards = true
				end
			end
		end

		if updateBillboards then
			penalty = LODService.stepRegionBillboards(region, (region.pivot - position).Unit, position, cframeList, partList, penalty)
		end
	end

	if #partList > 0 then
		-- ughh uhh uhhhhhhhhhhhh ughghgh
		workspace:BulkMoveTo(partList, cframeList, Enum.BulkMoveMode.FireCFrameChanged)
	end

	LODService.loadedLods = loaded
end


function LODService.unloadGroup(group : ModelGroup, penalty : number, loaded : number, deleteUnused : boolean, modelUnloader : ModelUnloader)
	: (number, number)

	if group.selectedLod == group.template.maxCellSize then
		return penalty, loaded
	end

	-- only attempt to unload lods that were loaded the previous step
	local previous = group.selectedLod
	group.selectedLod = group.template.maxCellSize
	local wasBillboard = group.selectedBillboard
	group.selectedBillboard = false

	for _, lodModel in group.models do
		if penalty > LODService.PenaltyTimeout then
			task.wait(LODService.Timeout)
			penalty = math.max(penalty - LODService.PenaltyTimeout, 0)
		end

		if wasBillboard then
			lodModel.selectedBillboard = nil

			-- not using the unloader function here because we can simplify it a lot
			if deleteUnused then
				for _, billboard in lodModel.billboards do
					if billboard.cellSize == previous then
						billboard.model:Destroy()
						penalty += billboard.loadingPenalty
						break
					end
				end
				
				lodModel.billboards = {}
			else
				for _, billboard in lodModel.billboards do
					if billboard.cellSize == previous then
						Util.hideModel(billboard.model, 0)
						penalty += billboard.loadingPenalty
						break
					end
				end
			end
		else
			penalty, loaded = LODService.unloadPreviousModel(previous, penalty, loaded, lodModel, modelUnloader)
		end
	end

	return penalty, loaded
end

function LODService.loadBillboard(group : ModelGroup, billboardCellSize : number, billboard : BillboardTemplate?, penalty : number, 
	loaded : number, modelUnloader : ModelUnloader, cframeList : {CFrame}, partList : {Instance}, position : Vector3, t : number)

	if group.selectedLod == billboardCellSize or not billboard then
		return penalty, loaded, false
	end

	local previous = group.selectedLod
	group.selectedLod = billboardCellSize
	local wasBillboard = group.selectedBillboard
	group.selectedBillboard = true

	local forceUpdate = false

	for _, lodModel in group.models do
		if penalty > LODService.PenaltyTimeout then
			task.wait(LODService.Timeout)
			penalty = math.max(penalty - LODService.PenaltyTimeout, 0)
		end

		if not wasBillboard then
			penalty, loaded = LODService.unloadPreviousModel(previous, penalty, loaded, lodModel, modelUnloader)
		end

		local found = false

		for i, billboard in pairs(lodModel.billboards) do
			if billboard.cellSize == billboardCellSize then
				found = true
				lodModel.selectedBillboard = billboard
				Util.loadModel(billboard.model)
				
				if billboard.lastUpdate < lodModel.lastPivoted then
					-- need the boundingbox
					if lodModel.lastUpdate0 < lodModel.lastPivoted then
						lodModel.lastUpdate0 = t
						lodModel.model0:PivotTo(lodModel.pivot)
					end
					
					local pivot = lodModel.pivot
					local boundingBox = lodModel.model0:GetBoundingBox().Position
					
					billboard.lastUpdate = t

					for _, plane in billboard.planes do
						plane.part.CFrame = Util.pivotPlane(plane, pivot, boundingBox)
					end

					billboard.yPlane.part.CFrame = Util.pivotPlane(billboard.yPlane, pivot, boundingBox)
				end
				
				penalty += billboard.loadingPenalty
			elseif billboard.cellSize == previous then
				loaded = modelUnloader(billboard.model, loaded, lodModel.billboards, i)
				penalty += billboard.loadingPenalty
			end
		end

		if not found then
			local billboardLoaded = Util.createBillboardFromTemplate(billboard, lodModel.model0:GetPivot(), 
				lodModel.model0:GetBoundingBox().Position, lodModel.model0:GetScale() * group.template.scale, billboardCellSize, cframeList, 
				partList, lodModel.loadingPenaltyMultiplier, t)
			
			penalty += billboardLoaded.loadingPenalty
			loaded += 1

			lodModel.selectedBillboard = billboardLoaded
			table.insert(lodModel.billboards, billboardLoaded)
		end

		-- force update on the billboard because it just got loaded in
		if lodModel.selectedBillboard then
			forceUpdate = true
		end
	end

	return penalty, loaded, forceUpdate
end

function LODService.loadMesh(group : ModelGroup, meshCellSize : number?, penalty : number, loaded : number, mesh : MeshTemplate?,
	modelUnloader : ModelUnloader, position : Vector3, cframeList : {CFrame}, partList : {Instance}, t : number)

	local meshCellSize = meshCellSize or 0

	if group.selectedLod == meshCellSize then
		return penalty, loaded, false
	end

	local previous = group.selectedLod
	group.selectedLod = meshCellSize
	local wasBillboard = group.selectedBillboard
	group.selectedBillboard = false

	local forceUpdate = false

	for _, lodModel in group.models do
		if penalty > LODService.PenaltyTimeout then
			task.wait(LODService.Timeout)
			penalty = math.max(penalty - LODService.PenaltyTimeout, 0)
		end

		if wasBillboard then
			for i, billboard in pairs(lodModel.billboards) do
				if billboard.cellSize == previous then
					loaded = modelUnloader(billboard.model, loaded, lodModel.billboards, i)
					penalty += billboard.loadingPenalty
					break
				end
			end
		end

		if meshCellSize == 0 or not mesh then
			Util.loadModel(lodModel.model0)
			if lodModel.lastUpdate0 < lodModel.lastPivoted then
				lodModel.lastUpdate0 = t
				lodModel.model0:PivotTo(lodModel.pivot)
			end
			penalty, loaded = LODService.unloadPreviousModel(previous, penalty, loaded, lodModel, modelUnloader)
			penalty += lodModel.loadingPenalty0
		else
			local found = false
			
			local index = lodModel.selectedLodIndex

			if index then
				local model = lodModel.lods[index]

				for i, pModel in pairs(lodModel.lods) do
					if pModel.cellSize == meshCellSize then
						LODService.loadModelIntoLOD(lodModel, i, position, cframeList, partList, t, position)
						found = true
						penalty += pModel.loadingPenalty
						break
					end
				end

				loaded = modelUnloader(model.model, loaded, lodModel.lods, index)
				penalty += model.loadingPenalty
			elseif previous == 0 then
				for i, model in pairs(lodModel.lods) do
					if model.cellSize == meshCellSize then
						LODService.loadModelIntoLOD(lodModel, i, position, cframeList, partList, t, position)
						found = true
						penalty += model.loadingPenalty
						break
					end
				end

				Util.hideModel(lodModel.model0, 0)
				penalty += lodModel.loadingPenalty0
			else
				for i, model in pairs(lodModel.lods) do
					if model.cellSize == meshCellSize then
						LODService.loadModelIntoLOD(lodModel, i, position, cframeList, partList, t, position)
						found = true
						penalty += model.loadingPenalty
					elseif model.cellSize == previous then
						loaded = modelUnloader(model.model, loaded, lodModel.lods, i)
						penalty += model.loadingPenalty
					end
				end
			end

			if not found then
				local model, lines, count = Util.createMeshFromTemplate(mesh, lodModel.pivot, 
					lodModel.model0:GetScale() * group.template.scale, cframeList, partList)
				
				local loadingPenalty = (0.03 * count + 0.25) * lodModel.loadingPenaltyMultiplier
				
				penalty += loadingPenalty
				loaded += 1

				forceUpdate = true

				local index = #lodModel.lods + 1

				lodModel.selectedLodIndex = index

				lodModel.lods[index] = {
					model = model,
					lines = lines,
					cellSize = meshCellSize,
					loadingPenalty = loadingPenalty,
					lastUpdate = t
				}
			end
		end
	end

	return penalty, loaded, forceUpdate
end


function LODService.stepBillboards()
	local camera = workspace.CurrentCamera

	if not camera then
		warn("Could not step billboards because workspace.CurrentCamera is nil!")
		return
	end

	local camPos = camera.CFrame.Position
	local penalty = 0

	local cframeList, partList = {}, {}

	for _, region in _G.regions do
		local dir = (region.pivot - camPos).Unit
		penalty += 5

		-- only update billboards if actually needed
		if region.lastDir:Dot(dir) < LODService.BillboardUpdateDot then
			penalty = LODService.stepRegionBillboards(region, dir, camPos, cframeList, partList, penalty)
		end

		if penalty > LODService.BillboardTimeout then
			penalty = 0
			task.wait()
		end
	end

	workspace:BulkMoveTo(partList, cframeList, Enum.BulkMoveMode.FireCFrameChanged)
end

function LODService.stepRegionBillboards(region : ModelRegion, dir : Vector3, camPos : Vector3, cframeList : {CFrame}, 
	partList : {Instance}, penalty : number)

	region.lastDir = dir

	for _, group in region.groups do
		penalty += 1

		-- naive approach but helps alot
		local sample = group.models[1]

		if not sample then
			continue
		end

		if sample.selectedBillboard then
			for _, model in group.models do
				if model.selectedBillboard then
					Util.updateBillboard(model.selectedBillboard, model.model0:GetPivot().Position, camPos)
				end
			end
		elseif sample.selectedLodIndex then
			local lines = sample.lods[sample.selectedLodIndex].lines

			if #lines > 0 then
				for _, model in group.models do
					if model.selectedLodIndex then
						Util.updateLines(model.lods[model.selectedLodIndex].lines, camPos, cframeList, partList)
					end
				end
			end
		end
	end

	return penalty
end


function LODService:GetLODGenerator()
	return LODService.lodGenerator
end

function LODService.createFixedMeshPart(editableMesh : EditableMesh)
	-- you can only have 8 non fixed size meshes but a lot of fixed size meshes
	-- and we can do this hacky kind of thing to convert non fixed to fixed
	local fixed = AS:CreateEditableMeshAsync(Content.fromObject(editableMesh), {FixedSize = true})
	editableMesh:Destroy()
	return AS:CreateMeshPartAsync(Content.fromObject(fixed))
end

function LODService.makePlaneTemplate(plane : LODGenerator.BillboardPlane, zIndex : number)
	local part = script.Part:Clone()
	part.Parent = DynamicallyGenerated
	part.Size = Vector3.new(plane.Size.X, plane.Size.Y, 0)
	part.CFrame = plane.CFrame

	local image1 = Instance.new("Decal", part)
	image1.TextureContent = Content.fromObject(plane.FrontFace)
	image1.Face = Enum.NormalId.Front
	image1.ZIndex = zIndex
	image1.Transparency = 1
	image1.Name = "FrontFace"

	local image2 = Instance.new("Decal", part)
	image2.TextureContent = Content.fromObject(plane.BackFace)
	image2.Face = Enum.NormalId.Back
	image2.ZIndex = zIndex
	image2.Transparency = 1
	image2.Name = "BackFace"

	return part
end

--[[ Takes the meshes and billboards generated by the LODGenerator and returns a template for runtime use,
THIS DELETES THE EDITABLEMESHES]]
function LODService:GeneratedToTemplate(
	lods : {{OpaqueMesh : EditableMesh, TransparentMesh : EditableMesh?, PixelLines : {VertexClustering.PixelLine}}}, 
	billboards : {{Planes : {LODGenerator.BillboardPlane}, YPlane : LODGenerator.BillboardPlane, MaxDot : number, YAngle : number}},
	maxCellSize : number, pivot : CFrame, meshTexture : string?, surfaceAppearance : SurfaceAppearance?, scale : number?) : Template

	assert(typeof(maxCellSize) == "number", "maxCellSize must be a number!")

	local templateLods = {}

	for cellSize, lod in pairs(lods) do
		local transparentPart
		local meshPart = LODService.createFixedMeshPart(lod.OpaqueMesh)
		meshPart.Parent = DynamicallyGenerated
		meshPart.Color = Color3.new(1, 1, 1)
		meshPart.CanCollide = false
		meshPart.CanQuery = false
		meshPart.CanTouch = false
		meshPart.Anchored = true

		if meshTexture then
			meshPart.TextureID = meshTexture
		end

		if surfaceAppearance then
			local clone = surfaceAppearance:Clone()
			clone.Parent = meshPart
		end

		if lod.TransparentMesh then
			transparentPart = LODService.createFixedMeshPart(lod.TransparentMesh)
			transparentPart.Parent = DynamicallyGenerated
			transparentPart.Color = Color3.new(1, 1, 1)
			transparentPart.CanCollide = false
			transparentPart.CanQuery = false
			transparentPart.CanTouch = false
			transparentPart.Anchored = true
			transparentPart.Transparency = 0.02

			if meshTexture then
				transparentPart.TextureID = meshTexture
			end

			if surfaceAppearance then
				local clone = surfaceAppearance:Clone()
				clone.Parent = transparentPart
			end
		end

		local pixelLines = {}

		for _, line in lod.PixelLines do
			local v1 = pivot:PointToObjectSpace(line.v1.position)
			local v2 = pivot:PointToObjectSpace(line.v2.position)

			local color = line.v1.color:Lerp(line.v2.color, 0.5)
			local alpha = math.lerp(line.v1.alpha, line.v2.alpha, 0.5)

			table.insert(pixelLines, {v1 = v1, v2 = v2, thickness = line.thickness, c = color, a = alpha})
		end

		templateLods[cellSize] = {opaqueMesh = meshPart, transparentMesh = transparentPart, pixelLines = pixelLines}
	end

	local templateBillboards =  {}

	for cellSize, billboard in pairs(billboards) do
		local templateBillboard = {planes = {}}
		
		templateBillboard.yPlane = LODService.makePlaneTemplate(billboard.YPlane, 0)
		
		local zIndex = 1

		for _, plane in billboard.Planes do
			table.insert(templateBillboard.planes, 
				LODService.makePlaneTemplate(plane, zIndex))
			zIndex += 1
		end

		assert(typeof(billboard.MaxDot) == "number", "MaxDot must be a number!")
		templateBillboard.m = 1 / (1 - billboard.MaxDot)
		assert(typeof(billboard.YAngle) == "number", "YAngle must be a number!")
		templateBillboard.m2 = 1 / math.cos(math.rad(billboard.YAngle))
	end

	return {maxCellSize = maxCellSize, lods = templateLods, billboards = templateBillboards, scale = scale and 1 / scale or 1}
end


return LODService