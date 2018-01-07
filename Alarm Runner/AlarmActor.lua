--[[
%% properties
%% weather
%% events
%% autostart
%% globals
alarm
alarm_state
--]]

------------------------------------------------------------------------------
------------------------------------------------------------------------------
-- 
-- Home Center 2 Lua Scene which monitors an alarm state flagged by a global
-- variable. It is the second part of a two scene alarm approach.
--
-- At the end of this script own code can be provided.
--
-- by Benjamin Pannier <github@ka.ro>
------------------------------------------------------------------------------
------------------------------------------------------------------------------

local debug = true

-- In which variable the alarm state will be hold.
local alarmVariable = "alarm"
-- On top we need to store some states also in a global variable.
local storeStateVariable = "alarm_state"

-- encoded runtime states, do not change
local runtime = { state = "", stateChangeTime = 0, reason = "" }

-------------------------------------------------------------------------------
-- Functions
-------------------------------------------------------------------------------
local function log(str)
  if debug then
    fibaro:debug(str);
  end
end

-------------------------------------------------------------------------------
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
local function getState()
  return runtime.state
end

-------------------------------------------------------------------------------
local function setAlarmReason(reason)
  runtime.reason = reason
end

-------------------------------------------------------------------------------
local function getAlarmReason()
  return runtime.reason
end

-------------------------------------------------------------------------------
-- Load runtime
local function setupState()
  variable = fibaro:getGlobal(storeStateVariable)
  if variable == nil then
    errorlog("Alarm script not running, global variable missing: " .. storeStateVariable)
  else
    runtimeDecode = json.decode(variable)
    if runtimeDecode == nil or runtimeDecode.state == nil or runtimeDecode.stateChangeTime == nil then
      errorlog("Can not decode runtime, alarm script not running?")
    else
      runtime = runtimeDecode
      -- log("De S: " .. runtime.state .. " - " .. tostring(runtime.stateChangeTime))
    end
  end
end

-------------------------------------------------------------------------------
-- use sendData if you like to call any URL via method (GET or POST)
local function sendData (id, url, method, requestBody, retryAgain)
  local returnValue = false
  local httpClient = net.HTTPClient({timeout=3000})
  
  httpClient:request(url, {
    options={
      data = requestBody,
      method = method,
      headers = { ['Accept'] = 'application/json', ['Content-Type'] = 'application/json' },
      timeout = 3000
    },
    success = function(response)
      if (response.status >= 200 and response.status < 300) then
        log(id .. ": url call was successful: " .. response.status .. " - " .. url .. " - " .. requestBody)
        returnValue = true
      else
        query = url .. " body: " .. requestBody
        errorlog(id .. ": request '" .. query .. "' failed: " .. response.status .. " -- " .. response.data .. " R:" .. tostring(retryAgain))
        if (retryAgain == true) then
          sendData(id, requestBody, false)
        end
      end
    end,
    error = function(response)
      query = url .. " body: " .. requestBody
      errorlog(id .. ": request '" .. query .. "' failed " .. tostring(response) .. " -- R:" .. tostring(retryAgain))
      if (retryAgain == true) then
        sendData(id, requestBody, false)
      end
    end
  })
  return returnValue
end

-------------------------------------------------------------------------------
local function onArmed()
  -- START EDITING HERE
  -- enter here what should happen when the system got armed
end

-------------------------------------------------------------------------------
local function onDisarmed()
  -- START EDITING HERE
  -- enter here what should happen when the system got disarmed
end

-------------------------------------------------------------------------------
local function onAlarmDelayed()
  -- START EDITING HERE
  -- enter here what should happen when an alarm was triggered but not yet flagged
  log("Alarm, delayed.")
  
  -- Example, change it. 
  -- I let Google Home say something so that I do not forget to disarm the alarm
  -- see here how: https://github.com/biofects/Google-Home-Messages
  sendData("GoogleHome", "http://nas2:8092/google-home-messages", "POST", '{"text":"Hallo","ipaddress":"192.168.178.49","token":"mysec"}', true)
end

-------------------------------------------------------------------------------
local function onAlarm(reason)
  -- START EDITING HERE
  -- enter here what should happen when an alarm was triggered
  
  -- call an ifttt maker action
  -- I created a global variable "iftttKey" to store the actual IFTTT Maker key, then it is easier to use it everywhere 
  local iftttKey = fibaro:getGlobalValue("iftttKey")
  sendData("IFTTT", "http://maker.ifttt.com/trigger/Alarm/with/key/" .. iftttKey, "POST", '{"value1":"' .. reason .. '", "value2":"' .. os.date() .. '"}', true)
  
  -- send an Email to User #2 with subject and message body
	fibaro:call(2, "sendEmail", "ALARM at home: " .. reason, "At home an alarm occured: " .. reason)
  
  -- send a push notification #5 to device #140
	--fibaro:call(140, "sendDefinedPushNotification", "5");
  -- following works only with iOS
  fibaro:call(140, "sendPush", "ALARM: " .. reason)
  
  -- add a notification on your HC2 interface desktop and mobile
  HomeCenter.PopupService.publish({
	 title = 'ALARM',
	 subtitle = os.date("%H:%M:%S | %B %d, %Y"),
	 contentTitle = 'ALARM at home',
	 contentBody = 'Reason: ' .. reason,
   type = 'Critical'
   --img = "http://fibarouk.co.uk/img/slider_icon_3.jpg",
	})
end

-------------------------------------------------------------------------------
-- Main loop starts here
-------------------------------------------------------------------------------

local sourceTrigger = fibaro:getSourceTrigger()

-- load runtime
setupState()

if sourceTrigger["type"] == "autostart" then
  log("Watchdog started, alarm variable: " .. fibaro:getGlobalValue(alarmVariable))
elseif sourceTrigger["type"] == "global" then
  
  if sourceTrigger['name'] == alarmVariable then
    if tonumber(fibaro:getGlobalValue(alarmVariable)) < 1  then
      log("Alarm turned off.")
    else
      errorlog("Trigger alarm procedure as alarm has been set: " .. getAlarmReason() )
      onAlarm(getAlarmReason())
    end
  elseif sourceTrigger['name'] == storeStateVariable then
    if getState() == getArmedState() then
      onArmed()
    elseif getState() == getDisarmedState() then
      onDisarmed()
    elseif getState() == getAlarmDelayedState() then
      onAlarmDelayed()
    end
    
  end
elseif sourceTrigger["type"] == "other" then
  errorlog("Trigger alarm procedure as manual alarm has been fired.")
  setAlarmReason("manual")
  
  onAlarm(getAlarmReason())
end
