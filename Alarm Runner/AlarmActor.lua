--[[
%% properties
%% weather
%% events
%% autostart
%% globals
alarm
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
end

-------------------------------------------------------------------------------
-- Main loop starts here
-------------------------------------------------------------------------------

local sourceTrigger = fibaro:getSourceTrigger()

-- load runtime
setupState()

if sourceTrigger["type"] == "autostart" then
  log("Watchdog started, alarm variable: " .. fibaro:getGlobalValue(alarmVariable))
elseif tonumber(fibaro:getGlobalValue(alarmVariable)) < 1 and sourceTrigger["type"] == "global" then
  log("Global variable changed, alarm variable: " .. fibaro:getGlobalValue(alarmVariable))
elseif tonumber(fibaro:getGlobalValue(alarmVariable)) >= 1 or sourceTrigger["type"] == "other" then
  -- either the alarm is set or the scene has been called explicitly 
  
  if sourceTrigger['type'] == 'global' then
    errorlog("Trigger alarm procedure as alarm has been set: " .. getAlarmReason() )
  elseif sourceTrigger['type'] == 'other' then
    errorlog("Trigger alarm procedure as manual alarm has been fired.")
    setAlarmReason("manual")
  end
  
  -- START EDITING HERE
  -- enter here what should happen when an alarm was triggered
  
  -- call an ifttt maker action
  -- I created a global variable "iftttKey" to store the actual IFTTT Maker key, then it is easier to use it everywhere 
  local iftttKey = fibaro:getGlobalValue("iftttKey")
  sendData("IFTTT", "http://maker.ifttt.com/trigger/Alarm/with/key/" .. iftttKey, "POST", '{"value1":"' .. getAlarmReason() .. '", "value2":"' .. os.date() .. '"}', true)
  
  -- send an Email to User #2 with subject and message body
	fibaro:call(2, "sendEmail", "ALARM at home: " .. getAlarmReason(), "At home an alarm occured: " .. getAlarmReason())
  
  -- send a push notification #5 to device #140
	--fibaro:call(140, "sendDefinedPushNotification", "5");
  -- following works only with iOS
  fibaro:call(140, "sendPush", "ALARM: " .. getAlarmReason())
  
  -- add a notification on your HC2 interface desktop and mobile
  HomeCenter.PopupService.publish({
	 title = 'ALARM',
	 subtitle = os.date("%H:%M:%S | %B %d, %Y"),
	 contentTitle = 'ALARM at home',
	 contentBody = 'Reason: ' .. getAlarmReason(),
   type = 'Critical'
   --img = "http://fibarouk.co.uk/img/slider_icon_3.jpg",
	})
  
end
