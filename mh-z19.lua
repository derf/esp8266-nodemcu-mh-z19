local mh_z19 = {}

mh_z19.c_query = string.char(0xff, 0x01, 0x86, 0x00, 0x00, 0x00, 0x00, 0x00, 0x79)

mh_z19.co2 = nil
mh_z19.temp = nil
mh_z19.abc_count = nil
mh_z19.abc_ticks = nil

function checksum(b1, b2, b3, b4, b5, b6, b7)
	return 0xff - ((b1 + b2 + b3 + b4 + b5 + b6 + b7) % 0x100) + 1
end

function mh_z19.parse_frame(data)
	local start, cmd, co2h, co2l, temp, u1, abc_ticks, abc_count, cksum = struct.unpack("BBBBBBBBB", data)
	if start ~= 0xff or cmd ~= 0x86 then
		return false
	end
	if checksum(cmd, co2h, co2l, temp, u1, abc_ticks, abc_count) ~= cksum then
		return false
	end
	mh_z19.co2 = co2h * 256 + co2l
	mh_z19.temp = temp - 40
	mh_z19.abc_ticks = abc_ticks
	mh_z19.abc_count = abc_count
	return true
end

return mh_z19
