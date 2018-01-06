--[[
%% properties
%% events
%% globals
--]]

-- An example how to do remote logging. 
-- Be careful not to use it in too many scenes which dumps simultaneously as
-- otherwise the maximum amount of allowed instances of the remote logging scene
-- will be reached and you will loose data.
--
-- by Benjamin Pannier <github@ka.ro>
-- latest version: https://github.com/bpannier/Home-Center-2/tree/master/Device%20Dashboard

local debugLevel = 3

local sceneIDofDumpScript = 4

local logDeviceClass = "logging"
local logDeviceName = "dummy"

local logCache = {}

------------------------------------------------------------------------------
-- This log functions caches all log entries, use logFlush to send them remote.
local function log(level, str)
  if debugLevel >= level then
    fibaro:debug(str);
    
    local counter = 0
    for _, v in ipairs(logCache) do
      counter = counter + 1
    end
    
    if counter < 50 then
      table.insert(logCache, str)
    end
  end
end

------------------------------------------------------------------------------
-- Dumps all cached log entries to the remote script/scene
local function logFlush()
  
  local counter = 0
  local sendData = {}
  
  for _, v in ipairs(logCache) do
    -- encode via json the content of all log entries
    encoded = string.sub(json.encode({ value= '"' .. v .. '"' }),2,-2) 
    table.insert(sendData, { deviceClass = logDeviceClass, deviceName = logDeviceName, values = encoded})
    counter = counter + 1
  end
  
  if counter > 0 then
    -- send all log entries 
    fibaro:startScene(sceneIDofDumpScript, sendData)
  end
  
  logCache = {}
end

------------------------------------------------------------------------------
-- Example on how to do remote logging

log(1, "test 1")
log(1, "test 2")
log(1, "test 3")

logFlush()
