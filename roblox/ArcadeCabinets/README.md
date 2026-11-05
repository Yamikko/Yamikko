# Bornes d'arcade (Common → Mythic)

## Installation dans Roblox Studio
1. Ouvrir `BuildArcadeCabinets.lua`, tout copier.
2. Studio > View > **Command Bar**, coller, Entrée.
3. Résultat :
   - `ServerStorage/ArcadeCabinets/Cabinet_{Common,Rare,Epic,Legendary,Mythic}` (templates)
   - `Workspace/ArcadeCabinets_Preview` : une copie de chaque, alignées de gauche à droite vues de face.

Le script est ré-exécutable (il remplace les versions précédentes). Les effets ne tournent
qu'en **Play** : `FX/CabinetFX` est un Script en `RunContext = Client`. Il s'exécute sur chaque client
dès que la borne est dans le Workspace, et rien n'est répliqué.

Pour placer une borne en jeu (côté serveur) :
```lua
local c = game.ServerStorage.ArcadeCabinets.Cabinet_Epic:Clone()
c:PivotTo(CFrame.new(10, 0, 0))   -- pivot au sol, au centre de l'empreinte ; face avant = -Z
c.Parent = workspace
```

## Structure d'une borne
`Cabinet_X` (Model, PrimaryPart `Base`, attributs `Rarity` / `Tier`, streaming Atomic)
- `Base`, `Body` (flancs, caisson, trappe, liserés), `Screen` (Bezel, ScreenFrame, Glass + SurfaceGui + lumières),
  `ControlPanel`, `Marquee` (PrimaryPart `MarqueeBox`), `FX` (Script, FXRoot, émetteurs, Highlight)
- Tout est anchored. Seuls `Base` et les parts structurelles de `Body` sont CanCollide.
- Nombre de parts : Common 34, Rare 54, Epic 58, Legendary 59, Mythic 57.

## Preview hors Studio (`tools/`)
`tools/preview.sh <node_modules avec three@0.160 et fengari> <dossier sortie>` exécute le builder dans
une émulation de l'API Roblox (`roblox_mock.lua`). Celle-ci valide les classes, les propriétés, les Enums et les cibles de Tween,
fait tourner les scripts FX avec une horloge simulée, puis produit des rendus three.js approximatifs (`renders/`).
