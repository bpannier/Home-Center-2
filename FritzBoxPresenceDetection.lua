--[[
%% properties
%% weather
%% events
%% autostart
%% globals
--]]

------------------------------------------------------------------------------
------------------------------------------------------------------------------
-- This scene tracks a given device which is or was connected to a Fritz.box router.
-- When the device is found a given global variable will be set accordingly to
-- to the connection state of the device. If the device is connected it 1 and
-- 0 otherwise.
-- I use this scene to track the presence of persons as I assume their mobile
-- phone is connected when they are at home and they will take their mobile
-- phone with them if they leave.
--
-- In addition I added some more potentially usefull methods to get informations
-- about your internet connection and your wifi network. 
--
-- The Fritz.box must not have enabled authorization, sorry for that. I might fix that
-- 
-- Example functions:
--getLANHostByEntry(1, 1, function(...) for k,v in pairs({...}) do print(tostring(k) .. ": " .. tostring(v)) end end )
--getLANHostByMACAddress(1, string.upper("A8:5B:78:82:0C:16"), function(...) for k,v in pairs({...}) do print(tostring(k) .. ": " .. tostring(v)) end end )

--getWifiInfo(1, function(...) for k,v in pairs({...}) do print(tostring(k) .. ": " .. tostring(v)) end end )
--getWifiHostByEntry(1, 1, function(...) for k,v in pairs({...}) do print(tostring(k) .. ": " .. tostring(v)) end end )
--getWifiHostByMACAddress(1, string.lower("98:7b:f3:c6:03:13"), function(...) for k,v in pairs({...}) do print(tostring(k) .. ": " .. tostring(v)) end end )

--getConnectionInfos(function(...) for k,v in pairs({...}) do print(tostring(k) .. ": " .. tostring(v)) end end )
--
-- by Benjamin Pannier <github@ka.ro>
------------------------------------------------------------------------------
------------------------------------------------------------------------------

local debugLevel = 2

local devices = {
     -- {macAddress = "", type = "", interface = 1, variable = ""}, 
     -- Every device you like to lookup needs one full entry with the following details:
     -- macAddress: the hardware address of the device you like to track
     -- type: is the device connected via WIFI or LAN, be aware that also WIFI devices could be found via LAN
     -- interface: your router might have more than one WIFI or LAN interface, like 2.4 or 5 GHZ or have different LAN ports
     -- variable: the global variable where the connection state (0 or 1) will be written in, the variable will be created automaticlly 
        { macAddress = "A8:5B:78:82:0C:16", type = "LAN", interface = 1, variable = "BPhone" },
        { macAddress = "48:5A:3F:52:CB:9F", type = "LAN", interface = 1, variable = "KPhone" }
      }

local router = "192.168.178.1" -- the IP address of your fritz.box
local routerPort = 49000 -- the port where TR64 is enabled, default is 49000
 
local checkDevicesEverySeconds = 20 -- how often should a device looked up in seconds
 
-------------------------------------------------------------------------------
-- Functions
-------------------------------------------------------------------------------
local function log(level, str)
  if level <= debugLevel then
    fibaro:debug(str);
  end
end

-------------------------------------------------------------------------------
local function errorlog(str)
  fibaro:debug("<font color='red'>"..str.."</font>")
end

-------------------------------------------------------------------------------
-- Quote all characters which could be interpreted as HTML
function htmlEscape(s)
    assert("Expected string in argument #1.")
    s = string.gsub(s, "\n", "")
    s = string.gsub(s, "\r", "")
    s = string.gsub(s, "\t", "")
    return (string.gsub(s, "[}{\">/<'&]", {
        ["&"] = "&amp;",
        ["<"] = "&lt;",
        [">"] = "&gt;",
        ['"'] = "&quot;",
        ["'"] = "&#39;",
        ["/"] = "&#47;",
        ["\n"] = "",
        ["\r"] = ""
    }))
end

-------------------------------------------------------------------------------
-- use sendData if you like to call any URL via method (GET or POST)
function sendData (id, url, method, requestBody, requestHeader, retryAgain, successFunction)
  local httpClient = net.HTTPClient({timeout=3000})
  local header = { ['Accept'] = 'application/json', ['Content-Type'] = 'application/json' }
  local body = ""
  
  if requestHeader ~= nil then
    header = requestHeader
  end
  
  if requestBody ~= nil then
    body = requestBody
  end
  
  local successFunc = function(response)
      if (response.status >= 200 and response.status < 300) then
        log(4, id .. ": url call was successful: " .. response.status .. " - " .. url .. " - " .. htmlEscape(requestBody))
      else
        query = url .. " body: " .. htmlEscape(requestBody)
        errorlog(id .. ": request '" .. url .. "' failed " .. query .. " - " .. response.status .. " - " .. htmlEscape(response.data))
      end
    end
    
  if successFunction then
    successFunc = successFunction
  end
  
  log(5, "Send: " .. body .. " - " .. method .. " - " .. tostring(header) .. " - " .. url)
  
  httpClient:request(url, {
    options={
      data = body,
      method = method,
      headers = header,
      timeout = 3000
    },
    success = successFunc,
    error = function(response)
      query = url .. " body: " .. htmlEscape(requestBody)
      errorlog(id .. ": request '" .. url .. "' failed " .. query .. " -- R:" .. tostring(retryAgain))
      if (retryAgain == true) then
        sendData(id, requestBody, false, successFunc)
      end
    end
  })
end

-------------------------------------------------------------------------------
-- Get informations about a device conntected via Wifi. This function is used
-- to iterate through all devices. 
-- INPUT: 
-- <interface id> - when your wifi router has more than one wifi network, like 2,4 vs 5 Ghz or guest network
-- <number> - the index of a device
-- <callback> - function will be calle on success
--
-- Callback arguments:
-- mac address, the hardware address of a device
-- ip address, the IP address of a device
-- auth state, 0 or 1 dependend if the device is active/connected
-- speed, the connection speed
-- signal strength, the wifi signal strength
local function getWifiHostByEntry(interface, number, callback)
    local url = "http://" .. router .. ":" .. tostring(routerPort) .. "/upnp/control/wlanconfig" .. tostring(interface)
    local header = { ["Soapaction"] = "urn:dslforum-org:service:WLANConfiguration:" .. tostring(interface) .. "#GetGenericAssociatedDeviceInfo", ["Content-Type"] = 'text/xml; charset="UTF-8"' } 
    
    local request = '<?xml version="1.0" encoding="UTF-8"?><s:Envelope s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/" xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><s:Header/><s:Body><u:GetGenericAssociatedDeviceInfo xmlns="urn:dslforum-org:service:WLANConfiguration:' .. tostring(interface) .. '"><NewAssociatedDeviceIndex>' .. number .. '</NewAssociatedDeviceIndex></u:GetGenericAssociatedDeviceInfo></s:Body></s:Envelope>'
    
    local successFunc = function(response)
        if (response.status >= 200 and response.status < 300) then
          log(4, "Search wifi by entry call was successful: " .. response.status .. " - " .. url)
          
          local macAddress = string.match(response.data, "<NewAssociatedDeviceMACAddress>(.+)</NewAssociatedDeviceMACAddress>")
          local ipAddress = string.match(response.data, "<NewAssociatedDeviceIPAddress>(.+)</NewAssociatedDeviceIPAddress>")
          local authState = string.match(response.data, "<NewAssociatedDeviceAuthState>(.+)</NewAssociatedDeviceAuthState>")
          local speed = string.match(response.data, "<NewX_AVM.DE_Speed>(.+)</NewX_AVM.DE_Speed>")
          local signalStrength = string.match(response.data, "<NewX_AVM.DE_SignalStrength>(.+)</NewX_AVM.DE_SignalStrength>")
          
          callback(macAddress, ipAddress, authState, speed, signalStrength)
        else
          errorlog("WIFIENTRY: request '" .. url .. "' failed - " .. response.status .. " - " .. htmlEscape(response.data))
        end
      end
    
    sendData("WIFIENTRY", url, "POST", request, header, false, successFunc )
end

-------------------------------------------------------------------------------
-- Get informations about a dedicated device conntected via Wifi. 
-- INPUT: 
-- <interface id> - when your wifi router has more than one wifi network, like 2,4 vs 5 Ghz or guest network
-- <macAddress> - the hardware address of the device you are looking for, a Fritz.Box expects the string to be lower case for Wifi Mac
-- <callback> - function will be calle on success
--
-- Callback arguments:
-- ip address, the IP address of a device
-- auth state, 0 or 1 dependend if the device is active/connected
-- speed, the connection speed
-- signal strength, the wifi signal strength
local function getWifiHostByMACAddress(interface, macAddress, callback)
    local url = "http://" .. router .. ":" .. tostring(routerPort) .. "/upnp/control/wlanconfig" .. tostring(interface)
    local header = { ["Soapaction"] = "urn:dslforum-org:service:WLANConfiguration:" .. tostring(interface) .. "#GetSpecificAssociatedDeviceInfo", ["Content-Type"] = 'text/xml; charset="UTF-8"' } 
    
    local request = '<?xml version="1.0" encoding="UTF-8"?><s:Envelope s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/" xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><s:Header/><s:Body><u:GetSpecificAssociatedDeviceInfo xmlns="urn:dslforum-org:service:WLANConfiguration:' .. tostring(interface) .. '"><NewAssociatedDeviceMACAddress>' .. macAddress .. '</NewAssociatedDeviceMACAddress></u:GetSpecificAssociatedDeviceInfo></s:Body></s:Envelope>'
    
    local successFunc = function(response)
        if (response.status >= 200 and response.status < 300) then
          log(4, "Search wifi by mac call was successful: " .. response.status .. " - " .. url)
          
          local ipAddress = string.match(response.data, "<NewAssociatedDeviceIPAddress>(.+)</NewAssociatedDeviceIPAddress>")
          local authState = string.match(response.data, "<NewAssociatedDeviceAuthState>(.+)</NewAssociatedDeviceAuthState>")
          local speed = string.match(response.data, "<NewX_AVM.DE_Speed>(.+)</NewX_AVM.DE_Speed>")
          local signalStrength = string.match(response.data, "<NewX_AVM.DE_SignalStrength>(.+)</NewX_AVM.DE_SignalStrength>")
          
          callback(ipAddress, authState, speed, signalStrength)
        else
          errorlog("WIFIMAC: request '" .. url .. "' failed - " .. response.status .. " - " .. htmlEscape(response.data))
        end
      end
    
    sendData("WIFIMAC", url, "POST", request, header, false, successFunc )
end

-------------------------------------------------------------------------------
-- Get information of your Wifi network
-- INPUT: 
-- <interface id> - when your wifi router has more than one wifi network, like 2,4 vs 5 Ghz or guest network
-- <callback> - function will be calle on success
--
-- Callback arguments:
-- ssid - the name of the network
-- channel - the wifi transmittion channel
-- bssid - the hardware id of the network
local function getWifiInfo(interface, callback)
    local url = "http://" .. router .. ":" .. tostring(routerPort) .. "/upnp/control/wlanconfig" .. tostring(interface)
    local header = { ["Soapaction"] = "urn:dslforum-org:service:WLANConfiguration:" .. tostring(interface) .. "#GetInfo", ["Content-Type"] = 'text/xml; charset="UTF-8"' } 
    
    local request = '<?xml version="1.0" encoding="UTF-8"?><s:Envelope s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/" xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><s:Header/><s:Body><u:GetInfo xmlns="urn:dslforum-org:service:WLANConfiguration:' .. tostring(interface) .. '"></u:GetInfo></s:Body></s:Envelope>'
    
    local successFunc = function(response)
        if (response.status >= 200 and response.status < 300) then
          log(4, "Wifi info call was successful: " .. response.status .. " - " .. url)
          
          local ssid = string.match(response.data, "<NewSSID>(.+)</NewSSID>")
          local channel = string.match(response.data, "<NewChannel>(.+)</NewChannel>")
          local bssid = string.match(response.data, "<NewBSSID>(.+)</NewBSSID>")
          
          callback(ssid, channel, bssid)
        else
          errorlog("WIFIINFO: request '" .. url .. "' failed - " .. response.status .. " - " .. htmlEscape(response.data))
        end
      end
    
    sendData("WIFIINFO", url, "POST", request, header, false, successFunc )
end

-------------------------------------------------------------------------------
-- Get informations about a device conntected via LAN. This function is used
-- to iterate through all devices. 
-- INPUT: 
-- <interface id> - when your wifi router has more than one LAN port
-- <number> - the index of a device
-- <callback> - function will be calle on success
--
-- Callback arguments:
-- mac address, the hardware address of a device
-- ip address, the IP address of a device
-- active, 0 or 1 if the device is active/connected
-- hostname, the name of the device
local function getLANHostByEntry(interface, number, callback)
    local url = "http://" .. router .. ":" .. tostring(routerPort) .. "/upnp/control/hosts"
    local header = { ["Soapaction"] = "urn:dslforum-org:service:Hosts:" .. tostring(interface) .. "#GetGenericHostEntry", ["Content-Type"] = 'text/xml; charset="UTF-8"' } 
    
    local request = '<?xml version="1.0" encoding="UTF-8"?><s:Envelope s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/" xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><s:Header/><s:Body><u:GetGenericHostEntry xmlns="urn:dslforum-org:service:Hosts:' .. tostring(interface) .. '"><NewIndex>' .. tostring(number) .. '</NewIndex></u:GetGenericHostEntry></s:Body></s:Envelope>'
    
    local successFunc = function(response)
        if (response.status >= 200 and response.status < 300) then
          log(4, "Search lan by entry call was successful: " .. response.status .. " - " .. url)
          
          local macAddress = string.match(response.data, "<NewMACAddress>(.+)</NewMACAddress>")
          local ipAddress = string.match(response.data, "<NewIPAddress>(.+)</NewIPAddress>")
          local active = string.match(response.data, "<NewActive>(.+)</NewActive>")
          local hostname = string.match(response.data, "<NewHostName>(.+)</NewHostName>")
          
          callback(macAddress, ipAddress, active, hostname)
        else
          errorlog(htmlEscape(request))
          errorlog("LANENTRY: request '" .. url .. "' failed - " .. response.status .. " - " .. htmlEscape(response.data))
        end
      end
    
    sendData("LANENTRY", url, "POST", request, header, false, successFunc )
end

-------------------------------------------------------------------------------
-- Get informations about a dedicated device conntected via LAN. 
-- INPUT: 
-- <interface id> - when your wifi router has more than one wifi network, like 2,4 vs 5 Ghz or guest network
-- <macAddress> - the hardware address of the device you are looking for, a Fritz.Box expects the string to be uppercase for LAN Mac
-- <callback> - function will be calle on success
--
-- Callback arguments:
-- ip address, the IP address of a device
-- active, 0 or 1 if the device is active/connected
-- hostname, the name of the device
local function getLANHostByMACAddress(interface, macAddress, callback)
    local url = "http://" .. router .. ":" .. tostring(routerPort) .. "/upnp/control/hosts"
    local header = { ["Soapaction"] = "urn:dslforum-org:service:Hosts:" .. tostring(interface) .. "#GetSpecificHostEntry", ["Content-Type"] = 'text/xml; charset="UTF-8"' } 
    
    local request = '<?xml version="1.0" encoding="UTF-8"?><s:Envelope s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/" xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><s:Header/><s:Body><u:GetSpecificHostEntry xmlns="urn:dslforum-org:service:Hosts:'  .. tostring(interface) .. '"><NewMACAddress>' .. macAddress .. '</NewMACAddress></u:GetSpecificHostEntry></s:Body></s:Envelope>'
    
    local successFunc = function(response)
        if (response.status >= 200 and response.status < 300) then
          log(4, "Search lan by mac call was successful: " .. response.status .. " - " .. url)
          
          local ipAddress = string.match(response.data, "<NewIPAddress>(.+)</NewIPAddress>")
          local active = string.match(response.data, "<NewActive>(.+)</NewActive>")
          local hostname = string.match(response.data, "<NewHostName>(.+)</NewHostName>")
          
          callback(ipAddress, active, hostname)
        else
          errorlog("LANMAC: request '" .. url .. "' failed - " .. response.status .. " - " .. htmlEscape(response.data))
        end
      end
    
    sendData("LANMAC", url, "POST", request, header, false, successFunc )
end

-------------------------------------------------------------------------------
-- Get informations about your internet connection
-- <callback> - function will be calle on success
--
-- Callback arguments:
-- uptime, since when is the connection established
-- external IP address, the external/Internet IP address of your router
-- dns server, comma seperated list of ip addresses of your DNS servers
local function getConnectionInfos(callback)
    local url = "http://" .. router .. ":" .. tostring(routerPort) .. "/upnp/control/wanipconnection1"
    local header = { ["Soapaction"] = "urn:dslforum-org:service:WANIPConnection:1#GetInfo", ["Content-Type"] = 'text/xml; charset="UTF-8"' } 
    
    local request = '<?xml version="1.0" encoding="UTF-8"?><s:Envelope s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/" xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><s:Header/><s:Body><u:GetInfo xmlns="urn:dslforum-org:service:WANIPConnection:1"></u:GetInfo></s:Body></s:Envelope>'
    
    local successFunc = function(response)
        if (response.status >= 200 and response.status < 300) then
          log(4, "Connection Info call was successful: " .. response.status .. " - " .. url)
          
          local uptime = string.match(response.data, "<NewUptime>(.+)</NewUptime>")
          local externalIPAddress = string.match(response.data, "<NewExternalIPAddress>(.+)</NewExternalIPAddress>")
          local dnsServer = string.match(response.data, "<NewDNSServers>(.+)</NewDNSServers>")
          
          callback(uptime, externalIPAddress, dnsServer)
        else
          errorlog("WANINFO: request '" .. url .. "' failed - " .. response.status .. " - " .. htmlEscape(response.data))
        end
      end
    
    sendData("WANINFO", url, "POST", request, header, false, successFunc )
end

-------------------------------------------------------------------------------
local function setVariable(variableName, state)
  local variable = fibaro:getGlobal(variableName)
  if variable == nil then
    log(1, "Create variable: " .. variableName)
    api.post("/globalVariables", {name=variableName, isEnum=0})
    variable = fibaro:getGlobal(variableName)
  end
  
  if variable ~= state then
    log(2, "Variable change: " .. variableName .. ": " .. tostring(state))
  end
  
  fibaro:setGlobal(variableName, tostring(state))
end

-------------------------------------------------------------------------------
local function checkDevices()
  for _, deviceDeclaration in ipairs(devices) do
    --Every device declaration contains: "macAddress" = "", "type" = "LAN", "interface" = 1, "variable" = ""
    
    if deviceDeclaration["type"] == "LAN" then
      local callback = function(ipAddress, active, hostname)
          setVariable(deviceDeclaration["variable"], active)
        end
      
      getLANHostByMACAddress(deviceDeclaration["interface"], string.upper(deviceDeclaration["macAddress"]), callback)
    elseif deviceDeclaration["type"] == "WIFI" then
      local callback = function(ipAddress, auth, speed, signal)
          setVariable(deviceDeclaration["variable"], auth)
        end
      getWifiHostByMACAddress(deviceDeclaration["interface"], string.lower(deviceDeclaration["macAddress"]),  callback)
    elseif deviceDeclaration["type"] == nil then
      errorlog("No device type given.")
    else
      errorlog("Given device type if unknown: " .. deviceDeclaration["type"])
    end
  end
end

-------------------------------------------------------------------------------
-- check every X minutes the status of all given devices
local function checkLoop()
  log(4, "Wake up.")
  checkDevices()
  setTimeout(checkLoop, checkDevicesEverySeconds * 1000)
end

-------------------------------------------------------------------------------

local sourceTrigger = fibaro:getSourceTrigger()

if sourceTrigger['type'] == 'autostart' then
  checkLoop()
else
  checkDevices()
end