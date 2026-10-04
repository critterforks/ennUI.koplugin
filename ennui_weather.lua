-- ennui_weather.lua
-- Current weather from a ZIP/postal code. Keyless services, cached, never forces Wi-Fi on.
--   ZIP -> coordinates: api.zippopotam.us   (looked up once, then stored)
--   coordinates -> weather: api.open-meteo.com

local logger = require("logger")
local _ = require("gettext")
local Store = require("ennui_store")
local Style = require("ennui_style")
local Weather = {}

local CACHE_TTL = 30 * 60 -- seconds

local function isOnline()
    local ok, NetworkMgr = pcall(require, "ui/network/manager")
    if not ok or not NetworkMgr then
        return false
    end
    local ok_w, wifi_on = pcall(function() return NetworkMgr:isWifiOn() end)
    if ok_w and wifi_on == false then
        return false
    end
    local ok_c, online = pcall(function()
        if NetworkMgr.isOnline then
            return NetworkMgr:isOnline()
        end
        return NetworkMgr:isConnected()
    end)
    return ok_c and online == true
end

local function getJSON(url)
    local ok, result = pcall(function()
        local http = require("socket/http")
        local ltn12 = require("ltn12")
        local socket = require("socket")
        local socketutil = require("socketutil")
        local json = require("json")
        local chunks = {}
        socketutil:set_timeout(4, 8)
        local code, headers = socket.skip(1, http.request({
            url = url,
            method = "GET",
            headers = { ["User-Agent"] = "KOReader-EnnUI" },
            sink = ltn12.sink.table(chunks),
            redirect = true,
        }))
        socketutil:reset_timeout()
        if code ~= 200 or headers == nil then
            return nil
        end
        return json.decode(table.concat(chunks))
    end)
    pcall(function() require("socketutil"):reset_timeout() end)
    if ok then
        return result
    end
    logger.warn("ennui: request failed:", tostring(result))
    return nil
end

local function esc(s)
    return (tostring(s):gsub("[^%w_%-%.~]", function(c)
        return string.format("%%%02X", c:byte())
    end))
end

local function geocode(zip, country)
    -- zippopotam.us wants only the first part of GB / CA postcodes.
    if country == "GB" or country == "CA" then
        zip = zip:match("^%S+") or zip
    end
    local data = getJSON(string.format("https://api.zippopotam.us/%s/%s", esc(country:lower()), esc(zip)))
    local place = type(data) == "table" and type(data.places) == "table" and data.places[1]
    if type(place) ~= "table" then
        return nil
    end
    local lat, lon = tonumber(place.latitude), tonumber(place.longitude)
    if not lat or not lon then
        return nil
    end
    return lat, lon
end

-- WMO weather codes -> one short word.
local function condition(code)
    if type(code) ~= "number" then return "" end
    if code <= 1 then return _("Clear") end
    if code == 2 then return _("Partly cloudy") end
    if code == 3 then return _("Overcast") end
    if code == 45 or code == 48 then return _("Fog") end
    if code >= 51 and code <= 57 then return _("Drizzle") end
    if code >= 61 and code <= 67 then return _("Rain") end
    if code >= 71 and code <= 77 then return _("Snow") end
    if code >= 80 and code <= 82 then return _("Showers") end
    if code == 85 or code == 86 then return _("Snow showers") end
    if code >= 95 then return _("Thunderstorm") end
    return ""
end

local function ago(secs)
    if secs < 3600 then
        return string.format(_("%dm ago"), math.max(1, math.floor(secs / 60)))
    elseif secs < 48 * 3600 then
        return string.format(_("%dh ago"), math.floor(secs / 3600))
    end
    return string.format(_("%dd ago"), math.floor(secs / 86400))
end

-- Text for the home screen ("14°C Cloudy"), or nil when there is nothing to show.
-- Adds "· 2h ago" only when the cached data is older than the refresh interval.
function Weather.display()
    local cache = Store.get("weather_cache")
    if type(cache) ~= "table" or type(cache.temp_c) ~= "number" then
        return nil
    end
    local unit = Store.get("weather_unit", "C")
    local temp = cache.temp_c
    if unit == "F" then
        temp = temp * 9 / 5 + 32
    end
    local text = string.format("%d°%s", math.floor(temp + 0.5), unit == "F" and "F" or "C")
    local word = condition(cache.code)
    if word ~= "" then
        text = text .. " " .. word
    end
    local age = os.time() - (cache.time or 0)
    if age > CACHE_TTL and Style.showWeatherAge() then
        text = text .. " · " .. ago(age)
    end
    return text
end

function Weather.online()
    return isOnline()
end

-- Fetches fresh data when the cache is stale (or `force` is set) and Wi-Fi is already up;
-- it never turns Wi-Fi on. Returns true when new data was stored, otherwise false plus a
-- reason: "disabled", "no_zip", "fresh", "offline", "geocode" or "fetch".
function Weather.refresh(force)
    if not Style.on("weather") then
        return false, "disabled"
    end
    local zip = Store.get("weather_zip", "")
    local country = Store.get("weather_country", "US")
    if zip == "" then
        return false, "no_zip"
    end
    local cache = Store.get("weather_cache")
    if not force and type(cache) == "table" and cache.zip == zip and cache.country == country
        and cache.time and math.abs(os.time() - cache.time) < CACHE_TTL then
        return false, "fresh"
    end
    if not isOnline() then
        return false, "offline"
    end
    local geo = Store.get("weather_geo")
    if not (type(geo) == "table" and geo.zip == zip and geo.country == country and geo.lat and geo.lon) then
        local lat, lon = geocode(zip, country)
        if not lat then
            return false, "geocode"
        end
        geo = { zip = zip, country = country, lat = lat, lon = lon }
        Store.set("weather_geo", geo)
    end
    local data = getJSON(string.format(
        "https://api.open-meteo.com/v1/forecast?latitude=%.4f&longitude=%.4f&current_weather=true",
        geo.lat, geo.lon))
    local current = type(data) == "table" and data.current_weather
    if type(current) ~= "table" or type(current.temperature) ~= "number" then
        return false, "fetch"
    end
    Store.set("weather_cache", {
        time = os.time(),
        temp_c = current.temperature,
        code = current.weathercode,
        zip = zip,
        country = country,
    })
    return true
end

return Weather
