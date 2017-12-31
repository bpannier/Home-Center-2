--[[
%% properties
54 value
90 value
44 value
161 value
105 value 
59 value 
61 value
149 value
33 power
101 power 
156 power
95 power
99 power
158 power
160 value
148 value
89 value
43 value
29 value
31 value
15 value
17 value
21 value
23 value
25 value
27 value
135 value
138 value
132 value
162 value
45 value
91 value
150 value
167 value
168 value
169 value
160 tamper
148 tamper
89 tamper
43 tamper
103 tamper
103 value
172 value
173 value
192 value
193 value
194 value
195 value
196 value
%% autostart
%% events
%% globals
BenStatus
alarm
DisableAlarm
--]]

------------------------------------------------------------------------------
------------------------------------------------------------------------------
-- 
-- Home Center 2 Lua Scene which dumps data of devices, variables and 
-- diagonis data of your HC2 to an InfluxDB. As the HC2 do not have a great
-- way of visualising historical data of most devices you now can store any
-- data to an external InfluxDB. Ideally you install a docker container of
-- InfluxDB and use additionally Grafana to visualise the data in a great way.
-- Add all device id's and global variables to the beginning of this script.
--
-- An example Grafana Dashboard is provided as well.
--
-- by Benjamin Pannier <github@ka.ro>
------------------------------------------------------------------------------
------------------------------------------------------------------------------

local debug = 1

-- on which host does InfluxDB run. Be careful with DHCP hostnames as
-- Home Center 2 has an issue with dynamic changing of IP addresses.
local influxdbHost   = "nas2"
local influxdbPort   = 8086
local influxdbDBName = "hc2"

-- timer if greater 0 it will dump each X seconds all device values, we do this to 
-- avoid triangle diagrams in the visualisation
local dumpFrequency = 10 * 60 -- every 10 minutes

-- If you like to disable the capturing of all diagnostic values of your Home Center Box set it to 0
-- The value should be much smaller than the dumpFrequency otherwise there will be an issue with the calculation for the right frequency for the device data
local diagnosticsFrequency = 20 -- every 20 seconds

-- under which devicename should the diagnostics Home Center Data be stored
local diagnosticsDevicename = "HC2"

-- what are the global variables which will be dumped
local variableList =
{
  variable = {"BenStatus", "alarm", "DisableAlarm"}
}

-- what are the devices which will be dumped.
-- The format is a list of key, value pairs were the key is the device class
-- like all temperature sensors. The value is an other array of key, value pairs.
-- These pairs are the name which will be used to store the  device value with the given
-- device id.
local deviceList =
{
  temperature = { netatmoOben = 54, wohnzimmer = 90, flurOben = 44, kueche = 161, kammer = 105,  schlafzimmer = 61, flurUnten = 149, terasse = 59, buero = 168, tuerUnten = 173, bad = 193},
  energy = { leselampe = 33, hifi = 101, wohnLampe = 156, waschmaschine = 95, trockner = 99, edv = 158 },
  motion = { kueche = 160, flurUnten = 148, wohnzimmer = 89, flurOben = 43, buero = 167, bad = 192 },
  thermostat = { tv = 29, sofa = 31, buero = 15, flurUnten = 17, schlafzimmer = 21, flurLinks = 23, flurMitte = 25, kueche = 27},
  door = { balkonWohn = 135, oben = 138, balkonKueche = 132, unten = 172},
  light = { kueche = 162, flurOben = 45, wohnzimmer = 91, flurUnten = 150, buero = 169, bad = 194 },
  co2 = {netatmoOben = 55, schlafzimmer = 63},
  humidity = {netatmoOben = 56, terasse = 60, schlafzimmer = 62, bad = 195},
  rain = {terasse = 64},
  tamper = { kueche = 160, flurUnten = 148, wohnzimmer = 89, flurOben = 43, kammer = 103 },
  water = { waschmaschine = 103 },
  uv = { bad = 196 }
}

-- for certain devices you like to give an explicit Z-wave lookup key for others the defaultDeviceValueLookup will be used.
-- Usually all z-wave sensors store their value in the given key "value", some sensors
-- do have more than one value, for the given device class you can give a n other z-wave lookup.
local deviceValueLookup =
{
  energy = "power",
  tamper = "tamper"
}

-- the default lookup key for the z-wave devices which are not given in deviceValueLookup
local defaultDeviceValueLookup = "value"

-- if set to true for all configured devices we will check if the device is dead
local reportDeadDevice = true

-- how long will be wait for each dump request.
local tcpTimeout = 10 * 1000

-------------------------------------------------------------------------------
-- Internal variables
-------------------------------------------------------------------------------

local wakeupFrequency = dumpFrequency * 1000
local nextDumpTime = 0

-------------------------------------------------------------------------------
-- Functions
-------------------------------------------------------------------------------
local function log(level, str)
  if level <= debug then
    fibaro:debug(str);
  end
end

-------------------------------------------------------------------------------
local function errorlog(str)
  fibaro:debug("<font color='red'>"..str.."</font>")
end

-------------------------------------------------------------------------------
local function sendData (id, requestBody, retryAgain)
  local url = "http://" .. influxdbHost .. ":" .. influxdbPort .. "/write?db=" .. influxdbDBName
  local httpClient = net.HTTPClient({timeout=tcpTimeout})

  log(4,"ID: " .. id .. " - URL: " .. url .. " - Send: " .. requestBody)

  httpClient:request(url, {
    options={
      data = requestBody,
      method = 'POST',
      timeout = tcpTimeout
    },
    success = function(response)
      if (response.status < 200 or response.status >= 300) then
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
local function sendDeviceData(deviceClass, deviceName, deviceID, retry)
  local lookup = deviceValueLookup[deviceClass]

  if (lookup == nil) then
    lookup = defaultDeviceValueLookup
  end

  local value = fibaro:getValue(deviceID, lookup)
  
  if value == nil then
    errorLog("Value is NIL: " .. deviceClass .. " - " .. deviceName)
  end
  
  local requestBody = deviceClass .. ",device=" .. deviceName .. " value=" .. value
  sendData(deviceID, requestBody, true)
  
  if reportDeadDevice then
    value = fibaro:getValue(deviceID, "dead")
    
    requestBody =  "dead,device=" .. deviceName .. " value=" .. value
    sendData(deviceID, requestBody, retry)
  end
end

-------------------------------------------------------------------------------
local function processDevice(findDeviceID)
  -- Go through all device classes to find the given device id
  for deviceClass, devices in pairs(deviceList) do
    for deviceName, deviceID in pairs(devices) do

      if (findDeviceID == deviceID) then
        sendDeviceData(deviceClass, deviceName, deviceID, true)
      end
    end
  end
end

-------------------------------------------------------------------------------
local function processAllDevices()
  -- Go through all device classes
  
  for deviceClass, devices in pairs(deviceList) do
    for deviceName, deviceID in pairs(devices) do
      sendDeviceData(deviceClass, deviceName, deviceID, false)
    end
  end
end

-------------------------------------------------------------------------------
local function sendVariableData(variableClass, variableName)
  local requestBody = variableClass .. ",variable=" .. variableName .. " value=" .. fibaro:getGlobal(variableName)
  sendData(variableName, requestBody, true)
end

-------------------------------------------------------------------------------
local function processVariable(findVariableName)
  -- Go through all variable classes to find the given variable name
  for variableClass, variables in pairs(variableList) do
    for key, variableName in ipairs(variables) do

      if (findVariableName == variableName) then
        sendVariableData(variableClass, variableName)
      end
    end
  end
end

-------------------------------------------------------------------------------
local function processAllVariables()
  -- Go through all variable classes
  for variableClass, variables in pairs(variableList) do
    for key, variableName in ipairs(variables) do
      sendVariableData(variableClass, variableName)
    end
  end
end

-------------------------------------------------------------------------------
local function processDevicesAndVariables()
  processAllDevices()
  processAllVariables()
end

-------------------------------------------------------------------------------
-- dump diagnostic data of your Home Center 2
local function processDiagnosticData()
  local diagnosticsData = api.get("/diagnostics")
  
  local requestBody = "diagnostics,device=" .. diagnosticsDevicename .. ",what=memory free=" .. diagnosticsData["memory"]["free"] .. ",cache=" .. diagnosticsData["memory"]["cache"] .. ",buffers=" .. diagnosticsData["memory"]["buffers"] .. ",used=" .. diagnosticsData["memory"]["used"]
  sendData("diagnostics", requestBody, true)
  
  for type, storages in pairs(diagnosticsData["storage"]) do
    for key, storageDevice in ipairs(storages) do
      requestBody = "diagnostics,device=" .. diagnosticsDevicename .. ",what=storage,type=" .. type .. ",name=" .. storageDevice["name"] .. " used=" .. storageDevice["used"]
      sendData("diagnostics", requestBody, true)
      
    end
  end
  
  for key, cpus in ipairs(diagnosticsData["cpuLoad"]) do
    for name, cpu in pairs(cpus) do
      requestBody = "diagnostics,device=" .. diagnosticsDevicename .. ",what=cpu,name=" .. name .. " user=" .. cpu["user"] .. ",nice=" .. cpu["nice"] .. ",system=" .. cpu["system"] .. ",idle=" .. cpu["idle"]
      sendData("diagnostics", requestBody, true)
    end
  end
end

-------------------------------------------------------------------------------
local function processEndlessLoop()
  
  if dumpFrequency > 0 and nextDumpTime <= os.time() then
    
    log(2,'Dump all device data and global variables.')
    -- it is time to do a dump of any data
    processDevicesAndVariables()
    nextDumpTime = os.time() + dumpFrequency
  end
  
  if diagnosticsFrequency > 0 then
    -- assumption is if diagnosticsFrequency is on it is much more often than the other dump time
    -- we always dump diagnostic data when we get called
    log(3,"Dump Diagnostics.")
    processDiagnosticData()
  end
  
  setTimeout(processEndlessLoop, wakeupFrequency)
end

-------------------------------------------------------------------------------
-- Main loop starts here
-------------------------------------------------------------------------------

local sourceTrigger = fibaro:getSourceTrigger()

if (sourceTrigger['type'] == 'property') then
  log(3,'Trigger: Source device = ' .. sourceTrigger['deviceID'] .. ' "' .. sourceTrigger['propertyName'].. '"')
  processDevice(sourceTrigger['deviceID'])
  
elseif (sourceTrigger['type'] == 'global') then
  log(1,'Trigger: Global variable source = ' .. sourceTrigger['name'])
  processVariable(sourceTrigger['name'])
  
else
  log(1,'Trigger: ' .. sourceTrigger['type'])
  
  if diagnosticsFrequency > 0 then
    processDiagnosticData()
  end
  
  processDevicesAndVariables()
end

if (sourceTrigger['type'] == 'autostart' and (dumpFrequency > 0 or diagnosticsFrequency > 0)) then
  
  if dumpFrequency == 0 then
    wakeupFrequency = diagnosticsFrequency * 1000
    log(1,'Will only store diagnostics')
    
  elseif dumpFrequency > diagnosticsFrequency then
    wakeupFrequency = diagnosticsFrequency * 1000
    nextDumpTime = os.time() + dumpFrequency
    log(1,'Will store device data, variable data and diagnostics')
  end
  
  setTimeout(processEndlessLoop, wakeupFrequency)
end