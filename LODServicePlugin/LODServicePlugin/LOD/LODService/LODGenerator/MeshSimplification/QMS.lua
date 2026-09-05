--!strict
--!native

-- please read the reference before trying to understand this

local QMS = {}
QMS.__index = QMS


local Matrix = require(script.Matrix)


export type QMS = typeof(setmetatable({} :: {
	vertices : {Vertex},
	triangles : {Triangle},
	progress : number
}, QMS))

export type Vertex = {
	index : number,
	position : Vector3,
	color : Color3,
	alpha : number,
	uv : Vector2?,
	normal : Vector3?,
	triangles : {Triangle},
	pairs : {Pair},
	Q : Matrix.Matrix
}

export type Triangle = {
	vertices : {Vertex},
	deleted : boolean,
	K : Matrix.Matrix
}

export type Pair = {
	vert1 : Vertex,
	vert2 : Vertex,
	target : Vector3,
	error : number,
	isEdge : boolean,
	deleted : boolean
}


-- auto removing deleted pairs to speed up the algorithm as pairs get contracted
local function pairsRemovable<T>(t : {Pair}) : () -> Pair?
	local size = #t
	local i = 0
	
	return function()
		i += 1
		
		if i > size then
			return nil
		end
		
		while t[i].deleted do
			table.remove(t, i)
			size -= 1
			
			if i > size then
				return nil
			end
		end
		
		return t[i]
	end
end

-- FNV-1a hash for fast vertex merging
local FNV_offset_basis = 2166136261
local FNV_prime = 16777619

local function hash(t : {number})
	local hash = FNV_offset_basis

	for _, v in t do
		hash = bit32.bxor(hash, v) * FNV_prime
	end

	return hash
end


function QMS.new() : QMS
	return setmetatable({
		vertices = {},
		triangles = {},
		progress = 0
	}, QMS)
end


function QMS.AddVertex(self : QMS, position : Vector3, color : Color3, alpha : number, normal : Vector3?, uv : Vector2?)
	local index = #self.vertices + 1
	
	local vertex : Vertex = {
		index = index,
		position = position,
		color = color,
		alpha = alpha,
		uv = uv,
		normal = normal,
		triangles = {},
		pairs = {},
		Q = Matrix.identity
	}
	
	self.vertices[index] = vertex
	
	return vertex
end

function QMS.AddTriangle(self : QMS, vert1 : Vertex, vert2 : Vertex, vert3 : Vertex) : Triangle?
	local K = Matrix.fromPlane(vert1.position, vert2.position, vert3.position)

	if not K then
		return nil
	end
	
	vert1.Q += K
	vert2.Q += K
	vert3.Q += K
	
	local triangle : Triangle = {
		vertices = {vert1, vert2, vert3},
		deleted = false,
		K = K
	}
	
	table.insert(self.triangles, triangle)
	table.insert(vert1.triangles, triangle)
	table.insert(vert2.triangles, triangle)
	table.insert(vert3.triangles, triangle)
	
	return triangle
end

-- [2] '6 Additional Details - Preventing Mesh Inversion' normals can flip when certain vertices are contracted which inverts the tri
local function isInversion(vert : Vertex, target : Vector3, edgeCos : number, inversionCos : number)
	local empty = true

	for _, tri in vert.triangles do
		if tri.deleted then
			continue
		end

		empty = false

		local vertIndex = table.find(tri.vertices, vert)
		
		if not vertIndex then
			tri.deleted = true
			warn("Could not find vertex in its own triangle!")
			return true
		end

		local vert0 = tri.vertices[vertIndex % 3 + 1]
		local vert1 = tri.vertices[(vertIndex + 1) % 3 + 1]

		local d0 = (vert0.position - target).Unit
		local d1 = (vert1.position - target).Unit

		-- tri is extremely thin, almost an edge
		if math.abs(d0:Dot(d1)) > edgeCos then
			return true
		end

		local originalNormal = ((vert0.position - vert.position):Cross(
			vert1.position - vert.position)).Unit

		local newNormal = (d0:Cross(d1)).Unit

		-- mesh inversion
		if originalNormal:Dot(newNormal) < inversionCos then
			return true
		end
	end

	return empty
end

-- color error for extra control
local function getColError(vert1 : Vertex, vert2 : Vertex)
	return Vector3.new(vert1.color.R - vert2.color.R, vert2.color.G - vert2.color.G, vert1.color.B - vert2.color.B).Magnitude 
end

local function getTargetAndError(vert1 : Vertex, vert2 : Vertex, edgeCos : number, inversionCos : number, inversionPenalty : number,
	boundaryPenalty : number, alphaPenalty : number, colorPenalty : number, determinantTolerance : number)
	
	-- most of this function refers to [2] '5 Deriving Error Quadrics'
	
	-- plane union
	local Q = vert1.Q + vert2.Q
	
	-- [2] '6 Additional Details - Preserving Boundaries' this algorithm tends to be funny
	-- and starts eating the mesh, so we adjust when a pair is along an edge that is a boundary
	local sharedTris = {}

	for _, tri in vert1.triangles do
		if tri.deleted then
			continue
		end

		for _, pTri in vert1.triangles do
			if tri == pTri then
				table.insert(sharedTris, tri)
				break
			end
		end
	end

	local isBoundary = #sharedTris == 1

	if isBoundary then
		local dir = vert2.position - vert1.position

		for _, tri in sharedTris do
			if tri.deleted then
				continue
			end
			
			-- plane that is perpendicular to the tri
			local A = tri.vertices[1].position
			local B = tri.vertices[2].position
			local C = tri.vertices[3].position
			local triNormal = (B - A):Cross(C - A)

			local normal = dir:Cross(triNormal)
			
			if normal ~= normal then
				continue
			end

			local a = normal.X
			local b = normal.Y
			local c = normal.Z
			local d = -normal:Dot(A)

			Q += Matrix.fromComponents(a * a,	a * b,	a * c,	a * d,
				b * b,	b * c,	b * d,
				c * c,	c * d,
				d * d)
		end
	end
	
	local det = Q:determinant()
	
	local target, targetError
	
	-- determinant is near zero, this leads to inaccuracies
	if math.abs(det) <= determinantTolerance then
		-- [2] '4 Approximating Error With Quadrics'
		-- if matrix is not invertible we use alternative positions
		
		local midPos = (vert1.position + vert2.position) * 0.5

		local error1 = Q:squaredDistance(vert1.position)
		local error2 = Q:squaredDistance(vert2.position)
		local errorMid = Q:squaredDistance(midPos)
		
		if error1 < error2 and error1 < errorMid then
			targetError = error1
			target = vert1.position
		elseif error2 < errorMid then
			targetError = error2
			target = vert2.position
		else
			targetError = errorMid
			target = midPos
		end
	else
		-- some matrix math, as per [2] '4.1 Algorithm Summary'
		-- if u dont understand the matrix math in the paper then here u go with some resources
		-- https://en.wikipedia.org/wiki/Matrix_multiplication
		-- https://en.wikipedia.org/wiki/Transpose
		-- https://semath.info/src/inverse-cofactor-ex4.html
		
		local detReciprocal = 1 / det

		local targetX = detReciprocal * Q:adjugate14()
		local targetY = detReciprocal * Q:adjugate24()
		local targetZ = detReciprocal * Q:adjugate34()

		target = Vector3.new(targetX, targetY, targetZ)
		targetError = Q:squaredDistance(target)
	end
	
	-- inversion penalties
	if isInversion(vert1, target, edgeCos, inversionCos) or isInversion(vert2, target, edgeCos, inversionCos) then
		targetError += inversionPenalty
	end
	
	-- boundary penalty
	if isBoundary then
		targetError += boundaryPenalty
	end
	
	-- extra customizable penalties
	targetError += math.abs(vert1.alpha - vert2.alpha) * alphaPenalty
	targetError += getColError(vert1, vert2) * colorPenalty
	
	return target, targetError
end

local oneThird = 1 / 3

function QMS.InitPairs(self : QMS, threshold : number, mergeThreshold : number, colorThreshold : number, normalThreshold : number, 
	edgeCos : number, inversionCos : number, inversionPenalty : number, boundaryPenalty : number, alphaPenalty : number, 
	colorPenalty : number, determinantTolerance : number, timeout : number)
	
	local penalty = 0
	local reciprocal = 1 / (#self.vertices * 3)
	
	-- optimized merge algorithm based on hashing
	if mergeThreshold > 0 and colorThreshold > 0 and normalThreshold > 0 then
		local hashMap = {}
		
		local mergeRecip = 1 / mergeThreshold
		local colorRecip = 1 / colorThreshold
		local normalRecip = 1 / normalThreshold

		for i = 1, #self.vertices do
			self.progress = i * reciprocal

			penalty += 2

			if penalty > timeout then
				penalty = 0
				task.wait()
			end
			
			local vert1 = self.vertices[i]
			
			local t = {
				math.round(vert1.position.X * mergeRecip), 
				math.round(vert1.position.Y * mergeRecip), 
				math.round(vert1.position.Z * mergeRecip),
				math.round(vert1.color.R * colorRecip),
				math.round(vert1.color.G * colorRecip),
				math.round(vert1.color.B * colorRecip)}
			
			if vert1.normal then
				t[7] = math.round(vert1.normal.X * normalRecip)
				t[8] = math.round(vert1.normal.Y * normalRecip)
				t[9] = math.round(vert1.normal.Z * normalRecip)
			end
			
			local hash = hash(t)
			
			local vert2 = hashMap[hash]
			
			if vert2 then
				for _, tri in vert1.triangles do
					if tri.deleted then
						continue
					end
					
					if table.find(vert2.triangles, tri) then
						tri.deleted = true
						continue
					end

					local vertIndex = table.find(tri.vertices, vert1)

					if vertIndex then
						tri.vertices[vertIndex] = vert2
						table.insert(vert2.triangles, tri)
						vert2.Q += tri.K
					else
						tri.deleted = true
						warn("Could not find vertex in its own triangle!")
					end
				end

				vert1.triangles = {}
			else
				hashMap[hash] = vert1
			end
		end
	end
	
	local vertexPairs = {}
	
	for i = 1, #self.vertices do
		local vert1 = self.vertices[i]
		
		if #vert1.triangles == 0 then
			continue
		end
		
		local edges = {}
		
		for _, tri in vert1.triangles do
			for _, vert in tri.vertices do
				edges[vert.index] = true
			end
		end
		
		self.progress = oneThird + i * reciprocal
		
		for j = i + 1, #self.vertices do
			penalty += 1
			
			if penalty > timeout then
				task.wait()
				penalty = 0
			end
			
			local vert2 = self.vertices[j]
			
			if #vert2.triangles == 0 then
				continue
			end
			
			local isEdge = edges[vert2.index]
			
			-- [2] '3.2 Pair Selection'
			if isEdge or (vert1.position - vert2.position).Magnitude < threshold then
				local target, targetError = getTargetAndError(vert1, vert2, edgeCos, inversionCos, inversionPenalty, boundaryPenalty, 
					alphaPenalty, colorPenalty, determinantTolerance)
				
				local pair : Pair = {
					vert1 = vert1,
					vert2 = vert2,
					target = target,
					error = targetError,
					isEdge = isEdge,
					deleted = false
				}
				
				table.insert(vert1.pairs, pair)
				table.insert(vert2.pairs, pair)
				table.insert(vertexPairs, pair)
			end
		end
	end
	
	return vertexPairs
end

local function doPairWork(pairsSet : {[Pair] : true}, pair : Pair, pVertex : Vertex)
	-- refreshing pairs
	
	if pair.isEdge then
		pVertex.Q = Matrix.identity

		for _, tri in pVertex.triangles do
			if tri.deleted then
				continue
			end

			pVertex.Q += tri.K
		end
	end

	pairsSet[pair] = true
	
	for pPair in pairsRemovable(pVertex.pairs) do
		pairsSet[pPair] = true
	end
end

local function contractPair(pair : Pair, edgeCos : number, inversionCos : number, inversionPenalty : number,
	boundaryPenalty : number, alphaPenalty : number, colorPenalty : number, determinantTolerance : number, colorBalancing : number, 
	alphaBalancing : number, normalBalancing : number, uvBalancing : number, deleted : number)
	
	pair.deleted = true
	
	local vert1 = pair.vert1
	local vert2 = pair.vert2
	
	-- deleting shared triangles
	if pair.isEdge then
		for _, tri in vert1.triangles do
			if tri.deleted then
				continue
			end
			
			for _, pTri in vert2.triangles do
				if tri == pTri then
					tri.deleted = true
					deleted += 1
				end
			end
		end
	end
	
	vert1.position = pair.target
	vert1.color = vert1.color:Lerp(vert2.color, colorBalancing)
	vert1.alpha = math.lerp(vert1.alpha, vert2.alpha, alphaBalancing)
	
	if vert1.normal and vert2.normal then
		vert1.normal = vert1.normal:Lerp(vert2.normal, normalBalancing)
	end
	
	if vert1.uv and vert2.uv then
		vert1.uv = vert1.uv:Lerp(vert2.uv, uvBalancing)
	end
	
	for _, tri in vert2.triangles do
		if tri.deleted then
			continue
		end
		
		local vertIndex = table.find(tri.vertices, vert2)
		
		if vertIndex then
			tri.vertices[vertIndex] = vert1
			table.insert(vert1.triangles, tri)
		else
			tri.deleted = true
			warn("Could not find vertex in its own triangle!")
		end
	end
	
	vert2.triangles = {}
	
	vert1.Q = Matrix.identity
	
	for _, tri in vert1.triangles do
		if tri.deleted then
			continue
		end
		
		local K = Matrix.fromPlane(tri.vertices[1].position, tri.vertices[2].position, tri.vertices[3].position)
		
		if not K then
			tri.deleted = true
			deleted += 1
			continue
		end
		
		tri.K = K
		vert1.Q += K
	end
	
	local pairsSet = {}
	
	local pairedWith = {}
	
	for pPair in pairsRemovable(vert1.pairs) do
		local pVertex
		
		if pPair.vert1 == vert1 then
			pVertex = pPair.vert2
		else
			pVertex = pPair.vert1
		end
		
		pairedWith[pVertex.index] = true
		
		doPairWork(pairsSet, pPair, pVertex)
	end
	
	for pPair in pairsRemovable(vert2.pairs) do
		local pVertex
		
		if pPair.vert1 == vert2 then
			if pairedWith[pPair.vert2.index] then
				pPair.deleted = true
				continue
			else
				pVertex = pPair.vert2
				pPair.vert1 = vert1
			end
		else
			if pairedWith[pPair.vert1.index] then
				pPair.deleted = true
				continue
			else
				pVertex = pPair.vert1
				pPair.vert2 = vert1
			end
		end
		
		table.insert(vert1.pairs, pPair)

		doPairWork(pairsSet, pPair, pVertex)
	end
	
	for pPair in pairsSet do
		if pPair.deleted then
			continue
		end
		
		local target, targetError = getTargetAndError(pPair.vert1, pPair.vert2, edgeCos, inversionCos, inversionPenalty, boundaryPenalty, 
			alphaPenalty, colorPenalty, determinantTolerance)
		pPair.target = target
		pPair.error = targetError
	end
	
	return deleted
end

local twoThirds = 2 * oneThird

function QMS.Simplify(self : QMS, triCount : number, threshold : number, mergeThreshold : number, colorThreshold : number, 
	normalThreshold : number, edgeCos : number, inversionCos : number, inversionPenalty : number, boundaryPenalty : number, 
	maxError : number, alphaPenalty : number, colorPenalty : number, determinantTolerance : number, timeout : number, 
	colorBalancing : number, alphaBalancing : number, normalBalancing : number, uvBalancing : number)
	
	local vertexPairs = self:InitPairs(threshold, mergeThreshold, colorThreshold, normalThreshold, edgeCos, inversionCos, inversionPenalty, 
		boundaryPenalty, alphaPenalty, colorPenalty, determinantTolerance, timeout)
	
	local originalTriCount = #self.triangles
	local deletedTris = 0
	local reciprocal = 1 / ((originalTriCount - triCount) * 3)
	
	local penalty = 0
	
	while originalTriCount - deletedTris > triCount do
		self.progress = twoThirds + deletedTris * reciprocal
		
		penalty += 50
		
		-- selecting the lowest error pair
		local selected
		
		for pair in pairsRemovable(vertexPairs) do
			if penalty > timeout then
				task.wait()
				penalty = 0
			end

			if (not selected or selected.error > pair.error) and pair.error < maxError then
				selected = pair
			end

			penalty += 2
		end
		
		if not selected then
			break
		end
		
		deletedTris = contractPair(selected, edgeCos, inversionCos, inversionPenalty, boundaryPenalty, alphaPenalty, colorPenalty,
			determinantTolerance, colorBalancing, alphaBalancing, normalBalancing, uvBalancing, deletedTris)
	end
	
	self:Cleanup()
	
	self.progress = 1
end


function QMS.Cleanup(self : QMS)
	local index = 1

	for i = 1, #self.vertices do
		local vert = self.vertices[i]

		local tris = {}

		for _, tri in vert.triangles do
			if not tri.deleted then
				table.insert(tris, tri)
			end
		end

		if #tris > 0 then
			vert.triangles = tris
			self.vertices[index] = vert
			vert.index = index
			index += 1
		end
	end

	for i = index, #self.vertices do
		self.vertices[i] = nil
	end

	task.wait()

	index = 1

	for i = 1, #self.triangles do
		local tri = self.triangles[i]

		if not tri.deleted then
			self.triangles[index] = tri
			index += 1
		end
	end

	for i = index, #self.triangles do
		self.triangles[i] = nil
	end
end


return QMS