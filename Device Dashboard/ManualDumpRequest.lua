--[[
%% properties
%% events
%% globals
--]]

-- an example how to dump values to an influxdb manually
-- change the first parameter to your scene ID of the main scene

fibaro:startScene(4, {{deviceClass = 'a', deviceName = 'b', values = '"c":1, "d":2'},{deviceClass = 'e', deviceName = 'f', values = '"g":1, "h":2'}})

