--!strict
--!native
--!optimize 2


-- Symmetric 4x4 Matrix class
-- Reference: [1], used for error quadrics


local Matrix = {}
Matrix.__index = Matrix


export type Matrix = typeof(setmetatable({}, Matrix))


function Matrix.fromComponents(	a11 : number, 	a12 : number,	a13 : number,	a14 : number,
	a22 : number,	a23 : number,	a24 : number,
	a33 : number,	a34 : number,
	a44 : number) : Matrix
	
	local self = setmetatable({}, Matrix)

	self[0] = a11	self[1] = a12	self[2] = a13	self[3] = a14
	self[4] = a22	self[5] = a23	self[6] = a24
	self[7] = a33	self[8] = a34
	self[9] = a44

	table.freeze(self)

	return self
end

function Matrix.fromPlane(A : Vector3, B : Vector3, C : Vector3) : Matrix?
	-- Reference: [2], basic plane math
	local normal = ((B - A):Cross(C - A)).Unit
	
	if normal ~= normal then
		warn("Plane normal is NaN (most likely an edge triangle)!")
		return nil
	end
	
	local a = normal.X
	local b = normal.Y
	local c = normal.Z
	local d = -normal:Dot(A)
	
	-- Reference: [1], '5 Deriving Error Quadrics', this matrix is marked as Kp
	return Matrix.fromComponents(a * a,	a * b,	a * c,	a * d,
		b * b,	b * c,	b * d,
		c * c,	c * d,
		d * d)
end


function Matrix.__add(self : Matrix, m : Matrix)
	return Matrix.fromComponents(self[0] + m[0], self[1] + m[1], self[2] + m[2], self[3] + m[3],
		self[4] + m[4], self[5] + m[5], self[6] + m[6],
		self[7] + m[7], self[8] + m[8],
		self[9] + m[9])
end


-- This is the result of the multiplication described in [1], '5 Deriving Error Quadrics'
function Matrix.squaredDistance(self : Matrix, position : Vector3)
	local x = position.X
	local y = position.Y
	local z = position.Z
	
	return 	x * x * self[0] + 2 * x * y * self[1] + 2 * x * z * self[2] + 2 * x * self[3] +
			y * y * self[4] + 2 * y * z * self[5] + 2 * y * self[6] +
			z * z * self[7] + 2 * z * self[8] + 
			self[9]
end


--[[
If you substitute the symmetric matrix, (with its 4th row missing as described in [1] '4 Approximating Error
	With Quadrics') in [5]'s formula and simplify, this is the result
]] 
function Matrix.determinant(self : Matrix)
	return 	self[0] * self[4] * self[7] + 2 * self[1] * self[2] * self[5] 
			- self[5] ^ 2 * self[0] - self[1] ^ 2 * self[7] - self[2] ^ 2 * self[4]
end


-- This is the adjugate of the already mentioned matrix from [1] '4 Approximating Error With Quadrics'

-- Equivalent to the target vertex's x position
function Matrix.adjugate14(self : Matrix)
	return 	self[5] ^ 2 * self[3] + self[2] * self[4] * self[8] + self[1] * self[6] * self[7] -
			self[1] * self[5] * self[8] - self[2] * self[6] * self[5] - self[3] * self[4] * self[7] 
end

-- Equivalent to the target vertex's y position
function Matrix.adjugate24(self : Matrix)
	return	self[0] * self[5] * self[8] + self[2] ^ 2 * self[6] + self[3] * self[1] * self[7] -
			self[3] * self[5] * self[2] - self[2] * self[1] * self[8] - self[0] * self[6] * self[7]
end

-- Equivalent to the target vertex's z position
function Matrix.adjugate34(self : Matrix)
	return	self[3] * self[4] * self[2] + self[1] ^ 2 * self[8] + self[0] * self[6] * self[5] -
			self[0] * self[4] * self[8] - self[1] * self[6] * self[2] - self[3] * self[1] * self[5]
end


Matrix.identity = Matrix.fromComponents(0, 0, 0, 0, 0, 0, 0, 0, 0, 0)


table.freeze(Matrix)


return Matrix