--!native
--!strict

-- please read the reference before trying to understand this

local VertexClustering = {}
VertexClustering.__index = VertexClustering


export type Vertex = {
	insertionIndex : number,
	position : Vector3,
	edges : {Vertex},
	color : Color3,
	alpha : number,
	weight : number,
	triangles : {Triangle},
	floatingCell : FloatingCell?,
	normal : Vector3?,
	uv : Vector2?
}

export type Triangle = {
	vertices : {Vertex},
	deleted : boolean
}

export type PixelLine = {
	v1 : Vertex,
	v2 : Vertex,
	thickness : number,
	volume : number
}


export type VertexClustering = typeof(setmetatable(
	{} :: {
		vertices : {Vertex},
		triangles : {Triangle},
		progress : number
	}, VertexClustering))


type FloatingCell = {
	vertices : {Vertex},
	center : Vertex,
	minX : number,
	minY : number,
	minZ : number,
	maxX : number,
	maxY : number,
	maxZ : number,
	associations : {{Triangle}},
	index : number,
	averageColor : Color3,
	averageAlpha : number
}


function VertexClustering.new() : VertexClustering
	return setmetatable({
		vertices = {},
		triangles = {},
		progress = 0
	}, VertexClustering)
end


local function safeInsert(f0 : FloatingCell, f1 : FloatingCell, triangle : Triangle)
	if not f0.associations[f1.index] then
		f0.associations[f1.index] = {triangle}
	else
		table.insert(f0.associations[f1.index], triangle)
	end
end

local function insertOnce(ignore : boolean, cell : FloatingCell, verts : {Vertex}, vert : Vertex)
	if not table.find(verts, vert) and (ignore or cell.center == vert or table.find(cell.vertices, vert)) then
		table.insert(verts, vert)
		return true
	end
	
	return false
end

function VertexClustering.Simplify(self : VertexClustering, dynamicNormals : boolean, cellSize : number, timeout : number, 
	averagingBias : number)
	
	local pixelLines : {PixelLine} = {}
	
	local minX, minY, minZ = math.huge, math.huge, math.huge
	local maxX, maxY = -math.huge, -math.huge
	
	for _, vertex in self.vertices do
		vertex.weight = self:GradeVertex(vertex)
		
		-- Bounding box checks for the 1d array
		minX = math.min(vertex.position.X, minX)
		minY = math.min(vertex.position.Y, minY)
		minZ = math.min(vertex.position.Z, minZ)
		
		maxX = math.max(vertex.position.X, maxX)
		maxY = math.max(vertex.position.Y, maxY)
	end
	
	task.wait()
	
	-- 1 extra space on each side for the adjacent checks
	local width = (maxX - minX) // cellSize + 2
	local height = (maxY - minY) // cellSize + 2
	local origin = Vector3.new(minX - cellSize, minY - cellSize, minZ - cellSize) // cellSize
	
	table.sort(self.vertices, function(a : Vertex, b : Vertex)
		return a.weight > b.weight
	end)
	
	task.wait()
	
	local cells = self:FloatingCellClustering(cellSize, width, height, origin, timeout)
	
	task.wait()

	for _, triangle in self.triangles do
		local vertices = triangle.vertices
		
		local f0 = vertices[1].floatingCell
		local f1 = vertices[2].floatingCell
		local f2 = vertices[3].floatingCell
		
		if not f0 or not f1 or not f2 then
			error("If you got this error, please torture me to death")
		end
		
		if dynamicNormals then
			local f01 = f0 == f1
			local f12 = f1 == f2
			
			if f01 and f12 then
				triangle.deleted = true
			elseif f01 then
				safeInsert(f0, f2, triangle)
				safeInsert(f2, f0, triangle)
			elseif f12 then
				safeInsert(f1, f0, triangle)
				safeInsert(f0, f1, triangle)
			elseif f0 == f2 then
				safeInsert(f0, f1, triangle)
				safeInsert(f1, f0, triangle)
			end
		else
			if f0 == f1 or f1 == f2 then
				triangle.deleted = true
			else
				triangle.vertices[1] = f0.center
				table.insert(f0.center.triangles, triangle)
				triangle.vertices[2] = f1.center
				table.insert(f1.center.triangles, triangle)
				triangle.vertices[3] = f2.center
				table.insert(f2.center.triangles, triangle)
			end
		end
	end
	
	if dynamicNormals then
		local i = 0
		
		local reciprocal = 1 / (#cells * 2)
		
		for i, cell in pairs(cells) do
			self.progress = 0.5 + i * reciprocal
			
			for index, tris in pairs(cell.associations) do
				local pCell = cells[index]
				pCell.associations[cell.index] = nil
				
				local x1 = cell.center.position
				local x2 = pCell.center.position
				
				local dis = (x2 - x1).Magnitude
				
				if dis == 0 then
					continue
				end
				
				local distanceReciprocal = 1 / dis

				local vA = {}
				local vB = {}

				for _, tri in tris do
					i += 3
					
					if tri.deleted then
						continue
					end
					
					tri.deleted = true
					
					if i >= timeout then
						task.wait()
						i = 0
					end
					
					if not insertOnce(false, cell, vA, tri.vertices[1]) then
						-- we can skip the second cell check if the first one failed, since the vertex
						-- is in one of the cells and we know its not in the first (this is what the ignore argument is for)
						insertOnce(true, pCell, vB, tri.vertices[1])
					end

					if not insertOnce(false, cell, vA, tri.vertices[2]) then
						insertOnce(true, pCell, vB, tri.vertices[2])
					end

					if not insertOnce(false, cell, vA, tri.vertices[3]) then
						insertOnce(true, pCell, vB, tri.vertices[3])
					end
				end
				
				local dA = 0
				local dB = 0
				
				for _, vert in vA do
					dA += (vert.position - x1):Cross(vert.position - x2).Magnitude * distanceReciprocal
				end
				
				for _, vert in vB do
					dB += (vert.position - x1):Cross(vert.position - x2).Magnitude * distanceReciprocal
				end
				
				dA /= #vA
				dB /= #vB
				
				local thickness = dA + dB
				
				table.insert(pixelLines, {
					v1 = cell.center,
					v2 = pCell.center,
					thickness = thickness,
					-- needed for removing excess pixel lines
					volume = (cell.center.position - pCell.center.position).Magnitude * thickness
				})
			end
			
			cell.associations = {}
		end
	end
	
	task.wait()
	
	self:Cleanup(averagingBias, cells)
	
	self.progress = 1
	
	return pixelLines
end


function VertexClustering.Cleanup(self : VertexClustering, averagingBias : number, floatingCells : {FloatingCell})
	-- fixing color bias
	
	for _, cell in floatingCells do
		local mul = 1 / (#cell.vertices + 1)
		
		local color = cell.averageColor
		local newColor = Color3.new(color.R * mul, color.G * mul, color.B * mul)
		
		local alpha = cell.averageAlpha * mul
		
		cell.center.color = cell.center.color:Lerp(newColor, averagingBias)
		local prevAlpha = cell.center.alpha
		cell.center.alpha = math.lerp(cell.center.alpha, alpha, averagingBias)
	end
	
	-- mesh cleanup
	local index = 1

	for i = 1, #self.vertices do
		local vert = self.vertices[i]

		local tris = {}

		for _, tri in vert.triangles do
			if not tri.deleted then
				table.insert(tris, tri)
				break
			end
		end

		if #tris > 0 then
			vert.triangles = tris
			self.vertices[index] = vert
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


function VertexClustering.AddVertex(self : VertexClustering, position : Vector3, color : Color3, alpha : number, normal : Vector3?, 
	uv : Vector2?, processor : (Vector2) -> (Color3, number, boolean)?)
	
	local index = #self.vertices + 1
	
	local vertex : Vertex = {
		insertionIndex = index,
		position = position,
		edges = {},
		color = color,
		alpha = alpha,
		weight = 0,
		triangles = {},
		uv = uv,
		normal = normal,
		processor = processor
	}
	
	self.vertices[index] = vertex
	
	return vertex
end

function VertexClustering.AddTriangle(self : VertexClustering, vertex0 : Vertex, vertex1 : Vertex, vertex2 : Vertex) : Triangle?
	if vertex0.alpha == 0 and vertex1.alpha == 0 and vertex2.alpha == 0 then
		return nil
	end
	
	local triangle : Triangle = {
		vertices = {vertex0, vertex1, vertex2},
		deleted = false
	}
	
	table.insert(vertex0.edges, vertex1)
	table.insert(vertex0.edges, vertex2)
	table.insert(vertex1.edges, vertex0)
	table.insert(vertex1.edges, vertex2)
	table.insert(vertex2.edges, vertex0)
	table.insert(vertex2.edges, vertex1)
	table.insert(vertex0.triangles, triangle)
	table.insert(vertex1.triangles, triangle)
	table.insert(vertex2.triangles, triangle)
	
	table.insert(self.triangles, triangle)
	
	return triangle
end


function VertexClustering.GradeVertex(self : VertexClustering, vertex : Vertex)
	-- [1] '3.1 Accuracy in Grading' for further detail
	-- I changed the original a bit for optimization, we do not need to get the angle, the dot product is enough
	-- Get the biggest angle (smallest dot product) between any connected edge
	local minDot = 1
	-- Get the longest edge
	local maxEdge = 0
	
	for i = 1, #vertex.edges do
		local vertex1 = vertex.edges[i]
		local d1 = vertex1.position - vertex.position
		local length = d1.Magnitude
		d1 /= length
		
		if length > maxEdge then
			length = maxEdge
		end
		
		for j = i + 1, #vertex.edges do
			local vertex2 = vertex.edges[j]
			local dot = d1:Dot((vertex2.position - vertex.position).Unit)
			
			if dot < minDot then
				minDot = dot
			end
		end
	end
	
	-- As stated in the previously mentioned reference, cos(θ / 2) = probability of seeing the vertex
	-- cos(θ / 2) = √((1 + cosθ) / 2), where θ is equal acos(dot(d1, d2)), therefore cosθ = dot(d1, d2)
	local visibility = math.sqrt(0.5 * (1 + minDot))
	
	return visibility + maxEdge
end


local function getCandidates(candidates : {FloatingCell}, x : number, y : number, z :  number, cells : {{FloatingCell}}, modelWidth : number, 
	modelHeight : number)
	local candidateCell = cells[x + modelWidth * (y + modelHeight * z)]

	if candidateCell then
		table.move(candidateCell, 1, #candidateCell, #candidates + 1, candidates)
	end
end

local function getAdjacentCells(position : Vector3, difference : Vector3, cells : {{FloatingCell}}, modelWidth : number, modelHeight : number)
	-- can't use sign because of the 0 case which breaks the algorithm
	local x = difference.X < 0 and -1 or 1
	local y = difference.Y < 0 and -1 or 1
	local z = difference.Z < 0 and -1 or 1
	local origX = position.X
	local origY = position.Y
	local origZ = position.Z
	
	local candidates = {}
	
	getCandidates(candidates, origX, origY, origZ, cells, modelWidth, modelHeight)
	getCandidates(candidates, origX + x, origY, origZ, cells, modelWidth, modelHeight)
	getCandidates(candidates, origX, origY + y, origZ, cells, modelWidth, modelHeight)
	getCandidates(candidates, origX, origY, origZ + z, cells, modelWidth, modelHeight)
	getCandidates(candidates, origX + x, origY + y, origZ, cells, modelWidth, modelHeight)
	getCandidates(candidates, origX + x, origY + y, origZ + z, cells, modelWidth, modelHeight)
	getCandidates(candidates, origX + x, origY, origZ + z, cells, modelWidth, modelHeight)
	getCandidates(candidates, origX, origY + y, origZ + z, cells, modelWidth, modelHeight)
	
	return candidates
end

function VertexClustering.FloatingCellClustering(self : VertexClustering, cellSize : number, modelWidth : number, modelHeight : number, 
	modelOrigin : Vector3, timeout : number) : {FloatingCell}
	-- local cellSizeReciprocal = 1 / cellSize
	local halfChunkSizeScalar = cellSize * 0.5
	local halfChunkSize = Vector3.one * halfChunkSizeScalar
	
	local cells = {}
	local ret = {}
	
	local reciprocal = 1 / (#self.vertices * 2)
	
	for i, vertex in ipairs(self.vertices) do
		if i % timeout == 0 then
			task.wait()
		end
		
		self.progress = i * reciprocal
		
		local position = vertex.position
		
		-- multiplying by reciprocal and flooring the individual elements is pretty much the same
		-- but floor division seems to be a tiny bit faster and more convenient
		local cellPositionWorldSpace = (position + halfChunkSize) // cellSize
		local cellPosition = cellPositionWorldSpace - modelOrigin
		local cellCenter = cellPositionWorldSpace * cellSize
		local difference = position - cellCenter
		
		local adjacentCells = getAdjacentCells(cellPosition, difference, cells, modelWidth, modelHeight)
		
		local closestDistance, closestCell
		
		if #adjacentCells > 0 then
			for _, adjacent in adjacentCells do
				if adjacent.minX < position.X and adjacent.maxX > position.X and
					adjacent.minY < position.Y and adjacent.maxY > position.Y and 
					adjacent.minZ < position.Z and adjacent.maxZ > position.Z then

					local distance = (position - adjacent.center.position).Magnitude

					if not closestDistance or closestDistance > distance then
						closestCell = adjacent
						closestDistance = distance
					end
				end
			end
		end
		
		if closestCell then
			table.insert(closestCell.vertices, vertex)
			vertex.floatingCell = closestCell
			local col = closestCell.averageColor
			local newCol = vertex.color
			closestCell.averageColor = Color3.new(col.R + newCol.R, col.G + newCol.G, col.B + newCol.B)
			closestCell.averageAlpha += vertex.alpha
		else
			local index = cellPosition.X + modelWidth * (cellPosition.Y + modelHeight * cellPosition.Z)
			local retIndex = #ret + 1
			
			local cell : FloatingCell = {
				vertices = {},
				center = vertex,
				minX = position.X - halfChunkSizeScalar,
				minY = position.Y - halfChunkSizeScalar,
				minZ = position.Z - halfChunkSizeScalar,
				maxX = position.X + halfChunkSizeScalar,
				maxY = position.Y + halfChunkSizeScalar,
				maxZ = position.Z + halfChunkSizeScalar,
				associations = {},
				index = retIndex,
				averageColor = vertex.color,
				averageAlpha = vertex.alpha
			}
			
			ret[retIndex] = cell
			
			if cells[index] then
				table.insert(cells[index], cell)
			else
				cells[index] = {cell}
			end
			
			vertex.floatingCell = cell
		end
	end
	
	return ret
end


return VertexClustering