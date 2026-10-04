-- ennui_style.lua
-- Per-item look: enabled, typeface, size, alignment, padding, letter spacing,
-- case, text color, drop shadow. Plus a few screen-wide extras (build mode,
-- section order, page-number visibility) and preset snapshot/apply.

local Blitbuffer = require("ffi/blitbuffer")
local Font = require("ui/font")
local Store = require("ennui_store")

local Style = {}

Style.PAD_SIDES = { "top", "bottom", "left", "right" }
Style.ITEM_KEYS = { "date", "clock", "weather", "entries" }
Style.SECTION_TITLES = {
    date    = "Date",
    clock   = "Clock",
    weather = "Weather",
    entries = "Plugin entries",
}
Style.COLORS = { "black", "white", "gray" }

-- Defaults (unscaled units, like the rest of EnnUI's sizes/paddings).
Style.ITEMS = {
    date    = { size = 22, on = false, pad = { top = 0,  bottom = 0, left = 0, right = 0 } },
    clock   = { size = 84, on = true,  legacy = "clock", pad = { top = 0,  bottom = 0, left = 0, right = 0 } },
    weather = { size = 22, on = false, legacy = "weather", pad = { top = 6,  bottom = 0, left = 0, right = 0 } },
    entries = { size = 30, on = true,  pad = { top = 22, bottom = 0, left = 0, right = 0 } },
}

-- A small, constant gap from the very top of the screen, applied once before
-- whichever section is shown first.
Style.BASE_TOP = 22

function Style.on(key)
    local def = Style.ITEMS[key]
    local value = Store.get(key .. "_on")
    if value == nil and def.legacy then
        value = Store.get(def.legacy) -- setting name used by the first version
    end
    if value == nil then
        return def.on
    end
    return value == true
end

function Style.setOn(key, value)
    Store.set(key .. "_on", value and true or false)
end

function Style.toggle(key)
    local value = not Style.on(key)
    Style.setOn(key, value)
    return value
end

-- The date follows the weather's typeface and size until it gets its own.
function Style.fontName(key)
    local value = Store.get(key .. "_font")
    if (value == nil or value == "") and key == "date" then
        value = Store.get("weather_font")
    end
    if type(value) == "string" and value ~= "" then
        return value
    end
    return nil
end

function Style.size(key)
    local value = tonumber(Store.get(key .. "_size"))
    if not value and key == "date" then
        value = tonumber(Store.get("weather_size"))
    end
    return value or Style.ITEMS[key].size
end

function Style.align(key)
    local value = Store.get(key .. "_align")
    if value == "center" or value == "right" then
        return value
    end
    return "left"
end

-- {top, bottom, left, right}, each defaulting to this item's own default.
function Style.padding(key)
    local base = Style.ITEMS[key].pad or {}
    local out = {}
    for _i, side in ipairs(Style.PAD_SIDES) do
        local value = tonumber(Store.get(key .. "_pad_" .. side))
        out[side] = value or base[side] or 0
    end
    return out
end

-- Extra space between letters, in unscaled px. 0 = off (the default look).
function Style.spacing(key)
    return tonumber(Store.get(key .. "_spacing")) or 0
end

-- "none" / "lower" / "upper" / "title".
function Style.case(key)
    local value = Store.get(key .. "_case")
    if value == "lower" or value == "upper" or value == "title" then
        return value
    end
    return "none"
end

local function titleCase(text)
    return (text:gsub("(%a)([%w']*)", function(first, rest) return first:upper() .. rest:lower() end))
end

-- Applies this item's case setting to a piece of dynamic text (not to
-- instructional/hint sentences, which callers should leave untouched).
function Style.applyCase(key, text)
    local mode = Style.case(key)
    if mode == "lower" then
        return text:lower()
    elseif mode == "upper" then
        return text:upper()
    elseif mode == "title" then
        return titleCase(text)
    end
    return text
end

-- "black" / "white" / "gray" -> a Blitbuffer color.
function Style.colorValue(name)
    if name == "white" then
        return Blitbuffer.COLOR_WHITE
    elseif name == "gray" then
        return Blitbuffer.gray and Blitbuffer.gray(0.5) or Blitbuffer.COLOR_DARK_GRAY
    end
    return Blitbuffer.COLOR_BLACK
end

-- This item's own text color ("black" by default).
function Style.color(key)
    local value = Store.get(key .. "_color")
    if value == "white" or value == "gray" then
        return value
    end
    return "black"
end

function Style.colorFace(key)
    return Style.colorValue(Style.color(key))
end

-- This item's text effect: "off", "outline" or "shadow". A plugin entry
-- saved before 0.6 only had an on/off shadow flag; that's honoured as a
-- fallback when no mode has been chosen explicitly.
function Style.effect(key)
    local value = Store.get(key .. "_effect")
    if value == "off" or value == "outline" or value == "shadow" then
        return value
    end
    if Store.on(key .. "_shadow_on", false) then
        return "shadow"
    end
    return "off"
end

-- Shared by outline and drop shadow (they're either/or, so one color serves both).
function Style.effectColor(key)
    local value = Store.get(key .. "_effect_color")
    if value == "black" or value == "white" or value == "gray" then
        return value
    end
    local legacy = Store.get(key .. "_shadow_color")
    if legacy == "black" or legacy == "white" then
        return legacy
    end
    return "gray"
end

function Style.effectColorFace(key)
    return Style.colorValue(Style.effectColor(key))
end

-- Drop-shadow offset (only meaningful when effect(key) == "shadow").
function Style.shadowOffset(key)
    return {
        dx = tonumber(Store.get(key .. "_shadow_dx")) or 2,
        dy = tonumber(Store.get(key .. "_shadow_dy")) or 2,
    }
end

-- Outline thickness, 1-10 (only meaningful when effect(key) == "outline").
function Style.outlineThickness(key)
    local value = tonumber(Store.get(key .. "_outline_thickness"))
    if value and value >= 1 and value <= 10 then
        return math.floor(value)
    end
    return 1
end

-- Whether the clock shows "AM"/"PM" (the clock is always 12-hour).
function Style.showAmPm()
    local value = Store.get("clock_ampm")
    if value == nil then
        return true
    end
    return value == true
end

-- Whether the weather line adds "· 2h ago" when showing cached data.
function Style.showWeatherAge()
    return Store.on("weather_show_age", true)
end

-- Long-press a home-screen section to jump straight to its settings.
function Style.buildMode()
    return Store.on("build_mode", false)
end

-- Whether the bottom-right page indicator is shown when there's more than one page.
function Style.showPageNumber()
    return Store.on("show_page_number", true)
end

-- "☑"/"☐" (default) or the original "On"/"Off" text, for every toggle row.
function Style.useEmojiCheckbox()
    return Store.on("checkbox_style", true)
end

-- Extra vertical space between plugin-entry rows (each row's own top/bottom padding).
function Style.entryRowGap()
    return tonumber(Store.get("entries_row_gap")) or 9
end

-- 0 = no extra cap beyond whatever fits on screen.
function Style.maxPerPage()
    return tonumber(Store.get("entries_max_per_page")) or 0
end

-- The order home-screen sections are drawn in, top to bottom. Falls back to
-- the built-in order, and drops/adds keys so a stale saved list can't hide a
-- section that still exists.
function Style.sectionOrder()
    local default = { "date", "clock", "weather", "entries" }
    local saved = Store.get("section_order")
    if type(saved) ~= "table" or #saved == 0 then
        return default
    end
    local seen, out = {}, {}
    for _i, key in ipairs(saved) do
        if Style.SECTION_TITLES[key] and not seen[key] then
            seen[key] = true
            out[#out + 1] = key
        end
    end
    for _i, key in ipairs(default) do
        if not seen[key] then
            out[#out + 1] = key
        end
    end
    return out
end

function Style.setSectionOrder(list)
    Store.set("section_order", list)
end

-- Fonts installed in KOReader (the ones its font menu lists). Loaded on first use only.
local fonts

local function loadFonts()
    if fonts then
        return fonts
    end
    fonts = { names = {}, paths = {} }
    local cre
    local ok, engine = pcall(function() return require("document/credocument"):engineInit() end)
    if ok and engine then
        cre = engine
    else
        local ok_lib, lib = pcall(require, "libs/libkoreader-cre")
        if ok_lib then
            cre = lib
        end
    end
    if not cre then
        return fonts
    end
    local ok_faces, faces = pcall(cre.getFontFaces)
    if not ok_faces or type(faces) ~= "table" then
        return fonts
    end
    for _i, name in ipairs(faces) do
        local ok_path, path = pcall(cre.getFontFaceFilenameAndFaceIndex, name)
        if ok_path and type(path) == "string" and path ~= "" then
            fonts.paths[name] = path
            fonts.names[#fonts.names + 1] = name
        end
    end
    table.sort(fonts.names, function(a, b) return a:lower() < b:lower() end)
    return fonts
end

function Style.fontNames()
    return loadFonts().names
end

function Style.fontPath(name)
    return loadFonts().paths[name]
end

-- Face for an item; falls back to KOReader's default UI font.
function Style.face(key)
    local size = Style.size(key)
    local name = Style.fontName(key)
    if name then
        local path = Style.fontPath(name)
        if path then
            local slot = "ennui:" .. name
            Font.fontmap[slot] = path
            local ok, face = pcall(Font.getFace, Font, slot, size)
            if ok and face then
                return face
            end
        end
    end
    return Font:getFace("cfont", size)
end

-- Presets: a snapshot is every style-related setting (appearance and layout),
-- never your ZIP code, plugin entries/folders, or their labels.
local function styleKeys()
    local keys = {
        "section_order", "clock_ampm", "weather_show_age",
        "build_mode", "show_page_number", "entries_row_gap", "entries_max_per_page",
        "wallpaper_on", "wallpaper_path", "wallpaper_fit", "wallpaper_lighten",
    }
    for _i, item in ipairs(Style.ITEM_KEYS) do
        for _j, suffix in ipairs({ "_on", "_font", "_size", "_align", "_spacing", "_case", "_color",
                                    "_pad_top", "_pad_bottom", "_pad_left", "_pad_right",
                                    "_effect", "_effect_color", "_shadow_dx", "_shadow_dy", "_outline_thickness" }) do
            keys[#keys + 1] = item .. suffix
        end
    end
    return keys
end
Style.styleKeys = styleKeys

-- { [key] = value, ... } for every style key currently set (keys left at
-- their default are simply absent, not stored as nil).
function Style.snapshot()
    local snap = {}
    for _i, key in ipairs(styleKeys()) do
        local value = Store.get(key)
        if value ~= nil then
            snap[key] = value
        end
    end
    return snap
end

-- A preset saved before 0.5 stored one universal text color and one universal
-- drop shadow. Expands those into the same per-item keys every item now uses,
-- so an old preset still looks the way it used to.
local function migrateLegacy(snapshot)
    if snapshot.text_color == nil and snapshot.shadow == nil
        and snapshot.shadow_dx == nil and snapshot.shadow_dy == nil then
        return snapshot
    end
    local migrated = {}
    for k, v in pairs(snapshot) do
        migrated[k] = v
    end
    for _i, item in ipairs(Style.ITEM_KEYS) do
        if snapshot.text_color ~= nil and migrated[item .. "_color"] == nil then
            migrated[item .. "_color"] = snapshot.text_color
        end
        if snapshot.shadow ~= nil and migrated[item .. "_effect"] == nil then
            migrated[item .. "_effect"] = snapshot.shadow and "shadow" or "off"
        end
        if snapshot.shadow_dx ~= nil and migrated[item .. "_shadow_dx"] == nil then
            migrated[item .. "_shadow_dx"] = snapshot.shadow_dx
        end
        if snapshot.shadow_dy ~= nil and migrated[item .. "_shadow_dy"] == nil then
            migrated[item .. "_shadow_dy"] = snapshot.shadow_dy
        end
    end
    migrated.text_color, migrated.shadow, migrated.shadow_dx, migrated.shadow_dy = nil, nil, nil, nil
    return migrated
end

-- Applies a snapshot: every style key is set to the snapshot's value, or
-- cleared back to default if the snapshot doesn't mention it. This makes the
-- result the same regardless of whatever style was in place before.
function Style.applyPreset(snapshot)
    snapshot = migrateLegacy(snapshot)
    for _i, key in ipairs(styleKeys()) do
        Store.set(key, snapshot[key])
    end
end

return Style
