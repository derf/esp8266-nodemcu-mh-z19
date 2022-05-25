local mhz19 = {}

local c_read = string.char(0xff, 0x01, 0x86, 0x00, 0x00, 0x00, 0x00, 0x00, 0x79)

mhz19.co2 = nil
mhz19.temp = nil
mhz19.tt = nil
mhz19.ss = nil
mhz19.uu = nil

function mhz19.query()
	return c_read
end

function mhz19.parse_frame(data)
	local head, cmd, co2h, co2l, temp, tt, ss, uh, ul = struct.unpack("BBBBBBBBB", data)
	if head ~= 0xff or cmd ~= 0x86 then
		return false
	end
	mhz19.co2 = co2h * 256 + co2l
	mhz19.temp = temp - 40
	mhz19.tt = tt
	mhz19.ss = ss
	mhz19.uu = uh * 256 + ul
	return true
end

return mhz19
