--[[
%% properties
89 value
43 value
160 value
148 value
138 value
132 value
167 value
172 value
135 value
192 value
%% autostart
%% events
%% globals
BenStatus
DisableAlarm
--]]

------------------------------------------------------------------------------
------------------------------------------------------------------------------
-- 
-- This Home Center 2 Lua Scene is a better replacement for the HC alarm center.
-- It checks if a presence is detected through given global variables. If
-- presence is detected the system will not be armed. If no presence is 
-- detected the system is armed after given seconds unless there is movement
-- detected. Any movement can delay arming the system, if not turned off. We
-- use this for our cleaning help for example. Once the system is armed, any  
-- motion or door will fire an alarm. One global variable can be used for manual 
-- disarming.
-- I suggest not to edit this script to react on an alarm. There is an 
-- other script which can be used to react on an alarm in the same directory on
-- Github.
--
-- Add all your motion, door sensor device ids and the global presence 
-- variables at the beginning of this script.
--
-- by Benjamin Pannier <github@ka.ro>
-- latest version: https://github.com/bpannier/Home-Center-2/tree/master/Alarm%20Runner
------------------------------------------------------------------------------
------------------------------------------------------------------------------

local debug = true

-- Global variables which are check for presence, need to be a number and > 0 is true
-- One varaible could also be used for manual disabling the alarm watching, do not forget to enable it again
local presenceDetection = { "BenStatus", "DisableAlarm" } 
local motionSensors = {89, 43, 160, 148, 167, 192}
local doorSensors = {138,132,172,135}

-- even when the main presents variable is not set any longer it might be ok that there is still some
-- movement for a while before arm. I use this for our cleaning help who can not arm or disarm the alarm
local secondsWhereMovementIsOKBeforeArm = 10 * 60

-- alarm might not get fired immediately to give someone the chance to disarm manually
local secondsBeforeAlarmGetFired = 2 * 60 

-- how often should the alarm be checked without any event occurs, usually 5 sec is good enough
local runFrequencyInSeconds = 5

-- DO NOT EDIT AFTER HERE

local alarmVariable = "alarm"
local storeStateVariable = "alarm_state"

-- we could do this with multiple global variables also we like only to use one
local runtime = { state = "", stateChangeTime = 0, reason = "" }

local sourceTrigger = fibaro:getSourceTrigger()

------------------------------------------------------------------------------
-- Functions
------------------------------------------------------------------------------

local function log(str)
  if debug then
    fibaro:debug(str);
  end
end

------------------------------------------------------------------------------
local function errorlog(str)
  fibaro:debug("<font color='red'>"..str.."</font>")
end

------------------------------------------------------------------------------
local function getDisarmedState()
  return "disarmed"
end

------------------------------------------------------------------------------
local function getArmedState()
  return "armed"
end

------------------------------------------------------------------------------
local function getAlarmDelayedState()
  return "alarm-delay"
end

------------------------------------------------------------------------------
local function howManySecondsSinceLastStateChange()
  return os.time() - runtime.stateChangeTime
end

------------------------------------------------------------------------------
local function getState()
  return runtime.state
end

------------------------------------------------------------------------------
local function setDisarmedState()
  if runtime.state ~= getDisarmedState() then
      log("Set state to DISARMED.")
  end
  fibaro:setGlobal(alarmVariable, "0");
  runtime.state = getDisarmedState()
  runtime.stateChangeTime = os.time()
  runtime.reason = ""
end

------------------------------------------------------------------------------
local function setArmedState()
  if runtime.state ~= getArmedState() then
      log("Set state to ARMED.")
  end
  runtime.state = getArmedState()
  runtime.stateChangeTime = os.time()
end

------------------------------------------------------------------------------
local function setOffAlarm(reason)
  fibaro:setGlobal(alarmVariable, "1")
  errorlog("ALARM ALARM ALARM: " .. reason)
  runtime.reason = reason
  setArmedState()
end

------------------------------------------------------------------------------
local function isAlarmTriggered()
  var = fibaro:getGlobal(alarmVariable)
  if tonumber(var) > 0 then
    return true
  end
  return false
end

------------------------------------------------------------------------------
local function setAlarmDelayedState(reason)
  if runtime.state ~= getAlarmDelayedState() then
    
    if secondsBeforeAlarmGetFired > 0 then

      errorlog("ALARM but delayed: " .. reason)
      runtime.reason = reason
      
      -- alarm delayed can only be set ones after that the alarm is triggered
      runtime.state = getAlarmDelayedState()
      runtime.stateChangeTime = os.time()
    else
      setOffAlarm(reason)
    end
  end
end

------------------------------------------------------------------------------
local function setupState()
  local variable = fibaro:getGlobal(alarmVariable)
  if variable == nil then
    log("Create variable: " .. alarmVariable)
    api.post("/globalVariables", {name=alarmVariable, isEnum=0})
    setDisarmedState()
  end

  variable = fibaro:getGlobal(storeStateVariable)
  if variable == nil then
    log("Create variable: " .. storeStateVariable)
    api.post("/globalVariables", {name=storeStateVariable, isEnum=0})
    setDisarmedState()
  else
    runtimeDecode = json.decode(variable)
    if runtimeDecode == nil or runtimeDecode.state == nil or runtimeDecode.stateChangeTime == nil then
      errorlog("Can not decode runtime")
      setDisarmedState()
    else
      runtime = runtimeDecode
      -- log("De S: " .. runtime.state .. " - " .. tostring(runtime.stateChangeTime))
    end
  end
end

------------------------------------------------------------------------------
local function saveState()
  store = json.encode(runtime)
  fibaro:setGlobal(storeStateVariable, store)
  -- log("En S: " .. runtime.state .. " - " .. tostring(runtime.stateChangeTime))
end

------------------------------------------------------------------------------
local function anyPresenceDetected()
  -- check if any mobile is in house
  for key, variableName in ipairs(presenceDetection) do
    value = fibaro:getGlobal(variableName)
    if tonumber(value) > 0 then
      return true
    end
  end
  return false
end

------------------------------------------------------------------------------
local function getPresence()
  -- return a string which of the presence variables are true, for debugging
  local presence = ""
  for key, variableName in ipairs(presenceDetection) do
    value = fibaro:getGlobal(variableName)
    if tonumber(value) > 0 then
      presence = presence .. " " .. variableName
    end
  end
  return presence
end

------------------------------------------------------------------------------
local function checkAllDoors()
  -- returns true if any door is open
  for key, deviceID in ipairs(doorSensors) do
    if tonumber(fibaro:getValue(deviceID, "value")) > 0 then
      return true
    end
  end
  return false
end

------------------------------------------------------------------------------
local function checkForMotion()
  -- returns true if any motion is detected
  for key, deviceID in ipairs(motionSensors) do
    if tonumber(fibaro:getValue(deviceID, "value")) > 0 then
      return true
    end
  end
  return false
end

------------------------------------------------------------------------------
local function checkAlarm()
  if anyPresenceDetected() then
    -- there is at least one presence detected in the house, reset everything to disarmed
    if getState() ~= getDisarmedState() then
      log("Presence detected, disarm.")
    end
    
    setDisarmedState() -- set the right state and always reset timer
    
  else

    if getState() == getAlarmDelayedState() then
      
      -- check if the time is over then start alarm
      if howManySecondsSinceLastStateChange() >= secondsBeforeAlarmGetFired then
        if isAlarmTriggered() == false then
          setOffAlarm(runtime.reason)
        end
      else
        log("Delayed ALARM, time to push: " .. tostring(secondsBeforeAlarmGetFired - howManySecondsSinceLastStateChange()))
      end
      
    elseif getState() == getDisarmedState() then
      if howManySecondsSinceLastStateChange() >= secondsWhereMovementIsOKBeforeArm then
        -- there was no movement since a while and no mobile, arm 
        log("Time is over, ARM.")
        setArmedState()
        
        if checkForMotion() then
          -- there was a long time no other event, now there is movement which is over the time, alarm
          setAlarmDelayedState("Motion detected after arming.")
        end
      elseif checkForMotion() then
        log("Motion detected, reset timer to : " .. tostring(secondsWhereMovementIsOKBeforeArm))
        setDisarmedState() -- as there is movement we reset the time and state to disarmed
      else
        log("No presence, no motion, time to arm: " .. tostring(secondsWhereMovementIsOKBeforeArm - howManySecondsSinceLastStateChange()))
      end
    elseif getState() == getArmedState() then
      
      if checkForMotion() then
        log("Motion detected while armed.")
        setAlarmDelayedState("Motion detected: " .. sourceTrigger['propertyName'])
      end
      
      if checkAllDoors() then
        log("Door detected while armed.")
        setAlarmDelayedState("Door change detected: " .. sourceTrigger['propertyName'])
      end
    else
      errorlog("Unknown state: " .. getState())
    end
  end
end

-------------------------------------------------------------------------------
-- Main loop starts here
-------------------------------------------------------------------------------

if sourceTrigger['type'] == 'autostart' then
  setupState()
  
  log('Trigger: Autostart - State: ' ..  getState() .. " - Alarm: " .. tostring(isAlarmTriggered()) .. " - Presence:" .. getPresence())
  
  while true do
    -- we run the check in an endless loop, could be done with a setTimeout()  as well, this is more stable
    fibaro:sleep(runFrequencyInSeconds * 1000)
    setupState()
    checkAlarm()
    saveState()
  end
  
else
  if sourceTrigger['type'] == 'property' then
    --log('Trigger: device = ' .. sourceTrigger['deviceID'] .. ' "' .. sourceTrigger['propertyName'] .. '"')
  elseif sourceTrigger['type'] == 'global' then
    var = fibaro:getGlobal(sourceTrigger['name'])
    log('Trigger: global variable changed: ' .. sourceTrigger['name'] .. " = " .. tostring(var))
  elseif sourceTrigger['type'] == 'other' then
    --log('Trigger: manually called')
  else
    log("Trigger unknown: " .. sourceTrigger['type'])
  end
  
  -- some state have changed or scene called manually, check everything
  setupState()
  checkAlarm()
  saveState()
end
