-- run.lua — exécute le builder + les scripts FX dans le mock, puis exporte la scène en JSON.
-- Variables fournies par l'hôte (run.js) : BUILDER_SRC, MOCK_SRC, FX_TIME, __emit(str)

local M = load(MOCK_SRC, "roblox_mock", "t", _G)()
local env = setmetatable({}, { __index = function(_, k) local v = M.env[k]; if v ~= nil then return v end return _G[k] end })
env.print = function(...) print(...) end

-- 1) Builder
local chunk = assert(load(BUILDER_SRC, "BuildArcadeCabinets", "t", env))
chunk()

local ws = M.getService(nil, "Workspace")
local ss = M.getService(nil, "ServerStorage")
local preview = assert(ws:FindFirstChild("ArcadeCabinets_Preview"))
local storage = assert(ss:FindFirstChild("ArcadeCabinets"))

-- 2) Vérifications structurelles
local report = {}
for _, cab in ipairs(storage:GetChildren()) do
	assert(cab.PrimaryPart and cab.PrimaryPart.Name == "Base", cab.Name .. " : PrimaryPart")
	for _, n in ipairs({ "Body", "Screen", "ControlPanel", "Marquee", "FX" }) do
		assert(cab:FindFirstChild(n), cab.Name .. " : manque " .. n)
	end
	local parts, collide, unanchored = 0, 0, 0
	for _, d in ipairs(cab:GetDescendants()) do
		if d:IsA("BasePart") then
			parts = parts + 1
			if not d.Anchored then unanchored = unanchored + 1 end
			if d.CanCollide then
				collide = collide + 1
				local grp = d.Parent
				assert(d == cab.PrimaryPart or grp.Name == "Body", "CanCollide hors Body/Base : " .. d:GetFullName())
			end
		end
	end
	assert(unanchored == 0, cab.Name .. " : parts non anchored")
	local scripts = 0
	for _, d in ipairs(cab.FX:GetChildren()) do if d.ClassName == "Script" then scripts = scripts + 1 end end
	assert(scripts == 1, cab.Name .. " : il faut exactement 1 Script dans FX")
	table.insert(report, string.format("%s parts=%d collide=%d", cab.Name, parts, collide))
end

-- 3) Scripts FX des copies du Workspace, avec horloge simulée
local clock = 0
local fxEnvBase = setmetatable({ os = { clock = function() return clock end } }, { __index = env })
local drivers = {}
for _, cab in ipairs(preview:GetChildren()) do
	local s = cab.FX.CabinetFX
	assert(s.RunContext == M.env.Enum.RunContext.Client)
	local fenv = setmetatable({ script = s }, { __index = fxEnvBase })
	local fn = assert(load(s.Source, "CabinetFX:" .. cab.Name, "t", fenv))
	fn()
	local d = cab.FX:FindFirstChild("FXDriver")
	if d then table.insert(drivers, d) end
end
-- Simule plusieurs images (vérifie l'absence d'erreur), puis l'instant FX_TIME
for step = 1, 40 do
	clock = clock + 0.05
	for _, d in ipairs(drivers) do
		d.Value = (step / 40) % 1
		for _, f in ipairs(d.Changed.fns) do f() end
	end
end
clock = clock + 1
for _, d in ipairs(drivers) do
	d.Value = FX_TIME
	for _, f in ipairs(d.Changed.fns) do f() end
end
local played = 0
for _, tw in ipairs(M.tweens) do if tw.played then played = played + 1 end end
table.insert(report, "tweens joués: " .. played .. " / créés: " .. #M.tweens)

-- 4) Export JSON
local function num(x) return string.format("%.4f", x) end
local function col(c) return "[" .. num(c.R) .. "," .. num(c.G) .. "," .. num(c.B) .. "]" end
local function vec(v) return "[" .. num(v.X) .. "," .. num(v.Y) .. "," .. num(v.Z) .. "]" end
local function cfr(c)
	local t = {}
	for i = 1, 9 do t[i] = num(c.R[i]) end
	return "{\"p\":" .. vec(c.p) .. ",\"R\":[" .. table.concat(t, ",") .. "]}"
end
local function str(s) return "\"" .. tostring(s):gsub("\\", "\\\\"):gsub("\"", "\\\"") .. "\"" end
local function udim(u) return "[" .. num(u.X.Scale) .. "," .. num(u.X.Offset) .. "," .. num(u.Y.Scale) .. "," .. num(u.Y.Offset) .. "]" end
local function cseq(s)
	local t = {}
	for _, k in ipairs(s.Keypoints) do table.insert(t, "{\"t\":" .. num(k.Time) .. ",\"c\":" .. col(k.Value) .. "}") end
	return "[" .. table.concat(t, ",") .. "]"
end
local function gui(n)
	local f = { "\"class\":" .. str(n.ClassName), "\"name\":" .. str(n.Name) }
	if n:IsA("GuiObject") then
		table.insert(f, "\"size\":" .. udim(n.Size))
		table.insert(f, "\"pos\":" .. udim(rawget(n, "__props").Position or M.env.UDim2.new()))
		table.insert(f, "\"bg\":" .. col(rawget(n, "__props").BackgroundColor3 or M.env.Color3.new(1, 1, 1)))
		table.insert(f, "\"bgT\":" .. num(n.BackgroundTransparency))
		table.insert(f, "\"z\":" .. n.ZIndex)
		if n.ClassName == "TextLabel" then
			table.insert(f, "\"text\":" .. str(n.Text))
			table.insert(f, "\"textColor\":" .. col(n.TextColor3))
		end
	else
		table.insert(f, "\"ppS\":" .. num(n.PixelsPerStud))
	end
	local ch = {}
	for _, c in ipairs(n:GetChildren()) do table.insert(ch, gui(c)) end
	table.insert(f, "\"children\":[" .. table.concat(ch, ",") .. "]")
	return "{" .. table.concat(f, ",") .. "}"
end

local items = {}
local function worldCF(att) return att.Parent.CFrame * att.CFrame end
for _, cab in ipairs(preview:GetChildren()) do
	for _, d in ipairs(cab:GetDescendants()) do
		if d:IsA("BasePart") then
			local f = {
				"\"kind\":\"part\"", "\"cab\":" .. str(cab.Name), "\"name\":" .. str(d.Name), "\"class\":" .. str(d.ClassName),
				"\"shape\":" .. str(rawget(d, "__props").Shape and d.Shape.Name or "Block"),
				"\"size\":" .. vec(d.Size), "\"cf\":" .. cfr(d.CFrame), "\"color\":" .. col(d.Color),
				"\"material\":" .. str(d.Material.Name), "\"transparency\":" .. num(d.Transparency),
				"\"reflectance\":" .. num(d.Reflectance),
			}
			local g = d:FindFirstChildOfClass("SurfaceGui")
			if g then table.insert(f, "\"gui\":" .. gui(g)) end
			table.insert(items, "{" .. table.concat(f, ",") .. "}")
		elseif d:IsA("Light") then
			local f = { "\"cab\":" .. str(cab.Name), "\"kind\":" .. str(d.ClassName), "\"pos\":" .. vec(d.Parent.CFrame.p), "\"cf\":" .. cfr(d.Parent.CFrame),
				"\"color\":" .. col(d.Color), "\"brightness\":" .. num(d.Brightness), "\"range\":" .. num(d.Range) }
			table.insert(items, "{" .. table.concat(f, ",") .. "}")
		elseif d.ClassName == "ParticleEmitter" then
			local p = d.Parent
			local f = { "\"cab\":" .. str(cab.Name), "\"kind\":\"emitter\"", "\"name\":" .. str(d.Name), "\"colors\":" .. cseq(d.Color), "\"rate\":" .. num(d.Rate) }
			if p.ClassName == "Attachment" then
				table.insert(f, "\"pos\":" .. vec(worldCF(p).p))
			else
				table.insert(f, "\"cf\":" .. cfr(p.CFrame)); table.insert(f, "\"size\":" .. vec(p.Size))
			end
			table.insert(items, "{" .. table.concat(f, ",") .. "}")
		elseif d.ClassName == "Beam" then
			local c0, c1 = worldCF(d.Attachment0), worldCF(d.Attachment1)
			local ax0 = M.env.Vector3.new(c0.R[1], c0.R[4], c0.R[7])
			local ax1 = M.env.Vector3.new(c1.R[1], c1.R[4], c1.R[7])
			local f = { "\"cab\":" .. str(cab.Name), "\"kind\":\"beam\"", "\"p0\":" .. vec(c0.p), "\"p1\":" .. vec(c1.p), "\"ax0\":" .. vec(ax0), "\"ax1\":" .. vec(ax1),
				"\"c0\":" .. num(d.CurveSize0), "\"c1\":" .. num(d.CurveSize1), "\"colors\":" .. cseq(d.Color), "\"width\":" .. num(d.Width0) }
			table.insert(items, "{" .. table.concat(f, ",") .. "}")
		elseif d.ClassName == "Highlight" then
			table.insert(items, "{\"kind\":\"highlight\",\"cab\":" .. str(cab.Name) .. ",\"fill\":" .. col(d.FillColor) ..
				",\"fillT\":" .. num(d.FillTransparency) .. ",\"outline\":" .. col(d.OutlineColor) .. ",\"outlineT\":" .. num(d.OutlineTransparency) .. "}")
		end
	end
end

__emit("{\"report\":[" .. (function() local t = {} for i, r in ipairs(report) do t[i] = str(r) end return table.concat(t, ",") end)() ..
	"],\"items\":[" .. table.concat(items, ",") .. "]}")
