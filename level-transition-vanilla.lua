---Thank you to Zipper, Monster Iestyn, Lactozilla for helping me with Lua
---during the making of this script

local SECTOR_SPECIAL_EXIT = 8192

local THINGTYPE_SIGNPOST = 501
local THINGTYPE_EGGMOBILE = 200
local THINGTYPE_FANG_WAYPOINT = 294

local player_old = {cmd = {}, mo = {}, powers = {}}
local player_default = {cmd = {}, powers = {}}
local signpost = {}

local signpostZ = 0
local signpostAngle = 0

local zDistance = 0
local viewAngleDifference = 0
local momentumAngleDifference = 0

local loadedOnce = false

local levelNormal = true
local prevLevelNormal = true

---Copies table_a into table_b
---
---Does not copy sub tables
---
---Thanks to Flame (mars543 on Discord) for helping me with this function
---@param table_a table
---@param table_b table
local function copyTable(table_a, table_b)
    for i = 0, #table_a - 1 do
        table_b[i] = table_a[i]
    end
end

---Returns mapthing.z * FRACUNIT + sector floorheight
---@param mapthing mapthing_t
---@return fixed_t
local function calculateAbsoluteZ(mapthing)
    local subsector = R_PointInSubsector(mapthing.x * FRACUNIT, mapthing.y * FRACUNIT)
    return (mapthing.z * FRACUNIT) + subsector.sector.floorheight
end

---Returns thing from thingtype number
---
---Returns empty mapthing if mapthing of specified type is not found
---
---TODO: Determine how to typecast empty table to mapthing_t
---@param type integer
---@return mapthing_t
local function mapthingFromThingType(type)
    local empty = {}
    for thing in mapthings.iterate do
        if thing.type == type then return thing end
    end
    print("WARNING: mapthing type " .. type .. " not found!")
    print("Returning empty mapthing.")
    return empty
end

---Resets all potentially modified player data
local function resetPlayerOld()
    player_old.mo.momx = 0
    player_old.mo.momy = 0
    player_old.mo.momz = 0
    player_old.state = player_default.state
    player_old.pflags = player_default.pflags
    player_old.cmd.buttons = player_default.cmd.buttons
    player_old.cmd.forwardmove = player_default.cmd.forwardmove
    player_old.cmd.sidemove = player_default.cmd.sidemove
    player_old.rings = player_default.rings
    copyTable(player_default.powers, player_old.powers)
    zDistance = 0
    momentumAngleDifference = 0
    viewAngleDifference = 0
end

---Initializes the player.mo.momx/y/z
---Doing this is to prevent nil problems (iirc)
local function initPlayerstate()
    player_old.mo.momx = players[0].mo.momx
    player_old.mo.momy = players[0].mo.momy
    player_old.mo.momz = players[0].mo.momz
    player_old.mo.state = players[0].mo.state
    player_old.pflags = players[0].pflags
    player_old.cmd.buttons = players[0].cmd.buttons
    player_old.cmd.forwardmove = players[0].cmd.forwardmove
    player_old.cmd.sidemove = players[0].cmd.sidemove
    player_old.rings = players[0].rings
    copyTable(players[0].powers, player_old.powers)
end

---Initializes playerstate to be default (vanilla behavior)
local function initPlayerDefault()
    player_default.state = players[0].state
    player_default.pflags = players[0].pflags
    player_default.cmd.buttons = players[0].cmd.buttons
    player_default.cmd.forwardmove = players[0].cmd.forwardmove
    player_default.cmd.sidemove = players[0].cmd.sidemove
    player_default.rings = players[0].rings -- NOTE: handle boss rings
    copyTable(players[0].powers, player_default.powers)
end

---Initializes the z and angle of the singpost
local function initSignpost()
    signpost = mapthingFromThingType(THINGTYPE_SIGNPOST)
    signpostZ = calculateAbsoluteZ(signpost)
    signpostAngle = signpost.angle * ANG1
end

---@param player player_t
local function saveFlags(player)
    player_old.pflags = player.pflags & ~PF_FINISHED
end

local function loadFlags()
    local player = players[0]
    player.pflags = player_old.pflags
end

---@param player player_t
local function saveState(player)
    player_old.mo.state = player.mo.state
end

local function loadState()
    local player = players[0]
    player.mo.state = player_old.mo.state
end

---@param player player_t
local function saveRings(player)
    player_old.rings = player.rings
end

---Sets ring count to what it was at the end of the previous level
---
---If current level is a boss level and player has less than 10 rigns, then set ring
---count to 10 (aka do nothing). If the player has more than 10 rings, then set ring
---count to that number no matter the level
local function loadRings()
    local player = players[0]
    if levelNormal == true then player.rings = player_old.rings end
    if levelNormal == false and player_old.rings > 10 then player.rings = player_old.rings end
end

---@param player player_t
local function savePowers(player)
    copyTable(player.powers, player_old.powers)
end

local function loadPowers()
    local player = players[0]
    copyTable(player_old.powers, player.powers)
    P_SpawnShieldOrb(player)
end

---@param player player_t
local function saveMomentum(player)
    player_old.mo.momx = player.mo.momx
    player_old.mo.momy = player.mo.momy
    player_old.mo.momz = player.mo.momz
end

---Adds momentum relative to the player's stating angle + the difference in angle between player momentum and signpost angle.
---
---Credit to Zipper for giving me the base of this function.
---
---This code is theirs except for the `+ momentumAngleDifference`
local function addRelativeMomentum()
    local player = players[0]
    local magnitude = P_AproxDistance(player_old.mo.momx, player_old.mo.momy)
    player.mo.momx = FixedMul(magnitude, cos(player.mo.angle + momentumAngleDifference))
    player.mo.momy = FixedMul(magnitude, sin(player.mo.angle + momentumAngleDifference))
    player.mo.momz = player_old.mo.momz
end

---@param player player_t
local function calcViewAngleDifference(player) -- Calculates difference between player view angle and signpost angle
    viewAngleDifference = player.mo.angle - (max(ANGLE_180, signpostAngle) - min(ANGLE_180, signpostAngle))
end

local function applyViewAngle()
    local player = players[0]
    player.mo.angle = player.mo.angle + viewAngleDifference
end

---@param player player_t
local function calcMomentumAngleDifference(player) -- Calculates difference between player momentum angle and signpost angle
    local angle = R_PointToAngle2(0, 0, player.mo.momx, player.mo.momy)
    momentumAngleDifference = angle - (max(ANGLE_180, signpostAngle) - min(ANGLE_180, signpostAngle))
end

---Calculates the distance between the player z and the signpost z
---@param player player_t
local function calcZDistance(player)
    zDistance = abs(player.mo.z - signpostZ)
end

local function addZDistance()
    local player = players[0]
    player.mo.z = player.mo.z + zDistance
end

---@param player player_t
local function saveInput(player)
    player_old.cmd.buttons = player.cmd.buttons
    player_old.cmd.forwardmove = player.cmd.forwardmove
    player_old.cmd.sidemove = player.cmd.sidemove
end

---This doesnt always work for some reason - TODO: FIX
local function loadInput()
    local player = players[0]
    player.cmd.buttons = player_old.cmd.buttons
    player.cmd.forwardmove = player_old.cmd.forwardmove
    player.cmd.sidemove = player_old.cmd.sidemove
end

---Saves all relevant data for transfering between normal levels,
---sets custom exit params, then force exits the level
---@param player player_t
local function exitOverrideNormal(player)
    saveMomentum(player)
    calcMomentumAngleDifference(player)
    calcViewAngleDifference(player)
    calcZDistance(player)
    saveState(player)
    saveFlags(player)
    saveInput(player)
    saveRings(player)
    savePowers(player)
    G_SetCustomExitVars(nil, 2)
    G_ExitLevel()
end

---Saves all relevant data for transfering between boss level and normal level.
---Sets exit parameters
---@param player player_t
local function exitOverrideBoss(player)
    saveRings(player)
    savePowers(player)
    G_SetCustomExitVars(nil, 2)
end


local function loadLevelNormal()
    addRelativeMomentum()
    applyViewAngle()
    addZDistance()
    loadState()
    loadFlags()
    loadInput()
    loadRings()
    loadPowers()
end

local function loadLevelBoss()
    loadRings()
    loadPowers()
end

---Resets player data to default when the player dies
---
---Unused parameters
---@param target nil
---@param inflictor nil
---@param source nil
---@param damagetype nil
local function mobjDeathHandler(target, inflictor, source, damagetype)
    resetPlayerOld()
end

---If the level is normal, then it checks for if the player is on the exit sector or not.
---If the player is in the level sector, execute `exitOverrideNormal()`
---@param player player_t
local function playerThinkHandler(player)
    if levelNormal == true and player.mo.subsector.sector.special == SECTOR_SPECIAL_EXIT then
        exitOverrideNormal(player)
    end
end

---Checks if the level is a boss level by iterating through the mapthings and
---checking if the thingtype is between 200 and 294
---(Egg Mobile and Fang Waypoint).
---@return boolean
local function bossLevelCheck()
    for mapthing in mapthings.iterate do
        if mapthing.type >= THINGTYPE_EGGMOBILE and mapthing.type <= THINGTYPE_FANG_WAYPOINT then
            return true
        end
    end
    return false
end

---Initializes default player data before anything else only once.
---Executes `bossLevelCheck()` to see if the current level is a boss level or a normal level.
---Checks if any level has been loaded yet. If not, then load default player data.
---If so, checks if the current level is a normal level. 
---If not, then load previous player data via `loadLevelBoss`.
---Then it checks if the previous level was normal. 
---If not, then load previous player data via `loadLevelBoss`.
---If all of those conditions are met, apply/load data from the previous level into current.
---After all of that, initialize the playerstate for the next map to compare data again.
---Finally, if the level is a normal level, then initialize data for the signpost
local function mapLoadHandler()
    if loadedOnce == false then initPlayerDefault() end -- initialize default player data
    if bossLevelCheck() == true then -- is the current level a boss level?
        levelNormal = false
        prevLevelNormal = false
    else levelNormal = true end
    if loadedOnce == true then -- checks if any map has been loaded\
        if levelNormal == true then -- is the current level a normal (non boss) level?
           if prevLevelNormal == true then -- was the previous level a normal level?
                loadLevelNormal()
           else loadLevelBoss() end
           prevLevelNormal = true
        else loadLevelBoss() end
    else initPlayerDefault() end

    initPlayerstate()
    if levelNormal == true then initSignpost() end

    loadedOnce = true
end

---@param mobj mobj_t
local function mobjSpawnHandler(mobj)
    if levelNormal == false then
        if mobj.type >= MT_FLICKY_01 and mobj.type <= MT_SECRETFLICKY_02_CENTER then
            exitOverrideBoss(players[0])
        end
    end
end

addHook("MobjDeath", mobjDeathHandler, MT_PLAYER)
addHook("PlayerThink", playerThinkHandler)
addHook("MapLoad", mapLoadHandler)
addHook("MobjSpawn", mobjSpawnHandler, MT_NULL)