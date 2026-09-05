--!strict
--!native

-- class for distributing mesh data to the algorithms

local MeshSimplification = {}
MeshSimplification.__index = MeshSimplification


local VertexClustering = require(script.VertexClustering)
local QMS = require(script.QMS)


export type Vertex = {
	insertionIndex : number,
	position : Vector3,
	color : Color3,
	alpha : number,
	triangles : {Triangle},
	normal : Vector3?,
	uv : Vector2?,
	processor : (Vector2) -> (Color3, number)?
}

export type Triangle = {
	vertices : {Vertex}
}


export type MeshSimplification = typeof(setmetatable(
	{} :: {
		inputVertices : {Vertex},
		inputTriangles : {Triangle},
		vertices : {Vertex},
		triangles : {Triangle},
		qms : QMS.QMS,
		vertexClustering : VertexClustering.VertexClustering
	}, MeshSimplification))


function MeshSimplification.new() : MeshSimplification
	return setmetatable({
		inputVertices = {},
		inputTriangles = {},
		vertices = {},
		triangles = {},
		qms = QMS.new(),
		vertexClustering = VertexClustering.new()
	}, MeshSimplification)
end

function MeshSimplification.VertexClustering(self : MeshSimplification, dynamicNormals : boolean, cellSize : number, timeout : number, 
	averagingBias : number)
	
	local vertexConversion = {}
	
	self.vertexClustering.vertices = {}
	self.vertexClustering.triangles = {}
	
	for _, vertex in self.inputVertices do
		vertexConversion[vertex.insertionIndex] = self.vertexClustering:AddVertex(vertex.position, vertex.color, vertex.alpha, 
			vertex.normal, vertex.uv)
	end
	
	for _, tri in self.inputTriangles do
		self.vertexClustering:AddTriangle(
			vertexConversion[tri.vertices[1].insertionIndex], 
			vertexConversion[tri.vertices[2].insertionIndex],
			vertexConversion[tri.vertices[3].insertionIndex])
	end
	
	local pixelLines = self.vertexClustering:Simplify(dynamicNormals, cellSize, timeout, averagingBias)
	
	local vertexConversion = {}
	
	self.vertices = {}
	self.triangles = {}
	
	for _, vertex in self.vertexClustering.vertices do
		local new = {
			insertionIndex = vertex.insertionIndex,
			position = vertex.position,
			color = vertex.color,
			alpha = vertex.alpha,
			triangles = {},
			uv = vertex.uv,
			normal = vertex.normal
		}
		
		vertexConversion[vertex] = new
		table.insert(self.vertices, new)
	end
	
	for _, tri in self.vertexClustering.triangles do
		local vertex0 = vertexConversion[tri.vertices[1]]
		local vertex1 = vertexConversion[tri.vertices[2]]
		local vertex2 = vertexConversion[tri.vertices[3]]
		
		local triangle : Triangle = {
			vertices = {vertex0, vertex1, vertex2}
		}

		table.insert(vertex0.triangles, triangle)
		table.insert(vertex1.triangles, triangle)
		table.insert(vertex2.triangles, triangle)

		table.insert(self.triangles, triangle)
	end
	
	return pixelLines
end

function MeshSimplification.QMS(self : MeshSimplification, triCount : number, threshold : number, mergeThreshold : number, 
	colorThreshold : number, normalThreshold : number, edgeCos : number, inversionCos : number, inversionPenalty : number, 
	boundaryPenalty : number, maxError : number, alphaPenalty : number, colorPenalty : number, determinantTolerance : number, 
	timeout : number, colorBalancing : number, alphaBalancing : number, normalBalancing : number, uvBalancing : number)
	
	local vertexConversion = {}
	
	self.qms.vertices = {}
	self.qms.triangles = {}
	
	for _, vertex in self.inputVertices do
		vertexConversion[vertex.insertionIndex] = self.qms:AddVertex(vertex.position, vertex.color, vertex.alpha, vertex.normal, vertex.uv)
	end
	
	for _, tri in self.inputTriangles do
		self.qms:AddTriangle(
			vertexConversion[tri.vertices[1].insertionIndex], 
			vertexConversion[tri.vertices[2].insertionIndex],
			vertexConversion[tri.vertices[3].insertionIndex])
	end
	
	self.qms:Simplify(triCount, threshold, mergeThreshold, colorThreshold, normalThreshold, edgeCos, inversionCos, inversionPenalty, 
		boundaryPenalty, maxError, alphaPenalty,colorPenalty, determinantTolerance, timeout, colorBalancing, alphaBalancing, 
		normalBalancing, uvBalancing)
	
	local vertexConversion = {}

	self.vertices = {}
	self.triangles = {}

	for _, vertex in self.qms.vertices do
		local new = {
			insertionIndex = vertex.index,
			position = vertex.position,
			color = vertex.color,
			alpha = vertex.alpha,
			triangles = {},
			uv = vertex.uv,
			normal = vertex.normal
		}

		vertexConversion[vertex] = new
		table.insert(self.vertices, new)
	end

	for _, tri in self.qms.triangles do
		local vertex0 = vertexConversion[tri.vertices[1]]
		local vertex1 = vertexConversion[tri.vertices[2]]
		local vertex2 = vertexConversion[tri.vertices[3]]

		local triangle : Triangle = {
			vertices = {vertex0, vertex1, vertex2}
		}

		table.insert(vertex0.triangles, triangle)
		table.insert(vertex1.triangles, triangle)
		table.insert(vertex2.triangles, triangle)

		table.insert(self.triangles, triangle)
	end
end


function MeshSimplification.Clear(self : MeshSimplification)
	self.inputVertices = {}
	self.inputTriangles = {}
end


function MeshSimplification.AddVertex(self : MeshSimplification, position : Vector3, color : Color3, alpha : number, normal : Vector3?, 
	uv : Vector2?, processor : (Vector2) -> (Color3, number)?)

	local index = #self.inputVertices + 1

	local vertex : Vertex = {
		insertionIndex = index,
		position = position,
		color = color,
		alpha = alpha,
		triangles = {},
		uv = uv,
		normal = normal,
		processor = processor
	}

	self.inputVertices[index] = vertex

	return vertex
end

function MeshSimplification.AddTriangle(self : MeshSimplification, vertex0 : Vertex, vertex1 : Vertex, vertex2 : Vertex) : Triangle?
	if vertex0.alpha == 0 and vertex1.alpha == 0 and vertex2.alpha == 0 then
		return nil
	end

	local triangle : Triangle = {
		vertices = {vertex0, vertex1, vertex2},
		deleted = false
	}

	table.insert(vertex0.triangles, triangle)
	table.insert(vertex1.triangles, triangle)
	table.insert(vertex2.triangles, triangle)

	table.insert(self.inputTriangles, triangle)

	return triangle
end


return MeshSimplification