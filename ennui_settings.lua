-- ennui_settings.lua
-- Settings > (Date, Clock, Weather, Plugin entries)
--          > that entry's own settings: Enabled, Alignment, Padding,
--            Text Style (typeface/size/spacing/case/color) and Drop Shadow /
--            Outline (mode/color/offsets/thickness) as their own submenus,
--            plus whatever's specific to that item.
--          Also Section order, Wallpaper, Extras (Build Mode, presets), and
--          the plugin version. Settings itself is reached only by swiping up
--          from the bottom of the home screen.

local DataStorage = require("datastorage")
local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")
local _ = require("gettext")

-- Bump this alongside _meta.lua's version field; reading it back from _meta.lua
-- at runtime isn't reliable inside KOReader's plugin loader.
local VERSION = "1.0.0"

local Entries = require("ennui_entries")
local Store = require("ennui_store")
local Style = require("ennui_style")
local UI = require("ennui_ui")
local Wallpaper = require("ennui_wallpaper")
local Weather = require("ennui_weather")

local Settings = {}

local function onoff(value)
    if Style.useEmojiCheckbox() then
        return value and "☑" or "☐"
    end
    return value and _("On") or _("Off")
end

local ALIGN_NEXT = { left = "center", center = "right", right = "left" }

local function alignLabel(value)
    if value == "center" then
        return _("Center")
    elseif value == "right" then
        return _("Right")
    end
    return _("Left")
end

local CASE_NEXT = { none = "lower", lower = "upper", upper = "title", title = "none" }
local CASE_LABEL = { none = _("None"), lower = _("lowercase"), upper = _("UPPERCASE"), title = _("Title Case") }

local COLOR_NEXT = { black = "white", white = "gray", gray = "black" }
local COLOR_LABEL = { black = _("Black"), white = _("White"), gray = _("50% gray") }

local PAD_LABEL = { top = _("Top"), bottom = _("Bottom"), left = _("Left"), right = _("Right") }

-- Typeface, size, padding and spacing pickers ---------------------------------------------

local function chooseFont(key, on_change)
    local names = Style.fontNames()
    if #names == 0 then
        UI.info(_("No fonts were found."))
        return
    end
    local current = Store.get(key .. "_font")
    local items = {
        {
            text = _("Default"),
            mandatory = (current == nil or current == "") and "✓" or nil,
            value = false,
        },
    }
    for _i, name in ipairs(names) do
        items[#items + 1] = {
            text = name,
            mandatory = (current == name) and "✓" or nil,
            value = name,
        }
    end
    for _i, row in ipairs(items) do
        row.action = function(m)
            Store.set(key .. "_font", row.value or nil)
            UIManager:close(m)
        end
    end
    UI.newMenu(_("Typeface"), items, on_change)
end

local function chooseSize(key, on_change)
    local SpinWidget = require("ui/widget/spinwidget")
    UIManager:show(SpinWidget:new{
        title_text = _("Font size"),
        value = Style.size(key),
        value_min = 8,
        value_max = 200,
        value_step = 1,
        value_hold_step = 5,
        default_value = Style.ITEMS[key].size,
        ok_text = _("Apply"),
        cancel_text = _("Cancel"),
        callback = function(spin)
            Store.set(key .. "_size", spin.value)
            on_change()
        end,
    })
end

local function chooseSpacing(key, on_change)
    local SpinWidget = require("ui/widget/spinwidget")
    UIManager:show(SpinWidget:new{
        title_text = _("Letter spacing"),
        info_text = _("Extra space between letters. 0 is the default."),
        value = Style.spacing(key),
        value_min = -20,
        value_max = 20,
        value_step = 1,
        default_value = 0,
        ok_text = _("Apply"),
        cancel_text = _("Cancel"),
        callback = function(spin)
            Store.set(key .. "_spacing", spin.value)
            on_change()
        end,
    })
end

local function chooseShadowOffset(key, axis, on_change)
    local SpinWidget = require("ui/widget/spinwidget")
    local offset = Style.shadowOffset(key)
    UIManager:show(SpinWidget:new{
        title_text = axis == "dx" and _("Shadow horizontal offset") or _("Shadow vertical offset"),
        value = offset[axis],
        value_min = -10,
        value_max = 10,
        value_step = 1,
        default_value = 2,
        ok_text = _("Apply"),
        cancel_text = _("Cancel"),
        callback = function(spin)
            Store.set(key .. "_shadow_" .. axis, spin.value)
            on_change()
        end,
    })
end

local function openPadding(key, on_close)
    local menu, refresh

    local function build()
        local rows = {}
        for _i, side in ipairs(Style.PAD_SIDES) do
            rows[#rows + 1] = {
                text = PAD_LABEL[side],
                mandatory = tostring(Style.padding(key)[side]),
                action = function()
                    local SpinWidget = require("ui/widget/spinwidget")
                    UIManager:show(SpinWidget:new{
                        title_text = PAD_LABEL[side] .. " " .. _("padding"),
                        value = Style.padding(key)[side],
                        value_min = -40,
                        value_max = 120,
                        value_step = 1,
                        value_hold_step = 5,
                        default_value = Style.ITEMS[key].pad[side] or 0,
                        ok_text = _("Apply"),
                        cancel_text = _("Cancel"),
                        callback = function(spin)
                            Store.set(key .. "_pad_" .. side, spin.value)
                            refresh()
                        end,
                    })
                end,
            }
        end
        return rows
    end

    refresh = function()
        UI.refreshItems(menu, build())
    end
    menu = UI.newMenu(_("Padding"), build(), on_close)
end

-- Text Style and Drop Shadow (one item's own typeface/size/.../color, and shadow) -----------

local function openTextStyle(key, on_close)
    local menu, refresh

    local function build()
        return {
            {
                text = _("Typeface"),
                mandatory = Style.fontName(key) or _("Default"),
                action = function() chooseFont(key, refresh) end,
            },
            {
                text = _("Font size"),
                mandatory = tostring(Style.size(key)),
                action = function() chooseSize(key, refresh) end,
            },
            {
                text = _("Letter spacing"),
                mandatory = tostring(Style.spacing(key)),
                action = function() chooseSpacing(key, refresh) end,
            },
            {
                text = _("Case"),
                mandatory = CASE_LABEL[Style.case(key)],
                action = function()
                    Store.set(key .. "_case", CASE_NEXT[Style.case(key)])
                    refresh()
                end,
            },
            {
                text = _("Color"),
                mandatory = COLOR_LABEL[Style.color(key)],
                action = function()
                    Store.set(key .. "_color", COLOR_NEXT[Style.color(key)])
                    refresh()
                end,
            },
        }
    end

    refresh = function()
        UI.refreshItems(menu, build())
    end
    menu = UI.newMenu(_("Text Style"), build(), on_close)
end

local EFFECT_NEXT = { off = "outline", outline = "shadow", shadow = "off" }
local EFFECT_LABEL = { off = _("Off"), outline = _("Outline"), shadow = _("Drop Shadow") }

local function chooseThickness(key, on_change)
    local SpinWidget = require("ui/widget/spinwidget")
    UIManager:show(SpinWidget:new{
        title_text = _("Outline thickness"),
        value = Style.outlineThickness(key),
        value_min = 1,
        value_max = 10,
        value_step = 1,
        default_value = 1,
        ok_text = _("Apply"),
        cancel_text = _("Cancel"),
        callback = function(spin)
            Store.set(key .. "_outline_thickness", spin.value)
            on_change()
        end,
    })
end

local function openEffect(key, on_close)
    local menu, refresh

    local function build()
        local mode = Style.effect(key)
        local rows = {
            {
                text = _("Mode"),
                mandatory = EFFECT_LABEL[mode],
                action = function()
                    Store.set(key .. "_effect", EFFECT_NEXT[mode])
                    refresh()
                end,
            },
            {
                text = _("Color"),
                mandatory = COLOR_LABEL[Style.effectColor(key)],
                action = function()
                    Store.set(key .. "_effect_color", COLOR_NEXT[Style.effectColor(key)])
                    refresh()
                end,
            },
        }
        if mode == "shadow" then
            local offset = Style.shadowOffset(key)
            rows[#rows + 1] = {
                text = _("Horizontal offset"),
                mandatory = tostring(offset.dx),
                action = function() chooseShadowOffset(key, "dx", refresh) end,
            }
            rows[#rows + 1] = {
                text = _("Vertical offset"),
                mandatory = tostring(offset.dy),
                action = function() chooseShadowOffset(key, "dy", refresh) end,
            }
        elseif mode == "outline" then
            rows[#rows + 1] = {
                text = _("Thickness"),
                mandatory = tostring(Style.outlineThickness(key)),
                action = function() chooseThickness(key, refresh) end,
            }
        end
        return rows
    end

    refresh = function()
        UI.refreshItems(menu, build())
    end
    menu = UI.newMenu(_("Drop Shadow / Outline"), build(), on_close)
end

-- Entry-specific rows --------------------------------------------------------------------

local function clockRows(refresh)
    return {
        {
            text = _("Show AM/PM"),
            mandatory = onoff(Style.showAmPm()),
            action = function()
                Store.set("clock_ampm", not Style.showAmPm())
                refresh()
            end,
        },
    }
end

local function weatherRows(refresh)
    local zip = Store.get("weather_zip", "")
    return {
        {
            text = _("ZIP / postal code"),
            mandatory = zip ~= "" and zip or "—",
            action = function()
                UI.askText(_("ZIP / postal code"), zip, function(value)
                    Store.set("weather_zip", value)
                    Store.set("weather_geo", nil)
                    Store.set("weather_cache", nil)
                    refresh()
                end)
            end,
        },
        {
            text = _("Country code"),
            mandatory = Store.get("weather_country", "US"),
            action = function()
                UI.askText(_("Country code (e.g. US, GB, DE)"), Store.get("weather_country", "US"), function(value)
                    if not value:match("^%a%a$") then
                        UI.info(_("Use a two-letter country code, for example US, GB or DE."))
                        return
                    end
                    Store.set("weather_country", value:upper())
                    Store.set("weather_geo", nil)
                    Store.set("weather_cache", nil)
                    refresh()
                end)
            end,
        },
        {
            text = _("Units"),
            mandatory = Store.get("weather_unit", "C") == "F" and "°F" or "°C",
            action = function()
                Store.set("weather_unit", Store.get("weather_unit", "C") == "F" and "C" or "F")
                refresh()
            end,
        },
        {
            text = _("Show last refreshed"),
            mandatory = onoff(Style.showWeatherAge()),
            action = function()
                Store.set("weather_show_age", not Style.showWeatherAge())
                refresh()
            end,
        },
        {
            text = _("Update now"),
            action = function()
                local InfoMessage = require("ui/widget/infomessage")
                local working = InfoMessage:new{ text = _("Updating weather…") }
                UIManager:show(working)
                UIManager:forceRePaint()
                local ok, updated = pcall(Weather.refresh, true)
                UIManager:close(working)
                if ok and updated then
                    UI.info(_("Weather updated."))
                else
                    UI.info(_("Couldn't update the weather. Check that Wi-Fi is on and the ZIP code and country are right."), 5)
                end
            end,
        },
    }
end

local function chooseRowGap(on_change)
    local SpinWidget = require("ui/widget/spinwidget")
    UIManager:show(SpinWidget:new{
        title_text = _("Row spacing"),
        info_text = _("Space above and below each plugin entry."),
        value = Style.entryRowGap(),
        value_min = 0,
        value_max = 40,
        value_step = 1,
        default_value = 9,
        ok_text = _("Apply"),
        cancel_text = _("Cancel"),
        callback = function(spin)
            Store.set("entries_row_gap", spin.value)
            on_change()
        end,
    })
end

local function chooseMaxPerPage(on_change)
    local SpinWidget = require("ui/widget/spinwidget")
    UIManager:show(SpinWidget:new{
        title_text = _("Max entries per page"),
        info_text = _("0 means no extra limit beyond whatever fits on screen."),
        value = Style.maxPerPage(),
        value_min = 0,
        value_max = 40,
        value_step = 1,
        default_value = 0,
        ok_text = _("Apply"),
        cancel_text = _("Cancel"),
        callback = function(spin)
            Store.set("entries_max_per_page", spin.value)
            on_change()
        end,
    })
end

local function entriesRows(refresh)
    local topContainer = {
        get = function() return Store.get("entries", {}) end,
        set = function(list) Store.set("entries", list) end,
    }
    return {
        {
            text = _("Add or remove plugins"),
            action = function() Entries.openPicker(topContainer, refresh) end,
        },
        {
            text = _("Edit entries (order, rename, folders)"),
            mandatory = tostring(#Store.get("entries", {})),
            action = function() Entries.openOrder(refresh) end,
        },
        {
            text = _("Row spacing"),
            mandatory = tostring(Style.entryRowGap()),
            action = function() chooseRowGap(refresh) end,
        },
        {
            text = _("Max entries per page"),
            mandatory = Style.maxPerPage() > 0 and tostring(Style.maxPerPage()) or _("Auto-fit to page"),
            action = function() chooseMaxPerPage(refresh) end,
        },
        {
            text = _("Show page number"),
            mandatory = onoff(Style.showPageNumber()),
            action = function()
                Store.set("show_page_number", not Style.showPageNumber())
                refresh()
            end,
        },
    }
end

-- One entry's settings screen -------------------------------------------------------------

local ITEM_DEFS = {
    { key = "date",    title = _("Date"),           align = true },
    { key = "clock",   title = _("Clock"),          align = true,  extras = clockRows },
    { key = "weather", title = _("Weather"),        align = true,  extras = weatherRows },
    { key = "entries", title = _("Plugin entries"), align = true,  extras = entriesRows },
}

function Settings.openItem(def, on_close)
    local key = def.key
    local menu, refresh

    local function build()
        local rows = {
            {
                text = _("Enabled"),
                mandatory = onoff(Style.on(key)),
                action = function()
                    local now_on = Style.toggle(key)
                    if key == "weather" and now_on then
                        UI.tutorialOnce("weather", _("Tap the weather on the home screen any time to refresh it."))
                    end
                    refresh()
                end,
            },
        }
        if def.align then
            rows[#rows + 1] = {
                text = _("Alignment"),
                mandatory = alignLabel(Style.align(key)),
                action = function()
                    Store.set(key .. "_align", ALIGN_NEXT[Style.align(key)])
                    refresh()
                end,
            }
        end
        rows[#rows + 1] = {
            text = _("Padding"),
            action = function() openPadding(key, refresh) end,
        }
        rows[#rows + 1] = {
            text = _("Text Style"),
            action = function() openTextStyle(key, refresh) end,
        }
        if def.shadow ~= false then
            rows[#rows + 1] = {
                text = _("Drop Shadow / Outline"),
                action = function() openEffect(key, refresh) end,
            }
        end
        if def.extras then
            for _i, row in ipairs(def.extras(refresh)) do
                rows[#rows + 1] = row
            end
        end
        return rows
    end

    refresh = function()
        UI.refreshItems(menu, build())
    end
    menu = UI.newMenu(def.title, build(), on_close)
end

function Settings.openItemByKey(key, on_close)
    for _i, def in ipairs(ITEM_DEFS) do
        if def.key == key then
            Settings.openItem(def, on_close)
            return true
        end
    end
    return false
end

-- Section order ---------------------------------------------------------------------------

local function openSectionOrder(on_close)
    Entries.openSectionOrder(Style.sectionOrder, Style.setSectionOrder, Style.SECTION_TITLES, on_close)
end

-- Wallpaper ---------------------------------------------------------------------------------

local function isImageFile(name)
    local ext = tostring(name):match("%.([^.]+)$")
    ext = ext and ext:lower()
    return ext == "png" or ext == "jpg" or ext == "jpeg" or ext == "bmp" or ext == "gif"
end

local function decodes(path)
    local ok, bb = pcall(function()
        local RenderImage = require("ui/renderimage")
        return RenderImage:renderImageFile(path, false, 64, 64)
    end)
    if ok and bb then
        pcall(function() bb:free() end)
        return true
    end
    return false
end

local function chooseImage(on_done)
    local PathChooser = require("ui/widget/pathchooser")
    local start = Store.get("wallpaper_path")
    start = type(start) == "string" and start:match("^(.*)/[^/]*$") or nil
    if not start or lfs.attributes(start, "mode") ~= "directory" then
        start = G_reader_settings:readSetting("home_dir") or DataStorage:getDataDir()
    end
    UIManager:show(PathChooser:new{
        select_directory = false,
        select_file = true,
        show_files = true,
        path = start,
        file_filter = isImageFile,
        onConfirm = function(path)
            if isImageFile(path) and decodes(path) then
                Store.set("wallpaper_path", path)
                Store.set("wallpaper_on", true)
            else
                UI.info(_("That image couldn't be loaded. Try a PNG or JPEG."), 4)
            end
            on_done()
        end,
    })
end

local FIT_LABEL = {
    fit = _("Fit"),
    fill = _("Fill"),
    stretch = _("Stretch"),
    original = _("Original size"),
}

function Settings.openWallpaper(on_close)
    local menu, refresh

    local function build()
        local path = Wallpaper.path()
        return {
            {
                text = _("Enable wallpaper"),
                mandatory = onoff(Wallpaper.enabled()),
                action = function()
                    if Wallpaper.enabled() then
                        Store.set("wallpaper_on", false)
                        refresh()
                    elseif path then
                        Store.set("wallpaper_on", true)
                        refresh()
                    else
                        chooseImage(refresh)
                    end
                end,
            },
            {
                text = _("Select wallpaper"),
                mandatory = path and (path:match("([^/]+)$") or path) or "—",
                action = function() chooseImage(refresh) end,
            },
            {
                text = _("Fit"),
                mandatory = FIT_LABEL[Wallpaper.fit()],
                action = function()
                    local current = Wallpaper.fit()
                    for i, name in ipairs(Wallpaper.FITS) do
                        if name == current then
                            Store.set("wallpaper_fit", Wallpaper.FITS[i % #Wallpaper.FITS + 1])
                            break
                        end
                    end
                    refresh()
                end,
            },
            {
                text = _("Lighten"),
                mandatory = Wallpaper.lighten() .. "%",
                action = function()
                    local SpinWidget = require("ui/widget/spinwidget")
                    UIManager:show(SpinWidget:new{
                        title_text = _("Lighten wallpaper"),
                        info_text = _("Fades the wallpaper toward white so text is easier to read. 0% is the default."),
                        value = Wallpaper.lighten(),
                        value_min = 0,
                        value_max = 99,
                        value_step = 1,
                        value_hold_step = 10,
                        unit = "%",
                        default_value = 0,
                        ok_text = _("Apply"),
                        cancel_text = _("Cancel"),
                        callback = function(spin)
                            Store.set("wallpaper_lighten", spin.value)
                            refresh()
                        end,
                    })
                end,
            },
        }
    end

    refresh = function()
        UI.refreshItems(menu, build())
    end
    menu = UI.newMenu(_("Wallpaper"), build(), on_close)
end

-- Presets -----------------------------------------------------------------------------------

local function presetList()
    return Store.get("presets", {})
end

local function savePresetList(list)
    Store.set("presets", list)
end

local function confirm(text, ok_text, on_ok)
    local ConfirmBox = require("ui/widget/confirmbox")
    UIManager:show(ConfirmBox:new{
        text = text,
        ok_text = ok_text,
        cancel_text = _("Cancel"),
        ok_callback = on_ok,
    })
end

local function applySnapshot(name, data)
    confirm(
        string.format(_("Apply the “%s” preset? This replaces your current style."), name),
        _("Apply"),
        function()
            Style.applyPreset(data)
            local Home = package.loaded["ennui_home"]
            if Home and Home.instance then
                Home.instance:rebuild()
            end
            UI.info(string.format(_("Applied “%s”."), name))
        end
    )
end

function Settings.openPresets(on_close)
    local menu, refresh

    local function renamePreset(preset, index)
        UI.askText(_("Preset name"), preset.name, function(value)
            if value ~= "" then
                local list = presetList()
                list[index].name = value
                savePresetList(list)
                refresh()
            end
        end)
    end

    local function overwritePreset(preset, index)
        confirm(
            string.format(_("Overwrite “%s” with your current style? This can't be undone."), preset.name),
            _("Overwrite"),
            function()
                local list = presetList()
                list[index].data = Style.snapshot()
                savePresetList(list)
                UI.info(string.format(_("“%s” updated."), preset.name))
            end
        )
    end

    local function deletePreset(index, name)
        confirm(
            string.format(_("Delete the “%s” preset? This can't be undone."), name),
            _("Delete"),
            function()
                local list = presetList()
                table.remove(list, index)
                savePresetList(list)
                refresh()
            end
        )
    end

    local function openPresetActions(preset, index)
        local ButtonDialog = require("ui/widget/buttondialog")
        local dialog
        local function dismiss() UIManager:close(dialog) end
        dialog = ButtonDialog:new{
            title = preset.name,
            buttons = {
                {{ text = _("Apply"), callback = function() dismiss(); applySnapshot(preset.name, preset.data) end }},
                {{ text = _("Rename"), callback = function() dismiss(); renamePreset(preset, index) end }},
                {{ text = _("Overwrite"), callback = function() dismiss(); overwritePreset(preset, index) end }},
                {{ text = _("Delete"), callback = function() dismiss(); deletePreset(index, preset.name) end }},
                {{ text = _("Cancel"), callback = dismiss }},
            },
        }
        UIManager:show(dialog)
    end

    local function openDefaultAction()
        local ButtonDialog = require("ui/widget/buttondialog")
        local dialog
        local function dismiss() UIManager:close(dialog) end
        dialog = ButtonDialog:new{
            title = _("Default"),
            buttons = {
                {{ text = _("Apply"), callback = function() dismiss(); applySnapshot(_("Default"), {}) end }},
                {{ text = _("Cancel"), callback = dismiss }},
            },
        }
        UIManager:show(dialog)
    end

    local function build()
        local rows = {
            {
                text = _("Save current style as preset"),
                action = function()
                    UI.askText(_("Preset name"), "", function(value)
                        if value == "" then
                            return
                        end
                        local list = presetList()
                        list[#list + 1] = { name = value, data = Style.snapshot() }
                        savePresetList(list)
                        refresh()
                    end)
                end,
            },
            {
                text = _("Default"),
                mandatory = _("(built-in)"),
                action = openDefaultAction,
            },
        }
        for i, preset in ipairs(presetList()) do
            rows[#rows + 1] = {
                text = preset.name,
                action = function() openPresetActions(preset, i) end,
            }
        end
        return rows
    end

    refresh = function()
        UI.refreshItems(menu, build())
    end
    menu = UI.newMenu(_("Presets"), build(), on_close)
end

-- Extras ---------------------------------------------------------------------------------------

function Settings.openExtras(on_close)
    local menu, refresh

    local function build()
        return {
            {
                text = _("Build Mode"),
                mandatory = onoff(Style.buildMode()),
                action = function()
                    Store.set("build_mode", not Style.buildMode())
                    refresh()
                end,
            },
            {
                text = _("Presets"),
                mandatory = tostring(#presetList()),
                action = function() Settings.openPresets(refresh) end,
            },
        }
    end

    refresh = function()
        UI.refreshItems(menu, build())
    end
    menu = UI.newMenu(_("Extras"), build(), on_close)
end

-- Top level ---------------------------------------------------------------------------------------

function Settings.open(on_close)
    Store.set("configured", true)
    local menu, refresh

    local function build()
        local rows = {}
        for _i, def in ipairs(ITEM_DEFS) do
            rows[#rows + 1] = {
                text = def.title,
                mandatory = onoff(Style.on(def.key)),
                action = function() Settings.openItem(def, refresh) end,
            }
        end
        rows[#rows + 1] = {
            text = _("Section order"),
            action = function() openSectionOrder(refresh) end,
        }
        rows[#rows + 1] = {
            text = _("Wallpaper"),
            mandatory = onoff(Wallpaper.enabled()),
            action = function() Settings.openWallpaper(refresh) end,
        }
        rows[#rows + 1] = {
            text = _("Extras"),
            action = function() Settings.openExtras(refresh) end,
        }
        rows[#rows + 1] = {
            text = _("ennUI version"),
            mandatory = VERSION,
        }
        return rows
    end

    refresh = function()
        UI.refreshItems(menu, build())
    end
    menu = UI.newMenu(_("ennUI Settings"), build(), on_close)
end

return Settings
