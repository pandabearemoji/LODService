--!strict

local LODGenerator = {}
LODGenerator.__index = LODGenerator


local AS = game:GetService("AssetService")
local Lighting = game:GetService("Lighting")
local HttpService = game:GetService("HttpService")


local VertexColorProcessor = require(script.VertexColorProcessor)
local PartData = require(script.PartData)
local MeshData = require(script.MeshData)
local MeshSimplification = require(script.MeshSimplification)
local PartOperationProcessor = require(script.PartOperationProcessor)
local MeshParser = require(script.MeshParser)


export type LODGenerator = typeof(setmetatable({} :: {
		meshSimplification : MeshSimplification.MeshSimplification,
		vertexColorProcessor : VertexColorProcessor.VertexColorProcessor,
		boxParts : boolean,
		textureSamplingRadius : number,
		textureSamplingIterations : number,
		pre2022Materials : boolean,
		useMaterialAverages : boolean,
		ignoreUnprocessable : boolean,
		-- boundaries used for billboard generation optimisation
		minX : number,
		maxX : number,
		minY : number,
		maxY : number,
		minZ : number,
		maxZ : number,
		progress : number,
		modelProgress : number
}, LODGenerator))

export type BillboardPlane = {
	CFrame : CFrame,
	Size : Vector2,
	FrontFace : EditableImage,
	BackFace : EditableImage
}


function LODGenerator.new(boxParts : boolean, textureSamplingRadius : number, textureSamplingIterations : number, 
	pre2022Materials : boolean, useMaterialAverages : boolean, ignoreUnprocessable : boolean): LODGenerator
	
	return setmetatable({
		meshSimplification = MeshSimplification.new(), 
		vertexColorProcessor = VertexColorProcessor.new(),
		boxParts = boxParts,
		textureSamplingRadius = textureSamplingRadius,
		textureSamplingIterations = textureSamplingIterations,
		pre2022Materials = pre2022Materials,
		useMaterialAverages = useMaterialAverages,
		ignoreUnprocessable = ignoreUnprocessable,
		minX = math.huge,
		maxX = -math.huge,
		minY = math.huge,
		maxY = -math.huge,
		minZ = math.huge,
		maxZ = -math.huge,
		progress = 0,
		modelProgress = 0
	}, LODGenerator)
end


function LODGenerator.OnVertexAdded(self : LODGenerator, position : Vector3)
	self.minX = math.min(position.X, self.minX)
	self.minY = math.min(position.Y, self.minY)
	self.minZ = math.min(position.Z, self.minZ)

	self.maxX = math.max(position.X, self.maxX)
	self.maxY = math.max(position.Y, self.maxY)
	self.maxZ = math.max(position.Z, self.maxZ)
end


local function getPartData(part : BasePart, boxParts : boolean, meshType : Enum.MeshType?) : ({Vector3}, {{number}}, {Vector3}, Vector3)
	local vertexData, faceData, normalData = PartData.blockVertices, PartData.blockFaces, PartData.blockNormals
	local size = part.Size
	
	if boxParts then
		return vertexData, faceData, normalData, size
	end
	
	local shape = Enum.PartType.Block
	
	if part:IsA("Part") then
		shape = part.Shape
	elseif part:IsA("CornerWedgePart") then
		shape = Enum.PartType.CornerWedge
	elseif part:IsA("WedgePart") then
		shape = Enum.PartType.Wedge
	end
	
	if not part:IsA("MeshPart") then
		if meshType then
			if meshType == Enum.MeshType.Sphere then
				vertexData = PartData.sphereVertices
				faceData = PartData.sphereFaces
				normalData = PartData.sphereNormals
			elseif meshType == Enum.MeshType.Wedge then
				vertexData = PartData.wedgeVertices
				faceData = PartData.wedgeFaces
				normalData = PartData.wedgeNormals
			elseif meshType == Enum.MeshType.Cylinder then
				vertexData = PartData.cylinderVertices
				faceData = PartData.cylinderFaces
				normalData = PartData.cylinderNormals
				local minSize = math.min(size.Y, size.Z)
				size = Vector3.new(size.X, minSize, minSize)
			elseif meshType == Enum.MeshType.Head then
				vertexData = MeshData.headVertices
				faceData = MeshData.headFaces
				normalData = MeshData.headNormals
				local minSize = math.min(size.X, size.Z)
				size = Vector3.new(minSize, size.Y, minSize)
			end
		else
			if shape == Enum.PartType.Ball then
				vertexData = PartData.sphereVertices
				faceData = PartData.sphereFaces
				normalData = PartData.sphereNormals
				size = Vector3.one * math.min(size.X, size.Y, size.Y)
			elseif shape == Enum.PartType.Wedge then
				vertexData = PartData.wedgeVertices
				faceData = PartData.wedgeFaces
				normalData = PartData.wedgeNormals
			elseif shape == Enum.PartType.Cylinder then
				vertexData = PartData.cylinderVertices
				faceData = PartData.cylinderFaces
				normalData = PartData.cylinderNormals
				local minSize = math.min(size.Y, size.Z)
				size = Vector3.new(size.X, minSize, minSize)
			elseif shape == Enum.PartType.CornerWedge then
				vertexData = PartData.cornerWedgeVertices
				faceData = PartData.cornerWedgeFaces
				normalData = PartData.cornerWedgeNormals
			end
		end
	end
	
	return vertexData, faceData, normalData, size
end


function LODGenerator.ProcessObjectWithData(self : LODGenerator, part : BasePart, vertexData : {Vector3}, normalData : {Vector3}, 
	faceData : {{number}}, size : Vector3, offset : Vector3)
	local vertices = {}
	
	-- get part color and alpha (accounting for materials and allat)
	local color, alpha = VertexColorProcessor.getPartColor(part, self.pre2022Materials, self.useMaterialAverages)

	for i, vertex in pairs(vertexData) do
		local position = part.CFrame:PointToWorldSpace(vertex * size + offset)

		self:OnVertexAdded(position)

		vertices[i] = self.meshSimplification:AddVertex(position, color, alpha, part.CFrame:VectorToWorldSpace(normalData[i]))
	end

	for _, face in faceData do
		self.meshSimplification:AddTriangle(vertices[face[1]], vertices[face[2]], vertices[face[3]])
	end
end

function LODGenerator.ProcessPart(self : LODGenerator, part : BasePart)
	local vertexData, faceData, normalData, size = getPartData(part, self.boxParts)
	
	self:ProcessObjectWithData(part, vertexData, normalData, faceData, size, Vector3.zero)
end

function LODGenerator.ParseRobloxMesh(self : LODGenerator, part : BasePart, meshId : string, pivot : CFrame, size : Vector3, 
	processor : (textureCoords : Vector2) -> (Color3, number))
	
	local function onVertexAdded(position : Vector3)
		self:OnVertexAdded(position)
	end
	
	local success, errorMessage = pcall(function()
		local assetId = meshId:match("%d+$")
		
		local location = HttpService:JSONDecode(HttpService:GetAsync(`http://localhost:8080/v1/assetId/{assetId}`)).location
		local str = HttpService:GetAsync(location)

		return MeshParser.Parse(str, self.meshSimplification, processor, onVertexAdded, pivot, size)
	end)
	
	if not success or errorMessage then
		warn(`Failed to process MeshPart {part:GetFullName()}, with error message: {errorMessage}`)
		
		if not self.ignoreUnprocessable then
			self:ProcessPart(part)
			warn("Falling back to block parts...")
			return
		end
	end
end

function LODGenerator.ProcessEditableMesh(self : LODGenerator, mesh : EditableMesh, pivot : CFrame, size : Vector3, 
	processor : (textureCoords : Vector2) -> (Color3, number), partColor: Color3, partAlpha: number)
	mesh:Triangulate()

	local vertices = {}

	for _, vertex in mesh:GetVertices() do
		-- average over all the uvs
		local r, g, b, a = 0, 0, 0, 0

		local ln = 0
		local uvCoords

		for _, uvId in mesh:GetVertexUVs(vertex) do
			local uv = mesh:GetUV(uvId)

			if uv then
				uvCoords = uv

				ln += 1
				local color, alpha = processor(uv)
				r += color.R
				g += color.G
				b += color.B
				a += alpha
			end
		end

		if ln > 0 then
			-- reciprocal for a bit of optimization (i just like doing this it doesnt help that much)
			ln = 1 / ln

			r *= ln
			g *= ln
			b *= ln
			a *= ln
		else
			-- no uv coloring, so we use base part color for tinting
			r = partColor.R
			g = partColor.G
			b = partColor.B
			a = partAlpha
		end
		
		-- add vertex colors if they exist
		local vertexR = 0
		local vertexG = 0
		local vertexB = 0
		local vertexA = 0

		local colorLn = 0
		local alphaLn = 0

		for _, colId in mesh:GetVertexColors(vertex) do
			local col, alpha = mesh:GetColor(colId), mesh:GetColorAlpha(colId)

			if col then
				colorLn += 1
				vertexR += col.R
				vertexG += col.G
				vertexB += col.B
			end

			if alpha then
				alphaLn += 1
				vertexA += alpha
			end
		end

		if colorLn ~= 0 then
			colorLn = 1 / colorLn
			r *= colorLn
			g *= colorLn
			b *= colorLn
		end

		if alphaLn ~= 0 then
			a /= alphaLn
		end

		local normal : Vector3?
		local normals = mesh:GetVertexNormals(vertex)

		if #normals > 0 then
			-- average all vertex normals
			local normalAverage = Vector3.zero
			ln = 0

			for _, n in normals do
				local dir = mesh:GetNormal(n)

				if dir then
					ln += 1
					normalAverage += dir
				end
			end

			if ln > 0 then
				normal = pivot:VectorToWorldSpace((normalAverage / ln).Unit)
			else
				normal = nil
			end
		end

		local position = pivot:PointToWorldSpace(mesh:GetPosition(vertex) * size)

		self:OnVertexAdded(position)

		vertices[vertex] = self.meshSimplification:AddVertex(position, Color3.new(r, g, b), a, normal, uvCoords, processor)
	end

	for _, _face in mesh:GetFaces() do
		local face = mesh:GetFaceVertices(_face)

		self.meshSimplification:AddTriangle(vertices[face[1]], vertices[face[2]], vertices[face[3]])
	end

	mesh:Destroy()
end

function LODGenerator.ProcessMeshPart(self : LODGenerator, part : MeshPart)
	local success, mesh = pcall(function()
		return AS:CreateEditableMeshAsync(part.MeshContent)
	end)
	
	local processor = self.vertexColorProcessor:GetMeshPartProcessor(part, self.textureSamplingRadius, self.textureSamplingIterations, 
		self.pre2022Materials, self.useMaterialAverages)
	
	if not success then
		self:ParseRobloxMesh(part, part.MeshId, part.CFrame, part.Size / part.MeshSize, processor)
		return
	end
	
	local size = part.Size / part.MeshSize
	
	local partColor, partAlpha = VertexColorProcessor.getPartColor(part, self.pre2022Materials, self.useMaterialAverages)
	self:ProcessEditableMesh(mesh, part.CFrame, size, processor, partColor, partAlpha)
end

function LODGenerator.ProcessFileMesh(self : LODGenerator, part : BasePart, mesh : FileMesh | SpecialMesh)
	local assetId = tonumber(mesh.MeshId:match("%d+$"))

	if not assetId then
		warn(`MeshId ({mesh.MeshId}) of Mesh {mesh:GetFullName()} is not a valid AssetId`)
		return
	end
	
	local success, editableMesh = pcall(function()
		return AS:CreateEditableMeshAsync(Content.fromAssetId(assetId))
	end)
	
	local processor = self.vertexColorProcessor:GetFileMeshProcessor(part, mesh, self.textureSamplingRadius, 
		self.textureSamplingIterations, self.pre2022Materials, self.useMaterialAverages)
	
	-- get MeshSize
	local meshPart = AS:CreateMeshPartAsync(Content.fromAssetId(assetId))
	local size = mesh.Scale * 0.5
	meshPart:Destroy()

	if not success then
		self:ParseRobloxMesh(part, mesh.MeshId, part.CFrame + mesh.Offset, size, processor)
		return
	end

	local partColor, partAlpha = VertexColorProcessor.getPartColor(part, self.pre2022Materials, self.useMaterialAverages)
	self:ProcessEditableMesh(editableMesh, part.CFrame, size, processor, partColor, partAlpha)
end

function LODGenerator.ProcessPartOperation(self : LODGenerator, partOperation : PartOperation) : string?
	local data, err = PartOperationProcessor.get(partOperation)
	
	if not data then
		return err
	end
	
	local pivot = partOperation.CFrame
	
	local vertices = {}
	
	for i, vertex in pairs(data.positions) do
		local pos = pivot:PointToWorldSpace(vertex)
		
		local colors = data.colors[i]
		local color = Color3.fromRGB(colors[1], colors[2], colors[3])
		
		self:OnVertexAdded(pos)
		
		-- todo: add texture processing
		vertices[i] = self.meshSimplification:AddVertex(pos, color, colors[4] / 255, pivot:VectorToWorldSpace(data.normals[i]))
	end
	
	for i = 1, #data.faces, 3 do
		local a = data.faces[i] + 1
		local b = data.faces[i + 1] + 1
		local c = data.faces[i + 2] + 1
		
		self.meshSimplification:AddTriangle(vertices[a], vertices[b], vertices[c])
	end
	
	return nil
end

function LODGenerator.ProcessMesh(self : LODGenerator, part : BasePart, mesh : BlockMesh | SpecialMesh | FileMesh, 
	ignoreUnprocessable : boolean)
	
	local meshType = mesh:IsA("SpecialMesh") and mesh.MeshType or Enum.MeshType.Brick
	
	-- SpecialMesh inherits from FileMesh so the IsA check is not enough
	if ((mesh:IsA("FileMesh") and mesh.ClassName == "FileMesh") 
		or (mesh:IsA("SpecialMesh") and mesh.MeshType == Enum.MeshType.FileMesh)) and not mesh:IsA("BlockMesh") then
		-- stupid strict complains so i have to add the blockmesh condition
		self:ProcessFileMesh(part, mesh)
		return
	end
	
	local vertexData, faceData, normalData, size = getPartData(part, self.boxParts, meshType)
	
	if meshType == Enum.MeshType.Cylinder then
		-- from my testing it looks like cylinder meshes have their z scale completely ignored
		-- + it also clips the y and z size even thought this isn't the case for sphere meshes for some reason lol
		size *= Vector3.new(mesh.Scale.X, mesh.Scale.Y, mesh.Scale.Y)
	elseif meshType == Enum.MeshType.Head then
		-- head has vertical cylinder like scaling
		local minScale = math.min(mesh.Scale.X, mesh.Scale.Z)
		size *= Vector3.new(minScale, mesh.Scale.Y, minScale)
	else
		size = part.Size * mesh.Scale
	end
	
	self:ProcessObjectWithData(part, vertexData, normalData, faceData, size, mesh.Offset)
end

function LODGenerator.ProcessCylinderMesh(self : LODGenerator, part : BasePart, cylinderMesh : CylinderMesh)
	local minScale = math.min(cylinderMesh.Scale.X, cylinderMesh.Scale.Z)
	local minSize = math.min(part.Size.X, part.Size.Z) * minScale
	local size = Vector3.new(minSize, part.Size.Y * cylinderMesh.Scale.Y, minSize)

	self:ProcessObjectWithData(part, MeshData.cylinderMeshVertices, MeshData.cylinderMeshNormals, MeshData.cylinderMeshFaces, size, 
		cylinderMesh.Offset)
end

-- Processes a model, use LODGenerator:Clear() if you already processed a model and you do not want a union of the previous and this one
function LODGenerator.ProcessModel(self : LODGenerator, model : Model)
	local descendants = model:GetDescendants()
	
	for i, v : Instance in pairs(descendants) do
		self.modelProgress = i / #descendants
		
		if v:IsA("BasePart") then
			if v:IsA("MeshPart") then
				self:ProcessMeshPart(v)
				continue
			end
			
			local cylinderMesh = v:FindFirstChildWhichIsA("CylinderMesh")

			if cylinderMesh then
				self:ProcessCylinderMesh(v, cylinderMesh)
				continue
			end

			local specialMesh = v:FindFirstChildWhichIsA("SpecialMesh") or v:FindFirstChildWhichIsA("BlockMesh")

			if specialMesh then
				self:ProcessMesh(v, specialMesh, self.ignoreUnprocessable)
				continue
			end

			if v:IsA("Part") or v:IsA("CornerWedgePart") or v:IsA("WedgePart") or v:IsA("TrussPart") or v:IsA("FlagStand") then
				self:ProcessPart(v)
			elseif v:IsA("PartOperation") then
				local err = self:ProcessPartOperation(v)

				if err then
					if self.ignoreUnprocessable then
						warn("Couldn't process " .. v:GetFullName() .. " (Reason: " .. err .. 
							"), PartOperation will be treated as a block!")
						self:ProcessPart(v)
					else
						warn("Couldn't process " .. v:GetFullName() .. " (Reason: " .. err .. ")!")
					end
				end
			end
		end
	end
end


function LODGenerator.Cleanup(self : LODGenerator)
	self.vertexColorProcessor:Cleanup()
end

function LODGenerator.Clear(self : LODGenerator)
	self.meshSimplification:Clear()
	self:Cleanup()
	
	self.minX = math.huge
	self.maxX = -math.huge
	self.minY = math.huge
	self.maxY = -math.huge
	self.minZ = math.huge
	self.maxZ = -math.huge
end


--[[Simplifies the model using vertex clustering, keep in mind that this overrides the previous simplified version's data, 
only use this after you used GetEditableMeshOpaque/GetEditableMeshWithTransparency in order to finalize the previous version

cellSize: The size of each floating cell (read Reference [1] for further details)
dynamicNormals: Whether certain triangles get turned into edges with dynamic normals 
	(read Reference [1] '4 IMPLEMENTATION Estimating thickness of edges.' for further details)
colorAveragingBias: How much the color of a floating cell center gets averaged (read documentation)]]
function LODGenerator.VertexClustering(self : LODGenerator, dynamicNormals : boolean, cellSize : number, colorAveragingBias : number, 
	timeout : number)
	
	return self.meshSimplification:VertexClustering(dynamicNormals, cellSize, timeout, colorAveragingBias)
end

--[[Simplifies the model using QMS (Quadric Mesh Simplification),
same rules apply as for vertex clustering

I will not be explaining EVERY SINGLE setting here, go watch the plugin tutorial]]
function LODGenerator.QMS(self : LODGenerator, triCount : number, threshold : number, mergeThreshold : number, colorThreshold : number, 
	normalThreshold : number, edgeCos : number, inversionCos : number, inversionPenalty : number, boundaryPenalty : number, 
	maxError : number, alphaPenalty : number, colorPenalty : number, determinantTolerance : number, colorBalancing : number, 
	alphaBalancing : number, normalBalancing : number, uvBalancing : number, timeout : number)
	
	self.meshSimplification:QMS(triCount, threshold, mergeThreshold, colorThreshold, normalThreshold, edgeCos , inversionCos, 
		inversionPenalty, boundaryPenalty, maxError, alphaPenalty, colorPenalty, determinantTolerance, timeout, colorBalancing, 
		alphaBalancing, normalBalancing, uvBalancing)
end


--[[ Gets the processed/simplified mesh without regard to transparency
pivot: the pivot of the generated mesh, for models just used model:GetPivot()
blockiness: number from 0 to 1, when 0 the normals from the original model are kept, when 1 new normals are generated
	(0 is recommended unless your mesh contains really weird normals)
timeout: the amount of instructions before relieving the thread, defaults to 1000]]
function LODGenerator.GetEditableMeshOpaque(self : LODGenerator, pivot : CFrame, blockiness : number, timeout : number?)
	local mesh = AS:CreateEditableMesh()
	
	local vertices = {}
	
	local vertexCount = 0
	
	local timeout = timeout or 1000
	
	for _, vertex in self.meshSimplification.vertices do
		vertexCount += 1
		
		if vertexCount % timeout == 0 then
			task.wait()
		end
		
		if vertexCount > 60000 then
			warn("EditableMesh vertex limit reached! This may leave holes in the mesh..")
			break
		end
		
		local pos = pivot:PointToObjectSpace(vertex.position)
		
		local uv = vertex.uv and mesh:AddUV(vertex.uv)
		
		vertices[vertex] = {
			vert = mesh:AddVertex(pos),
			color = mesh:AddColor(vertex.color, vertex.alpha),
			position = pos,
			normal = vertex.normal and pivot:VectorToObjectSpace(vertex.normal),
			uv = uv
		}
	end
	
	local triCount = 0
	
	for _, tri in self.meshSimplification.triangles do
		local vert1 = vertices[tri.vertices[1]]
		local vert2 = vertices[tri.vertices[2]]
		local vert3 = vertices[tri.vertices[3]]
		
		if vert1 and vert2 and vert3 then
			triCount += 1
			
			if triCount % timeout == 0 then
				task.wait()
			end

			if triCount > 20000 then
				warn("EditableMesh triangle limit reached! This may leave holes in the mesh..")
				break
			end
			
			local face = mesh:AddTriangle(vert1.vert, vert2.vert, vert3.vert)
			
			-- automatic normal
			local normal = (vert2.position - vert1.position):Cross(vert3.position - vert1.position)
			local normalId = mesh:AddNormal(normal)
			
			-- fall back to generated normal if a set one doesnt exist
			local normalId1 = vert1.normal and mesh:AddNormal(vert1.normal:Lerp(normal, blockiness)) or normalId
			local normalId2 = vert2.normal and mesh:AddNormal(vert2.normal:Lerp(normal, blockiness)) or normalId
			local normalId3 = vert3.normal and mesh:AddNormal(vert3.normal:Lerp(normal, blockiness)) or normalId
			
			mesh:SetFaceColors(face, {vert1.color, vert2.color, vert3.color})
			mesh:SetFaceNormals(face, {normalId1, normalId2, normalId3})
			
			if vert1.uv then
				mesh:SetVertexFaceUV(vert1.vert, face, vert1.uv)
			end
			
			if vert2.uv then
				mesh:SetVertexFaceUV(vert2.vert, face, vert2.uv)
			end
			
			if vert3.uv then
				mesh:SetVertexFaceUV(vert3.vert, face, vert3.uv)
			end
		end
	end
	
	mesh:RemoveUnused()
	
	return mesh
end


-- COLS AS IN CITADEL OF LAPTOP SPLITTING
local function safeGetVertex(indices : {[MeshSimplification.Vertex]: number}, cols : {[MeshSimplification.Vertex]: number}, 
	vertex : MeshSimplification.Vertex, editableMesh : EditableMesh, pivot : CFrame)
	
	local id = indices[vertex]

	if not id then
		local vert = editableMesh:AddVertex(pivot:PointToObjectSpace(vertex.position))
		indices[vertex] = vert

		local color = editableMesh:AddColor(vertex.color, vertex.alpha)
		cols[vertex] = color

		return vert, color, vertex.position
	end

	return id, cols[vertex], vertex.position
end

local function addTriToMesh(indices : {[MeshSimplification.Vertex]: number}, cols : {[MeshSimplification.Vertex]: number}, 
	editableMesh : EditableMesh, v1 : MeshSimplification.Vertex, v2 : MeshSimplification.Vertex, v3 : MeshSimplification.Vertex, 
	pivot : CFrame, blockiness : number)

	local id1, col1, pos1 = safeGetVertex(indices, cols, v1, editableMesh, pivot)
	local id2, col2, pos2 = safeGetVertex(indices, cols, v2, editableMesh, pivot)
	local id3, col3, pos3 = safeGetVertex(indices, cols, v3, editableMesh, pivot)

	local face = editableMesh:AddTriangle(id1, id2, id3)
	
	local normal = (pos2 - pos1):Cross(pos3 - pos1)
	local normalId = editableMesh:AddNormal(normal)
	
	local normalId1 = v1.normal and editableMesh:AddNormal(pivot:VectorToObjectSpace(v1.normal):Lerp(normal, blockiness)) or normalId
	local normalId2 = v2.normal and editableMesh:AddNormal(pivot:VectorToObjectSpace(v2.normal):Lerp(normal, blockiness)) or normalId
	local normalId3 = v3.normal and editableMesh:AddNormal(pivot:VectorToObjectSpace(v3.normal):Lerp(normal, blockiness)) or normalId
	
	if v1.uv then
		editableMesh:SetVertexFaceUV(id1, face, editableMesh:AddUV(v1.uv))
	end
	
	if v2.uv then
		editableMesh:SetVertexFaceUV(id2, face, editableMesh:AddUV(v2.uv))
	end
	
	if v3.uv then
		editableMesh:SetVertexFaceUV(id3, face, editableMesh:AddUV(v3.uv))
	end
	
	editableMesh:SetFaceColors(face, {col1, col2, col3})
	editableMesh:SetFaceNormals(face, {normalId1, normalId2, normalId3})
end

--[[Gets the processed/simplified mesh with regard to transparency,
this function returns a fully opaque mesh first and a transparent mesh second,
this is needed in order to help Roblox's transparent layering be more precise (more information on devforum post)

pivot: the pivot of the generated mesh, for models just used model:GetPivot()
blockiness: number from 0 to 1, when 0 the normals from the original model are kept, when 1 new normals are generated
	(0 is recommended unless your mesh contains really weird normals)
timeout: the amount of instructions before relieving the thread, defaults to 100]]
function LODGenerator.GetEditableMeshWithTransparency(self : LODGenerator, pivot : CFrame, blockiness : number, timeout : number?)
	local mesh = AS:CreateEditableMesh()
	local transparentMesh = AS:CreateEditableMesh()

	local vertexIndices = {}
	local transparentVertexIndices = {}
	local colors = {}
	local transparentColors = {}
	
	local timeout = timeout or 100
	
	local i = 0
	
	for _, tri in self.meshSimplification.triangles do
		i += 1

		if i >= timeout then
			i = 0
			task.wait()
		end

		local v1 = tri.vertices[1]
		local v2 = tri.vertices[2]
		local v3 = tri.vertices[3]

		if v1.alpha ~= 1 or v2.alpha ~= 1 or v3.alpha ~= 1 then
			if #transparentMesh:GetFaces() >= 20000 or #transparentMesh:GetVertices() >= 60000 then
				warn("EditableMesh memory limit reached! This may leave holes in the mesh..")
				break
			end

			addTriToMesh(transparentVertexIndices, transparentColors, transparentMesh, v1, v2, v3, pivot, blockiness)
		else
			if #mesh:GetFaces() >= 20000 or #mesh:GetVertices() >= 60000 then
				warn("EditableMesh memory limit reached! This may leave holes in the mesh..")
				break
			end

			addTriToMesh(vertexIndices, colors, mesh, v1, v2, v3, pivot, blockiness)
		end
	end
	
	mesh:RemoveUnused()
	transparentMesh:RemoveUnused()
	
	return mesh, transparentMesh
end


local GOLDEN_ANGLE = math.pi * (3 - math.sqrt(5))
local EPSILON = 0.0001

@native
local function raycast(pos : Vector3, dir : Vector3, pivot : CFrame, editableMesh : EditableMesh, 
	vertexConverter : {[number] : MeshSimplification.Vertex}, samples : number, samplesRecip : number, samplesRecip2: number,
	ambient : Color3, maxAoDistance : number, count : number) : (number, number, number, number, number, Vector3?)
	
	local face, point, barycentric, v1, v2, v3 = editableMesh:RaycastLocal(pos, dir)
	count += 1

	if face then
		local bX = barycentric.X
		local bY = barycentric.Y
		local bZ = barycentric.Z

		-- yeah these are pointer indices, yeah this is disgusting, no im not implementing any bullshit just for this small thing
		local vert1 = vertexConverter[v1]
		local vert2 = vertexConverter[v2]
		local vert3 = vertexConverter[v3]

		local col1, col2, col3, a1, a2, a3 = vert1.color, vert2.color, vert3.color, vert1.alpha, vert2.alpha, vert3.alpha
		local proc1, proc2, proc3

		local uv1 = vert1.uv
		local uv2 = vert2.uv
		local uv3 = vert3.uv

		if uv1 and uv2 and uv3 then
			local uv = Vector2.new(
				bX * uv1.X + bY * uv2.X + bZ * uv3.X,
				bX * uv1.Y + bY * uv2.Y + bZ * uv3.Y
			)

			if vert1.processor then
				col1, a1, proc1 = vert1.processor(uv)
			end

			if vert2.processor then
				col2, a2, proc2 = vert2.processor(uv)
			end

			if vert3.processor then
				col3, a3, proc3 = vert3.processor(uv)
			end
		end

		if not proc1 then
			col1 = vert1.color
			a1 = vert1.alpha
		end
		
		if not proc2 then
			col2 = vert2.color
			a2 = vert2.alpha
		end
		
		if not proc3 then
			col3 = vert3.color
			a3 = vert3.alpha
		end
		
		local a = bX * a1 + bY * a2 + bZ * a3
		
		if a == 0 then
			return 0, 0, 0, 0, point
		end
		
		local normal = (editableMesh:GetPosition(v2) - editableMesh:GetPosition(v1)):Cross(
			editableMesh:GetPosition(v3) - editableMesh:GetPosition(v1)).Unit
		
		local n1 = vert1.normal and pivot:VectorToWorldSpace(vert1.normal) or normal
		local n2 = vert2.normal and pivot:VectorToWorldSpace(vert2.normal) or normal
		local n3 = vert3.normal and pivot:VectorToWorldSpace(vert3.normal) or normal
		
		local nVector = Vector3.new(
			bX * n1.X + bY * n2.X + bZ * n3.X,
			bX * n1.Y + bY * n2.Y + bZ * n3.Y,
			bX * n1.Z + bY * n2.Z + bZ * n3.Z
		)
		local n = CFrame.lookAlong(Vector3.zero, -nVector)
		
		local ao = 0
		
		for i = 0, samples - 1 do
			local z = i * samplesRecip
			
			local radius = math.sqrt(1 - z * z)
			local theta = i * GOLDEN_ANGLE
			
			local x = radius * math.cos(theta)
			local y = radius * math.sin(theta)
			
			-- i am wayy too lazy to implement worldspace transforms
			local direction = n:VectorToWorldSpace(Vector3.new(x, y, z))
			
			local face = editableMesh:RaycastLocal(point + nVector * EPSILON, direction * maxAoDistance)
			
			if face then
				ao += 1
			end
			
			count += 1
		end
		
		ao *= samplesRecip2

		-- local shadow = ((n:Dot(sunDirection) + 1) * 0.5) ^ 2

		local r = bX * col1.R + bY * col2.R + bZ * col3.R
		r = math.lerp(r, ambient.R, ao)
		local g = bX * col1.G + bY * col2.G + bZ * col3.G
		g = math.lerp(g, ambient.G, ao)
		local b = bX * col1.B + bY * col3.B + bZ * col3.B
		b = math.lerp(b, ambient.B, ao)

		return count, r, g, b, a, point
	end
	
	return count, 0, 0, 0, 0
end

local function blendColor(aAlpha : number, aColor : number, bAlpha : number, bColor : number)
	return aAlpha * aColor + (1 - aAlpha) * bAlpha * bColor
end

-- this function wont have many useful comments cuz i forgot what each line is supposed to do
function LODGenerator.GenerateImage(self : LODGenerator, editableMesh : EditableMesh, xResolution : number, direction : Vector3,
	vertexConverter : {[number] : MeshSimplification.Vertex}, pivot : CFrame, timeout : number, samples : number,
	ambient : Color3, maxAoDistance : number, upVector : Vector3?)
	
	local c = 0
	local vertexTimeout = timeout * 10
	
	-- multiply by 4 to make sure that the near plane will always be out of view
	-- (i know this is the most brute force method ever but fuck it)
	local size = math.max(self.maxX - self.minX, self.maxY - self.minY, self.maxZ - self.minZ) * 4
	local cframe = CFrame.lookAlong(pivot.Position - direction * size, direction, upVector or Vector3.yAxis)

	local minX, minY = math.huge, math.huge
	local maxX, maxY = -math.huge, -math.huge
	local maxDepth = 0

	for _, vertex in editableMesh:GetVertices() do
		c += 1
		
		if c > vertexTimeout then
			c = 0
			task.wait()
		end
		
		local positionObjectSpace = cframe:PointToObjectSpace(editableMesh:GetPosition(vertex))

		local x = positionObjectSpace.X
		local y = positionObjectSpace.Y

		minX = math.min(x, minX)
		maxX = math.max(x, maxX)

		minY = math.min(y, minY)
		maxY = math.max(y, maxY)

		local depth = (cframe.Position - positionObjectSpace).Magnitude

		if depth > maxDepth then
			maxDepth = depth
		end
	end

	local dir = maxDepth * direction * 5
	local smallDir = dir.Unit * 0.01

	local xSize = maxX - minX
	local ySize = maxY - minY

	local ratio = xSize / ySize

	local yResolution = xResolution / ratio

	local xStep = xSize / xResolution
	local yStep = ySize / yResolution

	local editableImage = AS:CreateEditableImage({Size = Vector2.new(xResolution, math.ceil(yResolution))})
	
	local alphas = {}
	
	local max = (xResolution - 1)
	
	local samplesRecip = 1 / (samples - 1)
	local samplesRecip2 = 1 / samples
	
	local count = 0

	for x = 0, xResolution - 1 do
		local xPos = minX + x * xStep

		for y = 0, yResolution - 1 do
			if count > timeout then
				count = 0
				task.wait()
			end
			
			local yPos = maxY - y * yStep

			local pos = cframe:PointToWorldSpace(Vector3.new(xPos, yPos, 0))
			
			local r, g, b, a = 0, 0, 0, 0
			
			local i = 0
			
			while pos do
				pos += smallDir
				local newCount, pR, pG, pB, pA, pPos = raycast(pos, dir, pivot, editableMesh, vertexConverter, samples, 
					samplesRecip, samplesRecip2, ambient, maxAoDistance, count)
				
				count = newCount
				
				i += 1
				
				if i > 10 or not pPos then
					break
				end
				
				pos = pPos
				
				if pA ~= 0 then
					r = blendColor(a, r, pA, pR)
					g = blendColor(a, g, pA, pG)
					b = blendColor(a, b, pA, pB)
					a += (1 - a) * pA
				end
			end
			
			local buf = buffer.create(4)
			buffer.writeu8(buf, 0, r * 255)
			buffer.writeu8(buf, 1, g * 255)
			buffer.writeu8(buf, 2, b * 255)
			buffer.writeu8(buf, 3, a * 255)

			editableImage:WritePixelsBuffer(Vector2.new(x, y), Vector2.one, buf)
		end
	end

	return editableImage, xSize, ySize
end

--[[Generates a billboard, returning the vertical planes, the y plane 
	and the cosine of the angle between the planes (needed for templates where it's called MaxDot)
PLEASE TRY NOT TO USE THIS IT IS EXTREMELY SLOW AND BAD
]]
function LODGenerator.GenerateBillboard(self : LODGenerator, resolution : number, planes : number, pivot : CFrame,
	samples : number, ambient : Color3, maxAoDistance : number, timeout : number?) : ({BillboardPlane}, BillboardPlane, number)
	
	local timeout = timeout or 5
	
	local pivotUp = pivot:VectorToObjectSpace(Vector3.yAxis)
	
	local editableMesh = AS:CreateEditableMesh()
	
	local inputVertices = {}
	local vertexConverter = {}
	
	for _, inputVert in self.meshSimplification.inputVertices do
		local vert = editableMesh:AddVertex(inputVert.position)
			
		inputVertices[inputVert.insertionIndex] = {vert = vert, normal = inputVert.normal and 
			editableMesh:AddNormal(pivot:VectorToObjectSpace(inputVert.normal))}
		vertexConverter[vert] = inputVert
	end
	
	for _, inputTri in self.meshSimplification.inputTriangles do
		local vert1 = inputVertices[inputTri.vertices[1].insertionIndex]
		local vert2 = inputVertices[inputTri.vertices[2].insertionIndex]
		local vert3 = inputVertices[inputTri.vertices[3].insertionIndex]
		
		local tri = editableMesh:AddTriangle(vert1.vert, vert2.vert, vert3.vert)
		
		if vert1.normal then
			editableMesh:SetVertexFaceNormal(vert1.vert, tri, vert1.normal)
		end
		
		if vert2.normal then
			editableMesh:SetVertexFaceNormal(vert2.vert, tri, vert2.normal)
		end
		
		if vert3.normal then
			editableMesh:SetVertexFaceNormal(vert3.vert, tri, vert3.normal)
		end
	end
	
	local angleStep = math.pi / planes

	local billboardPlanes = {}
	
	local max = (planes - 1) * 2 + 3

	for i = 0, planes - 1 do
		local angle = i * angleStep

		local dir = Vector3.new(math.sin(angle), 0, math.cos(angle))

		local img1, xSize, ySize = self:GenerateImage(editableMesh, resolution, dir, vertexConverter, pivot, timeout, samples,
			ambient, maxAoDistance)
		self.progress = i * 2 / max
		local img2 = self:GenerateImage(editableMesh, resolution, -dir, vertexConverter, pivot, timeout, samples, ambient, maxAoDistance)
		self.progress = (i * 2 + 1) / max
		
		table.insert(billboardPlanes, {
			CFrame = CFrame.lookAlong(Vector3.zero, pivot:VectorToObjectSpace(-dir.Unit), pivotUp),
			Size = Vector2.new(xSize, ySize),
			FrontFace = img1,
			BackFace = img2
		})
	end
	
	local img1, xSize, ySize = self:GenerateImage(editableMesh, resolution, Vector3.yAxis, vertexConverter, pivot, timeout, 
		samples, ambient, maxAoDistance, -Vector3.zAxis)
	self.progress = (max - 1) / max
	local img2 = self:GenerateImage(editableMesh, resolution, -Vector3.yAxis, vertexConverter, pivot, timeout,
		samples, ambient, maxAoDistance, -Vector3.zAxis)
	self.progress = 1
	
	editableMesh:Destroy()
	
	return billboardPlanes, {
		CFrame = CFrame.lookAlong(Vector3.zero, pivot:VectorToObjectSpace(-Vector3.yAxis), pivot:VectorToObjectSpace(-Vector3.zAxis)),
		Size = Vector2.new(xSize, ySize),
		FrontFace = img1,
		BackFace = img2
	}, math.cos(angleStep)
end


return LODGenerator