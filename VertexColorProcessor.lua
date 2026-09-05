--!strict

-- processes textures

-- notes: 
-- SurfaceAppearance overrides Texture
-- Texture overrides MaterialVariant

local VertexColorProcessor = {}
VertexColorProcessor.__index = VertexColorProcessor


local AS = game:GetService("AssetService")
local MS = game:GetService("MaterialService")
local HttpService = game:GetService("HttpService")

local random = Random.new(os.clock())


local materialColors = require(script.MaterialColors)
local materialColorsPre = require(script.MaterialColorsPre)

local png = require(script.png)

local WHITE = Color3.new(1, 1, 1)


local function processCoordinate(v : number)
	-- if a coordinate is 0 then the special case in line 19 would return 1, even though we actually need 0
	if v == 0 then
		return 0
	else
		local n = v % 1

		-- if a coordinate is a positive integer (non 0), then the modulus would return 0, 
		-- even though we need 1, so this is another special case
		if n == 0 then
			n = 0.9999
		end

		-- coords can be negative so we just wrap it around the other way
		if v < 0 then
			n = 1 - n
		end
		
		return n
	end
end


-- this is probably the way roblox interprets obj files' texture coords, but not sure lol
local function getColor(textCoordX : number, textCoordY : number, editableImage : EditableImage)
	if not editableImage then
		error([[Attempted to read pixels from deleted editableImage, 
			please only use ModelProcessor:Clear()/VertexColorProcessor:Cleanup() when no lod generation is being done!]])
	end
	
	-- texture coords are 'scale' vector2 positions of the vertex on the texture
	-- they sometimes wrap around the texture (meaning they are bigger than 1),
	-- so we get the decimals with modulus later on
	local x = processCoordinate(textCoordX)
	local y = processCoordinate(textCoordY)
	
	local buf = editableImage:ReadPixelsBuffer(
		-- convert scale to offset
		Vector2.new(x * editableImage.Size.X, y * editableImage.Size.Y),
		-- we only need 1 pixel
		Vector2.one
	)
	-- that method returns a u8 buffer with 4 values, one for each RGBA channel
	
	return 
		-- color
		buffer.readu8(buf, 0) / 255,
		buffer.readu8(buf, 1) / 255,
		buffer.readu8(buf, 2) / 255,
		-- alpha
		buffer.readu8(buf, 3) / 255
end

local function getColorAverage(centerTexCoords : Vector2, editableImage : EditableImage, radius : number, iterations : number)
	local r, g, b, a = 0, 0, 0, 0
	
	local ln = 0
	
	local centerX = centerTexCoords.X
	local centerY = centerTexCoords.Y
	
	for i = 1, iterations do
		local x = random:NextInteger(-radius, radius)
		local y = random:NextInteger(-radius, radius)
		
		local pR, pG, pB, pA = getColor(centerX + x, centerY + y, editableImage)
		
		if pA == 0 then
			continue
		end
		
		ln += 1
		
		r += pR
		g += pG
		b += pB
		a += pA
	end
	
	if ln == 0 then
		return 0, 0, 0, 0
	end
	
	ln = 1 / ln
	
	return r * ln, g * ln, b * ln, a * ln
end


local function getEditableImage(assetId : string, name : string) : EditableImage?
	local id = tonumber(assetId:match("%d+$"))
	
	if not id then
		warn(`Failed to load {name}, assetId is not a number!`)
		return nil
	end
	
	local success, editableImage = pcall(function()
		return AS:CreateEditableImageAsync(Content.fromAssetId(id))
	end)

	if not success then
		local success, decoded = pcall(function()
			local location = HttpService:JSONDecode(HttpService:GetAsync(`http://localhost:8080/v1/assetId/{id}`)).location
			local str = HttpService:GetAsync(location)
			
			return png.decode(buffer.fromstring(str))
		end)
		
		if not success then
			warn(`Failed to load {name}, due to error message: {decoded}`)
			return nil
		end
		
		editableImage = AS:CreateEditableImage({Size = Vector2.new(decoded.width, decoded.height)})
		editableImage:WritePixelsBuffer(Vector2.zero, editableImage.Size, decoded.pixels)
	end
	
	return editableImage
end


export type VertexColorProcessor = typeof(setmetatable({} :: {editableImages : {EditableImage}}, VertexColorProcessor))


function VertexColorProcessor.new() : VertexColorProcessor
	return setmetatable({
		editableImages = {}
	}, VertexColorProcessor)
end


function VertexColorProcessor.processSurfaceAppearance(textureCoords : Vector2, surfaceAppearance : SurfaceAppearance, part : BasePart,
	editableImage : EditableImage, radius : number, iterations : number)
	
	local r, g, b, a = getColorAverage(textureCoords, editableImage, radius, iterations)
	
	if surfaceAppearance.AlphaMode == Enum.AlphaMode.Overlay then
		-- overlay mixes the base color with the texture color based on alpha and keeps the part transparency
		return part.Color:Lerp(
				Color3.new(
				r * surfaceAppearance.Color.R, 
				g * surfaceAppearance.Color.G, 
				b * surfaceAppearance.Color.B), 
			a), 
			1 - part.Transparency
	elseif surfaceAppearance.AlphaMode == Enum.AlphaMode.Transparency then
		if part.Transparency >= 0.02 then
			return Color3.new(
				r * surfaceAppearance.Color.R, 
				g * surfaceAppearance.Color.G, 
				b * surfaceAppearance.Color.B), a
		else
			-- the SurfaceAppearance documentation says that with this specific transparency
			-- if a > 0 then it will actually render as a = 1
			return Color3.new(
				r * surfaceAppearance.Color.R, 
				g * surfaceAppearance.Color.G, 
				b * surfaceAppearance.Color.B), a == 0 and 0 or 1
		end
	else
		-- basically the opposite of overlay from what ive seen
		-- honestly these things are so undocumented i dont know shit
		return Color3.new(
				r * surfaceAppearance.Color.R, 
				g * surfaceAppearance.Color.G, 
				b * surfaceAppearance.Color.B):Lerp(part.Color, a), 
			1 - part.Transparency
	end
end


function VertexColorProcessor.processTexture(textureCoords : Vector2, meshPart : MeshPart, editableImage : EditableImage,
	radius : number, iterations : number)
	local r, g, b, a = getColorAverage(textureCoords, editableImage, radius, iterations)
	
	if meshPart.Transparency >= 0.02 then
		return Color3.new(r, g, b), a
	else
		return Color3.new(r, g, b), 1 - meshPart.Transparency
	end
end



VertexColorProcessor.materialColors = {} :: {[string] : Color3}


-- ok so i have no fucking idea how materialvariants work i cannot find anything related to this
-- so im just gonna average the pixel colors cuz this is fucked
-- the only reason i implemented this is that materialvariants are used kinda often
function VertexColorProcessor.processMaterialVariant(part : BasePart, materialVariant : MaterialVariant) : (Color3?, number?)
	-- already got the average color
	local col = VertexColorProcessor.materialColors[materialVariant.Name]
	
	if col then
		return Color3.new(col.R * part.Color.R, col.G * part.Color.G, col.B * part.Color.B), 1 - part.Transparency
	end
	
	local editableImage = getEditableImage(materialVariant.ColorMap, `MaterialVariant {materialVariant:GetFullName()}`)
	
	if not editableImage then
		return nil, nil
	end
	
	local buf = editableImage:ReadPixelsBuffer(Vector2.zero, editableImage.Size)
	editableImage:Destroy()
	
	local r, g, b = 0, 0, 0
	
	-- this buffer is a u8 with the 4 RGBA channels every 4 indices (buffers start from 0 if ur confused)
	
	local len = buffer.len(buf) * 0.125 - 1
	
	for i = 0, len, 4 do
		r += buffer.readu8(buf, i)
		g += buffer.readu8(buf, i + 1)
		b += buffer.readu8(buf, i + 2)
	end
	
	-- the RGBA starts every 4 indices so the length is the quarter of the whole buffer size
	len *= 0.25
	-- get reciprocal so its faster
	len = 1 / len
	
	r *= len / 255
	g *= len / 255
	b *= len / 255
	
	VertexColorProcessor.materialColors[materialVariant.Name] = Color3.new(r, g, b)
	
	return Color3.new(r * part.Color.R, g * part.Color.G, b * part.Color.B), 1 - part.Transparency
end


function VertexColorProcessor.getPartColor(part : BasePart, pre2022 : boolean, useMaterialAverages : boolean) : (Color3, number)
	local variant = part.MaterialVariant ~= "" and MS:GetMaterialVariant(part.Material, part.MaterialVariant) or nil
	
	if variant then
		local color, alpha = VertexColorProcessor.processMaterialVariant(part, variant)
		
		if color and alpha then
			return color, alpha
		end
	end
	
	local partColor = part.Color

	if useMaterialAverages then
		local materialColor

		if pre2022 then
			materialColor = materialColorsPre[part.Material]
		end

		if not materialColor then
			materialColor = materialColors[part.Material]
		end

		materialColor = materialColor or WHITE

		return Color3.new(partColor.R * materialColor.R, partColor.G * materialColor.G, partColor.B * materialColor.B), 
			1 - part.Transparency
	else
		return partColor, 1 - part.Transparency
	end
end


function VertexColorProcessor.GetMeshPartProcessor(self : VertexColorProcessor, meshPart : MeshPart, radius : number, iterations : number,
	pre2022 : boolean, useMaterialAverages : boolean) : 
	(textureCoords : Vector2) -> (Color3, number)
	
	local surfaceAppearance = meshPart:FindFirstChildOfClass("SurfaceAppearance")
	
	if surfaceAppearance then
		local editableImage = getEditableImage(surfaceAppearance.ColorMap, `SurfaceApperance {surfaceAppearance:GetFullName()}`)
		
		if not editableImage then
			return function()
				local col, alpha = VertexColorProcessor.getPartColor(meshPart, pre2022, useMaterialAverages)
				return col, alpha
			end
		end
		
		table.insert(self.editableImages, editableImage)
		
		return function(textureCoords : Vector2)
			local col, alpha = VertexColorProcessor.processSurfaceAppearance(textureCoords, surfaceAppearance, meshPart, editableImage, 
				radius, iterations)
			return col, alpha
		end
	end
	
	if meshPart.TextureID ~= "" then
		local editableImage = getEditableImage(meshPart.TextureID, `the texture of MeshPart {meshPart:GetFullName()}`)

		if not editableImage then
			return function()
				local col, alpha = VertexColorProcessor.getPartColor(meshPart, pre2022, useMaterialAverages)
				return col, alpha
			end
		end
		
		table.insert(self.editableImages, editableImage)
		
		return function(textureCoords : Vector2)
			local col, alpha = VertexColorProcessor.processTexture(textureCoords, meshPart, editableImage, radius, iterations)
			return col, alpha
		end
	end
	
	return function()
		local col, alpha = VertexColorProcessor.getPartColor(meshPart, pre2022, useMaterialAverages)
		return col, alpha
	end
end

function VertexColorProcessor.GetFileMeshProcessor(self : VertexColorProcessor, part : BasePart, mesh : FileMesh | SpecialMesh, 
	radius : number, iterations : number, pre2022 : boolean, useMaterialAverages : boolean) 
	: (textureCoords : Vector2) -> (Color3, number)
	
	if mesh.TextureId ~= "" then
		local editableImage = getEditableImage(mesh.TextureId, `the texture of Mesh {mesh:GetFullName()}`)
		
		if editableImage then
			table.insert(self.editableImages, editableImage)
			
			return function(textureCoords : Vector2)
				local r, g, b, a = getColorAverage(textureCoords, editableImage, radius, iterations)

				return Color3.new(r, g, b), 1 - part.Transparency
			end
		end
	end
	
	return function()
		local col, alpha = VertexColorProcessor.getPartColor(part, pre2022, useMaterialAverages)
		return col, alpha
	end
end


-- i originally planned to implement textures and decals
-- but i honestly have no idea how they work (no documentation either lol)


function VertexColorProcessor.Cleanup(self : VertexColorProcessor)
	for _, editableImage in self.editableImages do
		editableImage:Destroy()
	end
end


return VertexColorProcessor