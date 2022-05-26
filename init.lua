station_cfg = {}
publishing_mqtt = false
publishing_http = false

watchdog = tmr.create()
chip_id = string.format("%06X", node.chipid())
device_id = "esp8266_" .. chip_id
mqtt_prefix = "sensor/" .. device_id
mqttclient = mqtt.Client(device_id, 120)

dofile("config.lua")

print("ESP8266 " .. chip_id)

ledpin = 4
gpio.mode(ledpin, gpio.OUTPUT)
gpio.write(ledpin, 0)

mh_z19 = require("mh-z19")

poll = tmr.create()

function log_restart()
	print("Network error " .. wifi.sta.status())
end

function setup_client()
	print("Connected")
	gpio.write(ledpin, 1)
	port = softuart.setup(9600, 1, 2)
	port:on("data", 9, uart_callback)
	publishing_mqtt = true
	mqttclient:publish(mqtt_prefix .. "/state", "online", 0, 1, function(client)
		publishing_mqtt = false
		query_data()
		poll:start()
	end)
end

function connect_mqtt()
	print("IP address: " .. wifi.sta.getip())
	print("Connecting to MQTT " .. mqtt_host)
	mqttclient:on("connect", hass_register)
	mqttclient:on("offline", log_restart)
	mqttclient:lwt(mqtt_prefix .. "/state", "offline", 0, 1)
	mqttclient:connect(mqtt_host)
end

function connect_wifi()
	print("WiFi MAC: " .. wifi.sta.getmac())
	print("Connecting to ESSID " .. station_cfg.ssid)
	wifi.eventmon.register(wifi.eventmon.STA_GOT_IP, connect_mqtt)
	wifi.eventmon.register(wifi.eventmon.STA_DHCP_TIMEOUT, log_restart)
	wifi.eventmon.register(wifi.eventmon.STA_DISCONNECTED, log_restart)
	wifi.setmode(wifi.STATION)
	wifi.sta.config(station_cfg)
	wifi.sta.connect()
end

function uart_callback(data)
	if not mh_z19.parse_frame(data) then
		print("Invalid MH-Z19 frame")
		return
	end

	local json_str = string.format('{"rssi_dbm":%d,"co2_ppm":"%d"}', wifi.sta.getrssi(), mh_z19.co2)
	local influx_str = string.format("co2_ppm=%d", mh_z19.co2)

	if not publishing_mqtt then
		watchdog:start(true)
		publishing_mqtt = true
		gpio.write(ledpin, 0)
		mqttclient:publish(mqtt_prefix .. "/data", json_str, 0, 0, function(client)
			publishing_mqtt = false
			if influx_url and influx_attr and influx_str then
				publish_influx(influx_str)
			else
				gpio.write(ledpin, 1)
				collectgarbage()
			end
		end)
	end
end

function publish_influx(payload)
	if not publishing_http then
		publishing_http = true
		http.post(influx_url, influx_header, "mh_z19" .. influx_attr .. " " .. payload, function(code, data)
			publishing_http = false
			gpio.write(ledpin, 1)
			collectgarbage()
		end)
	end
end

function query_data()
	port:write(mh_z19.c_query)
end

function hass_register()
	local hass_device = string.format('{"connections":[["mac","%s"]],"identifiers":["%s"],"model":"ESP8266 + MH-Z19","name":"MH-Z19 %s","manufacturer":"derf"}', wifi.sta.getmac(), device_id, chip_id)
	local hass_entity_base = string.format('"device":%s,"state_topic":"%s/data","expire_after":120', hass_device, mqtt_prefix)
	local hass_co2 = string.format('{%s,"name":"CO₂","object_id":"%s_co2","unique_id":"%s_co2","device_class":"carbon_dioxide","unit_of_measurement":"ppm","value_template":"{{value_json.co2_ppm}}"}', hass_entity_base, device_id, device_id)
	local hass_rssi = string.format('{%s,"name":"RSSI","object_id":"%s_rssi","unique_id":"%s_rssi","device_class":"signal_strength","unit_of_measurement":"dBm","value_template":"{{value_json.rssi_dbm}}","entity_category":"diagnostic"}', hass_entity_base, device_id, device_id)

	mqttclient:publish("homeassistant/sensor/" .. device_id .. "/co2/config", hass_co2, 0, 1, function(client)
		mqttclient:publish("homeassistant/sensor/" .. device_id .. "/rssi/config", hass_rssi, 0, 1, function(client)
			collectgarbage()
			setup_client()
		end)
	end)
end

watchdog:register(180 * 1000, tmr.ALARM_SEMI, node.restart)
poll:register(20 * 1000, tmr.ALARM_AUTO, query_data)
watchdog:start()

connect_wifi()
