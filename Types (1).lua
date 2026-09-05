--!strict
--!native

export type BillboardTemplate = {
	planes : {Part & {FrontFace : Decal, BackFace : Decal}},
	yPlane : Part & {FrontFace : Decal, BackFace : Decal},
	m : number,
	m2 : number
}

export type PixelLine = {
	v1 : Vector3,
	v2 : Vector3,
	thickness : number,
	c : Color3,
	a : number
}

export type MeshTemplate = {
	opaqueMesh : MeshPart,
	transparentMesh : MeshPart?,
	pixelLines : {PixelLine}
}

export type Template = {
	maxCellSize : number,
	lods : {MeshTemplate},
	billboards : {BillboardTemplate},
	scale : number
}

export type BillboardPlane = {
	frontFace : Decal,
	backFace : Decal,
	part : Part,
	-- 3d lookvector used for the y angle determination
	-- 2d lookvector used for the xz plane angle determination
	lookVector3d : Vector3,
	lookVector2d : Vector2,
	cframe : CFrame
}

export type Billboard = {
	model : Model,
	planes : {BillboardPlane},
	yPlane : BillboardPlane,
	-- the slope of the angle to transparency function
	m : number,
	-- the slope of the y angle to transparency function
	m2 : number,
	cellSize : number,
	loadingPenalty : number,
	lastUpdate : number
}

export type LoadedLine = {
	origv1 : Vector3,
	origv2 : Vector3,
	v1 : Vector3, 
	v2 : Vector3, 
	pos : Vector3,
	plane : MeshPart, 
	rightVector : Vector3
}

export type MeshModel = {
	cellSize : number,
	model : Model,
	lines : {LoadedLine},
	loadingPenalty : number,
	lastUpdate : number
}

export type LODModel = {
	pivot : CFrame,
	lods : {MeshModel},
	billboards : {Billboard},
	model0 : Model,
	loadingPenalty0 : number,
	loadingPenaltyMultiplier : number,
	selectedBillboard : Billboard?,
	selectedLodIndex : number?,
	lastPivoted : number,
	lastUpdate0 : number,
	parent : ModelGroup,
	pivotConnection : RBXScriptConnection?,
	destroyConnection : RBXScriptConnection?,
	Destroy : (self : LODModel) -> (),
	PivotTo : (self : LODModel, pivot : CFrame) -> (),
	PreloadAll : (self : LODModel) -> ()
}

export type ModelGroup = {
	selectedLod : number,
	template : Template,
	models : {LODModel},
	selectedBillboard : boolean,
	parent : ModelRegion,
	scaleMultiplier : number,
	LODifyModel : (self : ModelGroup, model0 : Model, autoPivot : boolean?, loadingPenaltyMultiplier : number?) -> (LODModel),
	Destroy : (self : ModelGroup, timeout : number?) -> (),
	ParentTo : (self : ModelGroup, parent : ModelRegion) -> (),
	RefreshScaleMultiplier : (self : ModelGroup) -> ()
}

export type ModelRegion = {
	pivot : Vector3,
	groups : {ModelGroup},
	-- last direction to the model region, used for billboard updates
	lastDir : Vector3,
	CreateGroup : (self : ModelRegion, template : Template) -> (ModelGroup),
	Destroy : (self : ModelRegion, timeout : number?) -> ()
}


return {}