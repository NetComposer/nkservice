function test2()
	for k,v in pairs(package.loaded._G.log) do
		print ("k: " .. k)
	end
end


function log1(txt)
	log.warning(txt)
end