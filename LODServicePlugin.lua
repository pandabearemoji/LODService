-- WARNING !!! WARNING
-- HORRENDOUS CODE AHEAD, THIS PLUGIN IS NOT WELL WRITTEN
-- BECAUSE I AM LAZY TO PROPERLY WRITE SOMETHING THAT DOESNT RUN DURING RUNTIME

if not game:GetService("RunService"):IsEdit() then
	return
end

local RS = game:GetService("ReplicatedStorage")
local AS = game:GetService("AssetService")
local Lighting = game:GetService("Lighting")

local Iris = require(script.Parent.Iris)
local Input = require(script.Parent.UserInputService)

-- lodgenerator used to be called modelprocessor and im lazy to change it LOL
local ModelProcessorModule = require(script.LOD.LODService.LODGenerator)
local VertexClustering = require(script.LOD.LODService.LODGenerator.MeshSimplification.VertexClustering)

local ModelProcessor = ModelProcessorModule.new(false, 0, 1, false, false, false)

local widgetInfo = DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Float, false, false, 400, 300)

local Toolbar = plugin:CreateToolbar("LODService Plugin")
local ToggleButton = Toolbar:CreateButton("Toggle LOD Constructor", "Toggle LODService's LOD Constructor", "rbxassetid://88856916120350")
local IrisWidget = plugin:CreateDockWidgetPluginGuiAsync("LOD Constructor", widgetInfo)

IrisWidget.Name = "LOD Constructor"
IrisWidget.Title = "LOD Constructor"
IrisWidget.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ToggleButton.ClickableWhenViewportHidden = true

local IrisEnabled = false
Input.SinkFrame.Parent = IrisWidget

Iris.Internal._utility.UserInputService = Input
Iris.UpdateGlobalConfig({
	UseScreenGUIs = false,
})
Iris.Disabled = true

Iris.Init(IrisWidget)

type LoadedLine = {
	v1 : Vector3, 
	v2 : Vector3, 
	plane : MeshPart, 
	rightVector : Vector3
}

type Mesh = {
	opaqueMesh : EditableMesh?,
	transparentMesh : EditableMesh?,
	model : Model?,
	isOriginal : boolean,
	texture : string?,
	pixelLines : {VertexClustering.PixelLine},
	loadedLines : LoadedLine,
	surfaceAppearance : SurfaceAppearance?,
	algorithm : string,
	targetTriCount : number?,
	threshold : number?,
	custom : MeshPart?
}

type Plane = {
	dir2d : Vector2, 
	dir3d : Vector3,
	img1 : Decal,
	img2 : Decal,
	part : BasePart
}

type Billboard = {
	yPlane : ModelProcessorModule.BillboardPlane?,
	planes : {ModelProcessorModule.BillboardPlane}?,
	resolution : number,
	n : number,
	yAngle : number,
	m : number?,
	m2 : number?,
	parts : {Plane}?,
	yPart : Plane?
}

type Level = {
	cellSize : number,
	mesh : Mesh?,
	billboard : Billboard?,
	triCount : number,
	lineCount : number
}

local levels : {Level} = {}
local previewing = false

local function createPlane(model : Model, zIndex : number, v : ModelProcessorModule.BillboardPlane) : Plane
	local part = script.LOD.LODService.Part:Clone()
	part.Parent = workspace
	part.CFrame = CFrame.new(model:GetBoundingBox().Position) * model:GetPivot():ToWorldSpace(v.CFrame).Rotation
	part.Size = Vector3.new(v.Size.X, v.Size.Y, 0)

	local image1 = Instance.new("Decal", part)
	image1.TextureContent = Content.fromObject(v.FrontFace)
	image1.Face = Enum.NormalId.Front
	image1.ZIndex = zIndex
	image1.Transparency = 1

	local image2 = Instance.new("Decal", part)
	image2.TextureContent = Content.fromObject(v.BackFace)
	image2.Face = Enum.NormalId.Back
	image2.ZIndex = zIndex
	image2.Transparency = 1

	zIndex += 1

	local dir = part.CFrame.LookVector
	
	return {dir2d = Vector2.new(dir.X, dir.Z).Unit, dir3d = dir, img1 = image1, img2 = image2, part = part}, zIndex
end

local function createPixelLine(template : VertexClustering.PixelLine, pivot : CFrame, parent : Instance)
	local rightVector = template.v2.position - template.v1.position
	
	local plane = script.LOD.LODService.LODGenerator.plane:Clone()
	plane.Parent = parent
	plane.Position = template.v1.position:Lerp(template.v2.position, 0.5)
	plane.Size = Vector3.new(rightVector.Magnitude, template.thickness, 0)
	
	plane.Color = template.v1.color:Lerp(template.v2.color, 0.5)
	plane.Transparency = 1 - math.lerp(template.v1.alpha, template.v2.alpha, 0.5)
	plane.LocalTransparencyModifier = 1
	
	return {v1 = template.v1.position, v2 = template.v2.position, plane = plane, rightVector = rightVector}
end

local selectedLod = 0
local selectedBillboard : Billboard? = nil
local selectedLines : {LoadedLine} = {}

local function stepPreview(model : Model, x : number, maxCellSize : number)
	local camera = workspace.CurrentCamera
	local position = camera.CFrame.Position
	local direction = model:GetPivot().Position - position
	local R = (x * 2 * math.tan(math.rad(camera.FieldOfView) * 0.5) / camera.ViewportSize.Y) * direction.Magnitude
	
	if R > maxCellSize then
		if selectedLod ~= maxCellSize then
			selectedLod = maxCellSize
			selectedBillboard = nil
			selectedLines = {}

			for _, level in levels do
				if level.mesh and level.mesh.model then
					for _, v in level.mesh.model:GetDescendants() do
						if v:IsA("BasePart") then
							v.LocalTransparencyModifier = 1
						end
					end
				elseif level.billboard.parts then
					for _, plane in level.billboard.parts do
						plane.img1.Transparency = 1
						plane.img2.Transparency = 1
					end

					level.billboard.yPart.img1.Transparency = 1
					level.billboard.yPart.img2.Transparency = 1
				end
			end
		end
	else
		local meshCellSize, billboardCellSize = nil, nil
		local meshCellSizeDiff, billboardCellSizeDiff = math.huge, math.huge

		for _, level in levels do
			if level.cellSize < R then
				local diff = R - level.cellSize

				if level.mesh and diff < meshCellSizeDiff then
					meshCellSizeDiff = diff
					meshCellSize = level.cellSize
				elseif level.billboard and diff < billboardCellSizeDiff then
					billboardCellSizeDiff = diff
					billboardCellSize = level.cellSize
				end
			end
		end
		
		if not meshCellSize and not billboardCellSize then
			meshCellSize = 0
			meshCellSizeDiff = 0
			billboardCellSizeDiff = 1
		end

		if billboardCellSizeDiff < meshCellSizeDiff then
			if selectedLod ~= billboardCellSize then
				selectedLod = billboardCellSize
				selectedLines = {}

				for _, level in levels do
					if level.mesh and level.mesh.model then
						for _, v in level.mesh.model:GetDescendants() do
							if v:IsA("BasePart") then
								v.LocalTransparencyModifier = 1
							end
						end
					elseif level.billboard and level.billboard.planes then
						if level.cellSize == billboardCellSize then
							selectedBillboard = level.billboard
						elseif level.billboard.parts then
							for _, plane in level.billboard.parts do
								plane.img1.Transparency = 1
								plane.img2.Transparency = 1
							end

							level.billboard.yPart.img1.Transparency = 1
							level.billboard.yPart.img2.Transparency = 1
						end
					end
				end
			end
		else
			if selectedLod ~= meshCellSize then
				selectedLod = meshCellSize
				selectedBillboard = nil

				for _, level in levels do
					if level.billboard and level.billboard.parts then
						for _, plane in level.billboard.parts do
							plane.img1.Transparency = 1
							plane.img2.Transparency = 1
						end

						level.billboard.yPart.img1.Transparency = 1
						level.billboard.yPart.img2.Transparency = 1
					elseif level.mesh and level.mesh.model then
						if level.cellSize == meshCellSize then
							selectedLines = level.mesh.loadedLines
							
							for _, v in level.mesh.model:GetDescendants() do
								if v:IsA("BasePart") then
									v.LocalTransparencyModifier = 0
								end
							end
						else
							for _, v in level.mesh.model:GetDescendants() do
								if v:IsA("BasePart") then
									v.LocalTransparencyModifier = 1
								end
							end
						end
					end
				end
			end
		end
	end
	
	if selectedBillboard then
		local vector2d = Vector2.new(direction.X, direction.Z).Unit

		local yBillboard = selectedBillboard.yPart
		local m = selectedBillboard.m
		local m2 = selectedBillboard.m2

		-- the 'y element' of the transparency of the non y oriented images equals 1 - yTransparency => yAlpha = 1 - (1 - yTransparency) =>
		-- yAlpha = yTransparency
		local yAlpha = math.min(
			-- linear transparency = (1 - |dot|) / (1 - fullTransparentAngle)
			(1 - math.abs(yBillboard.dir3d:Dot(direction.Unit))) * m2,
			1)


		for _, plane in selectedBillboard.parts do
			-- same linear transparency as before but we reverse it to get the alpha (i found that this cannot be simplified further)
			local alpha = math.max(1 - 
				(1 - math.abs(vector2d:Dot(plane.dir2d))) * m, 
				0)

			local transparency = 1 - (alpha * yAlpha)
			plane.img1.Transparency = transparency
			plane.img2.Transparency = transparency
		end

		yBillboard.img1.Transparency = yAlpha
		yBillboard.img2.Transparency = yAlpha
	end
	
	if selectedLines then
		for _, line in selectedLines do
			local normal = (line.v1 - position):Cross(line.v2 - position):Cross(line.rightVector)

			line.plane.CFrame = CFrame.lookAlong(line.plane.Position, normal, line.rightVector:Cross(normal))
		end
	end
end

local function shutdown()
	previewing = false

	for i, level in pairs(levels) do
		if level.mesh and level.mesh.model then
			if level.mesh.isOriginal then
				for _, v in level.mesh.model:GetDescendants() do
					if v:IsA("BasePart") then
						v.LocalTransparencyModifier = 0
					end
				end

				table.remove(levels, i)
			else
				level.mesh.model:Destroy()
			end
		elseif level.billboard and level.billboard.parts then
			for _, v in level.billboard.parts do
				v.part:Destroy()
			end

			level.billboard.yPart.part:Destroy()
		end
	end
end

-- planes are instantly reparented when loaded but use BulkMoveTo to be put into position
-- which happens at the end of the update loop, not positioning it far would lead to popping
-- if the game is positioned around the initial position of the plane
local FAR = CFrame.new(0, 1000000, 0)

local function makePlaneTemplate(plane : ModelProcessorModule.BillboardPlane, parent : Instance, name : string, cellSize : number, 
	zIndex : number)
	
	local part = script.LOD.LODService.Part:Clone()
	part.Parent = parent
	part.Size = Vector3.new(plane.Size.X, plane.Size.Y, 0)
	part.Name = name
	part.CFrame = FAR * plane.CFrame.Rotation
	
	local result, id = AS:CreateAssetAsync(plane.FrontFace, Enum.AssetType.Image, {
		Name = name .. "_front",
		Description = "(Generated by LODService) Cell Size:" .. cellSize
	})
	
	if result ~= Enum.CreateAssetResult.Success then
		error("Failed to publish Image, result: " .. result.Name)
	end

	local image1 = Instance.new("Decal", part)
	image1.Texture = "rbxassetid://" .. id
	image1.Face = Enum.NormalId.Front
	image1.ZIndex = zIndex
	image1.Transparency = 1
	image1.Name = "FrontFace"
	
	local result, id = AS:CreateAssetAsync(plane.BackFace, Enum.AssetType.Image, {
		Name = name .. "_back",
		Description = "(Generated by LODService) Cell Size:" .. cellSize
	})

	if result ~= Enum.CreateAssetResult.Success then
		error("Failed to publish Image, result: " .. result.Name)
	end

	local image2 = Instance.new("Decal", part)
	image2.Texture = "rbxassetid://" .. id
	image2.Face = Enum.NormalId.Back
	image2.ZIndex = zIndex
	image2.Transparency = 1
	image2.Name = "BackFace"
end

local function round(n : number, decimals : number)
	local d = math.pow(10, decimals)
	
	return math.round(n * d) / d
end


-- We can start defining our code. This just uses the demo window and then forces it to be the same size
-- as the Plugin Widget. You don't have to do it this way.
Iris:Connect(function()
	local camera = workspace.CurrentCamera
	
	local window = Iris.Window({"Main Window"})
	
	window.state.size:set(IrisWidget.AbsoluteSize)
	window.state.position:set(Vector2.zero)
	
	Iris.CollapsingHeader({"General"})
	
	if Iris.Button({"Insert LOD Folder"}).clicked() then
		script.LOD:Clone().Parent = RS
	end
	local reset = Iris.Button({"Reset Settings"})
	
	Iris.SeparatorText({"Model Processing"})
	local boxParts = Iris.Checkbox({"Use Box Parts"})
	local ignoreUnprocessable = Iris.Checkbox({"Ignore Unprocessable Parts (Unions, FileMeshes etc.)"})
	local samplingRadius = Iris.DragNum({"Texture Sampling Radius", 1, 0, 128}, {number = Iris.State(0)})
	local samplingIterations = Iris.DragNum({"Texture Sampling Iterations", 1, 1, 32}, {number = Iris.State(1)})
	local useMaterialAverages = Iris.Checkbox({"Use Averaged Material Colors"})
	local preMaterials = Iris.Checkbox({"Pre 2022 Materials"})
	Iris.Separator()
	local modelProgress = Iris.State(0)
	modelProgress:set(ModelProcessor.modelProgress)
	Iris.ProgressBar({"Model Processing Progress"}, {progress = modelProgress})
	local model = Iris.InputInstance({"Model Template", "Click to Select", "Select a Model ...", "Model", 
		"Invalid Selection, Model needed"})
	local triCount = Iris.Text({string.format("Model Tri Count: %i Triangles", #ModelProcessor.meshSimplification.inputTriangles)})
	local instance = model.state.instance:get()
	
	Iris.SeparatorText({"General Generation Settings"})
	local blockiness = Iris.SliderNum({"Mesh Blockiness", 0.01, 0, 1})
	local generationTimeout = Iris.DragNum({"Mesh Generation Timeout", 1, 25, 10000}, {number = Iris.State(100)})
	
	Iris.SeparatorText({"Rendering Settings"})
	local x = Iris.DragNum({"X (Render Distance Coefficient)", 0.05, 1, 50}, {number = Iris.State(3)})
	local unrenderCellSize = Iris.DragNum({"Unrender Cell Size", 0.1, 2, 2056}, {number = Iris.State(64)})
	Iris.Text({string.format("Unrender Distance: %.2f Studs", 
		(unrenderCellSize.state.number:get() * camera.ViewportSize.Y)
			/ (2 * x.state.number:get() * math.tan(math.rad(camera.FieldOfView) * 0.5))
		)})

	Iris.SeparatorText({"Preview"})
	
	if Iris.Button({"Start Preview"}).clicked() and not previewing and instance then
		task.spawn(function()
			local pivot = instance:GetPivot()

			table.insert(levels, {
				cellSize = 0,
				mesh = {
					isOriginal = true,
					model = instance
				}
			})

			for _, level in levels do
				if level.mesh and not level.mesh.isOriginal then
					local model = Instance.new("Model")
					model.Parent = workspace
					
					if level.mesh.custom then
						local meshPart = level.mesh.custom:Clone()
						meshPart.Parent = model
						meshPart.CFrame = pivot
						meshPart.LocalTransparencyModifier = 1
					else
						local opaqueMesh = AS:CreateMeshPartAsync(Content.fromObject(level.mesh.opaqueMesh))
						opaqueMesh.Parent = model
						opaqueMesh.CFrame = pivot
						opaqueMesh.LocalTransparencyModifier = 1
						opaqueMesh.Color = Color3.new(1, 1, 1)

						if level.mesh.texture then
							opaqueMesh.Texture = level.mesh.texture
						end

						if level.mesh.surfaceAppearance then
							local surfaceApperance = level.mesh.surfaceAppearance:Clone()
							surfaceApperance.Parent = opaqueMesh
						end

						if level.mesh.transparentMesh and #level.mesh.transparentMesh:GetFaces() > 0 then
							local transparentMesh = AS:CreateMeshPartAsync(Content.fromObject(level.mesh.transparentMesh))
							transparentMesh.Parent = model
							transparentMesh.CFrame = pivot
							transparentMesh.LocalTransparencyModifier = 1
							transparentMesh.Color = Color3.new(1, 1, 1)
							transparentMesh.Transparency = 0.02

							if level.mesh.texture then
								transparentMesh.Texture = level.mesh.texture
							end

							if level.mesh.surfaceAppearance then
								local surfaceApperance = level.mesh.surfaceAppearance:Clone()
								surfaceApperance.Parent = transparentMesh
							end
						end

						local lines = {}

						for _, line in level.mesh.pixelLines do
							table.insert(lines, createPixelLine(line, pivot, model))
						end

						level.mesh.loadedLines = lines
					end

					level.mesh.model = model
				elseif level.billboard and level.billboard.planes then
					local parts = {}

					local zIndex = 0

					local yPlane, z = createPlane(instance, zIndex, level.billboard.yPlane)
					zIndex = z

					for _, v in level.billboard.planes do
						local plane, z = createPlane(instance, zIndex, v)
						zIndex = z

						table.insert(parts, plane)
					end

					level.billboard.parts = parts
					level.billboard.yPart = yPlane
				end
			end

			previewing = true
		end)
	end

	if Iris.Button({"Stop Preview"}).clicked() then
		shutdown()
	end
	
	Iris.SeparatorText({"Template Generation"})

	local name = Iris.InputText({"Template Name"}, {text = Iris.State("MyTemplate")}).state.text:get()
	local precision = Iris.DragNum({"Pixel Line Precision", 1, 1, 8}, {number = Iris.State(2)}).state.number:get()

	if Iris.Button({"Generate Template"}).clicked() and instance then
		task.spawn(function()
			local pivot = instance:GetPivot()

			local templates = RS:FindFirstChild("LOD")

			if not templates then
				warn("Could not find templates folder, please click Insert LOD Folder before generating a template!")
				return
			end

			templates = templates:FindFirstChild("Templates")

			if not templates then
				warn("Could not find templates folder, please click Insert LOD Folder before generating a template!")
				return
			end

			print("Starting template generation..")

			local module = Instance.new("ModuleScript")
			module.Name = name
			module.Parent = templates

			local str = [[
--!native

local Types = require(script.Parent.Parent.Types)

local ]] .. name .. [[ : Types.Template = {
	maxCellSize = ]] .. unrenderCellSize.state.number:get() .. ", \n"

			local lodString = "{\n"
			local billboardString = "{\n"

			for _, level in levels do
				if level.cellSize ~= 0 then
					local cellString = string.gsub(tostring(level.cellSize), "%.", "_")

					if level.mesh and level.mesh.custom then
						local meshPart = level.mesh.custom:Clone()
						meshPart.Parent = module
						lodString ..= "		[" .. level.cellSize .. "] = " .. "{\n			opaqueMesh = script." .. meshPart.Name .. ", "
					elseif level.mesh and level.mesh.opaqueMesh then
						print("Uploading mesh..")

						local meshName = name .. "_" .. cellString .. "_mesh_opaque"

						local result, id = AS:CreateAssetAsync(level.mesh.opaqueMesh, Enum.AssetType.Mesh, {
							Name = meshName,
							Description = "(Generated by LODService) Cell Size: " .. level.cellSize
						})

						if result ~= Enum.CreateAssetResult.Success then
							error("Failed to publish Mesh, result: " .. result.Name)
						end
						lodString ..= "		[" .. level.cellSize .. "] = " .. "{\n			opaqueMesh = script." .. meshName .. ", "
						local meshPart = AS:CreateMeshPartAsync(Content.fromAssetId(id))
						meshPart.Parent = module
						meshPart.Name = meshName
						meshPart.Color = Color3.new(1, 1, 1)
						meshPart.CanCollide = false
						meshPart.CanQuery = false
						meshPart.CanTouch = false
						meshPart.Anchored = true
						meshPart.CFrame = pivot

						if level.mesh.texture then
							meshPart.Texture = level.mesh.texture
						end

						if level.mesh.surfaceAppearance then
							local surfaceApperance = level.mesh.surfaceAppearance:Clone()
							surfaceApperance.Parent = meshPart
						end

						if level.mesh.transparentMesh then
							meshName = name .. "_" .. cellString .. "_mesh_transparent"

							result, id = AS:CreateAssetAsync(level.mesh.transparentMesh, Enum.AssetType.Mesh, {
								Name = meshName,
								Description = "(Generated by LODService) Cell Size: " .. level.cellSize
							})

							if result ~= Enum.CreateAssetResult.Success then
								error("Failed to publish Mesh, result: " .. result.Name)
							end
							lodString ..= "transparentMesh = script." .. meshName .. ", "

							meshPart = AS:CreateMeshPartAsync(Content.fromAssetId(id))
							meshPart.Parent = module
							meshPart.Name = meshName
							meshPart.Color = Color3.new(1, 1, 1)
							meshPart.CanCollide = false
							meshPart.CanQuery = false
							meshPart.CanTouch = false
							meshPart.Anchored = true
							meshPart.Transparency = 0.02
							meshPart.CFrame = pivot

							if level.mesh.texture then
								meshPart.Texture = level.mesh.texture
							end

							if level.mesh.surfaceAppearance then
								local surfaceApperance = level.mesh.surfaceAppearance:Clone()
								surfaceApperance.Parent = meshPart
							end
						end

						local i = 0

						if #level.mesh.pixelLines > 0 then
							local moduleName = "PixelLines_" .. cellString
							local linesModule = Instance.new("ModuleScript", module)
							linesModule.Name = moduleName

							local pivot = instance:GetPivot()

							local lines = "return {\n"

							for _, line in level.mesh.pixelLines do
								i += 1

								local v1 = pivot:PointToObjectSpace(line.v1.position)
								local v2 = pivot:PointToObjectSpace(line.v2.position)

								local x1 = round(v1.X, precision)
								local y1 = round(v1.Y, precision)
								local z1 = round(v1.Z, precision)
								local x2 = round(v2.X, precision)
								local y2 = round(v2.Y, precision)
								local z2 = round(v2.Z, precision)

								local color = line.v1.color:Lerp(line.v2.color, 0.5)

								local r = round(color.R, precision + 1)
								local g = round(color.G, precision + 1)
								local b = round(color.B, precision + 1)

								local alpha = round(math.lerp(line.v1.alpha, line.v2.alpha, 0.5), precision)

								lines ..= "	{v1=Vector3.new(" .. x1 .. "," .. y1 .. "," .. z1  .. "),v2=Vector3.new(" .. 
									x2 .. "," .. y2 .. "," .. z2 .. "),thickness=" .. round(line.thickness, precision) .. ",c=Color3.new(" 
									.. r .. "," .. g .. "," .. b ..  "),a=" .. alpha .. "}, \n"

								if string.len(lines) > 199800 then
									break
								end
							end

							lines ..= "}"

							linesModule.Source = lines

							lodString ..= "\n			pixelLines = require(script." .. moduleName .. ") \n"
						else
							lodString ..= "\n			pixelLines = {} \n"
						end
						lodString ..= "		},\n"

						print("Finished with " .. i .. " pixel lines!")
					elseif level.billboard then
						print("Uploading billboard..")

						local planesString = "{"

						local yName = name .. "_" .. cellString .. "_billboard_y"
						makePlaneTemplate(level.billboard.yPlane, module, yName, level.cellSize, 0)

						local zIndex = 1

						for _, plane in level.billboard.planes do
							local planeName = name .. "_" .. cellString .. "_billboard_" .. zIndex
							makePlaneTemplate(plane, module, planeName, level.cellSize, zIndex)
							planesString ..= "script." .. planeName .. ", "
							zIndex += 1
						end

						planesString ..= "}"
						billboardString ..= "		[" .. level.cellSize .. "] = " .. [[{
			planes = ]] .. planesString .. [[,
			yPlane = script.]] .. yName ..[[,
			m = ]] .. level.billboard.m .. [[,
			m2 = ]] .. level.billboard.m2 .. "\n		},\n"

						print("Finished!")
					end
				end
			end

			str ..= "	lods = " .. lodString .. [[	},
	billboards = ]] .. billboardString .. "	},\n	scale = " .. 1 / instance:GetScale() .. "\n}\n\nreturn " .. name

			module.Source = str

			print("Template generated!")
		end)
	end
	
	Iris.End()
	Iris.Separator()

	Iris.CollapsingHeader({"Vertex Clustering Settings"})
	local averagingBias = Iris.DragNum({"Cell Color Averaging Bias", 0.01, 0, 1}, {number = Iris.State(0)})
	local clusteringTimeout = Iris.DragNum({"Vertex Clustering Timeout", 1, 1000, 100000}, {number = Iris.State(5000)})
	local dynamicNormals = Iris.Checkbox({"Generate Dynamic Normals"}, {isChecked = Iris.State(true)})
	local maximumPixelLines = Iris.DragNum({"Maximum Pixel Lines (Per Level)", 1, 3, 2000}, {number = Iris.State(1500)})
	Iris.End()
	Iris.Separator()
	
	Iris.CollapsingHeader({"QMS Settings"})
	local qmsTimeout = Iris.DragNum({"QMS Timeout", 1000, 10000, 1000000}, {number = Iris.State(100000)})
	Iris.SeparatorText({"Vertex Merging"})
	local mergeThreshold = Iris.DragNum({"Merging Threshold (Position)", 0.001, 0, 3, {"%.3f Studs"}}, {number = Iris.State(0.01)})
	local colorThreshold = Iris.DragNum({"Merging Threshold (Color)", 0.001, 0, 3}, {number = Iris.State(3)}) 
	local normalThreshold = Iris.DragNum({"Merging Threshold (Normal)", 0.001, 0, 3}, {number = Iris.State(3)})
	Iris.SeparatorText({"Penalties"})
	local edgeAngle = Iris.DragNum({"Angle of an Edge", 0.1, 0, 15, {"%.1f Degrees"}}, {number = Iris.State(8)})
	local inversionAngle = Iris.DragNum({"Minimum Angle of Inversion", 0.1, 10, 180, {"%.1f Degrees"}}, {number = Iris.State(80)})
	local inversionPenalty = Iris.DragNum({"Inversion Penalty", 0.1, 0, 1024}, {number = Iris.State(64)})
	local boundaryPenalty = Iris.DragNum({"Boundary Penalty", 0.1, 0, 1024}, {number = Iris.State(64)})
	local maxError = Iris.DragNum({"Maximum Error", 0.1, 0, 4096}, {number = Iris.State(96)})
	local alphaPenalty = Iris.DragNum({"Alpha Penalty", 0.1, 0, 128}, {number = Iris.State(1)})
	local colorPenalty = Iris.DragNum({"Color Penalty", 0.1, 0, 128}, {number = Iris.State(1)})
	local determinantTolerance = Iris.DragNum({"Determinant Tolerance", 0.0001, 0, 1}, {number = Iris.State(0.01)})
	Iris.SeparatorText({"Contraction Settings"})
	local colorBalancing = Iris.DragNum({"Color Balancing", 0.001, 0, 0.5}, {number = Iris.State(0.25)})
	local alphaBalancing = Iris.DragNum({"Alpha Balancing", 0.001, 0, 0.5}, {number = Iris.State(0.2)})
	local normalBalancing = Iris.DragNum({"Normal Balancing", 0.001, 0, 0.5}, {number = Iris.State(0.25)})
	local uvBalancing = Iris.DragNum({"UV Balancing", 0.001, 0, 0.5}, {number = Iris.State(0.1)})
	Iris.End()
	Iris.Separator()
	
	Iris.CollapsingHeader({"Billboard Settings"})
	local billboardTimeout = Iris.DragNum({"Billboard Generation Timeout", 1, 100, 10000}, {number = Iris.State(3000)})
	local ambient = Iris.InputColor3({"Ambient"}, {color = Iris.State(Lighting.Ambient)})
	local samples = Iris.DragNum({"Ambient Occlusion Samples", 1, 2, 100}, {number = Iris.State(10)})
	local maxAoDistance = Iris.DragNum({"Ambient Occlusion Distance", 0.1, 0.1, 100}, {number = Iris.State(1)})
	Iris.End()
	Iris.Separator()
	
	local edgeCos = math.cos(math.rad(edgeAngle.state.number:get()))
	local inversionCos = math.cos(math.rad(inversionAngle.state.number:get()))
	local maximumLines = maximumPixelLines.state.number:get()
	
	if reset.clicked() then
		boxParts.state.isChecked:set(false)
		clusteringTimeout.state.number:set(5000)
		generationTimeout.state.number:set(100)
		billboardTimeout.state.number:set(3000)
		unrenderCellSize.state.number:set(64)
		x.state.number:set(3)
		blockiness.state.number:set(0)
		dynamicNormals.state.isChecked:set(true)
		maximumPixelLines.state.number:set(500)
		samplingRadius.state.number:set(0)
		samplingIterations.state.number:set(1)
		averagingBias.state.number:set(0)
		preMaterials.state.isChecked:set(false)
		ignoreUnprocessable.state.isChecked:set(false)
		useMaterialAverages.state.isChecked:set(false)
		mergeThreshold.state.number:set(0.001)
		edgeAngle.state.number:set(8)
		inversionAngle.state.number:set(80)
		inversionPenalty.state.number:set(64)
		boundaryPenalty.state.number:set(64)
		maxError.state.number:set(96)
		alphaPenalty.state.number:set(1)
		colorPenalty.state.number:set(1)
		determinantTolerance.state.number:set(0.01)
		qmsTimeout.state.number:set(100000)
		colorBalancing.state.number:set(0.25)
		alphaBalancing.state.number:set(0.2)
		normalBalancing.state.number:set(0.25)
		uvBalancing.state.number:set(0.1)
		mergeThreshold.state.number:set(0.01)
		colorThreshold.state.number:set(3)
		normalThreshold.state.number:set(3)
		ambient.state.color:set(Lighting.Ambient)
		samples.state.number:set(10)
		maxAoDistance.state.number:set(1)
		
		ModelProcessor.boxParts = false
		ModelProcessor.textureSamplingRadius = 0
		ModelProcessor.textureSamplingIterations = 1
		ModelProcessor.useMaterialAverages = false
		ModelProcessor.ignoreUnprocessable = false
	end
	
	if boxParts.checked() then
		ModelProcessor.boxParts = true
	elseif boxParts.unchecked() then
		ModelProcessor.boxParts = false
	end
	
	if preMaterials.checked() then
		ModelProcessor.pre2022Materials = true
	elseif preMaterials.unchecked() then
		ModelProcessor.pre2022Materials = false
	end
	
	if useMaterialAverages.checked() then
		ModelProcessor.useMaterialAverages = true
	elseif useMaterialAverages.unchecked() then
		ModelProcessor.useMaterialAverages = false
	end
	
	if ignoreUnprocessable.checked() then
		ModelProcessor.ignoreUnprocessable = true
	elseif ignoreUnprocessable.unchecked() then
		ModelProcessor.ignoreUnprocessable = false
	end
	
	if samplingRadius.numberChanged() then
		ModelProcessor.textureSamplingRadius = samplingRadius.state.number:get()
	end
	
	if samplingIterations.numberChanged() then
		ModelProcessor.textureSamplingIterations = samplingIterations.state.number:get()
	end
	
	if model.instanceChanged() and instance then
		task.spawn(function()
			print("Processing model...")
			
			ModelProcessor:Clear()
			ModelProcessor:ProcessModel(instance)

			print("Finished!")
		end)
	end
	
	Iris.CollapsingHeader({"LOD Levels"})
	
	if instance then
		Iris.Text({string.format("Distance to Model: %.2f", (camera.CFrame.Position - instance:GetPivot().Position).Magnitude)})
	end
	
	Iris.Separator()
	
	if Iris.Button({"Add Mesh Element"}).clicked() then
		table.insert(levels, {
			cellSize = 1,
			triCount = 0,
			lineCount = 0
		})
	end

	if Iris.Button({"Add Billboard Element"}).clicked() then
		table.insert(levels, {
			cellSize = 1,
			billboard = {
				resolution = 1,
				n = 1,
				yAngle = 60,
			},
			triCount = 0,
			lineCount = 0
		})
	end
	
	local billboardProgress = Iris.State(0)
	billboardProgress:set(ModelProcessor.progress)
	Iris.ProgressBar({"Billboard Generation Progress"}, {progress = billboardProgress})
	local clusteringProgress = Iris.State(0)
	clusteringProgress:set(ModelProcessor.meshSimplification.vertexClustering.progress)
	Iris.ProgressBar({"Vertex Clustering Progress"}, {progress = clusteringProgress})
	local qmsProgress = Iris.State(0)
	qmsProgress:set(ModelProcessor.meshSimplification.qms.progress)
	Iris.ProgressBar({"QMS Progress"}, {progress = qmsProgress})
	
	Iris.Separator()
	
	for i, level in pairs(levels) do
		if level.mesh and level.mesh.isOriginal then
			continue
		end
		
		Iris.Tree({string.format("Level %i", level.cellSize or 1)})
		
		local cell = Iris.DragNum({"Cell Size", 0.01, 0.1, 1000, {"%.2f Studs"}}, {number = Iris.State(1)})
		Iris.Text({string.format("Min Visible Distance: %.2f Studs", 
			(cell.state.number:get() * camera.ViewportSize.Y)
				/ (2 * x.state.number:get() * math.tan(math.rad(camera.FieldOfView) * 0.5))
			)})
		level.cellSize = cell.state.number:get()
		local delete = Iris.Button({level.billboard and "Delete Billboard" or "Delete Mesh"})
		
		if delete.clicked() then
			levels[i] = nil
			
			if level.billboard then
				if level.billboard.planes then
					for _, plane in level.billboard.planes do
						plane.FrontFace:Destroy()
						plane.BackFace:Destroy()
					end
					
					level.billboard.yPlane.FrontFace:Destroy()
					level.billboard.yPlane.BackFace:Destroy()
				end
			elseif level.mesh and level.mesh.opaqueMesh then
				level.mesh.opaqueMesh:Destroy()
				
				if level.mesh.transparentMesh then
					level.mesh.transparentMesh:Destroy()
				end
			end
			
			Iris.End()
			
			continue
		end
		
		if level.billboard then
			Iris.Separator()
			
			local resolution = Iris.DragNum({"Resolution", 1, 100, 8000, {"%i Pixels"}}, {number = Iris.State(144)})
			level.billboard.resolution = resolution.state.number:get()
			local planes = Iris.DragNum({"Sides", 1, 2, 16}, {number = Iris.State(4)})
			level.billboard.n = planes.state.number:get()
			local yAngle = Iris.DragNum({"Y Angle", 1, 5, 70}, {number = Iris.State(60)})
			level.billboard.yAngle = yAngle.state.number:get()
			
			Iris.Separator()
			
			if Iris.Button({"Generate Billboard"}).clicked() and instance then
				local timeout = billboardTimeout.state.number:get()
				
				task.spawn(function()
					print("Generating billboard...")
					
					local billboards, yBillboard, maxDot = ModelProcessor:GenerateBillboard(level.billboard.resolution, level.billboard.n, 
						instance:GetPivot(), samples.state.number:get(), ambient.state.color:get(), maxAoDistance.state.number:get(),
						timeout)
					
					level.triCount = level.billboard.n * 4 + 4

					level.billboard.planes = billboards
					level.billboard.yPlane = yBillboard
					level.billboard.m = 1 / (1 - maxDot)
					level.billboard.m2 = 1 / math.cos(math.rad(level.billboard.yAngle))
					
					print("Finished!")
				end)
			end
		else
			Iris.Separator()
			local algorithmIndex = Iris.State("Vertex Clustering")
			local algorithm = Iris.Combo({"Simplification Algorithm"}, {index = algorithmIndex})
			Iris.Selectable({"Vertex Clustering", "Vertex Clustering"}, {index = algorithmIndex})
			Iris.Selectable({"QMS", "QMS"}, {index = algorithmIndex})
			Iris.Selectable({"Custom", "Custom"}, {index = algorithmIndex})
			Iris.End()
			
			if not level.mesh then
				level.mesh = {}
			end
			
			level.mesh.algorithm = algorithm.state.index:get()
			
			if level.mesh.algorithm == "QMS" then
				level.mesh.targetTriCount = Iris.DragNum({"Target Tri Count", 1, 1, 40000}, {number = Iris.State(1000)}).state.number:get()
				level.mesh.threshold = Iris.DragNum({"Pairing Threshold", 0.001, 0, 248, {"%.3f Studs"}}, 
					{number = Iris.State(1)}).state.number:get()
			elseif level.mesh.algorithm == "Vertex Clustering" then
				Iris.Text({string.format("Pixel Line Count: %i Lines", level.lineCount)})
			end
			
			if level.mesh.algorithm == "Custom" then
				level.mesh.custom = Iris.InputInstance({"Custom LOD Model", "Click to Select", "Select a MeshPart ...", "MeshPart", 
					"Invalid Selection, MeshPart needed"}).state.instance:get()
			else
				Iris.Separator()
				
				local texture = Iris.InputText({"LOD Texture"})

				local id = texture.state.text:get()

				if id ~= "" then
					level.mesh.texture = id
				end

				local appearance = Iris.InputInstance({"LOD SurfaceAppearance",  "Click to Select", "Select a SurfaceAppearance ...", 
					"SurfaceAppearance", "Invalid Selection, SurfaceAppearance needed"})

				local surfaceAppearance = appearance.state.instance:get()

				if surfaceAppearance then
					level.mesh.surfaceAppearance = surfaceAppearance
				end
				
				Iris.Separator()
				
				local generateTransparent = Iris.Checkbox({"Generate Transparent Mesh"})
				
				if Iris.Button({"Generate Mesh"}).clicked() and instance then
					task.spawn(function()
						print("Generating mesh...")

						local lines = {}

						if level.mesh.algorithm == "Vertex Clustering" then
							lines = ModelProcessor:VertexClustering(dynamicNormals.state.isChecked:get(), level.cellSize, 
								averagingBias.state.number:get(), clusteringTimeout.state.number:get())
						else
							ModelProcessor:QMS(level.mesh.targetTriCount, level.mesh.threshold, mergeThreshold.state.number:get(),
								colorThreshold.state.number:get(), normalThreshold.state.number:get(), edgeCos, inversionCos, 
								inversionPenalty.state.number:get(), boundaryPenalty.state.number:get(), maxError.state.number:get(), 
								alphaPenalty.state.number:get(), colorPenalty.state.number:get(), determinantTolerance.state.number:get(), 
								colorBalancing.state.number:get(), alphaBalancing.state.number:get(), normalBalancing.state.number:get(), 
								uvBalancing.state.number:get(), qmsTimeout.state.number:get())
						end

						level.lineCount = #lines

						if #lines > maximumLines then
							local toRemove = #lines - maximumLines

							table.sort(lines, function(a : VertexClustering.PixelLine, b : VertexClustering.PixelLine)
								return a.volume > b.volume
							end)

							for i = 1, toRemove do
								lines[#lines] = nil
							end
						end

						level.mesh.pixelLines = lines

						level.triCount = #ModelProcessor.meshSimplification.triangles + #lines * 2

						if level.triCount == 0 then
							warn("Simplified model has no tris (most likely due to the cellSize being bigger than the model)")
						end

						if generateTransparent.state.isChecked:get() then
							local opaque, transparent = ModelProcessor:GetEditableMeshWithTransparency(instance:GetPivot(), 
								blockiness.state.number:get(), generationTimeout.state.number:get())

							level.mesh.opaqueMesh = opaque
							level.mesh.transparentMesh = transparent
						else
							local mesh = ModelProcessor:GetEditableMeshOpaque(instance:GetPivot(), blockiness.state.number:get(), 
								generationTimeout.state.number:get())

							level.mesh.opaqueMesh = mesh
						end

						print("Finished!")
					end)
				end
			end
		end
		
		if not level.mesh or level.mesh.algorithm ~= "Custom" then
			Iris.Text({string.format("Tri Count: %i Triangles", level.triCount)})
		end
		
		Iris.End()
	end
	
	Iris.End()
	
	if previewing then
		task.spawn(stepPreview, instance, x.state.number:get(), unrenderCellSize.state.number:get())
	end
	
	Iris.End()
end)

IrisWidget:BindToClose(function()
	IrisEnabled = false
	IrisWidget.Enabled = false
	Iris.Disabled = true
	ToggleButton:SetActive(false)
	shutdown()
end)

ToggleButton.Click:Connect(function()
	IrisEnabled = not IrisEnabled
	IrisWidget.Enabled = IrisEnabled
	Iris.Disabled = not IrisEnabled
	ToggleButton:SetActive(IrisEnabled)
	
	if Iris.Disabled then
		shutdown()
	end
end)

plugin.Unloading:Connect(function()
	Iris.Shutdown()

	for _, connection in Input._connections do
		connection:Disconnect()
	end

	Input.SinkFrame:Destroy()

	IrisEnabled = false
	IrisWidget.Enabled = false
	Iris.Disabled = true
	ToggleButton:SetActive(false)
	shutdown()
end)