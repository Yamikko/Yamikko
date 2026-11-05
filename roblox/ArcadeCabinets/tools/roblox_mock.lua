-- roblox_mock.lua — mini-émulation de l'API Roblox, juste assez pour exécuter
-- BuildArcadeCabinets.lua et CabinetFX hors de Studio (Lua 5.3 / fengari).
-- Les propriétés et valeurs d'Enum sont VALIDÉES : une faute de frappe lève une erreur.

local M = {}

---------------------------------------------------------------- Vector3 / Vector2
local Vector3 = {}
local V3MT = {}
local function v3(x, y, z) return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0, __type = "Vector3" }, V3MT) end
V3MT.__index = function(v, k)
	if k == "Magnitude" then return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z) end
	if k == "Unit" then local m = math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z); return v3(v.X / m, v.Y / m, v.Z / m) end
	return Vector3[k]
end
V3MT.__add = function(a, b) return v3(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
V3MT.__sub = function(a, b) return v3(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
V3MT.__mul = function(a, b)
	if type(a) == "number" then return v3(a * b.X, a * b.Y, a * b.Z) end
	if type(b) == "number" then return v3(a.X * b, a.Y * b, a.Z * b) end
	return v3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V3MT.__unm = function(a) return v3(-a.X, -a.Y, -a.Z) end
V3MT.__tostring = function(v) return string.format("%g, %g, %g", v.X, v.Y, v.Z) end
Vector3.new = v3
function Vector3.Dot(a, b) return a.X * b.X + a.Y * b.Y + a.Z * b.Z end
Vector3.zero = v3(0, 0, 0)

local Vector2 = { new = function(x, y) return { X = x or 0, Y = y or 0, __type = "Vector2" } end }

---------------------------------------------------------------- CFrame
-- R : matrice 3x3 ligne par ligne (r00 r01 r02 r10 ...), monde = R*local + p
local CFrame = {}
local CFMT = {}
local function cf(p, R)
	return setmetatable({ p = p, R = R or { 1, 0, 0, 0, 1, 0, 0, 0, 1 }, __type = "CFrame" }, CFMT)
end
local function matmul(A, B)
	local C = {}
	for i = 0, 2 do
		for j = 0, 2 do
			C[i * 3 + j + 1] = A[i * 3 + 1] * B[j + 1] + A[i * 3 + 2] * B[3 + j + 1] + A[i * 3 + 3] * B[6 + j + 1]
		end
	end
	return C
end
local function matvec(R, v)
	return v3(R[1] * v.X + R[2] * v.Y + R[3] * v.Z, R[4] * v.X + R[5] * v.Y + R[6] * v.Z, R[7] * v.X + R[8] * v.Y + R[9] * v.Z)
end
local function transpose(R) return { R[1], R[4], R[7], R[2], R[5], R[8], R[3], R[6], R[9] } end

CFMT.__index = function(c, k)
	if k == "Position" then return c.p end
	if k == "X" then return c.p.X end
	if k == "Y" then return c.p.Y end
	if k == "Z" then return c.p.Z end
	if k == "LookVector" then return v3(-c.R[3], -c.R[6], -c.R[9]) end
	if k == "UpVector" then return v3(c.R[2], c.R[5], c.R[8]) end
	if k == "RightVector" then return v3(c.R[1], c.R[4], c.R[7]) end
	return CFrame[k]
end
CFMT.__mul = function(a, b)
	if b.__type == "CFrame" then return cf(matvec(a.R, b.p) + a.p, matmul(a.R, b.R)) end
	if b.__type == "Vector3" then return matvec(a.R, b) + a.p end
	error("CFrame * " .. tostring(b.__type))
end
CFMT.__add = function(a, b) return cf(a.p + b, a.R) end
CFrame.new = function(x, y, z)
	if x == nil then return cf(v3(0, 0, 0)) end
	if type(x) == "table" and x.__type == "Vector3" then return cf(x) end
	assert(type(x) == "number" and type(y) == "number" and type(z) == "number", "CFrame.new: arguments invalides")
	return cf(v3(x, y, z))
end
CFrame.Angles = function(rx, ry, rz)
	local cx, sx, cy, sy, cz, sz = math.cos(rx), math.sin(rx), math.cos(ry), math.sin(ry), math.cos(rz), math.sin(rz)
	local Rx = { 1, 0, 0, 0, cx, -sx, 0, sx, cx }
	local Ry = { cy, 0, sy, 0, 1, 0, -sy, 0, cy }
	local Rz = { cz, -sz, 0, sz, cz, 0, 0, 0, 1 }
	return cf(v3(0, 0, 0), matmul(matmul(Rx, Ry), Rz))
end
CFrame.fromEulerAnglesXYZ = CFrame.Angles
function CFrame.Inverse(c)
	local Rt = transpose(c.R)
	return cf(-matvec(Rt, c.p), Rt)
end
function CFrame.ToObjectSpace(a, b) return CFrame.Inverse(a) * b end
function CFrame.ToWorldSpace(a, b) return a * b end
CFrame.identity = cf(v3(0, 0, 0))

---------------------------------------------------------------- Color3
local Color3 = {}
local C3MT = { __index = Color3 }
local function c3(r, g, b) return setmetatable({ R = r, G = g, B = b, __type = "Color3" }, C3MT) end
Color3.new = function(r, g, b) return c3(r or 0, g or 0, b or 0) end
Color3.fromRGB = function(r, g, b) return c3(r / 255, g / 255, b / 255) end
Color3.fromHex = function(h)
	h = h:gsub("#", "")
	assert(#h == 6, "fromHex: " .. h)
	return c3(tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255)
end
Color3.fromHSV = function(h, s, v)
	assert(h >= 0 and h <= 1 and s >= 0 and s <= 1 and v >= 0 and v <= 1, "fromHSV hors bornes")
	local i = math.floor(h * 6) % 6
	local f = h * 6 - math.floor(h * 6)
	local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
	local r, g, b
	if i == 0 then r, g, b = v, t, p elseif i == 1 then r, g, b = q, v, p elseif i == 2 then r, g, b = p, v, t
	elseif i == 3 then r, g, b = p, q, v elseif i == 4 then r, g, b = t, p, v else r, g, b = v, p, q end
	return c3(r, g, b)
end
function Color3.Lerp(a, b, t) return c3(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t) end

---------------------------------------------------------------- UDim2, séquences, ranges, TweenInfo
local UDim2 = {}
UDim2.new = function(xs, xo, ys, yo)
	return { X = { Scale = xs or 0, Offset = xo or 0 }, Y = { Scale = ys or 0, Offset = yo or 0 }, __type = "UDim2" }
end
UDim2.fromScale = function(x, y) return UDim2.new(x, 0, y, 0) end
UDim2.fromOffset = function(x, y) return UDim2.new(0, x, 0, y) end

local NumberRange = { new = function(a, b) return { Min = a, Max = b or a, __type = "NumberRange" } end }
local NumberSequenceKeypoint = { new = function(t, v, e) return { Time = t, Value = v, Envelope = e or 0 } end }
local NumberSequence = {
	new = function(a, b)
		if type(a) == "number" then
			return { Keypoints = { NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(1, b or a) }, __type = "NumberSequence" }
		end
		assert(#a >= 2 and a[1].Time == 0 and a[#a].Time == 1, "NumberSequence : keypoints de 0 à 1 requis")
		return { Keypoints = a, __type = "NumberSequence" }
	end,
}
local ColorSequenceKeypoint = { new = function(t, c) return { Time = t, Value = c } end }
local ColorSequence = {
	new = function(a, b)
		if a.__type == "Color3" then
			return { Keypoints = { ColorSequenceKeypoint.new(0, a), ColorSequenceKeypoint.new(1, b or a) }, __type = "ColorSequence" }
		end
		assert(#a >= 2 and a[1].Time == 0 and a[#a].Time == 1, "ColorSequence : keypoints de 0 à 1 requis")
		return { Keypoints = a, __type = "ColorSequence" }
	end,
}
local TweenInfo = {
	new = function(time, style, dir, repeatCount, reverses, delay)
		return { Time = time, EasingStyle = style, EasingDirection = dir, RepeatCount = repeatCount or 0, Reverses = reverses or false, __type = "TweenInfo" }
	end,
}

---------------------------------------------------------------- Enum (validé)
local ENUMS = {
	Material = { "Plastic", "SmoothPlastic", "Neon", "Glass", "Metal", "Foil", "DiamondPlate", "ForceField" },
	PartType = { "Ball", "Block", "Cylinder", "Wedge", "CornerWedge" },
	SurfaceType = { "Smooth", "Studs", "Inlet" },
	NormalId = { "Front", "Back", "Top", "Bottom", "Left", "Right" },
	SurfaceGuiSizingMode = { "FixedSize", "PixelsPerStud" },
	Font = { "Arcade", "GothamBold", "SourceSans", "FredokaOne" },
	RunContext = { "Legacy", "Server", "Client", "Plugin" },
	ParticleEmitterShape = { "Box", "Sphere", "Cylinder", "Disc" },
	ParticleEmitterShapeStyle = { "Volume", "Surface" },
	ParticleEmitterShapeInOut = { "Outward", "Inward", "InAndOut" },
	HighlightDepthMode = { "AlwaysOnTop", "Occluded" },
	EasingStyle = { "Linear", "Sine", "Quad", "Back", "Quint" },
	EasingDirection = { "In", "Out", "InOut" },
	ModelStreamingMode = { "Default", "Atomic", "Persistent", "PersistentPerPlayer", "Nonatomic" },
}
local Enum = {}
for typeName, items in pairs(ENUMS) do
	local t = {}
	for _, n in ipairs(items) do t[n] = { EnumType = typeName, Name = n, __type = "EnumItem" } end
	Enum[typeName] = setmetatable(t, { __index = function(_, k) error("Enum." .. typeName .. "." .. tostring(k) .. " n'existe pas", 2) end })
end
setmetatable(Enum, { __index = function(_, k) error("Enum." .. tostring(k) .. " inconnu du mock", 2) end })

---------------------------------------------------------------- Instances
local PART_PROPS = { "Anchored", "CanCollide", "CanTouch", "CanQuery", "CastShadow", "Material", "Color", "Transparency",
	"Reflectance", "Size", "CFrame", "TopSurface", "BottomSurface", "PivotOffset", "Locked", "Massless" }
local GUI_PROPS = { "Size", "Position", "AnchorPoint", "BackgroundColor3", "BackgroundTransparency", "BorderSizePixel",
	"ClipsDescendants", "ZIndex", "Rotation", "Visible", "LayoutOrder" }
local LIGHT_PROPS = { "Brightness", "Range", "Color", "Shadows", "Enabled" }

local CLASSES = {
	Folder = { props = {} },
	Model = { props = { "PrimaryPart", "WorldPivot", "ModelStreamingMode" } },
	Part = { base = "BasePart", props = PART_PROPS, extra = { "Shape" } },
	WedgePart = { base = "BasePart", props = PART_PROPS },
	Script = { props = { "Source", "RunContext", "Disabled", "Enabled" } },
	SurfaceGui = { props = { "Face", "SizingMode", "PixelsPerStud", "LightInfluence", "Brightness", "ClipsDescendants",
		"AlwaysOnTop", "CanvasSize", "MaxDistance", "Adornee" } },
	Frame = { base = "GuiObject", props = GUI_PROPS },
	TextLabel = { base = "GuiObject", props = GUI_PROPS, extra = { "Text", "TextColor3", "TextScaled", "Font", "TextSize",
		"TextStrokeTransparency", "TextTransparency" } },
	PointLight = { base = "Light", props = LIGHT_PROPS },
	SurfaceLight = { base = "Light", props = LIGHT_PROPS, extra = { "Face", "Angle" } },
	Attachment = { props = { "CFrame", "Position", "Visible" } },
	ParticleEmitter = { props = { "Color", "LightEmission", "LightInfluence", "Size", "Transparency", "Lifetime", "Rate",
		"Speed", "SpreadAngle", "Acceleration", "EmissionDirection", "Texture", "Shape", "ShapeStyle", "ShapeInOut",
		"Rotation", "RotSpeed", "Drag", "LockedToPart", "ZOffset", "Enabled", "Brightness" } },
	Beam = { props = { "Attachment0", "Attachment1", "Color", "Transparency", "Width0", "Width1", "CurveSize0", "CurveSize1",
		"FaceCamera", "LightEmission", "LightInfluence", "Segments", "Texture", "TextureSpeed", "Enabled", "Brightness" } },
	Highlight = { props = { "Adornee", "FillColor", "FillTransparency", "OutlineColor", "OutlineTransparency", "DepthMode", "Enabled" } },
	NumberValue = { props = { "Value" } },
}
for _, c in pairs(CLASSES) do
	c.allowed = { Name = true, Parent = true }
	for _, p in ipairs(c.props) do c.allowed[p] = true end
	for _, p in ipairs(c.extra or {}) do c.allowed[p] = true end
end

local DEFAULTS = {
	Transparency = 0, Reflectance = 0, CastShadow = true, Anchored = false, CanCollide = true, Brightness = 1,
	Enabled = true, Value = 0, BackgroundTransparency = 0, ZIndex = 1, Visible = true,
}

local Methods = {}
local InstMT = {}
local allInstances = {}

local function newInstance(className, isService)
	local cls = CLASSES[className]
	assert(cls or isService, "Instance.new : classe inconnue du mock " .. tostring(className))
	local self = setmetatable({ __props = { Name = className }, __children = {}, __attrs = {}, ClassName = className,
		__type = "Instance", __service = isService }, InstMT)
	local p = rawget(self, "__props")
	if className == "Part" or className == "WedgePart" then
		p.Size = v3(4, 1, 2); p.CFrame = CFrame.new(); p.PivotOffset = CFrame.new(); p.Color = c3(0.64, 0.64, 0.64)
		p.Material = Enum.Material.Plastic
	elseif className == "Attachment" then
		p.CFrame = CFrame.new()
	elseif className == "Model" then
		p.WorldPivot = CFrame.new()
	end
	table.insert(allInstances, self)
	return self
end

InstMT.__index = function(self, k)
	local props = rawget(self, "__props")
	local v = props[k]
	if v ~= nil then return v end
	if Methods[k] then return Methods[k] end
	if k == "Changed" then
		local sig = { fns = {} }
		function sig:Connect(fn) table.insert(self.fns, fn); return { Disconnect = function() end } end
		props.Changed = sig
		return sig
	end
	if k == "Position" and self.ClassName == "Attachment" then return props.CFrame.p end
	if DEFAULTS[k] ~= nil then return DEFAULTS[k] end
	for _, c in ipairs(rawget(self, "__children")) do
		if c.Name == k then return c end
	end
	if k == "Parent" or k == "PrimaryPart" or k == "Adornee" then return nil end
	error(self.ClassName .. "." .. tostring(k) .. " : membre inconnu (ou non initialisé dans le mock)", 2)
end

InstMT.__newindex = function(self, k, v)
	local cls = CLASSES[self.ClassName]
	if cls and not cls.allowed[k] then
		error("Propriété '" .. tostring(k) .. "' invalide pour " .. self.ClassName, 2)
	end
	local props = rawget(self, "__props")
	if k == "Parent" then
		local old = props.Parent
		if old then
			local ch = rawget(old, "__children")
			for i, c in ipairs(ch) do if c == self then table.remove(ch, i) break end end
		end
		props.Parent = v
		if v then table.insert(rawget(v, "__children"), self) end
		return
	end
	if k == "Position" and self.ClassName == "Attachment" then
		props.CFrame = cf(v, props.CFrame.R)
		return
	end
	if k == "PrimaryPart" and v ~= nil then
		assert(Methods.IsDescendantOf(v, self), "PrimaryPart doit être un descendant du Model")
	end
	props[k] = v
end

local BASES = { BasePart = { Part = true, WedgePart = true }, GuiObject = { Frame = true, TextLabel = true },
	Light = { PointLight = true, SurfaceLight = true } }

function Methods.IsA(self, name)
	return self.ClassName == name or (BASES[name] ~= nil and BASES[name][self.ClassName] == true) or name == "Instance"
end
function Methods.GetChildren(self)
	local t = {}
	for i, c in ipairs(rawget(self, "__children")) do t[i] = c end
	return t
end
function Methods.GetDescendants(self)
	local out = {}
	local function walk(n) for _, c in ipairs(rawget(n, "__children")) do table.insert(out, c); walk(c) end end
	walk(self)
	return out
end
function Methods.FindFirstChild(self, name, recursive)
	for _, c in ipairs(rawget(self, "__children")) do if c.Name == name then return c end end
	if recursive then
		for _, c in ipairs(rawget(self, "__children")) do
			local f = Methods.FindFirstChild(c, name, true)
			if f then return f end
		end
	end
	return nil
end
function Methods.WaitForChild(self, name)
	return assert(Methods.FindFirstChild(self, name), "WaitForChild bloquerait : " .. name)
end
function Methods.FindFirstChildOfClass(self, cn)
	for _, c in ipairs(rawget(self, "__children")) do if c.ClassName == cn then return c end end
	return nil
end
function Methods.IsDescendantOf(self, anc)
	local p = rawget(self, "__props").Parent
	while p do if p == anc then return true end p = rawget(p, "__props").Parent end
	return false
end
function Methods.Destroy(self) self.Parent = nil end
function Methods.SetAttribute(self, k, v)
	local t = type(v)
	assert(t == "number" or t == "string" or t == "boolean" or v == nil, "type d'attribut non supporté")
	rawget(self, "__attrs")[k] = v
end
function Methods.GetAttribute(self, k) return rawget(self, "__attrs")[k] end
function Methods.GetFullName(self)
	local names = {}
	local n = self
	while n and not rawget(n, "__service") do table.insert(names, 1, n.Name) n = rawget(n, "__props").Parent end
	if n then table.insert(names, 1, n.Name) end
	return table.concat(names, ".")
end

function Methods.GetPivot(self)
	if self:IsA("BasePart") then return self.CFrame * self.PivotOffset end
	if self.ClassName == "Model" then
		local pp = rawget(self, "__props").PrimaryPart
		if pp then return Methods.GetPivot(pp) end
		return self.WorldPivot
	end
	error("GetPivot sur " .. self.ClassName)
end
function Methods.PivotTo(self, target)
	if self:IsA("BasePart") then
		self.CFrame = target * CFrame.Inverse(self.PivotOffset)
		return
	end
	local delta = target * CFrame.Inverse(Methods.GetPivot(self))
	for _, d in ipairs(Methods.GetDescendants(self)) do
		if d:IsA("BasePart") then rawget(d, "__props").CFrame = delta * d.CFrame end
		if d.ClassName == "Model" and not rawget(d, "__props").PrimaryPart then
			rawget(d, "__props").WorldPivot = delta * d.WorldPivot
		end
	end
	if not rawget(self, "__props").PrimaryPart then rawget(self, "__props").WorldPivot = target end
end

function Methods.Clone(self)
	local map = {}
	local function copy(n)
		local c = newInstance(n.ClassName, rawget(n, "__service"))
		map[n] = c
		local src = rawget(n, "__props")
		local dst = rawget(c, "__props")
		for k, v in pairs(src) do if k ~= "Parent" and k ~= "Changed" then dst[k] = v end end
		for k, v in pairs(rawget(n, "__attrs")) do rawget(c, "__attrs")[k] = v end
		for _, ch in ipairs(rawget(n, "__children")) do
			local cc = copy(ch)
			rawget(cc, "__props").Parent = c
			table.insert(rawget(c, "__children"), cc)
		end
		return c
	end
	local root = copy(self)
	-- Remappe les références internes (PrimaryPart, Adornee, Attachment0/1)
	for orig, c in pairs(map) do
		local props = rawget(c, "__props")
		for k, v in pairs(props) do
			if k ~= "Parent" and type(v) == "table" and v.__type == "Instance" and map[v] then props[k] = map[v] end
		end
	end
	return root
end

---------------------------------------------------------------- game / services
local services = {}
local game = newInstance("DataModel", true)
local function getService(_, name)
	if not services[name] then
		local s = newInstance(name, true)
		rawget(s, "__props").Name = name
		rawset(s, "__service", true)
		services[name] = s
	end
	return services[name]
end
rawget(game, "__props").Name = "game"
Methods.GetService = getService

local TweenService = getService(nil, "TweenService")
M.tweens = {}
rawget(TweenService, "__props").Create = function(_, inst, info, goal)
	assert(info.__type == "TweenInfo", "TweenInfo attendu")
	for k, _ in pairs(goal) do
		local cls = CLASSES[inst.ClassName]
		assert(cls and cls.allowed[k], "Tween : propriété invalide " .. k .. " pour " .. inst.ClassName)
	end
	local tw = { inst = inst, info = info, goal = goal, played = false }
	function tw:Play() self.played = true end
	table.insert(M.tweens, tw)
	return tw
end

local workspace = getService(nil, "Workspace")
rawget(workspace, "__props").CurrentCamera = { CFrame = CFrame.new(0, 5, -20) }

function math.clamp(x, a, b) return math.max(a, math.min(b, x)) end

M.env = {
	game = game, workspace = workspace, Workspace = workspace,
	Instance = { new = function(cn) return newInstance(cn) end },
	Vector3 = Vector3, Vector2 = Vector2, CFrame = CFrame, Color3 = Color3, UDim2 = UDim2,
	NumberRange = NumberRange, NumberSequence = NumberSequence, NumberSequenceKeypoint = NumberSequenceKeypoint,
	ColorSequence = ColorSequence, ColorSequenceKeypoint = ColorSequenceKeypoint, TweenInfo = TweenInfo, Enum = Enum,
}
M.services = services
M.getService = getService
M.allInstances = allInstances
return M
