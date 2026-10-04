-- ennui_home.lua
-- The EnnUI home screen widget: date, clock, weather and plugin entries (or a
-- folder's contents), in a user-chosen order. Static: it only redraws on
-- input. Swipe up from the bottom edge to reach Settings; long-pressing a
-- section opens its settings directly when Build Mode is on.

local Blitbuffer = require("ffi/blitbuffer")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local Device = require("device")
local Event = require("ui/event")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local InputContainer = require("ui/widget/container/inputcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local logger = require("logger")
local _ = require("gettext")

local Plugins = require("ennui_plugins")
local Store = require("ennui_store")
local Style = require("ennui_style")
local UI = require("ennui_ui")
local Wallpaper = require("ennui_wallpaper")
local Weather = require("ennui_weather")

local Screen = Device.screen

local SWIPE_ZONE = 0.12 -- bottom part of the screen where an upward swipe opens the menu

-- Weather refreshes once per KOReader launch (plus whenever you tap it), not
-- every time the home screen reappears. This is a plain module-level flag
-- (not a saved setting) so it naturally resets on the next launch.
local weather_refreshed_this_session = false

local function ordinal(n)
    local last_two = n % 100
    if last_two >= 11 and last_two <= 13 then
        return n .. "th"
    end
    local last = n % 10
    if last == 1 then
        return n .. "st"
    elseif last == 2 then
        return n .. "nd"
    elseif last == 3 then
        return n .. "rd"
    end
    return n .. "th"
end

-- "Thursday, September 24th"
local function dateText()
    local now = os.date("*t")
    return string.format("%s, %s %s", os.date("%A"), os.date("%B"), ordinal(now.day))
end

-- Always 12-hour; "Show AM/PM" (Clock settings) controls the suffix.
local function clockText()
    local t = os.date("*t")
    local hour = t.hour % 12
    if hour == 0 then
        hour = 12
    end
    local text = string.format("%d:%02d", hour, t.min)
    if Style.showAmPm() then
        text = text .. " " .. (t.hour < 12 and "AM" or "PM")
    end
    return text
end

local function fileManagerMenu()
    local FileManager = package.loaded["apps/filemanager/filemanager"]
    local instance = FileManager and FileManager.instance
    return instance and instance.menu or nil
end

local function menuZoneHeight()
    local ok, zone = pcall(function() return G_defaults:readSetting("DTAP_ZONE_MENU") end)
    if ok and type(zone) == "table" and type(zone.h) == "number" then
        return zone.h
    end
    return 0.125
end

-- The most recent book in KOReader's history that still exists on disk
-- (used only by "Resume current book" in the plugin picker).
local function lastBookFile()
    local ok, ReadHistory = pcall(require, "readhistory")
    if not ok or type(ReadHistory) ~= "table" or type(ReadHistory.hist) ~= "table" then
        return nil
    end
    local lfs = require("libs/libkoreader-lfs")
    for _i, item in ipairs(ReadHistory.hist) do
        if item.file and lfs.attributes(item.file, "mode") == "file" then
            return item.file
        end
    end
    return nil
end

local Home = InputContainer:extend{
    name = "ennui_home",
    covers_fullscreen = true,
    disable_double_tap = true,
    page = 1,
    pages = 1,
    folder = nil, -- nil = top-level entries; a folder entry = viewing its contents
}

Home.instance = nil
Home.pending = nil -- a built-ahead-of-time instance, not shown yet (see main.lua)

-- Builds a fresh instance ahead of time, without showing it, so that once
-- KOReader is ready to display it on top of the file browser, doing so is
-- just a paint rather than a full build (which may decode a book cover).
function Home.prebuild()
    local ok, widget = pcall(function() return Home:new{} end)
    if ok then
        Home.pending = widget
    end
    return Home.pending
end

function Home:init()
    self.page = 1
    self:build()
    self.ges_events = {
        EnnTap = {
            GestureRange:new{ ges = "tap", range = function() return self.dimen end },
        },
        EnnSwipe = {
            GestureRange:new{ ges = "swipe", range = function() return self.dimen end },
        },
        EnnHold = {
            GestureRange:new{ ges = "hold", range = function() return self.dimen end },
        },
    }
    self:scheduleWeather()
end

-- A line of text for `key` (date, clock, weather, ...) in its own typeface,
-- size, letter spacing, color, and outline/drop shadow. `text` should already
-- have that item's case setting applied if relevant.
function Home:textLine(key, text, max_width)
    local face = Style.face(key)
    local color = Style.colorFace(key)
    local effect = Style.effect(key)
    local spacing = Style.spacing(key)

    local function build(c)
        if spacing ~= 0 then
            return UI.spacedLabel(text, face, Screen:scaleBySize(spacing), c, false)
        end
        return UI.label(text, face, max_width, c, false)
    end

    local widget = build(color)
    if effect == "off" then
        return widget
    end

    local effect_color = Style.effectColorFace(key)
    if effect == "outline" then
        return UI.Outlined:new{ main = widget, outline = build(effect_color), thickness = Style.outlineThickness(key) }
    end
    -- "shadow"
    local off = Style.shadowOffset(key)
    local dx, dy = Screen:scaleBySize(off.dx), Screen:scaleBySize(off.dy)
    return UI.Shadowed:new{ main = widget, shadow = build(effect_color), dx = dx, dy = dy }
end

-- Shortens the line spacing of big text so stacked lines sit closer together.
local function tight(widget)
    return UI.Tight:new{ child = widget, trim = math.floor(widget:getSize().h * 0.16) }
end

-- Wraps `builder(w)` (given the width left after this section's own left/right
-- padding) in a frame that adds this section's padding on all four sides.
-- Also records this section's vertical span (for Build Mode's long-press).
function Home:section(key, avail_width, builder)
    local pad = Style.padding(key)
    local pl, pr = Screen:scaleBySize(pad.left), Screen:scaleBySize(pad.right)
    local pt, pb = Screen:scaleBySize(pad.top), Screen:scaleBySize(pad.bottom)
    local w = math.max(1, avail_width - pl - pr)
    local content = builder(w)
    if not content then
        return nil
    end
    local frame = FrameContainer:new{
        bordersize = 0, margin = 0, padding = 0,
        padding_top = pt, padding_bottom = pb, padding_left = pl, padding_right = pr,
        content,
    }
    local top = self._section_used or 0
    local height = frame:getSize().h
    self._section_bounds[#self._section_bounds + 1] = { key = key, top = top, bottom = top + height }
    self._section_used = top + height
    return frame
end

-- Section builders -------------------------------------------------------------------------

function Home:buildDate(w)
    local text = Style.applyCase("date", dateText())
    return UI.alignWrap(tight(self:textLine("date", text, w)), Style.align("date"), w)
end

function Home:buildClock(w)
    self.clock_text = clockText()
    local display = Style.applyCase("clock", self.clock_text)
    self.clock_widget = self:textLine("clock", display, w)
    return UI.alignWrap(tight(self.clock_widget), Style.align("clock"), w)
end

function Home:buildWeather(w)
    local raw = Weather.display()
    local text
    if raw then
        text = Style.applyCase("weather", raw)
    else
        text = Store.get("weather_zip", "") == "" and _("Set a ZIP code in settings")
            or _("Tap to update weather")
    end
    local line = tight(self:textLine("weather", text, w))
    return UI.TapRow:new{
        width = w,
        height = line:getSize().h + Screen:scaleBySize(10),
        align = Style.align("weather"),
        content = line,
        callback = function() self:tapWeather() end,
    }
end

function Home:buildEntries(w, sh, used, bar_h)
    local vpad = Screen:scaleBySize(Style.entryRowGap())
    local list = VerticalGroup:new{ align = "left" }
    local in_folder = self.folder ~= nil
    local items = in_folder and (self.folder.items or {}) or Store.get("entries", {})

    local function entryRow(content, callback)
        return UI.TapRow:new{
            width = w,
            align = Style.align("entries"),
            content = FrameContainer:new{
                bordersize = 0, margin = 0, padding = 0,
                padding_top = vpad, padding_bottom = vpad,
                content,
            },
            callback = callback,
        }
    end

    local extra_h = 0
    if in_folder then
        local back = entryRow(self:textLine("entries", "←", w), function()
            self.folder = nil
            self.page = 1
            self:rebuild()
        end)
        list[#list + 1] = back
        extra_h = extra_h + back:getSize().h
    end
    if #items > 0 then
        local row_h = entryRow(self:textLine("entries", "Ag", w), function() end):getSize().h
        local avail = sh - used - bar_h - extra_h
        local per_page = math.max(1, math.floor(avail / row_h))
        local cap = Style.maxPerPage()
        if cap > 0 then
            per_page = math.min(per_page, cap)
        end
        self.pages = math.max(1, math.ceil(#items / per_page))
        if self.page > self.pages then
            self.page = self.pages
        end
        local first = (self.page - 1) * per_page + 1
        local last = math.min(#items, self.page * per_page)
        for i = first, last do
            local entry = items[i]
            local label = Style.applyCase("entries", entry.label or entry.text or "?")
            list[#list + 1] = entryRow(self:textLine("entries", label, w), function() self:launch(entry) end)
        end
    end
    return list
end

function Home:build()
    if self[1] then
        pcall(function() self[1]:free() end)
        self[1] = nil
    end

    local sw, sh = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
    local pad_x = Screen:scaleBySize(36)
    local inner_w = sw - 2 * pad_x

    self.wallpaper = Wallpaper.get(sw, sh)
    self.dithered = self.wallpaper ~= nil
    self._section_bounds = {}
    self._section_used = 0

    local body = VerticalGroup:new{ align = "left" }
    local used = 0
    local function add(widget)
        if not widget then
            return
        end
        body[#body + 1] = widget
        used = used + widget:getSize().h
    end

    local bottom_margin = Screen:scaleBySize(18)
    local bar_h = Screen:scaleBySize(64) + bottom_margin

    self.clock_widget, self.clock_text = nil, nil
    self.pages = 1

    if not Store.on("configured", false) then
        body[#body + 1] = VerticalSpan:new{ width = Screen:scaleBySize(40) }
        add(self:textLine("entries", _("Swipe up from the bottom of the screen to set up ennUI."), inner_w))
    else
        UI.tutorialOnce("swipe", _("Swipe up from the bottom of the screen to open ennUI Settings."))
        body[#body + 1] = VerticalSpan:new{ width = Screen:scaleBySize(Style.BASE_TOP) }
        self._section_used = Screen:scaleBySize(Style.BASE_TOP)
        for _i, key in ipairs(Style.sectionOrder()) do
            if key == "date" and Style.on("date") then
                add(self:section("date", inner_w, function(w) return self:buildDate(w) end))
            elseif key == "clock" and Style.on("clock") then
                add(self:section("clock", inner_w, function(w) return self:buildClock(w) end))
            elseif key == "weather" and Style.on("weather") then
                add(self:section("weather", inner_w, function(w) return self:buildWeather(w) end))
            elseif key == "entries" and Style.on("entries") then
                add(self:section("entries", inner_w, function(w)
                    return self:buildEntries(w, sh, used, bar_h)
                end))
            end
        end
    end

    -- Bottom right: page indicator, when there is more than one page.
    local bar = HorizontalGroup:new{ align = "center" }
    if self.pages > 1 and Style.showPageNumber() then
        bar[#bar + 1] = UI.TapRow:new{
            content = FrameContainer:new{
                bordersize = 0, margin = 0, padding = Screen:scaleBySize(12),
                UI.label(string.format("%d / %d  ›", self.page, self.pages), Style.face("entries"), nil, Style.colorFace("entries")),
            },
            callback = function() self:turnPage(1) end,
        }
    end

    local layers = OverlapGroup:new{ dimen = Geom:new{ w = sw, h = sh }, allow_mirroring = false }
    layers[#layers + 1] = FrameContainer:new{
        bordersize = 0, margin = 0, padding = 0,
        padding_left = pad_x,
        body,
    }
    if #bar > 0 then
        local bar_frame = FrameContainer:new{
            bordersize = 0, margin = 0, padding = 0,
            padding_right = math.max(0, pad_x - Screen:scaleBySize(16)),
            padding_bottom = bottom_margin,
            bar,
        }
        layers[#layers + 1] = BottomContainer:new{
            dimen = Geom:new{ w = sw, h = sh },
            RightContainer:new{
                dimen = Geom:new{ w = sw, h = bar_frame:getSize().h },
                bar_frame,
            },
        }
    end
    self[1] = layers
end

function Home:rebuild(refresh_type)
    self:build()
    UIManager:setDirty(self, refresh_type or "ui")
end

-- Weather refreshes once per KOReader launch, a moment after the first home
-- screen is up, and only if the cache is already stale.
function Home:scheduleWeather()
    if weather_refreshed_this_session or not Style.on("weather") then
        return
    end
    weather_refreshed_this_session = true
    UIManager:scheduleIn(1, function()
        local ok, changed = pcall(Weather.refresh)
        if ok and changed and Home.instance then
            Home.instance:rebuild()
        end
    end)
end

-- Tapping the weather line refreshes it now (Wi-Fi is never turned on for this).
function Home:tapWeather()
    if Store.get("weather_zip", "") == "" then
        UI.info(_("Set a ZIP code in ennUI Settings > Weather."))
        return
    end
    if not Weather.online() then
        UI.info(_("Wi-Fi is off, so the weather can't be updated."))
        return
    end
    local InfoMessage = require("ui/widget/infomessage")
    local working = InfoMessage:new{ text = _("Updating weather…") }
    UIManager:show(working)
    UIManager:forceRePaint()
    local ok, updated = pcall(Weather.refresh, true)
    UIManager:close(working)
    if ok and updated then
        if Home.instance == self then
            self:rebuild()
        end
    else
        UI.info(_("Couldn't update the weather. Check the ZIP code and country in ennUI Settings."), 4)
    end
end

function Home:refreshClock()
    if not self.clock_widget then
        return
    end
    local text = Style.applyCase("clock", clockText())
    if text ~= self.clock_text and self.clock_widget.setText then
        self.clock_text = text
        self.clock_widget:setText(text)
        UIManager:setDirty(self, "ui")
    end
end

function Home:turnPage(delta)
    if self.pages <= 1 then
        return
    end
    self.page = (self.page - 1 + delta) % self.pages + 1
    self:rebuild()
end

-- Actions ---------------------------------------------------------------------------------

function Home:launch(entry)
    if entry.type == "folder" then
        self.folder = entry
        self.page = 1
        self:rebuild()
        return
    end
    if entry.id == "__book" then
        local file = lastBookFile()
        if file then
            self:openBook(file)
        else
            UI.info(_("No recent book to resume."))
        end
        return
    end
    if entry.id == "__fm" then
        -- The File Manager entry: step aside and reveal KOReader's file browser.
        self:close()
        return
    end
    local ok = Plugins.launch(entry)
    if not ok then
        UI.info(string.format(_("“%s” isn't available right now."), entry.label or entry.text or "?"))
    end
end

function Home:openBook(file)
    local ok, err = pcall(function()
        local ReaderUI = require("apps/reader/readerui")
        ReaderUI:showReader(file)
    end)
    if not ok then
        logger.err("ennui: could not open book:", tostring(err))
    end
end

function Home:openSettings()
    require("ennui_settings").open(function()
        if Home.instance == self then
            self:rebuild()
        end
    end)
end

function Home:showGearMenu()
    local ButtonDialog = require("ui/widget/buttondialog")
    local dialog
    local function dismiss()
        if dialog then
            UIManager:close(dialog)
        end
    end
    local buttons = {
        {{ text = _("ennUI Settings"), callback = function() dismiss(); self:openSettings() end }},
    }
    if Device:canRestart() then
        buttons[#buttons + 1] = {{ text = _("Restart KOReader"), callback = function() dismiss(); self:leave("Restart") end }}
    end
    buttons[#buttons + 1] = {{ text = _("Quit KOReader"), callback = function() dismiss(); self:leave("Exit") end }}
    dialog = ButtonDialog:new{
        width = math.floor(Screen:getWidth() * 0.5),
        buttons = buttons,
    }
    UIManager:show(dialog)
end

-- KOReader only exits once the window stack is empty, so step aside first.
function Home:leave(event_name)
    self:close()
    UIManager:nextTick(function()
        UIManager:broadcastEvent(Event:new(event_name))
    end)
end

function Home:close()
    if Home.instance == self then
        Home.instance = nil
    end
    UIManager:close(self)
end

-- Build Mode: which section (if any) contains this y-position.
function Home:sectionAt(y)
    for _i, span in ipairs(self._section_bounds or {}) do
        if y >= span.top and y < span.bottom then
            return span.key
        end
    end
    return nil
end

-- Events ------------------------------------------------------------------------------------

-- Back / close requests from the system do nothing: the home screen can't be exited.
function Home:onClose()
    return true
end

function Home:onCloseWidget()
    if Home.instance == self then
        Home.instance = nil
    end
end

-- A book is opening: the home screen makes way for the reader.
function Home:onShowingReader()
    self:close()
end
Home.onSetupShowReader = Home.onShowingReader

function Home:onResume()
    self:refreshClock()
    return false
end

function Home:onScreenResize()
    UIManager:scheduleIn(0.3, function()
        if Home.instance == self then
            self:rebuild("full")
        end
    end)
    return false
end
Home.onSetRotationMode = Home.onScreenResize

-- Draws the background (white, or the wallpaper), then the content. The
-- first completed paint clears the startup guard.
function Home:paintTo(bb, x, y)
    local w, h = self.dimen.w, self.dimen.h
    bb:paintRect(x, y, w, h, Blitbuffer.COLOR_WHITE)
    local wallpaper = self.wallpaper
    if wallpaper and wallpaper.bb then
        bb:blitFrom(wallpaper.bb, x, y, 0, 0, w, h)
        if wallpaper.lighten and wallpaper.lighten > 0 then
            bb:lightenRect(x, y, w, h, wallpaper.lighten)
        end
    end
    InputContainer.paintTo(self, bb, x, y)
    if not self._painted then
        self._painted = true
        UIManager:nextTick(function()
            Store.set("boot_pending", false)
        end)
    end
end

-- Gestures ------------------------------------------------------------------------------------

function Home:onEnnTap(args, ges)
    local menu = fileManagerMenu()
    if menu and menu.onTapShowMenu and ges and ges.pos and ges.pos.y < self.dimen.h * menuZoneHeight() then
        local ok, handled = pcall(menu.onTapShowMenu, menu, ges)
        if ok and handled then
            return true
        end
    end
    self:refreshClock()
    return false
end

function Home:onEnnSwipe(args, ges)
    local dir = ges and ges.direction
    if dir == "south" then
        local menu = fileManagerMenu()
        if menu and menu.onSwipeShowMenu and ges.pos and ges.pos.y < self.dimen.h * menuZoneHeight() then
            local ok, handled = pcall(menu.onSwipeShowMenu, menu, ges)
            if ok and handled then
                return true
            end
        end
    elseif dir == "north" then
        -- Swiping up from the bottom edge is the only way to reach the gear menu.
        if ges.pos and ges.pos.y >= self.dimen.h * (1 - SWIPE_ZONE) then
            self:showGearMenu()
            return true
        end
    elseif (dir == "west" or dir == "east") and self.pages > 1 then
        self:turnPage(dir == "west" and 1 or -1)
        return true
    end
    return false
end

-- Build Mode: long-pressing a section jumps straight to its settings.
function Home:onEnnHold(args, ges)
    if not Style.buildMode() or not ges or not ges.pos then
        return false
    end
    local key = self:sectionAt(ges.pos.y)
    if not key then
        return false
    end
    local ok = pcall(function()
        require("ennui_settings").openItemByKey(key, function()
            if Home.instance == self then
                self:rebuild()
            end
        end)
    end)
    return ok
end

-- Anything the home screen doesn't use (your own gestures, e.g. frontlight edge
-- swipes) is passed on to the File Manager underneath.
function Home:onGesture(ges)
    local own = InputContainer.onGesture
    if own and own(self, ges) then
        return true
    end
    local FileManager = package.loaded["apps/filemanager/filemanager"]
    local fm = FileManager and FileManager.instance
    if fm and own then
        local ok, handled = pcall(own, fm, ges)
        return ok and handled == true
    end
    return false
end

return Home
