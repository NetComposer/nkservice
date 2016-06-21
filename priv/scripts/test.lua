print("Hello")

-- function tellme(offset, story)
--     local n,v
--     for n,v in pairs(story) do
--         if n ~= "loaded" and n ~= "_G" then
--     	    io.write (offset .. n .. " " )
-- 	        print (v)
--         	if type(v) == "table" then
--             	tellme(offset .. "--> ",v)
--         	end
--     	end
--        end
-- end

function confirm(p, d)
	return p .. ' (it really is)'
end

-- tellme("", _G)





table1 = {b=2, c={d=3}}

for k in pairs(package.searchers) do
	print("k: " .. k)
end 

return pairs(package)