--!native
--!strict


local MeshParser = {}

local MeshSimplification = require(script.Parent.MeshSimplification)
local BufferStream = require(script.Parent.PartOperationProcessor.BufferStream)


local function tableToVector3(t : {string})
	return Vector3.new(tonumber(t[1]), tonumber(t[2]), tonumber(t[3]))
end

local function tableToVector2(t : {string})
	return Vector2.new(tonumber(t[1]), tonumber(t[2]))
end


function MeshParser.Parse(str : string, meshSimplification : MeshSimplification.MeshSimplification, 
	processor : (textureCoords : Vector2) -> (Color3, number), onVertexAdded : (vertex : Vector3) -> (), pivot : CFrame,
	size : Vector3) : string?
	
	local reader = BufferStream.new(buffer.fromstring(str))
	
	if reader:readString(8) ~= "version " then
		return "invalid mesh file"
	end
	
	local versionNumber = reader:readString(4)
	
	if versionNumber == "1.00" or versionNumber == "1.01" then
		return MeshParser.ParseText(str, versionNumber, meshSimplification, processor, onVertexAdded, pivot, size)
	elseif versionNumber == "2.00" or versionNumber == "3.00" or versionNumber == "3.01" or versionNumber == "4.00" 
		or versionNumber == "4.01" or versionNumber == "5.00" then
		
		return MeshParser.ParseBin(str, versionNumber, meshSimplification, processor, onVertexAdded, pivot, size)
	elseif versionNumber == "6.00" or versionNumber == "7.00" then
		return MeshParser.ParseChunk(str, versionNumber, meshSimplification, processor, onVertexAdded, pivot, size)
	end
	
	return `unknown .mesh version {versionNumber}`
end


function MeshParser.ParseText(str : string, versionNumber : string, meshSimplification : MeshSimplification.MeshSimplification, 
	processor : (textureCoords : Vector2) -> (Color3, number, boolean), onVertexAdded : (vertex : Vector3) -> (), pivot : CFrame,
	size : Vector3) : string?
	local lines = str:split("\n")

	if #lines ~= 3 then
		return `incorrect ({#lines}) amount of line`
	end

	local versionHeader = lines[1]
	local faceCount = tonumber(lines[2])
	
	if not faceCount then
		return `face count ({lines[2]}) is not a number`
	end
	
	local data = lines[3]

	local vectors = data:split("][")
	vectors[1] = vectors[1]:sub(2)
	local last = vectors[#vectors]
	vectors[#vectors] = last:sub(1, last:len() - 1)
	
	if #vectors ~= faceCount * 9 then
		return "length mismatch"
	end
	
	local scaleMultiplier = versionHeader == "version 1.00" and 0.5 or 1
	local vertexCount = faceCount * 3
	
	for i = 1, #vectors, 9 do
		local nanVertex = false
		
		local vertices = {}
		
		local index = i
		
		for j = 1, 3 do
			local vert = vectors[index]:split(",")
			local normal = vectors[index + 1]:split(",")
			local uv = vectors[index + 2]:split(",")
			index += 3
			
			local texCoords = tableToVector2(uv)
			local col, alpha = processor(texCoords)
			
			local position = pivot:PointToWorldSpace(tableToVector3(vert) * size)
			
			if position ~= position then
				nanVertex = true
				break
			end
			
			table.insert(vertices, meshSimplification:AddVertex(position * scaleMultiplier, col, alpha, 
				pivot:VectorToWorldSpace(tableToVector3(normal)), texCoords, processor))
			onVertexAdded(position)
		end
		
		if nanVertex then
			continue
		end
		
		meshSimplification:AddTriangle(vertices[1], vertices[2], vertices[3])
	end
	
	return nil
end


function MeshParser.ParseBin(str : string, versionNumber : string, meshSimplification : MeshSimplification.MeshSimplification, 
	processor : (textureCoords : Vector2) -> (Color3, number), onVertexAdded : (vertex : Vector3) -> (), pivot : CFrame,
	size : Vector3) : string?
	
	local reader = BufferStream.new(buffer.fromstring(str))
	
	if reader:readString(12) ~= `version {versionNumber}` then
		return "bad header"
	end
	
	local newLine = reader:readu8()
	
	if not (newLine == 0x0A or (newLine == 0x0D and reader:readu8() == 0x0A)) then
		return `bad newline {newLine}`
	end
	
	local begin = reader.cursor
	
	local vertexSize = 40
	local headerSize = reader:readu16()
	local faceSize = 12
	
	local vertexCount, faceCount
	local boneCount = 0
	
	local versionStart = versionNumber:sub(1, 2)
	
	if versionNumber == "2.00" then
		if headerSize < 12 then
			return `invalid header size {headerSize}`
		end
		
		vertexSize = reader:readu8()
		faceSize = reader:readu8()
		vertexCount = reader:readu32()
		faceCount = reader:readu32()
	elseif versionStart == "3." then
		if headerSize < 16 then
			return `invalid header size {headerSize}`
		end
		
		vertexSize = reader:readu8()
		faceSize = reader:readu8()
		-- lodSize and lodCount
		reader:skipBytes(4)
		vertexCount = reader:readu32()
		faceCount = reader:readu32()
	elseif versionStart == "4." then
		if headerSize < 24 then
			return `invalid header size {headerSize}`
		end
		
		-- lodType
		reader:skipBytes(2)
		vertexCount = reader:readu32()
		faceCount = reader:readu32()
		-- lodCount
		reader:skipBytes(2)
		boneCount = reader:readu16()
		-- nameTableSize: u32 + subsetCount: u16 + 2 bytes (numHighQualityLOds, unused)
		reader:skipBytes(8)
	elseif versionStart == "5." then
		if headerSize < 32 then
			return `invalid header size {headerSize}`
		end
		
		-- meshCount
		reader:skipBytes(2)
		vertexCount = reader:readu32()
		faceCount = reader:readu32()
		-- lodCount
		reader:skipBytes(2)
		boneCount = reader:readu16()
		-- nameTableSize: u32 + subsetCount: u16 + 2 bytes (numHighQualityLOds, unused) + facsDataFormat: u32 + facsDataSize: u32
		reader:skipBytes(16)
	else
		return `invalid version {versionNumber}`
	end
	
	reader.cursor = begin + headerSize
	
	if vertexSize < 36 then
		return `invalid vertex size {vertexSize}`
	end
	
	if faceSize < 12 then
		return `invalid face size {faceSize}`
	end
	
	local vertices = {}
	local vertexColors = vertexSize >= 40
	
	for i = 1, vertexCount do
		local position = Vector3.new(reader:readf32(), reader:readf32(), reader:readf32())
		position = pivot:PointToWorldSpace(position * size)
		
		if position ~= position then
			-- -nan position :(
			reader:skipBytes(vertexSize - 12)
			continue
		end
		
		local normal = Vector3.new(reader:readf32(), reader:readf32(), reader:readf32())
		local uv = Vector2.new(reader:readf32(), reader:readf32())
		
		-- 4 u8s for the tangent
		reader:skipBytes(4)
		
		local col, alpha = processor(uv)
		
		if vertexColors then
			local vertexCol = Color3.new(reader:readu8() / 255, reader:readu8() / 255, reader:readu8() / 255)
			-- vertex coloring multiplicative proeprty
			col = Color3.new(col.R * vertexCol.R, col.G * vertexCol.G, col.B * vertexCol.B)
			alpha *= reader:readu8() / 255

			reader:skipBytes(vertexSize - 40)
		else
			reader:skipBytes(vertexSize - 36)
		end
		
		vertices[i] = meshSimplification:AddVertex(position, col, alpha, pivot:VectorToWorldSpace(normal), uv, processor)
		onVertexAdded(position)
	end
	
	if boneCount > 0 then
		-- 4 indices, 4 weights for each vertex
		reader:skipBytes(vertexCount * 8)
	end
	
	for i = 1, faceCount do
		local v1 = vertices[reader:readu32() + 1]
		local v2 = vertices[reader:readu32() + 1]
		local v3 = vertices[reader:readu32() + 1]
		
		if v1 and v2 and v3 then
			meshSimplification:AddTriangle(v1, v2, v3)
		end
		
		reader:skipBytes(faceSize - 12)
	end
	
	return nil
end


function MeshParser.ParseChunk(str : string, versionNumber : string, meshSimplification : MeshSimplification.MeshSimplification, 
	processor : (textureCoords : Vector2) -> (Color3, number), onVertexAdded : (vertex : Vector3) -> (), pivot : CFrame,
	size : Vector3) : string?
	
	local reader = BufferStream.new(buffer.fromstring(str))

	if reader:readString(12) ~= `version {versionNumber}` then
		return "bad header"
	end

	local newLine = reader:readu8()

	if not (newLine == 0x0A or (newLine == 0x0D and reader:readu8() == 0x0A)) then
		return `bad newline {newLine}`
	end
	
	while reader:getRemaining() >= 16 do
		local chunkType = reader:readString(8)
		local chunkVersion = reader:readu32()
		local chunkSize = reader:readu32()
		local chunkData = reader:readString(chunkSize)
		
		if chunkType == "COREMESH" then
			local chunk = BufferStream.new(buffer.fromstring(chunkData))
			
			if chunkVersion == 1 then
				local numVerts = chunk:readu32()
				
				local vertices = {}
				
				for i = 1, numVerts do
					local position = Vector3.new(chunk:readf32(), chunk:readf32(), chunk:readf32())
					position = pivot:PointToWorldSpace(position * size)
					
					if position ~= position then
						continue
					end
					
					local normal = Vector3.new(chunk:readf32(), chunk:readf32(), chunk:readf32())
					local uv = Vector2.new(chunk:readf32(), chunk:readf32())

					-- 4 u8s for the tangent
					chunk:skipBytes(4)

					local col, alpha = processor(uv)
					local vertexCol = Color3.new(chunk:readu8() / 255, chunk:readu8() / 255, chunk:readu8() / 255)
					col = Color3.new(col.R * vertexCol.R, col.G * vertexCol.G, col.B * vertexCol.B)
					alpha *= chunk:readu8() / 255

					table.insert(vertices, meshSimplification:AddVertex(position, col, alpha, pivot:VectorToWorldSpace(normal), uv, 
						processor))
					onVertexAdded(position)
				end
				
				local numFaces = chunk:readu8()
				
				for i = 1, numFaces do
					local v1 = vertices[reader:readu32() + 1]
					local v2 = vertices[reader:readu32() + 1]
					local v3 = vertices[reader:readu32() + 1]
					
					if v1 and v2 and v3 then
						meshSimplification:AddTriangle(v1, v2, v3)
					end
				end
			elseif chunkVersion == 2 then
				-- TODO: this version is not yet supported because it requires dracobitstreams
				-- which are from what ive seen a spawn of the devil
				return "Chunk Version 2 not yet supported"
			else
				return `unsupported Chunk Version {chunkVersion}`
			end
		end
	end
	
	return nil
end


return MeshParser