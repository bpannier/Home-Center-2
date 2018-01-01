--[[
%% properties
89 value
43 value
160 value
148 value
167 value
%% autostart
%% events
%% globals
BenStatus
--]]

------------------------------------------------------------------------------
------------------------------------------------------------------------------
-- 
-- Home Center 2 Lua Scene which does dynamic heating based on HC2 heating
-- plan. When movement is detected it takes the actual temperature and adds
-- some degrees on it for the next hours. All values can be configured.
-- Add all motion sensores in the header of the script as well.
--
-- by Benjamin Pannier <github@ka.ro>
------------------------------------------------------------------------------
------------------------------------------------------------------------------

local debug = true

-- Add motion sensor id's to properties at the beginning of this scene in properties area

-- ID's of the heating scenes
local heatingIDList = {4, 6}

-- Global Variables which tells us about presence
local presenceDetection = { "BenStatus" } 
local checkTimer = 5 * 60 * 1000

-- by how much should the temperature be increased
local increaseTemperatureBy = 2

-- for how long should the temperature be increased when a move was detected but no presence
local increaseTemperatureForMinutes = 60

-- For how long should the temperature be increased when a move was detected and presence was detected
local increaseTemperaturePresenceForMinutes = 120

-- When no presence was detected any longer we reset the temperature.
-- Before we reset we wait for giving seconds so that we can use this behavior also for night setting and have enough time to go to bed.
-- If set to 0 we switch this behavior off.
local waitBeforeResetAfterPresenceClearing = 120

------------------------------------------------------------------------------
-- Functions
------------------------------------------------------------------------------
local function log(str)
  if debug then
    fibaro:debug(str);
  end
end

-------------------------------------------------------------------------------
local function errorlog(str)
  fibaro:debug("<font color='red'>"..str.."</font>")
end

-------------------------------------------------------------------------------
-- Get the name of a given heating scene
local function getHeatingSceneName(id)
  structure = api.get("/panels/heating/" .. tostring(id) )
  
  if structure["name"] == nil then
    return "id " .. tostring(id)
  end
  
  return structure["name"]
end

-------------------------------------------------------------------------------
local function resetTemperature()
  local didReset = false
  
  for key, heatingID in ipairs(heatingIDList) do
    heatingData = api.get("/panels/heating/" .. tostring(heatingID))
    
    if heatingData ~= nil and heatingData["properties"]["handTemperature"] > 0 then
      -- we only can set the time short so that the system resets the temp soon
      heatingData["properties"]["handTimestamp"] = os.time() + 1
      
      local name = getHeatingSceneName(heatingID)
      
      log("Reset temperature for '" .. name .. "'")
      api.put("/panels/heating/" .. tostring(heatingID), heatingData)
      didReset = true
    end
  end
  
  if didReset then
    -- wait until reset was done
    fibaro:sleep(3 * 1000)
    log("Wakeup and run.")
  end
end

-------------------------------------------------------------------------------
local function checkPresence()
  for key, variableName in ipairs(presenceDetection) do
    var = fibaro:getGlobal(variableName)
    if tonumber(var) > 0 then
      return true
    end
  end
  return false
end

-------------------------------------------------------------------------------
local function increaseTemperature()
  for key, heatingID in ipairs(heatingIDList) do
    heatingData = api.get("/panels/heating/" .. tostring(heatingID))
    
    local name = getHeatingSceneName(heatingID)
    
    if heatingData == nil then
      errorlog("Heating panel '" .. name .. "' not found.")
    else
      
      if heatingData["properties"]["vacationTemperature"] == 0 then
        -- only when vacation is not set then we go further 
        
        local forHowLong = increaseTemperatureForMinutes
        
        if checkPresence() then
          forHowLong = increaseTemperaturePresenceForMinutes
        end
        
        if heatingData["properties"]["handTemperature"] == 0 then
          -- only set new temperature when not already done as we need to wait for switch in heating plan
          
          heatingData["properties"]["handTemperature"] = heatingData["properties"]["currentTemperature"] + increaseTemperatureBy
          log("Increase temperature for '" .. name .. "' from " .. tostring(heatingData["properties"]["currentTemperature"]) .. " to " .. tostring(heatingData["properties"]["handTemperature"]) .. " for " .. tostring(forHowLong) .. " minutes.")
        end
        
        -- reset in any way the time
        heatingData["properties"]["handTimestamp"] = os.time() + forHowLong * 60
        
        api.put("/panels/heating/" .. tostring(heatingID), heatingData)
      end
    end
  end
end

-------------------------------------------------------------------------------
-- Main loop starts here
-------------------------------------------------------------------------------

local sourceTrigger = fibaro:getSourceTrigger()

if sourceTrigger['type'] == 'autostart' then
  log('Trigger: Autostart')
  resetTemperature()
elseif sourceTrigger['type'] == 'global' then
  
  -- a global variable has changed, check if we need to reset the temperature
  
  if checkPresence() == false then
    if waitBeforeResetAfterPresenceClearing > 0  then
      log("No presence detected any longer, reset temperature soon.")
      fibaro:sleep(waitBeforeResetAfterPresenceClearing * 1000)
      resetTemperature()
    end
  else
    increaseTemperature()
  end
  
else
  increaseTemperature()
end

