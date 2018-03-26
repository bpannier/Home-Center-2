--[[
%% properties
%% weather
%% events
%% autostart
%% globals
--]]

local debug = 1

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
        errorlog(id .. ": request '" .. url .. "' failed: " .. response.status .. " -- " .. query .. " R:" .. tostring(retryAgain))
        if (retryAgain == true) then
          sendData(id, requestBody, false)
        end
      end
    end,
    error = function(response)
      query = url .. " body: " .. requestBody
      errorlog(id .. ": request '" .. url .. "' failed " .. response.data .. " -- R:" .. tostring(retryAgain))
      if (retryAgain == true) then
        sendData(id, requestBody, false)
      end
    end
  })
end

-------------------------------------------------------------------------------
local function onCall(number)
  -- START EDITING HERE
  -- enter here what should happen when an call comes in
  log(1, "Call incoming: " .. number)
  
  -- Example, change it. 
  
  local iftttKey = fibaro:getGlobalValue("iftttKey")
  
  local iftttText = "Telephone call incoming: " .. tostring(number)
  local say = "Telefon"
  
  if number == 017673146813 then
    log(1, "Auto Alarm")
    iftttText = "Auto Alarm. Auto Alarm. Auto Alarm"
  	say = iftttText
  end

  -- I let Google Home say something 
  -- see here how: https://github.com/biofects/Google-Home-Messages
  sendData("GoogleHome", "http://nas2:8092/google-home-messages", "POST", '{"text":"' .. say .. '","ipaddress":"192.168.178.49","token":"mysec"}', true)
  sendData("GoogleHome", "http://nas2:8092/google-home-messages", "POST", '{"text":"' .. say .. '","ipaddress":"192.168.178.56","token":"mysec"}', true)
  sendData("GoogleHome", "http://nas2:8092/google-home-messages", "POST", '{"text":"' .. say .. '","ipaddress":"192.168.178.46","token":"mysec"}', true)

  sendData("IFTTT", "http://maker.ifttt.com/trigger/Notify/with/key/" .. iftttKey, "POST", '{"value1":"' .. iftttText .. '"}', true)
end

-------------------------------------------------------------------------------
local function processParameters(params)
  local number = nil
  local status = nil
  
  local trigger = false
  
  for k, vals in ipairs(params) do
    -- there could be multiple requests in one, iterate through all of them 
    
    for key, value in pairs(vals) do
      -- check what have been given within the parameters and save the variables
      
      if key == "number" then
        number = value
      elseif key == "status" then
        status = value
      else
        log(0, "Unknown parameter received: " .. key .. " = " .. tostring(value))
      end
    end
    
    if status then
      if status == "RING" then
        onCall(number)
      else
        log(1, "Status: " .. status .. " Number: " .. tostring(number))
      end
    end
  end
end

-------------------------------------------------------------------------------
-------------------------------------------------------------------------------

local sourceTrigger = fibaro:getSourceTrigger()

if (sourceTrigger['type'] == 'property') then
  log(3,'Trigger: Source device = ' .. sourceTrigger['deviceID'] .. ' "' .. sourceTrigger['propertyName'].. '"')
elseif (sourceTrigger['type'] == 'global') then
  log(2,'Trigger: Global variable source = ' .. sourceTrigger['name'])
else
  log(2,'Trigger: ' .. sourceTrigger['type'])
  
  local params = fibaro:args()
  
  if (params) then
    processParameters(params)
  end
end
