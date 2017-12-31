--[[
%% properties
45 values
91 values
%% weather
%% events
%% autostart
%% globals
--]]

------------------------------------------------------------------------------
------------------------------------------------------------------------------
-- 
-- Home Center 2 Lua Scene which checks if one sensor is reporting bright light
-- react on it, an other sensor is checked if it gets dark again. Both will
-- trigger some actions.
-- I use this simple script to lower the blinds if the sun is shining on the
-- books and open them again when its gets dark.
--
-- by Benjamin Pannier <github@ka.ro>
------------------------------------------------------------------------------
------------------------------------------------------------------------------

local debug = 3

local checkBrightnessDeviceID = 45
local checkDarknessDeviceID = 91

local whenIsItTooBright = 160
local whenIsItTooDark = 70

local stateVariableName = "buecherSchutz"

------------------------------------------------------------------------------
-- Functions
------------------------------------------------------------------------------
local function log(level, str)
  if level <= debug then
    fibaro:debug(str);
  end
end

------------------------------------------------------------------------------
local function errorlog(str)
  fibaro:debug("<font color='red'>"..str.."</font>")
end

------------------------------------------------------------------------------
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
        log(2, id .. ": url call was successful: " .. response.status .. " - " .. url .. " - " .. requestBody)
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

------------------------------------------------------------------------------
local function onTooBright()
  local iftttKey = fibaro:getGlobalValue("iftttKey")
  sendData("IFTTT", "http://maker.ifttt.com/trigger/BuecherSchutz/with/key/" .. iftttKey, "POST", '{"value1":"' .. os.date() .. '"}', true)
end

------------------------------------------------------------------------------
local function onGettingDark()
  local iftttKey = fibaro:getGlobalValue("iftttKey")
  sendData("IFTTT", "http://maker.ifttt.com/trigger/BuecherSchutzEnde/with/key/" .. iftttKey, "POST", '{"value1":"' .. os.date() .. '"}', true)
end

------------------------------------------------------------------------------
local function setup()
  local variable = fibaro:getGlobal(stateVariableName)
  if variable == nil then
    log(1, "Create variable: " .. stateVariableName)
    api.post("/globalVariables", {name=stateVariableName, isEnum=0})
    fibaro:setGlobal(stateVariableName, "0")
  end
end

-------------------------------------------------------------------------------
-- Main loop starts here
-------------------------------------------------------------------------------

setup()
log(2, "Check light conditions.")
local state = fibaro:getGlobal(stateVariableName)

if tonumber(state) > 0 then
  -- waiting to get dark
  
  local value = fibaro:getValue(checkDarknessDeviceID, "value")
  
  if tonumber(value) <= whenIsItTooDark then
    log(1, "Getting dark with " .. tostring(value) .. ", need " .. tostring(whenIsItTooDark));
    onGettingDark()
    fibaro:setGlobal(stateVariableName, "0")
  else
    log(3, "Not dark enough with " .. tostring(value) .. ", need " .. tostring(whenIsItTooDark))
  end
  
else
  -- waiting until it is too bright
  
  local value = fibaro:getValue(checkBrightnessDeviceID, "value")
  
  if tonumber(value) >= whenIsItTooBright then
    log(1, "Getting bright with " .. tostring(value) .. ", need " .. tostring(whenIsItTooBright));
    onTooBright()
    fibaro:setGlobal(stateVariableName, "1")
  else
    log(3, "Not bright enough with " .. tostring(value) .. ", need " .. tostring(whenIsItTooBright))
  end
end

