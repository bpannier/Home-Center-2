--[[
%% properties
%% events
%% globals
BenStatus
--]]

local debugLevel = 3

local logDeviceClass = "logging"
local logDeviceName = "dummy"

local logCache = {}

------------------------------------------------------------------------------
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
local function logFlush()
  
  local counter = 0
  local sendData = {}
  for _, v in ipairs(logCache) do
    encoded = string.sub(json.encode({ value= '"' .. v .. '"' }),2,-2) 
    table.insert(sendData, { deviceClass = logDeviceClass, deviceName = logDeviceName, values = encoded})
    counter = counter + 1
  end
  
  if counter > 0 then
    fibaro:startScene(4, sendData)
  end
  
  logCache = {}
end

------------------------------------------------------------------------------

log(1, "test 1")
log(1, "test 2")
log(1, "test 3")

logFlush()
