--[[
	BuildArcadeCabinets.lua
	-----------------------------------------------------------------------------
	Construit 5 bornes d'arcade (Common → Mythic) en Parts, fidèles à la planche
	de référence, et les range dans ServerStorage/ArcadeCabinets.
	Une copie de chaque borne est alignée dans Workspace/ArcadeCabinets_Preview.

	UTILISATION : Roblox Studio > View > Command Bar, coller ce fichier, Entrée.
	(Ou en Script de plugin.) Ré-exécutable : remplace les versions précédentes.

	Repère local d'une borne : sol = y 0, face avant vers -Z (LookVector),
	pivot du Model au sol, au centre de l'empreinte.
	Hiérarchie : Cabinet_X (Model, PrimaryPart = Base)
	             ├ Base · Body · Screen · ControlPanel · Marquee
	             └ FX (Folder) : CabinetFX (Script, RunContext Client) + émetteurs
]]

local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

-------------------------------------------------------------------------------
-- Script d'effets (un seul par borne, identique pour toutes ; le palier est lu
-- dans l'attribut "Tier"). RunContext = Client : il tourne sur chaque client
-- dès que la borne est dans le Workspace, et rien n'est répliqué par le réseau.
-------------------------------------------------------------------------------
local FX_SOURCE = [==[
--[[ CabinetFX — effets visuels de la borne (RunContext = Client).
	Paliers cumulatifs, lus dans l'attribut "Tier" du Model :
	1 Common    : motif d'écran qui défile
	2 Rare      : pulse des néons et de la PointLight
	3 Epic      : cycle de couleur des néons (+ SurfaceLight)
	4 Legendary : palette dorée + Highlight
	5 Mythic    : arc-en-ciel, anneaux de Beams en rotation, lévitation du Marquee
	Une seule boucle d'animation : un Tween linéaire infini sur un NumberValue
	"pilote" (0 → 1 en CYCLE secondes). Aucun Tween n'est recréé.
]]
local TweenService = game:GetService("TweenService")

local fx = script.Parent
local cabinet = fx.Parent
local tier = cabinet:GetAttribute("Tier") or 1

local TAU = math.pi * 2
local CYCLE = 8            -- durée d'un cycle complet (s)
local PULSES = 6           -- pulses de luminosité par cycle
local BOBS = 3             -- oscillations de lévitation par cycle
local LIFT = 0.35          -- amplitude de lévitation (studs)
local UPDATE_RATE = 1 / 30 -- limite de rafraîchissement (mobile)
local CULL_DISTANCE = 150  -- au-delà, on n'anime plus les couleurs
local BLACK = Color3.new(0, 0, 0)

local screen = cabinet:WaitForChild("Screen")
local glass = screen:WaitForChild("Glass")

-- Palier 1 : le motif de l'écran défile (Tween infini, joué une fois)
local scroller = glass:FindFirstChild("Scroller", true)
if scroller then
	local info = TweenInfo.new(4, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1)
	TweenService:Create(scroller, info, { Position = UDim2.fromScale(0, 0) }):Play()
end

if tier < 2 then
	return
end

-- Palier 2 : la PointLight respire (Tween infini aller-retour)
local light = glass:FindFirstChildOfClass("PointLight")
if light then
	local info = TweenInfo.new(CYCLE / PULSES / 2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
	TweenService:Create(light, info, { Brightness = light.Brightness * 2.2 }):Play()
end

-- Néons animés : toutes les BaseParts marquées FXNeon par le builder
local neons = {}
for _, d in ipairs(cabinet:GetDescendants()) do
	if d:IsA("BasePart") and d:GetAttribute("FXNeon") then
		table.insert(neons, { part = d, color = d.Color, phase = d:GetAttribute("FXPhase") or 0 })
	end
end

local PALETTES = {
	[3] = { Color3.fromRGB(61, 232, 255), Color3.fromRGB(176, 76, 255), Color3.fromRGB(255, 79, 163) },
	[4] = { Color3.fromRGB(255, 214, 107), Color3.fromRGB(255, 160, 30), Color3.fromRGB(255, 246, 210) },
}
local palette = PALETTES[math.min(tier, 4)]

local function paletteAt(t)
	local n = #palette
	local x = (t % 1) * n
	local i = math.floor(x)
	return palette[i + 1]:Lerp(palette[(i + 1) % n + 1], x - i)
end

local function rainbow(t)
	return Color3.fromHSV(t % 1, 0.7, 1)
end

local surfaceLight = glass:FindFirstChildOfClass("SurfaceLight")
local highlight = fx:FindFirstChildOfClass("Highlight")
if highlight then
	highlight.Adornee = cabinet
end

-- Palier 5 : offsets relatifs au pivot (robuste si la borne est déplacée)
local pivot0 = cabinet:GetPivot()
local fxRoot = fx:FindFirstChild("FXRoot")
local rootOffset = fxRoot and pivot0:ToObjectSpace(fxRoot.CFrame)
local marquee = cabinet:FindFirstChild("Marquee")
local marqueeOffset = marquee and pivot0:ToObjectSpace(marquee:GetPivot())

local driver = Instance.new("NumberValue")
driver.Name = "FXDriver"
driver.Parent = fx

local lastUpdate = 0
local function update()
	local now = os.clock()
	if now - lastUpdate < UPDATE_RATE then
		return
	end
	lastUpdate = now

	local pivot = cabinet:GetPivot()
	local camera = workspace.CurrentCamera
	if camera and (camera.CFrame.Position - pivot.Position).Magnitude > CULL_DISTANCE then
		return
	end

	local t = driver.Value
	local pulse = 0.8 + 0.2 * math.sin(t * TAU * PULSES)
	for _, n in ipairs(neons) do
		local c
		if tier >= 5 then
			c = rainbow(t + n.phase)
		elseif tier >= 3 then
			c = paletteAt(t + n.phase)
		else
			c = n.color
		end
		n.part.Color = c:Lerp(BLACK, 1 - pulse)
	end

	if surfaceLight then
		surfaceLight.Color = (tier >= 5) and rainbow(t) or paletteAt(t)
	end

	if tier >= 5 then
		if highlight then
			highlight.FillColor = rainbow(t)
			highlight.OutlineColor = rainbow(t + 0.5)
		end
		if fxRoot then
			fxRoot.CFrame = pivot * rootOffset * CFrame.Angles(0, t * TAU, 0)
		end
		if marquee then
			local lift = LIFT * (0.5 + 0.5 * math.sin(t * TAU * BOBS))
			marquee:PivotTo(pivot * marqueeOffset * CFrame.new(0, lift, 0))
		end
	end
end

driver.Changed:Connect(update)
local driverInfo = TweenInfo.new(CYCLE, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1)
TweenService:Create(driver, driverInfo, { Value = 1 }):Play()
]==]

-------------------------------------------------------------------------------
-- Géométrie (studs)
-------------------------------------------------------------------------------
local W = 3.0                 -- largeur hors-tout des flancs
local T = 0.25                -- épaisseur d'un flanc
local SX = W / 2 - T / 2      -- x du centre d'un flanc
local IW = W - 2 * T          -- largeur intérieure (caisson)
local SCREEN_TILT = math.rad(12)
local MARQUEE_MIN_Y = 5.1     -- tout ce qui est au-dessus appartient au Marquee
local atan2 = math.atan2 or math.atan

-- Profil du flanc (z, y), face avant à gauche (z négatif)
local PROFILE_FRONT = {
	{ -1.7, 0.2 }, { -1.7, 3.2 }, { -2.0, 3.2 }, { -2.0, 3.7 }, { -1.0, 4.3 },
	{ -1.0, 5.1 }, { -1.7, 5.5 }, { -1.7, 7.0 },
}
local PROFILE_TOP = { { -1.7, 7.0 }, { 2.0, 7.0 } }
local PROFILE_BACK = { { 2.0, 7.0 }, { 2.0, 0.2 } }
local PROFILE_BACK_SPLIT = { { 2.0, 7.0 }, { 2.0, 5.5 }, { 2.0, 0.2 } }

-- Motif de l'écran : étoiles {x, y, taille px} + deux bandes
local SCREEN_DOTS = {
	{ 0.08, 0.10, 6 }, { 0.30, 0.32, 4 }, { 0.55, 0.06, 5 }, { 0.82, 0.24, 6 },
	{ 0.18, 0.55, 5 }, { 0.45, 0.62, 4 }, { 0.70, 0.46, 6 }, { 0.90, 0.70, 4 },
	{ 0.12, 0.84, 4 }, { 0.62, 0.88, 5 },
}
local SCREEN_BARS = { 0.38, 0.78 }

-------------------------------------------------------------------------------
-- Thèmes (couleurs relevées sur l'image)
-------------------------------------------------------------------------------
local THEMES = {
	Common = {
		tier = 1,
		colors = {
			base = "#2C5CA6", side = "#3B7DD8", body = "#3470C6", marquee = "#3B7DD8",
			sign = "#4C8DE6", cap = "#3B7DD8", deck = "#346FC4",
			bezel = "#1B2230", frame = "#2B3547", glass = "#141B28",
			stick = "#18181C", ball = "#18181C", door = "#1A1B21", doorInner = "#2A2C34",
			slot = "#3A3D47", buttons = { "#262A33", "#262A33", "#262A33", "#262A33" },
		},
		materials = {},
		slots = 1,
		screen = { bg = "#0D1B33", fg = { "#5FA8FF", "#A8CCFF", "#FFFFFF" }, text = "#FFFFFF", brightness = 1.2 },
		light = { color = "#7FB2FF", brightness = 0.6, range = 7 },
	},

	Rare = {
		tier = 2,
		colors = {
			base = "#3B1773", side = "#5B2BA6", body = "#4E2496", marquee = "#5B2BA6",
			sign = "#2A0F57", signGlow = "#5FD0FF", cap = "#5B2BA6", deck = "#46208A",
			bezel = "#1A1033", frame = "#5FD0FF", glass = "#1B2A5C",
			stick = "#22123F", ball = "#B04CFF", door = "#1C0F33", doorInner = "#2C1A4D",
			slot = "#FF5FD2", buttons = { "#FF4FD8", "#4FD8FF", "#FF4FD8", "#4FD8FF" },
		},
		materials = { frame = "Neon", signGlow = "Neon", ball = "Neon", buttons = "Neon", slot = "Neon" },
		slots = 2,
		edges = { color = "#5FD0FF", material = "Neon", width = 0.07, back = PROFILE_BACK, outer = true },
		screen = { bg = "#101B4A", fg = { "#7FE3FF", "#FF7FE6", "#FFFFFF" }, text = "#7FE3FF", brightness = 1.4 },
		light = { color = "#8FA8FF", brightness = 0.8, range = 8 },
	},

	Epic = {
		tier = 3,
		colors = {
			base = "#5E0C33", side = "#A3185C", body = "#8E1450", marquee = "#A3185C",
			sign = "#3B0820", signGlow = "#3DE8FF", cap = "#C8CDD6", deck = "#7A1145",
			bezel = "#2A0A1A", frame = "#3DE8FF", glass = "#132A40",
			stick = "#C8CDD6", ball = "#FF4FA3", door = "#2A0A1A", doorInner = "#C8CDD6",
			slot = "#3DE8FF", buttons = { "#3DE8FF", "#FF4FA3", "#3DE8FF", "#FF4FA3" },
		},
		materials = {
			frame = "Neon", signGlow = "Neon", ball = "Neon", buttons = "Neon", slot = "Neon",
			cap = "Metal", stick = "Metal", doorInner = "Metal",
		},
		slots = 2,
		edges = { color = "#C8CDD6", material = "Metal", width = 0.14, back = nil },
		sideLines = {
			{ -0.7, 6.7, 1.85, 4.4, "#3DE8FF", 0.1, 0.0 },
			{ -0.8, 4.9, 1.85, 2.5, "#FF4FA3", 0.1, 0.66 },
			{ -1.5, 2.9, 1.85, 0.6, "#3DE8FF", 0.1, 0.0 },
		},
		screen = { bg = "#14244A", fg = { "#3DE8FF", "#FF4FA3", "#FFFFFF" }, text = "#3DE8FF", brightness = 1.6 },
		light = { color = "#3DE8FF", brightness = 0.8, range = 8 },
		surfaceLight = { color = "#3DE8FF", brightness = 1.5, range = 10, angle = 70 },
	},

	Legendary = {
		tier = 4,
		colors = {
			base = "#D9A21B", side = "#151515", body = "#121212", marquee = "#151515",
			sign = "#0E0E0E", signGlow = "#FFD66B", cap = "#E2B13C", deck = "#D4A027",
			bezel = "#C8961E", frame = "#FFD66B", glass = "#FFE7A8",
			stick = "#E2B13C", ball = "#FFD24A", door = "#E2B13C", doorInner = "#121212",
			slot = "#FFD24A", buttons = { "#FFE9A6", "#FFC93C", "#FFE9A6", "#FFC93C" },
		},
		materials = {
			base = "Foil", cap = "Foil", deck = "Foil", bezel = "Foil", stick = "Foil", door = "Foil",
			frame = "Neon", signGlow = "Neon", ball = "Neon", buttons = "Neon", slot = "Neon",
		},
		slots = 2,
		edges = { color = "#EDBE45", material = "Foil", width = 0.3, back = PROFILE_BACK },
		sideLines = {
			{ 1.85, 0.5, -1.3, 2.9, "#FFC93C", 0.07, 0.0 },
			{ 1.85, 3.9, -0.6, 6.7, "#FFC93C", 0.07, 0.5 },
		},
		screen = { bg = "#FFE2A0", fg = { "#C77A00", "#FFFFFF", "#FFB300" }, text = "#8A4B00", brightness = 1.5 },
		light = { color = "#FFD27A", brightness = 1.0, range = 9 },
		surfaceLight = { color = "#FFD27A", brightness = 1.8, range = 10, angle = 70 },
		sparkles = { "#FFF1B0", "#FFB300" },
		highlight = { fill = "#FFC93C", outline = "#FFE08A", fillT = 0.9, outlineT = 0.45 },
	},

	Mythic = {
		tier = 5,
		colors = {
			base = "#B8A2FF", side = "#F29BFF", body = "#D6C2FF", marquee = "#FFC9F2",
			sideLower = "#7FD8FF", sideCP = "#A8F0FF", sideRamp = "#FFA8DF", sideMid = "#F29BFF",
			sideHood = "#FFE07A", sideTop = "#FFEC9A",
			sign = "#FFF4FC", signGlow = "#FF9BE6", cap = "#FFFFFF", deck = "#9FE6FF",
			bezel = "#E0D2FF", frame = "#9BEFFF", glass = "#FFF8E8",
			stick = "#FFFFFF", ball = "#FFB3E6", door = "#D8F6FF", doorInner = "#FFFFFF",
			slot = "#FFFFFF", buttons = { "#9EE8FF", "#FFB3E6", "#FFF3B8", "#C9B8FF" },
		},
		materials = { frame = "Neon", signGlow = "Neon", ball = "Neon", buttons = "Neon", slot = "Neon" },
		reflectance = 0.15,
		slots = 2,
		edges = { color = "#FFFFFF", material = "Neon", width = 0.08, back = PROFILE_BACK_SPLIT, outer = true },
		screen = { bg = "#FFF3E0", fg = { "#FF7FD0", "#5FD8FF", "#FFC23F" }, text = "#A04CFF", brightness = 1.6 },
		light = { color = "#FFFFFF", brightness = 1.0, range = 10 },
		surfaceLight = { color = "#FFFFFF", brightness = 2, range = 10, angle = 70 },
		sparkles = { "#FFFFFF", "#FFD6F5" },
		highlight = { fill = "#FFFFFF", outline = "#FFFFFF", fillT = 0.82, outlineT = 0.35 },
		mythic = true,
	},
}
local ORDER = { "Common", "Rare", "Epic", "Legendary", "Mythic" }

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------
local function rgb(hex)
	return Color3.fromHex(hex)
end

local function colorOf(theme, key, fallback)
	return rgb(theme.colors[key] or theme.colors[fallback or "body"])
end

local function materialOf(theme, key, fallback)
	local m = theme.materials[key] or (fallback and theme.materials[fallback]) or "SmoothPlastic"
	return Enum.Material[m]
end

local function newModel(name, parent)
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

-- Crée une part anchored, sans collision par défaut (opts.collide pour l'activer)
local function makePart(className, parent, name, size, cf, color, material, opts)
	local p = Instance.new(className)
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	opts = opts or {}
	if opts.shape then
		p.Shape = opts.shape
	end
	if opts.collide then
		p.CanCollide = true
		p.CanQuery = true
	end
	if opts.reflectance then
		p.Reflectance = opts.reflectance
	end
	if opts.noShadow or material == Enum.Material.Neon then
		p.CastShadow = false
	end
	p.Parent = parent
	return p
end

local function tagNeon(part, phase)
	if part.Material == Enum.Material.Neon then
		part:SetAttribute("FXNeon", true)
		part:SetAttribute("FXPhase", phase or 0)
	end
end

local V = Vector3.new
local CF = CFrame.new
local VERTICAL = CFrame.Angles(0, 0, math.pi / 2) -- cylindre debout
local FLIP = CFrame.Angles(0, 0, math.pi)         -- wedge retourné (pente vers le bas)

-------------------------------------------------------------------------------
-- Écran : SurfaceGui avec motif qui défile
-------------------------------------------------------------------------------
local function buildScreenGui(glass, theme)
	local s = theme.screen
	local gui = Instance.new("SurfaceGui")
	gui.Name = "ScreenGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 60
	gui.LightInfluence = 0
	gui.Brightness = s.brightness
	gui.MaxDistance = 120
	gui.Parent = glass

	local display = Instance.new("Frame")
	display.Name = "Display"
	display.Size = UDim2.fromScale(1, 1)
	display.BackgroundColor3 = rgb(s.bg)
	display.BorderSizePixel = 0
	display.ClipsDescendants = true
	display.Parent = gui

	-- Contenu deux fois plus haut que l'écran, deux moitiés identiques :
	-- on le fait glisser de -1 à 0 en boucle → défilement sans couture.
	local scroller = Instance.new("Frame")
	scroller.Name = "Scroller"
	scroller.Size = UDim2.fromScale(1, 2)
	scroller.Position = UDim2.fromScale(0, -1)
	scroller.BackgroundTransparency = 1
	scroller.Parent = display

	for half = 0, 1 do
		for i, d in ipairs(SCREEN_DOTS) do
			local dot = Instance.new("Frame")
			dot.Name = "Dot"
			dot.BorderSizePixel = 0
			dot.BackgroundColor3 = rgb(s.fg[(i - 1) % #s.fg + 1])
			dot.Size = UDim2.fromOffset(d[3], d[3])
			dot.Position = UDim2.fromScale(d[1], (d[2] + half) / 2)
			dot.Parent = scroller
		end
		for _, y in ipairs(SCREEN_BARS) do
			local bar = Instance.new("Frame")
			bar.Name = "Bar"
			bar.BorderSizePixel = 0
			bar.BackgroundColor3 = rgb(s.fg[1])
			bar.BackgroundTransparency = 0.55
			bar.Size = UDim2.new(1, 0, 0, 3)
			bar.Position = UDim2.fromScale(0, (y + half) / 2)
			bar.Parent = scroller
		end
	end

	local label = Instance.new("TextLabel")
	label.Name = "InsertCoin"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(0.84, 0.2)
	label.Position = UDim2.fromScale(0.08, 0.72)
	label.Font = Enum.Font.Arcade
	label.Text = "INSERT COIN"
	label.TextScaled = true
	label.TextColor3 = rgb(s.text)
	label.ZIndex = 2
	label.Parent = display
end

-------------------------------------------------------------------------------
-- Construction d'une borne (au repère d'origine)
-------------------------------------------------------------------------------
local function buildCabinet(rarity)
	local th = THEMES[rarity]
	local model = Instance.new("Model")
	model.Name = "Cabinet_" .. rarity
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model:SetAttribute("Rarity", rarity)
	model:SetAttribute("Tier", th.tier)

	-- Base (PrimaryPart) : pivot ramené au sol, au centre de l'empreinte
	local base = makePart("Part", model, "Base", V(3.1, 0.2, 3.85), CF(0, 0.1, 0.15),
		colorOf(th, "base"), materialOf(th, "base"), { collide = true })
	base.PivotOffset = CF(0, -0.1, -0.15)
	model.PrimaryPart = base

	local body = newModel("Body", model)
	local screen = newModel("Screen", model)
	local panel = newModel("ControlPanel", model)
	local marquee = newModel("Marquee", model)
	local fx = Instance.new("Folder")
	fx.Name = "FX"
	fx.Parent = model

	local refl = th.reflectance

	-- Flancs (profil en escalier), gauche puis droite
	for _, s in ipairs({ -1, 1 }) do
		local tag = (s < 0) and "_L" or "_R"
		local x = s * SX
		local function side(class, parent, name, key, size, cf)
			return makePart(class, parent, name .. tag, size, cf, colorOf(th, key, "side"),
				materialOf(th, key, "side"), { collide = (parent == body), reflectance = refl })
		end
		side("Part", body, "SideLower", "sideLower", V(T, 3.0, 3.7), CF(x, 1.7, 0.15))
		side("Part", body, "SideCP", "sideCP", V(T, 0.5, 4.0), CF(x, 3.45, 0))
		side("WedgePart", body, "SideRamp", "sideRamp", V(T, 0.6, 1.0), CF(x, 4.0, -1.5))
		side("Part", body, "SideMid", "sideMid", V(T, 1.8, 3.0), CF(x, 4.6, 0.5))
		side("WedgePart", marquee, "SideHood", "sideHood", V(T, 0.4, 0.7), CF(x, 5.3, -1.35) * FLIP)
		side("Part", marquee, "SideTop", "sideTop", V(T, 1.5, 3.7), CF(x, 6.25, 0.15))
	end

	-- Caisson
	makePart("Part", body, "LowerBody", V(IW, 3.0, 3.5), CF(0, 1.7, 0.2),
		colorOf(th, "body"), materialOf(th, "body"), { collide = true, reflectance = refl })
	makePart("Part", body, "UpperBody", V(IW, 2.3, 2.85), CF(0, 4.35, 0.525),
		colorOf(th, "body"), materialOf(th, "body"), { collide = true, reflectance = refl })

	-- Trappe à pièces
	makePart("Part", body, "CoinDoor", V(0.85, 1.0, 0.08), CF(0, 1.6, -1.59),
		colorOf(th, "door"), materialOf(th, "door"), { noShadow = true })
	makePart("Part", body, "CoinDoorInner", V(0.55, 0.5, 0.04), CF(0, 1.7, -1.64),
		colorOf(th, "doorInner"), materialOf(th, "doorInner"), { noShadow = true })
	local slotX = (th.slots == 1) and { 0 } or { -0.13, 0.13 }
	for i, sx in ipairs(slotX) do
		makePart("Part", body, "CoinSlot" .. i, V(0.1, 0.26, 0.04), CF(sx, 1.7, -1.67),
			colorOf(th, "slot"), materialOf(th, "slot"), { noShadow = true })
	end

	-- Écran incliné (le haut part vers l'arrière)
	local tilt = CF(0, 4.55, -1.0) * CFrame.Angles(SCREEN_TILT, 0, 0)
	makePart("Part", screen, "Bezel", V(2.45, 1.75, 0.2), tilt, colorOf(th, "bezel"), materialOf(th, "bezel"))
	local frame = makePart("Part", screen, "ScreenFrame", V(2.15, 1.5, 0.04), tilt * CF(0, 0.04, -0.105),
		colorOf(th, "frame"), materialOf(th, "frame"), { noShadow = true })
	tagNeon(frame, 0.25)
	local glass = makePart("Part", screen, "Glass", V(2.0, 1.36, 0.04), tilt * CF(0, 0.04, -0.125),
		colorOf(th, "glass"), Enum.Material.Glass, { noShadow = true })
	glass.Reflectance = 0.05
	buildScreenGui(glass, th)

	local light = Instance.new("PointLight")
	light.Color = rgb(th.light.color)
	light.Brightness = th.light.brightness
	light.Range = th.light.range
	light.Shadows = false
	light.Parent = glass

	if th.tier >= 3 then
		local sl = Instance.new("SurfaceLight")
		sl.Face = Enum.NormalId.Front
		sl.Color = rgb(th.surfaceLight.color)
		sl.Brightness = th.surfaceLight.brightness
		sl.Range = th.surfaceLight.range
		sl.Angle = th.surfaceLight.angle
		sl.Shadows = false
		sl.Parent = glass
	end

	-- Pupitre : plateau, 2 joysticks, 4 boutons
	makePart("Part", panel, "Deck", V(IW, 0.5, 1.1), CF(0, 3.45, -1.45), colorOf(th, "deck"), materialOf(th, "deck"))
	for i, jx in ipairs({ -0.8, 0.35 }) do
		makePart("Part", panel, "StickShaft" .. i, V(0.36, 0.08, 0.08), CF(jx, 3.88, -1.6) * VERTICAL,
			colorOf(th, "stick"), materialOf(th, "stick"), { shape = Enum.PartType.Cylinder, noShadow = true })
		makePart("Part", panel, "StickBall" .. i, V(0.24, 0.24, 0.24), CF(jx, 4.08, -1.6),
			colorOf(th, "ball"), materialOf(th, "ball"), { shape = Enum.PartType.Ball, noShadow = true })
	end
	for i, bx in ipairs({ -0.45, -0.2, 0.7, 0.95 }) do
		makePart("Part", panel, "Button" .. i, V(0.08, 0.2, 0.2), CF(bx, 3.74, -1.55) * VERTICAL,
			rgb(th.colors.buttons[i]), materialOf(th, "buttons"), { shape = Enum.PartType.Cylinder, noShadow = true })
	end

	-- Marquee (caisson haut, auvent, enseigne, chapeau)
	local box = makePart("Part", marquee, "MarqueeBox", V(IW, 1.4, 3.55), CF(0, 6.2, 0.175),
		colorOf(th, "marquee"), materialOf(th, "marquee"), { reflectance = refl })
	marquee.PrimaryPart = box
	makePart("WedgePart", marquee, "Hood", V(IW, 0.4, 0.7), CF(0, 5.3, -1.25) * FLIP,
		colorOf(th, "marquee"), materialOf(th, "marquee"), { reflectance = refl })
	if th.colors.signGlow then
		local glow = makePart("Part", marquee, "SignGlow", V(2.25, 1.0, 0.04), CF(0, 6.2, -1.615),
			colorOf(th, "signGlow"), materialOf(th, "signGlow"), { noShadow = true })
		tagNeon(glow, 0.5)
	end
	makePart("Part", marquee, "Sign", V(2.1, 0.85, 0.06), CF(0, 6.2, -1.64),
		colorOf(th, "sign"), materialOf(th, "sign"), { noShadow = true })
	makePart("Part", marquee, "Cap", V(3.1, 0.15, 3.85), CF(0, 7.075, 0.15),
		colorOf(th, "cap"), materialOf(th, "cap"), { reflectance = refl })

	-- Liserés le long du profil des flancs (néon, chrome ou or)
	if th.edges then
		local e = th.edges
		local polylines = { PROFILE_FRONT, PROFILE_TOP }
		if e.back then
			table.insert(polylines, e.back)
		end
		for _, s in ipairs({ -1, 1 }) do
			local n = 0
			for _, line in ipairs(polylines) do
				for i = 1, #line - 1 do
					local z1, y1, z2, y2 = line[i][1], line[i][2], line[i + 1][1], line[i + 1][2]
					local dz, dy = z2 - z1, y2 - y1
					local len = math.sqrt(dz * dz + dy * dy)
					local parent = (math.min(y1, y2) >= MARQUEE_MIN_Y) and marquee or body
					n = n + 1
					-- outer : filet fin sur l'arête extérieure ; sinon trim qui enveloppe la tranche du flanc
					local sizeX = e.outer and e.width or (T + 0.06)
					local x = e.outer and (s * W / 2) or (s * SX)
					local strip = makePart("Part", parent, "Edge" .. ((s < 0) and "_L" or "_R") .. n,
						V(sizeX, len + e.width, e.width),
						CF(x, (y1 + y2) / 2, (z1 + z2) / 2) * CFrame.Angles(atan2(dz, dy), 0, 0),
						rgb(e.color), Enum.Material[e.material], { noShadow = true })
					tagNeon(strip, (y1 + y2) / 14)
				end
			end
		end
	end

	-- Motifs néon sur la face extérieure des flancs
	if th.sideLines then
		for _, s in ipairs({ -1, 1 }) do
			for i, l in ipairs(th.sideLines) do
				local z1, y1, z2, y2 = l[1], l[2], l[3], l[4]
				local dz, dy = z2 - z1, y2 - y1
				local line = makePart("Part", body, "SideLine" .. ((s < 0) and "_L" or "_R") .. i,
					V(0.04, math.sqrt(dz * dz + dy * dy), l[6]),
					CF(s * (W / 2 + 0.02), (y1 + y2) / 2, (z1 + z2) / 2) * CFrame.Angles(atan2(dz, dy), 0, 0),
					rgb(l[5]), Enum.Material.Neon, { noShadow = true })
				tagNeon(line, l[7])
			end
		end
	end

	-- FX : script unique + émetteurs selon le palier
	local fxScript = Instance.new("Script")
	fxScript.Name = "CabinetFX"
	fxScript.RunContext = Enum.RunContext.Client
	fxScript.Source = FX_SOURCE
	fxScript.Parent = fx

	if th.tier >= 4 then
		local root = makePart("Part", fx, "FXRoot", V(3.6, 7.0, 4.4), CF(0, 3.6, 0.1),
			Color3.new(1, 1, 1), Enum.Material.SmoothPlastic, { noShadow = true })
		root.Transparency = 1

		local top = Instance.new("Attachment")
		top.Name = "SparkTop"
		top.Position = V(0, 3.6, -0.2)
		top.Parent = root

		local sparks = Instance.new("ParticleEmitter")
		sparks.Name = "Sparkles"
		sparks.Color = ColorSequence.new(rgb(th.sparkles[1]), rgb(th.sparkles[2]))
		sparks.LightEmission = 1
		sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.22), NumberSequenceKeypoint.new(1, 0) })
		sparks.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 0.6) })
		sparks.Lifetime = NumberRange.new(1, 1.8)
		sparks.Rate = 10
		sparks.Speed = NumberRange.new(1.5, 3)
		sparks.SpreadAngle = Vector2.new(55, 55)
		sparks.Acceleration = V(0, -3, 0)
		sparks.EmissionDirection = Enum.NormalId.Top
		sparks.Parent = top

		local hl = Instance.new("Highlight")
		hl.FillColor = rgb(th.highlight.fill)
		hl.OutlineColor = rgb(th.highlight.outline)
		hl.FillTransparency = th.highlight.fillT
		hl.OutlineTransparency = th.highlight.outlineT
		hl.DepthMode = Enum.HighlightDepthMode.Occluded
		hl.Adornee = model
		hl.Parent = fx

		if th.mythic then
			local rainbow = ColorSequence.new({
				ColorSequenceKeypoint.new(0, rgb("#FF5F9E")),
				ColorSequenceKeypoint.new(0.2, rgb("#FFD25F")),
				ColorSequenceKeypoint.new(0.4, rgb("#7CFF8A")),
				ColorSequenceKeypoint.new(0.6, rgb("#5FE3FF")),
				ColorSequenceKeypoint.new(0.8, rgb("#8F7CFF")),
				ColorSequenceKeypoint.new(1, rgb("#FF5FD8")),
			})

			-- Aura : particules émises depuis la surface du volume FXRoot
			local aura = Instance.new("ParticleEmitter")
			aura.Name = "Aura"
			aura.Shape = Enum.ParticleEmitterShape.Box
			aura.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
			aura.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
			aura.Color = rainbow
			aura.LightEmission = 1
			aura.Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.4, 0.35), NumberSequenceKeypoint.new(1, 0),
			})
			aura.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
			aura.Lifetime = NumberRange.new(1.5, 2.5)
			aura.Rate = 18
			aura.Speed = NumberRange.new(0.3, 0.8)
			aura.Acceleration = V(0, 0.8, 0)
			aura.Parent = root

			-- Deux anneaux d'énergie (2 Beams courbes chacun), inclinés, en rotation via le script
			local R = 2.5
			local K = R * 4 / 3 -- demi-cercle de Bézier
			for i, ring in ipairs({ { y = -1.6, tiltY = 0.45 }, { y = 1.7, tiltY = -0.45 } }) do
				local a0 = Instance.new("Attachment")
				a0.Name = "Ring" .. i .. "_A"
				a0.CFrame = CF(R, ring.y + ring.tiltY, 0) * CFrame.Angles(0, math.pi / 2, 0) -- Axis = -Z
				a0.Parent = root
				local a1 = Instance.new("Attachment")
				a1.Name = "Ring" .. i .. "_B"
				a1.CFrame = CF(-R, ring.y - ring.tiltY, 0) * CFrame.Angles(0, math.pi / 2, 0)
				a1.Parent = root
				for j, sign in ipairs({ 1, -1 }) do
					local beam = Instance.new("Beam")
					beam.Name = "Ring" .. i .. "_" .. j
					beam.Attachment0 = a0
					beam.Attachment1 = a1
					beam.CurveSize0 = K * sign
					beam.CurveSize1 = -K * sign
					beam.Color = rainbow
					beam.Transparency = NumberSequence.new({
						NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(0.5, 0.05), NumberSequenceKeypoint.new(1, 0.5),
					})
					beam.Width0 = 0.12
					beam.Width1 = 0.12
					beam.FaceCamera = true
					beam.LightEmission = 1
					beam.Segments = 24
					beam.Parent = root
				end
			end
		end
	end

	return model
end

-------------------------------------------------------------------------------
-- Construction, rangement et preview
-------------------------------------------------------------------------------
local old = ServerStorage:FindFirstChild("ArcadeCabinets")
if old then
	old:Destroy()
end
local oldPreview = Workspace:FindFirstChild("ArcadeCabinets_Preview")
if oldPreview then
	oldPreview:Destroy()
end

local storage = Instance.new("Folder")
storage.Name = "ArcadeCabinets"
storage.Parent = ServerStorage

local preview = Instance.new("Folder")
preview.Name = "ArcadeCabinets_Preview"
preview.Parent = Workspace

local SPACING = 7
for i, rarity in ipairs(ORDER) do
	local cabinet = buildCabinet(rarity)
	cabinet.Parent = storage

	local count = 0
	for _, d in ipairs(cabinet:GetDescendants()) do
		if d:IsA("BasePart") then
			count = count + 1
		end
	end

	local copy = cabinet:Clone()
	-- Face avant vers -Z : vu de face, +X est à gauche → Common à gauche, Mythic à droite
	copy:PivotTo(CFrame.new((3 - i) * SPACING, 0, 0))
	copy.Parent = preview

	print(string.format("[ArcadeCabinets] %-17s %2d parts", cabinet.Name, count))
end
print("[ArcadeCabinets] OK : ServerStorage.ArcadeCabinets + Workspace.ArcadeCabinets_Preview")
