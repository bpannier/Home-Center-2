--[[
%% properties
%% events
%% globals
--]]

-- A scene which shows all known functions and variables available on a Fibaro Home Center 2.
-- Original from: https://forum.fibaro.com/index.php?/topic/28094-solved-how-to-get-scene-id-within-its-code/&tab=comments#comment-137115


function printTable(tab,indt, pre)
  if type(tab) ~= 'table' then
    print(string.format("%s %s",indt,tostring(tab)))
  elseif tab[1] then
    for i,j in ipairs(tab) do
      printTable(j,indt)
    end
  else
    local funcsTable = {}
    for i,j in pairs(tab) do
      if type(j) == 'table' then
        funcsTable[tostring(i)] = j
      else
        print(string.format("%s %s = %s",indt,tostring(i),tostring(j)))
      end
    end
    for i,j in pairs(funcsTable) do
      print()
      local className
      if string.len(pre) == 0 then
        className = tostring(i)
      else
      	className = pre .. ":" .. tostring(i)
      end
      print(string.format("%sTable %s",indt,className))
      printTable(j,indt.."-",className)
    end
  end
end

printTable(_ENV,"","")