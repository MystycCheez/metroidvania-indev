local SECTOR_SPECIAL_EXIT = 8192
local SECTOR_SPECIAL_EGGCAPSULE = 144

local LINEDEF_SPECIAL_EXIT = 462

local THINGTYPE_SIGNPOST = 501
local THINGTYPE_EGGMOBILE = 200
local THINGTYPE_FANG_WAYPOINT = 294

local player_old = {cmd = {}, mo = {}}
local player_default = {cmd = {}}
local signpost = {}

local signpostZ = 0
local signpostAngle = 0

local zDistance = 0
local viewAngleDifference = 0
local momentumAngleDifference = 0

local loadedOnce = false
local iteratedOnce = false

local exitNormal = true

local function calculateAbsoluteZ(mapthing)
    local subsector = R_PointInSubsector(mapthing.x * FRACUNIT, mapthing.y * FRACUNIT)
    return (mapthing.z * FRACUNIT) + subsector.sector.floorheight
end

local function mapthingFromThingType(type)
    for thing in mapthings.iterate do
        if thing.type == type then return thing end
    end
end

local function getTagFromLinedefType(type) -- returns first instance of found type
    for line in lines.iterate do
        if line.tag ~= 0 then
            -- print("line.tag: " .. line.tag)
            print("line.special: " .. line.special)
        end
        if line.special == type then
            return line.tag
        end
    end
end

local function resetPlayerOld()
    player_old.mo.momx = 0
    player_old.mo.momy = 0
    player_old.mo.momz = 0
    player_old.state = player_default.state
    player_old.pflags = player_default.pflags
    zDistance = 0
    momentumAngleDifference = 0
    viewAngleDifference = 0
    player_old.cmd.buttons = player_default.cmd.buttons
    player_old.cmd.forwardmove = player_default.cmd.forwardmove
    player_old.cmd.sidemove = player_default.cmd.sidemove
end

local function initPlayerstate() -- Initializes the player.mo.momx/y/z
    -- Doing this is to prevent nil problems (iirc)
    player_old.mo.momx = players[0].mo.momx
    player_old.mo.momy = players[0].mo.momy
    player_old.mo.momz = players[0].mo.momz
    player_old.mo.state = players[0].mo.state
    player_old.pflags = players[0].pflags
    player_old.cmd.buttons = players[0].cmd.buttons
    player_old.cmd.forwardmove = players[0].cmd.forwardmove
    player_old.cmd.sidemove = players[0].cmd.sidemove
end

local function initPlayerDefault()
    player_default.state = players[0].state
    player_default.pflags = players[0].pflags
    player_default.cmd.buttons = players[0].cmd.buttons
    player_default.cmd.forwardmove = players[0].cmd.forwardmove
    player_default.cmd.sidemove = players[0].cmd.sidemove
end

local function initSignpost() -- Initializes the z and angle of the singpost
    signpost = mapthingFromThingType(THINGTYPE_SIGNPOST)
    signpostZ = calculateAbsoluteZ(signpost)
    print("thing angle: " .. signpost.angle)
    print("thing angle * ANG1: " .. signpost.angle * ANG1)
    signpostAngle = signpost.angle * ANG1
end

local function saveFlags(player)
    player_old.pflags = player.pflags & ~PF_FINISHED
end

local function loadFlags()
    local player = players[0]
    player.pflags = player_old.pflags
end

local function saveState(player)
    player_old.mo.state = player.mo.state
end

local function loadState()
    local player = players[0]
    player.mo.state = player_old.mo.state
end

local function saveMomentum(player)
    player_old.mo.momx = player.mo.momx
    player_old.mo.momy = player.mo.momy
    player_old.mo.momz = player.mo.momz
end

local function loadRelativeMomentum()
    local player = players[0]
    local magnitude = P_AproxDistance(player_old.mo.momx, player_old.mo.momy)
    player.mo.momx = FixedMul(magnitude, cos(player.mo.angle + momentumAngleDifference))
    player.mo.momy = FixedMul(magnitude, sin(player.mo.angle + momentumAngleDifference))
    player.mo.momz = player_old.mo.momz
end

local function saveViewAngle(player)
    viewAngleDifference = player.mo.angle - (max(ANGLE_180, signpostAngle) - min(ANGLE_180, signpostAngle))
end

local function applyViewAngle()
    local player = players[0]
    player.mo.angle = player.mo.angle + viewAngleDifference
end

local function saveMomentumAngle(player)
    local angle = R_PointToAngle2(0, 0, player.mo.momx, player.mo.momy)
    momentumAngleDifference = angle - (max(ANGLE_180, signpostAngle) - min(ANGLE_180, signpostAngle))
end

local function saveZDistance(player)
    zDistance = abs(player.mo.z - signpostZ)
end

local function addZDistance()
    local player = players[0]
    player.mo.z = player.mo.z + zDistance
end

local function saveInput(player)
    player_old.cmd.buttons = player.cmd.buttons
    player_old.cmd.forwardmove = player.cmd.forwardmove
    player_old.cmd.sidemove = player.cmd.sidemove
end

local function loadInput()
    local player = players[0]
    player.cmd.buttons = player_old.cmd.buttons
    player.cmd.forwardmove = player_old.cmd.forwardmove
    player.cmd.sidemove = player_old.cmd.sidemove
end

local function exitOverride(player)
    if player.mo.subsector.sector.special == SECTOR_SPECIAL_EXIT then
        saveMomentum(player)
        saveMomentumAngle(player)
        saveViewAngle(player)
        saveZDistance(player)
        saveState(player)
        saveFlags(player)
        saveInput(player)
        -- G_SetCustomExitVars(player.mo.subsector.sector.tag, 2) -- for future
        G_SetCustomExitVars(nil, 2)
        G_ExitLevel()
    end
end

local function exitOverrideBoss(player)
    resetPlayerOld()
    -- G_SetCustomExitVars(player.mo.subsector.sector.tag, 1) -- for future
    G_SetCustomExitVars(nil, 1)
end

local function mobjDeathHandler(target, inflictor, source, damagetype)
    resetPlayerOld()
end

local function playerThinkHandler(player)
    if exitNormal == true then
        exitOverride(player)
    else
        exitOverrideBoss(player)
    end
end

local function mapLoadHandler()
    if loadedOnce == true and exitNormal == true then
        -- loadRelativeCoords() -- only for non vanilla
        loadRelativeMomentum()
        applyViewAngle()
        addZDistance()
        loadState()
        loadFlags()
        loadInput()
    else
        initPlayerDefault()
    end

    exitNormal = true
    for mapthing in mapthings.iterate do
        if mapthing.type >= THINGTYPE_EGGMOBILE and mapthing.type <= THINGTYPE_FANG_WAYPOINT then
            exitNormal = false
        end
    end

    initPlayerstate()
    if exitNormal == true then
        initSignpost()
    end

    loadedOnce = true
end

addHook("MobjDeath", mobjDeathHandler, MT_PLAYER)
addHook("PlayerThink", playerThinkHandler)
addHook("MapLoad", mapLoadHandler)