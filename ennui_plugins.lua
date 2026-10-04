-- ennui_plugins.lua
-- Finds the menu entries that loaded plugins register (the same ones KOReader's
-- top menu shows) and runs them, so the home screen can launch them.

local Device = require("device")
local UIManager = require("ui/uimanager")
local logger = require("logger")

local Screen = Device.screen

local Plugins = {}

local function safe(fn, ...)
    if type(fn) ~= "function" then
        return nil
    end
    local ok, result = pcall(fn, ...)
    if ok then
        return result
    end
    return nil
end

local function entryText(entry)
    local text = entry.text
    if text == nil and entry.text_func then
        text = safe(entry.text_func)
    end
    if type(text) ~= "string" or text == "" then
        return nil
    end
    return text
end

local function subItems(entry)
    local sub = entry.sub_item_table
    if sub == nil and entry.sub_item_table_func then
        sub = safe(entry.sub_item_table_func)
    end
    if type(sub) == "table" then
        return sub
    end
    return nil
end

-- Menu callbacks receive KOReader's TouchMenu; hand them something harmless.
local function noopMenu()
    return setmetatable({}, { __index = function() return function() end end })
end

local function liveFileManager()
    local FileManager = package.loaded["apps/filemanager/filemanager"]
    return FileManager and FileManager.instance or nil
end

-- Returns { { id, text, entry, source }, ... } sorted by text.
function Plugins.scan()
    local out, seen = {}, {}
    local fm = liveFileManager()
    if not fm then
        return out
    end
    for i = 1, #fm do
        local widget = fm[i]
        if type(widget) == "table" and type(widget.addToMainMenu) == "function" and widget.name ~= "ennui" then
            local probe = {}
            if pcall(widget.addToMainMenu, widget, probe) then
                for key, entry in pairs(probe) do
                    if type(entry) == "table" and (entry.callback or entry.sub_item_table or entry.sub_item_table_func) then
                        local text = entryText(entry)
                        local source = tostring(widget.name or key)
                        local id = source .. "|" .. tostring(key)
                        if text and not seen[id] then
                            seen[id] = true
                            out[#out + 1] = { id = id, text = text, entry = entry, source = source }
                        end
                    end
                end
            end
        end
    end
    local counts = {}
    for _i, e in ipairs(out) do
        local k = e.text:lower()
        counts[k] = (counts[k] or 0) + 1
    end
    for _i, e in ipairs(out) do
        if counts[e.text:lower()] > 1 then
            e.text = e.text .. " (" .. e.source .. ")"
        end
    end
    table.sort(out, function(a, b) return a.text:lower() < b.text:lower() end)
    return out
end

-- A simple list for entries that have a sub-menu (New game / Continue / ...).
function Plugins.showSubMenu(title, items)
    local Menu = require("ui/widget/menu")

    local function build()
        local list = {}
        for _i, item in ipairs(items) do
            if type(item) == "table" then
                local text = entryText(item)
                local enabled = item.enabled ~= false
                if enabled and item.enabled_func then
                    enabled = safe(item.enabled_func) ~= false
                end
                local sub = subItems(item)
                if text and enabled and (item.callback or sub) then
                    local checked = item.checked
                    if item.checked_func then
                        checked = safe(item.checked_func)
                    end
                    list[#list + 1] = {
                        text = text,
                        mandatory = checked and "✓" or (sub and "›" or nil),
                        _item = item,
                    }
                end
            end
        end
        return list
    end

    local menu = Menu:new{
        title = title,
        item_table = build(),
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        is_borderless = true,
        is_popout = false,
        covers_fullscreen = true,
        onMenuSelect = function(m, row)
            local item = row._item
            if not item then
                return true
            end
            local sub = subItems(item)
            if sub then
                Plugins.showSubMenu(entryText(item) or title, sub)
            elseif type(item.callback) == "function" then
                if item.keep_menu_open then
                    pcall(item.callback, noopMenu())
                    local fresh = build()
                    for i = #m.item_table, 1, -1 do
                        m.item_table[i] = nil
                    end
                    for i, v in ipairs(fresh) do
                        m.item_table[i] = v
                    end
                    m:updateItems()
                else
                    UIManager:close(m)
                    local ok, err = pcall(item.callback, noopMenu())
                    if not ok then
                        logger.err("ennui: menu action failed:", tostring(err))
                    end
                end
            end
            return true
        end,
    }
    UIManager:show(menu)
end

-- Runs a saved entry ({ id, text }). Returns true, or false plus a reason.
function Plugins.launch(saved)
    local found
    for _i, e in ipairs(Plugins.scan()) do
        if e.id == saved.id then
            found = e
            break
        end
    end
    if not found then
        return false, "not available"
    end
    local sub = subItems(found.entry)
    if sub then
        Plugins.showSubMenu(saved.text or found.text, sub)
        return true
    end
    if type(found.entry.callback) == "function" then
        local ok, err = pcall(found.entry.callback, noopMenu())
        if not ok then
            logger.err("ennui: plugin entry failed:", tostring(err))
            return false, tostring(err)
        end
        return true
    end
    return false, "not runnable"
end

return Plugins
