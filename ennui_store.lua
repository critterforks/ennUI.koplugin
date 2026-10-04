-- ennui_store.lua
-- Tiny persistent settings wrapper: one file in KOReader's settings folder.

local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")

local Store = {}

local settings

local function open()
    if not settings then
        settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/ennui.lua")
    end
    return settings
end

function Store.get(key, default)
    local value = open():readSetting(key)
    if value == nil then
        return default
    end
    return value
end

function Store.set(key, value)
    local s = open()
    if value == nil then
        s:delSetting(key)
    else
        s:saveSetting(key, value)
    end
    s:flush()
end

-- Boolean setting with an explicit default for "never set".
function Store.on(key, default)
    local value = open():readSetting(key)
    if value == nil then
        return default and true or false
    end
    return value == true
end

function Store.toggle(key, default)
    local new_value = not Store.on(key, default)
    Store.set(key, new_value)
    return new_value
end

return Store
