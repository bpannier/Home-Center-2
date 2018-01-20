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
-- This Scene improves the heating plan which is part of every Home Center 2.
-- The heating plan defines fix temperatures for certain rooms for a given
-- time frame. This is good to heat up the rooms and cool down if not needed.
-- Also the heating plan do not take into account if someone is actually
-- present or not.
-- This Scene will make the heating plan more dynamic, when any of the 
-- configured motion sensors report movement the temperature will be increased
-- for a given time. The time can be different dependend if a presence 
-- variable is set or not. After the given time if no movement happend again
-- the orginial temperature in the heating plan will be set again.
--
-- Configure:
--   -add at the beginning of this file your motion detction devices (properties)
--   -add at the beginning of this file your presence variable (globals)
--   -the id's of your heating plans you like to build on (heatingIDList)
--   -the presence variables if you have any (presenceDetection)
--
-- This is the third implementation with the same goal of me. The other
-- implementations failed because of the Home Center 2 did not behave as 
-- expected. For example modifying the manual value in the heating plan resulted
-- in that not all devices in one heating plan were steered in the same way.
-- What seems to work now is to use the heating plan as guidance and to control
-- the devices directly. 
--
-- by Benjamin Pannier <github@ka.ro>
-- latest version: https://github.com/bpannier/Home-Center-2/tree/master/Dynamic%20Heating
------------------------------------------------------------------------------
------------------------------------------------------------------------------

local debug = 2

-- Add motion sensor id's to properties at the beginning of this scene in properties area

-- ID's of the heating scenes
local heatingIDList = {4, 6}

-- Global Variables which tells us about presence
local presenceDetection = { "BenStatus" } 

-- by how much should the temperature be increased
local increaseTemperatureBy = 2

-- for how long should the temperature be increased when a move was detected but no presence
local increaseTemperatureForMinutes = 60

-- For how long should the temperature be increased when a move was detected and presence was detected
local increaseTemperaturePresenceForMinutes = 120

------------------------------------------------------------------------------
------------------------------------------------------------------------------

-- How often does this script check the actual temperature
local checkTemperatureEveryMinutes = 5

-- Name of the global variable to store our state
-- States are 0: Not incremented temperature yet; >0 incremented until the given time; -1: turned off
local stateVariableName = "heatingState"

local sourceTrigger = fibaro:getSourceTrigger()
------------------------------------------------------------------------------
-- Functions
------------------------------------------------------------------------------
-- Debug Function
local function log(level, str)
  if debug >= level then
    fibaro:debug(str);
  end
end

-------------------------------------------------------------------------------
local function errorlog(str)
  fibaro:debug("<font color='red'>"..str.."</font>")
end

------------------------------------------------------------------------------
-- Setup the needed global variable as state holder
local function setup()
  local variable = fibaro:getGlobal(stateVariableName)
  if variable == nil then
    log(1, "Create variable: " .. stateVariableName)
    api.post("/globalVariables", {name=stateVariableName, isEnum=0})
    fibaro:setGlobal(stateVariableName, "0")
  end
end

-------------------------------------------------------------------------------
-- Calculate the Unix time of a given heating plan and a time.
local function getHeatingSlotEnd(now, heatingDataProps, timeOfDay)
  
  local today = os.date("*t", now)
  
  if heatingDataProps[timeOfDay]["hour"] < 5 then
    -- strange heatingplan starts at 5 in the morning, so it is already the next day
    today = os.date("*t", now+24*60*60)
  end
    
  local tmp = os.time({year=today["year"], month=today["month"], day=today["day"], hour=heatingDataProps[timeOfDay]["hour"], min=heatingDataProps[timeOfDay]["minute"]})
  
  log(6, "UNTIL: " .. timeOfDay .. " " .. os.date("%x %X", tmp) .. " -- " .. tostring(today["day"]) .. " " .. tostring(heatingDataProps[timeOfDay]["hour"]) .. " " .. tostring(heatingDataProps[timeOfDay]["minute"]) .. " -- " .. tostring(tmp))
  return tmp
end

-------------------------------------------------------------------------------
-- Find the matching heating plan slot for the given time.
local function getHeatingPlan(now, heatingDataProps)
  
  local dayName = string.lower(os.date("%A",now))
  
  log(6, "START: " .. dayName .. " " .. os.date("%x %X", now) .. " -- " .. tostring(now))
  
  if getHeatingSlotEnd(now, heatingDataProps[dayName], "night") <= now then
    -- it is night, get tomorrows morning as this is our end time
    tomorrowDayName = string.lower(os.date("%A",now + 24*60*60))
    return dayName, "night", getHeatingSlotEnd(now + 24*60*60, heatingDataProps[tomorrowDayName], "morning")
  end
  
  if getHeatingSlotEnd(now, heatingDataProps[dayName], "evening") <= now then
    return dayName, "evening", getHeatingSlotEnd(now, heatingDataProps[dayName], "night")
  end
  
  if getHeatingSlotEnd(now, heatingDataProps[dayName], "day") <= now then
    return dayName, "day", getHeatingSlotEnd(now, heatingDataProps[dayName], "evening")
  end
  
   if getHeatingSlotEnd(now, heatingDataProps[dayName], "morning") <= now then
    return dayName, "morning", getHeatingSlotEnd(now, heatingDataProps[dayName], "day")
  end
  
  -- not yet morning meaning it is still the night of the previous day
  local yesterdayDayName = string.lower(os.date("%A", now - 24*60*60))
  return yesterdayDayName, "night", getHeatingSlotEnd(today, heatingDataProps[dayName], "morning")
end

-------------------------------------------------------------------------------
-- Get the next slot in the heating plan after the given slot.
local function getNextSlotInHeatingPlan(dayName, timeOfDay)
  if timeOfDay == "morning" then
    return dayName, "day"
  elseif timeOfDay == "day" then
    return dayName, "evening"
  elseif timeOfDay == "evening" then
    return dayName, "night"
  else
    local day
    
    if dayName == "monday" then
      day = "tuesday"
    elseif dayName == "tuesday" then
      day = "wednesday"
    elseif dayName == "wednesday" then
      day = "thursday"
    elseif dayName == "thursday" then
      day = "friday"
    elseif dayName == "friday" then
      day = "saturday"
    elseif dayName == "saturday" then
      day = "sunday"
    else
      day = "monday"
    end
    
    return day, "morning"
  end
end

-------------------------------------------------------------------------------
-- Collect all needed data of a heating plan and associated devices.
local function getHeatingPanelDetailsFor(now, heatingID)
  
  local heatingDetails = {}
  local heatingData = api.get("/panels/heating/" .. tostring(heatingID))
  
  if heatingData == nil then
    errorlog("Can not get details for heating panel id " .. tostring(heatingID) .. ", edit scene configuration.")
    return nil
  end
  
  -- create details from the raw data
  heatingDetails["id"]                  = heatingData["id"]
  heatingDetails["name"]                = heatingData["name"]
  heatingDetails["handTemperature"]     = heatingData["properties"]["handTemperature"]
  heatingDetails["handTimestamp"]       = heatingData["properties"]["handTimestamp"]
  heatingDetails["vacationTemperature"] = heatingData["properties"]["vacationTemperature"]
  heatingDetails["currentTemperature"]  = heatingData["properties"]["currentTemperature"]
  heatingDetails["rooms"]               = heatingData["properties"]["rooms"]
  
  -- find the matching daytime and all details associated with it
  local dayName, timeOfDay, endsAt = getHeatingPlan(now, heatingData["properties"])
  
  heatingDetails["match_dayName"]     = dayName
  heatingDetails["match_timeOfDay"]   = timeOfDay
  heatingDetails["match_endsAt"]      = endsAt
  heatingDetails["match_temperature"] = heatingData["properties"][dayName][timeOfDay]["temperature"]
  
  -- we also need the temperature of the next slot
  local nextSlotDayName, nextSlotTimeOfDay = getNextSlotInHeatingPlan(dayName, timeOfDay)
  heatingDetails["match_temperatureNext"] = heatingData["properties"][nextSlotDayName][nextSlotTimeOfDay]["temperature"]

  heatingDetails["devices"] = {}
  
  -- find all thermostat devices associated with the given room id's, stores the id as key and the complete device data as value
  for _, i in ipairs(heatingDetails["rooms"]) do 
    local deviceList = api.get("/devices?baseType=com.fibaro.hvac&roomID=" .. tostring(i))
    
    for _, device in ipairs(deviceList) do
      heatingDetails["devices"][device["id"]] = device
    end
  end
  
  return heatingDetails
end

-------------------------------------------------------------------------------
-- check all given global presence variables if any of them is set
local function checkPresence()
  for key, variableName in ipairs(presenceDetection) do
    var = fibaro:getGlobal(variableName)
    if var == nil then
      errorlog("Global variable '" .. tostring(variableName) .. "' does not exist, edit scene configuration.")
    elseif tonumber(var) > 0 then
      return true
    end
  end
  return false
end

-------------------------------------------------------------------------------
-- Request to increase the temperature if not done already
local function increaseTemperature(maxUntilWhen)
  
  local now = os.time()
  
  -- go through all given heating scenes
  for key, heatingID in ipairs(heatingIDList) do
    local logAppend = ""
    local heatingDetails = getHeatingPanelDetailsFor(now, heatingID)
    
    local temperature = heatingDetails["match_temperature"] + increaseTemperatureBy
    local untilWhen   = now + increaseTemperatureForMinutes * 60
    
    if checkPresence() then
      untilWhen = now + increaseTemperaturePresenceForMinutes * 60
      logAppend = logAppend .. "(presence) "
    end
    
    if maxUntilWhen ~= nil and maxUntilWhen <= untilWhen then
      untilWhen = maxUntilWhen
      logAppend = logAppend .. "(maxUntilWhen) "
    end
    
    if untilWhen <= now then
      -- nothing to do for us
      return
    end
    
    -- remember until when we intend to increase the temperature
    fibaro:setGlobal(stateVariableName, tostring(untilWhen))
    
    if untilWhen > heatingDetails["match_endsAt"] then
      -- the temperature change would overlap the next slot in the heating pannel
      
      if heatingDetails["match_endsAt"] <= now + checkTemperatureEveryMinutes * 60 then
        -- the temperature in the heating plan would change before we wake up again.
        -- we already set the temperature of the next slot in the heating plan.
        temperature = heatingDetails["match_temperatureNext"] + increaseTemperatureBy
        -- making sure we can set the right timing in the next round
        untilWhen = now + checkTemperatureEveryMinutes * 60 * 2
        
        logAppend = logAppend .. "(next slot) "
      else
        -- we have enough time to set the right temperature and timing when we wake up again
        untilWhen = heatingDetails["match_endsAt"] - 1
        logAppend = logAppend .. "(shortened) "
      end
    end
    
    if heatingDetails["vacationTemperature"] > 0 then
      temperature = heatingDetails["vacationTemperature"]
      logAppend = logAppend .. "(vacation) "
    end
    
    -- for debugging only
    if (sourceTrigger['type'] == 'property') then
      logAppend = logAppend .. "(D:" .. sourceTrigger['deviceID'] .. ") "
    end
    
    local deviceListStr = ""
    
    -- go through all devices which are part of this heating plan
    for deviceID, device in pairs(heatingDetails["devices"]) do
      
      -- debug string is device dependend
      local logAppendDevice = logAppend
        
      if device["properties"]["targetLevel"] ~= temperature then
        -- intendet temperature is not the same as the one which is set, set a new one
        
        fibaro:call(deviceID, "setTargetLevel", tostring(temperature))
        fibaro:call(deviceID, "setTime", tostring(untilWhen))
        
        -- debug
        deviceListStr = deviceListStr .. tostring(deviceID) .. " "
        logAppend = logAppend .. "S "
        
      elseif device["properties"]["timestamp"] <= now + checkTemperatureEveryMinutes * 60 then
        -- device would change temperature before next wake up, extend time stamp.
        -- we do not always extend the time to avoid too many events in the system as with
        -- every touch of the timestamp HC2 triggers an update event for many (all?) device properties.
        
        fibaro:call(deviceID, "setTime", tostring(untilWhen))
        
        -- debug
        deviceListStr = deviceListStr .. tostring(deviceID) .. " "
        logAppendDevice = logAppendDevice .. "(extend) "
        logAppend = logAppend .. "X "
      end
      
      log(5, "Device:'" .. device['name'] .. "' (" ..  tostring(deviceID) .. ") is:" .. tostring(device["properties"]["value"]) .. " target:" .. tostring(device["properties"]["targetLevel"]) .. " should:" .. tostring(temperature) .. " until:" .. os.date("%x %X", device["properties"]["timestamp"]) .. " " .. logAppendDevice)
    end
    
    if deviceListStr ~= "" then
      log(1, "Temperature changed for '" .. heatingDetails["name"] .. "' to " .. tostring(temperature) .. " until " .. os.date("%x %X", untilWhen) .. " (" .. untilWhen .. ") for id: " .. deviceListStr .. logAppend)
    else 
      log(4, "Checked heating plan '" .. heatingDetails["name"] .. "' set:" .. tostring(temperature) .. " until " .. os.date("%x %X", untilWhen) .. " " .. logAppend)
    end
  end
end

-------------------------------------------------------------------------------
-- Resets always the temperature, independent of the current state unless turned off
local function resetTemperature()
  local now = os.time()
  local state = fibaro:getGlobal(stateVariableName)
  local untilWhen = tonumber(state)
  
  -- go through all given heating scenes
  for key, heatingID in ipairs(heatingIDList) do
    local deviceListStr = ""
    local heatingDetails = getHeatingPanelDetailsFor(now, heatingID)
    
    -- go through all devices which are part of this heating plan
    for deviceID, device in pairs(heatingDetails["devices"]) do
      if device["properties"]["targetLevel"] ~= heatingDetails["match_temperature"] then
        -- there is some other temperature set, reset it
        deviceListStr = deviceListStr .. tostring(deviceID) .. " "
        --device["properties"]["targetLevel"] = heatingDetails["match_temperature"]
        fibaro:call(deviceID, "setTargetLevel", tostring( heatingDetails["match_temperature"]))
      end
    end
    
    if deviceListStr ~= "" then
      log(1, "Reset temperature to " .. tostring(heatingDetails["match_temperature"]) .. " for '" .. heatingDetails["name"] .. "' for id: " .. deviceListStr)
    end
  end
  
  -- reset state
  fibaro:setGlobal(stateVariableName, "0")
end

-------------------------------------------------------------------------------
-- Validate if we should have increased the temperature
local function checkTemperature()
  local now = os.time()
  local state = fibaro:getGlobal(stateVariableName)
  local untilWhen = tonumber(state)
  
  if untilWhen == 0 then
    return
  elseif untilWhen <= now then
    log(1, "Time is up.")
    resetTemperature()
    return
  end
  
  increaseTemperature(untilWhen)
end

-------------------------------------------------------------------------------
-- check every X minutes if the temperature is still ok
local function checkLoop()
  log(4, "Wake up.")
  checkTemperature()
  setTimeout(checkLoop, checkTemperatureEveryMinutes * 60 * 1000)
end

-------------------------------------------------------------------------------
-- Main loop starts here
-------------------------------------------------------------------------------

setup()

if sourceTrigger['type'] == 'autostart' then
  local state = fibaro:getGlobal(stateVariableName)
  local untilWhen = tonumber(state)
    
  if untilWhen > 0 then
    log(1, 'Trigger: Autostart, system is already running until ' .. os.date("%x %X", untilWhen))
  else    
    log(1, 'Trigger: Fresh Autostart.')
  end
  checkLoop()
  
elseif sourceTrigger['type'] == 'global' then
  
  -- a global variable has changed, check if we need to reset the temperature
  if checkPresence() == false then      
    log(1, "No presence detected any longer, reset temperature.")
    resetTemperature()
  end
else
  -- motion detected or manual call or from an other scene
  
  local params = fibaro:args()
  
  if (params) then
    -- this scene has been called with parameters
    for k, v in ipairs(params) do
      if (v.reset) then
        log(1, 'External reset call received')
        resetTemperature()
      end
    end
  else
    if (sourceTrigger['type'] == 'property') then
      log(4,'Trigger: Source device = ' .. sourceTrigger['deviceID'] .. ' "' .. sourceTrigger['propertyName'].. '"')
    end
    -- no parameters, increase the temperature or increase the time
    increaseTemperature()
  end
end
