--!strict

-- module for functions that are used by different classes

local Util = {}

Util.folder = workspace :: Instance

local Types = require(script.Parent.Parent.Types)

type BillboardTemplate = Types.BillboardTemplate
type MeshTemplate = Types.MeshTemplate
type BillboardPlane = Types.BillboardPlane
type Billboard = Types.Billboard
type LoadedLine = Types.LoadedLine


function Util.createPlaneFromTempalte(plane : Part, parent : Model, pivot : CFrame, cframeList : {CFrame}, partList : {Instance}, 
	scale : number) : BillboardPlane

	local part = plane:Clone()

	-- pretty un-oop but meh
	local frontFace = part:FindFirstChild("FrontFace")
	if not frontFace or not frontFace:IsA("Decal") then
		error("Could not find FrontFace decal in plane template!")
	end

	local backFace = part:FindFirstChild("BackFace")
	if not backFace or not backFace:IsA("Decal") then
		error("Could not find BackFace decal in plane template!")
	end

	part.Parent = parent
	-- thankfully we do not need to apply the scale to the cframe
	-- since the cframe's position is always at 0, 0, 0 (since they are billboards)
	local cf = pivot:ToWorldSpace(plane.CFrame.Rotation)
	table.insert(cframeList, cf)
	table.insert(partList, part)
	part.Size *= scale

	local dir = cf.LookVector

	return {
		-- sorry for these unorthodox methods but i just cannot be bothered to optimize bs like this
		lookVector2d = Vector2.new(dir.X, dir.Z).Unit, 
		lookVector3d = dir, 
		frontFace = frontFace, 
		backFace = backFace, 
		part = part,
		cframe = plane.CFrame
	}
end


function Util.createBillboardFromTemplate(template : BillboardTemplate, pivot : CFrame, boundingBox : Vector3, scale : number, 
	cellSize : number, cframeList : {CFrame}, partList : {Instance}, penaltyMultiplier : number, t : number) : Billboard

	local model = Instance.new("Model")
	model.Parent = Util.folder
	
	pivot = CFrame.new(boundingBox) * pivot.Rotation

	local yPlane = Util.createPlaneFromTempalte(template.yPlane, model, pivot, cframeList, partList, scale)
	local planes = {}

	for _, plane in template.planes do
		table.insert(planes, Util.createPlaneFromTempalte(plane, model, pivot, cframeList, partList, scale))
	end

	return {
		model = model,
		yPlane = yPlane,
		planes = planes,
		m = template.m,
		m2 = template.m2,
		cellSize = cellSize,
		loadingPenalty = (#planes + 2) * 0.035 * penaltyMultiplier,
		lastUpdate = t
	}
end

local plane = script.Parent.LODGenerator.plane

function Util.createMeshFromTemplate(mesh : MeshTemplate, pivot : CFrame, scale : number, cframeList : {CFrame}, 
	partList : {Instance})
	
	local partCount = 1

	local model = Instance.new("Model")
	model.Parent = Util.folder

	local opaqueMesh = mesh.opaqueMesh:Clone()
	opaqueMesh.Parent = model
	opaqueMesh.Size *= scale
	table.insert(cframeList, pivot)
	table.insert(partList, opaqueMesh)

	if mesh.transparentMesh then
		local transparentMesh = mesh.transparentMesh:Clone()
		transparentMesh.Parent = model
		transparentMesh.Size *= scale
		table.insert(cframeList, pivot)
		table.insert(partList, transparentMesh)
		
		partCount += 1
	end

	local pixelLines : {LoadedLine} = {}

	for _, line in mesh.pixelLines do
		-- line.v1 and line.v2 are relative to the pivot, therefore multiplying by the relative scale
		-- is the same as using ScaleTo
		local v1 = pivot:PointToWorldSpace(line.v1 * scale)
		local v2 = pivot:PointToWorldSpace(line.v2 * scale)
		local rightVector = v2 - v1

		local plane = plane:Clone()
		plane.Parent = model
		plane.Size = Vector3.new(rightVector.Magnitude, line.thickness, 0)

		plane.Color = line.c
		plane.Transparency = 1 - line.a

		table.insert(pixelLines, {v1 = v1, v2 = v2, plane = plane, rightVector = rightVector, origv1 = line.v1, origv2 = line.v2,
			pos = v1:Lerp(v2, 0.5)})
		
		partCount += 1
	end

	return model, pixelLines, partCount
end

function Util.hideModel(model : Model, loaded : number)
	--[[for _, v in parts do
		penalty += 0.04
		
		if penalty > Util.PenaltyTimeout then
			penalty = 0
			task.wait()
		end
		
		v.LocalTransparencyModifier = 1
	end]]
	
	model.Parent = nil

	return loaded
end

function Util.loadModel(model : Model)
	model.Parent = Util.folder
	
	--[[for _, v in model:GetDescendants() do
		if v:IsA("BasePart") then
			v.LocalTransparencyModifier = 0
		end
	end]]
end

function Util.pivotPlane(plane : BillboardPlane, pivot : CFrame, boundingBox : Vector3)
	local cframe = CFrame.new(boundingBox) * pivot:ToWorldSpace(plane.cframe).Rotation

	local dir = cframe.LookVector
	-- the 2 vectors needed for adjusting the plane's transparency
	plane.lookVector2d = Vector2.new(dir.X, dir.Z).Unit
	plane.lookVector3d = dir

	return cframe
end


function Util.updateBillboard(billboard : Billboard, pivot : Vector3, cameraPosition : Vector3)
	local lookVector = (pivot - cameraPosition).Unit
	local vector2d = Vector2.new(lookVector.X, lookVector.Z).Unit

	local yBillboard = billboard.yPlane
	local m = billboard.m
	local m2 = billboard.m2

	-- the 'y element' of the transparency of the non y oriented images equals 1 - yTransparency => yAlpha = 1 - (1 - yTransparency) =>
	-- yAlpha = yTransparency
	local yAlpha = math.min(
		-- linear transparency = (1 - |dot|) / (1 - fullTransparentAngle)
		(1 - math.abs(yBillboard.lookVector3d:Dot(lookVector))) * m2,
		1)


	for _, plane in billboard.planes do
		-- same linear transparency as before but we reverse it to get the alpha (i found that this cannot be simplified further)
		local alpha = math.max(1 - 
			(1 - math.abs(vector2d:Dot(plane.lookVector2d))) * m, 
			0)

		local transparency = 1 - (alpha * yAlpha)
		plane.frontFace.Transparency = transparency
		plane.backFace.Transparency = transparency
	end

	yBillboard.frontFace.Transparency = yAlpha
	yBillboard.backFace.Transparency = yAlpha
end

function Util.updateLines(lines : {LoadedLine}, camPosition : Vector3, cframeList : {CFrame}, partList : {Instance})
	for _, line in lines do
		local normal = (line.v1 - camPosition):Cross(line.v2 - camPosition):Cross(line.rightVector)

		table.insert(partList, line.plane)
		table.insert(cframeList, CFrame.lookAlong(line.pos, normal, line.rightVector:Cross(normal)))
	end
end


return Util