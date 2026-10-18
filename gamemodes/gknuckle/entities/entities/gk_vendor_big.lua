AddCSLuaFile()

-- White Knuckle's big late-game vending machine (Prop_VendingMachine_Big):
-- the same machine as gk_vendor with eight item slots in a 4x2 grid, the
-- roach dial in the small screen top right and the inserter on the right.
-- Model: models/gknuckle/items/vendor_big.mdl (origin bottom centre, front +X),
-- markers from the WK prefab (Unity (x, y, z) m -> model (z, -x, y) * 39.37).
ENT.Type = "anim"
ENT.Base = "gk_vendor"
ENT.PrintName = "Vending Machine (Big)"
ENT.Spawnable = true
ENT.Category = "gKnuckle"
ENT.GKModel = "models/gknuckle/items/vendor_big.mdl"
ENT.GKDepth = 60

local X = 32.6 -- the front panel
local COLS = { -31.7, -15.6, -0.2, 15.8 } -- WK x 0.806, 0.395, 0.004, -0.402
local ROWS = { 83.2, 55.5 }               -- WK y 2.112, 1.41
local slots = {}
for _, z in ipairs(ROWS) do
    for _, y in ipairs(COLS) do slots[#slots + 1] = Vector(X, y, z) end
end

ENT.Layout = {
    slots = slots,
    slotSize = 13,
    inserter = Vector(27.1, 34.6, 81.1),  -- WK Inserter Slot (-0.878, 2.06, 0.688)
    spawn = Vector(24, 0, 24),            -- the tray across the bottom
    -- The wheels (WK hundreds/tens/ones at x -0.481/-0.681/-0.881, y 2.721).
    dial = { pos = Vector(X, 15.4, 110.6), step = 7.9, w = 7, h = 7 },
}
