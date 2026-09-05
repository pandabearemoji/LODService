local PartOperationProcessor = {}

local SS = game:GetService("SerializationService")

local SharedString = require(script.SharedString)
local Parser = require(script.Parser)

function PartOperationProcessor.get(partOperation : PartOperation)
	local csg : UnionOperation?
	local success, err = pcall(function()
		csg = partOperation:UnionAsync({}, partOperation.CollisionFidelity, partOperation.RenderFidelity) :: UnionOperation?
	end)
	
	if success and csg then
		local serialized = SS:SerializeInstancesAsync({csg})
		csg:Destroy()
		local csgmdlBuffer = SharedString.readCSGMDLBuffer(serialized)
		
		local result = Parser.parse(csgmdlBuffer)
		
		if not result then
			return nil, "Buffer is not CSGMDLV5"
		end
		
		return result, "Success"
	end

	return nil, err
end

return PartOperationProcessor