-- ennui_ui.lua
-- Small shared widgets and helpers used by the home screen and the settings screens.

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local RightContainer = require("ui/widget/container/rightcontainer")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local Widget = require("ui/widget/widget")
local logger = require("logger")

local Screen = Device.screen

local UI = {}

UI.BLACK = Blitbuffer.COLOR_BLACK
UI.DIM = (Blitbuffer.gray and Blitbuffer.gray(0.45)) or Blitbuffer.COLOR_DARK_GRAY or Blitbuffer.COLOR_BLACK
UI.SHADOW = (Blitbuffer.gray and Blitbuffer.gray(0.5)) or Blitbuffer.COLOR_DARK_GRAY or Blitbuffer.COLOR_BLACK

local ALIGN = {
    left = LeftContainer,
    center = CenterContainer,
    right = RightContainer,
}

-- A row that runs `callback` when tapped. `align` places the content inside the row.
local TapRow = InputContainer:extend{
    width = 0,
    height = 0,
    align = "left",
}

function TapRow:init()
    local size = self.content:getSize()
    if not (self.width and self.width > 0) then
        self.width = size.w
    end
    if not (self.height and self.height > 0) then
        self.height = size.h
    end
    self.dimen = Geom:new{ w = self.width, h = self.height }
    local Container = ALIGN[self.align] or LeftContainer
    self[1] = Container:new{
        dimen = Geom:new{ w = self.width, h = self.height },
        self.content,
    }
    self.ges_events = {
        TapRow = {
            GestureRange:new{ ges = "tap", range = function() return self.dimen end },
        },
    }
end

function TapRow:onTapRow()
    if self.callback then
        local ok, err = pcall(self.callback)
        if not ok then
            logger.err("ennui: tap failed:", tostring(err))
        end
    end
    return true
end

UI.TapRow = TapRow

-- Reports a shorter height than the wrapped widget and paints it shifted up, which pulls
-- the next line closer (fonts carry extra spacing above and below the glyphs).
local Tight = Widget:extend{
    child = nil,
    trim = 0,
}

function Tight:getSize()
    local size = self.child:getSize()
    return Geom:new{ w = size.w, h = math.max(1, size.h - self.trim) }
end

function Tight:paintTo(bb, x, y)
    self.child:paintTo(bb, x, y - math.floor(self.trim / 2))
end

function Tight:setText(text)
    if self.child.setText then
        self.child:setText(text)
    end
end

function Tight:free()
    if self.child and self.child.free then
        self.child:free()
    end
end

UI.Tight = Tight

-- Text with a drop shadow: a gray copy drawn slightly down and to the right.
local Shadowed = Widget:extend{
    main = nil,
    shadow = nil,
    dx = 2,
    dy = 2,
}

function Shadowed:getSize()
    return self.main:getSize()
end

function Shadowed:paintTo(bb, x, y)
    self.shadow:paintTo(bb, x + self.dx, y + self.dy)
    self.main:paintTo(bb, x, y)
end

function Shadowed:setText(text)
    self.main:setText(text)
    self.shadow:setText(text)
end

function Shadowed:free()
    self.main:free()
    self.shadow:free()
end

UI.Shadowed = Shadowed

-- Text with an outline: the text repeated in a ring around itself in the
-- outline color, at `thickness` px, with the normal text on top. Only the
-- outermost 8 points of each 1px ring are painted (not a filled square),
-- which keeps the cost linear in thickness rather than quadratic — this
-- matters once thickness gets into double digits.
local Outlined = Widget:extend{
    main = nil,
    outline = nil,
    thickness = 1,
}

function Outlined:getSize()
    local s = self.main:getSize()
    return { w = s.w + 2 * self.thickness, h = s.h + 2 * self.thickness }
end

function Outlined:paintTo(bb, x, y)
    local t = self.thickness
    local ox, oy = x + t, y + t
    for r = 1, t do
        self.outline:paintTo(bb, ox - r, oy)
        self.outline:paintTo(bb, ox + r, oy)
        self.outline:paintTo(bb, ox, oy - r)
        self.outline:paintTo(bb, ox, oy + r)
        self.outline:paintTo(bb, ox - r, oy - r)
        self.outline:paintTo(bb, ox + r, oy - r)
        self.outline:paintTo(bb, ox - r, oy + r)
        self.outline:paintTo(bb, ox + r, oy + r)
    end
    self.main:paintTo(bb, ox, oy)
end

function Outlined:setText(text)
    self.main:setText(text)
    self.outline:setText(text)
end

function Outlined:free()
    self.main:free()
    self.outline:free()
end

UI.Outlined = Outlined

-- Shows an info toast the first time this tutorial key fires, and never again.
function UI.tutorialOnce(key, text, timeout)
    local Store = require("ennui_store")
    if Store.on("tutorial_" .. key, false) then
        return
    end
    Store.set("tutorial_" .. key, true)
    UI.info(text, timeout or 6)
end

-- Text label. `color` (a Blitbuffer color) defaults to black when omitted;
-- `shadow` adds a drop shadow. `dx`/`dy` (px, already scaled) set the
-- shadow's offset, defaulting to a small offset when omitted.
function UI.label(text, face, max_width, color, shadow, dx, dy)
    local main = TextWidget:new{
        text = text,
        face = face,
        max_width = max_width,
        fgcolor = color or UI.BLACK,
    }
    if not shadow then
        return main
    end
    dx = dx or math.max(1, math.floor(Screen:scaleBySize(1.5)))
    dy = dy or dx
    return Shadowed:new{
        main = main,
        shadow = TextWidget:new{
            text = text,
            face = face,
            max_width = max_width,
            fgcolor = UI.SHADOW,
        },
        dx = dx,
        dy = dy,
    }
end

-- Splits a UTF-8 string into its characters (byte-length aware, so accented
-- and multi-byte characters stay intact).
local function utf8Chars(text)
    local chars, i, n = {}, 1, #text
    while i <= n do
        local b = text:byte(i)
        local len = 1
        if b >= 0xF0 then len = 4
        elseif b >= 0xE0 then len = 3
        elseif b >= 0xC0 then len = 2 end
        chars[#chars + 1] = text:sub(i, i + len - 1)
        i = i + len
    end
    return chars
end

-- Text with extra space between letters. Used only when an item's letter
-- spacing is non-zero; single line only (max_width / wrapping isn't
-- supported here, since each letter is its own small widget).
function UI.spacedLabel(text, face, extra_px, color, shadow, dx, dy)
    local group = HorizontalGroup:new{ align = "center" }
    local chars = utf8Chars(text)
    for i, ch in ipairs(chars) do
        if i > 1 and extra_px ~= 0 then
            group[#group + 1] = HorizontalSpan:new{ width = extra_px }
        end
        group[#group + 1] = UI.label(ch, face, nil, color, shadow, dx, dy)
    end
    return group
end

-- Full-width row with the widget aligned left, center or right.
function UI.alignWrap(widget, align, width)
    local size = widget:getSize()
    local Container = ALIGN[align] or LeftContainer
    return Container:new{
        dimen = Geom:new{ w = width, h = size.h },
        widget,
    }
end

-- Shows a full-screen widget with a full e-ink refresh, so it draws correctly right away.
-- A second, slightly later refresh makes sure the finished screen reaches the panel.
function UI.showFull(widget)
    UIManager:show(widget, "full")
    UIManager:scheduleIn(0.5, function()
        UIManager:setDirty(widget, "ui")
    end)
end

function UI.info(text, timeout)
    local InfoMessage = require("ui/widget/infomessage")
    UIManager:show(InfoMessage:new{ text = text, timeout = timeout or 3 })
end

-- A full-screen list. Rows carry an `action(menu, row)`; `on_close` runs when it closes.
function UI.newMenu(title, items, on_close)
    local Menu = require("ui/widget/menu")
    local original_on_close_widget = Menu.onCloseWidget
    local menu = Menu:new{
        title = title,
        item_table = items,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        is_borderless = true,
        is_popout = false,
        covers_fullscreen = true,
        onMenuSelect = function(m, row)
            if row.action then
                local ok, err = pcall(row.action, m, row)
                if not ok then
                    logger.err("ennui: menu action failed:", tostring(err))
                end
            end
            return true
        end,
        onCloseWidget = function(m, ...)
            if original_on_close_widget then
                original_on_close_widget(m, ...)
            end
            if on_close then
                pcall(on_close)
            end
        end,
    }
    UIManager:show(menu)
    return menu
end

-- Replaces the rows of an open list in place and redraws it (keeps the current page).
function UI.refreshItems(menu, items)
    if not menu then
        return
    end
    for i = #menu.item_table, 1, -1 do
        menu.item_table[i] = nil
    end
    for i, row in ipairs(items) do
        menu.item_table[i] = row
    end
    menu:updateItems()
end

-- Asks for a line of text; calls on_save(trimmed_text) on Save.
function UI.askText(title, current, on_save)
    local InputDialog = require("ui/widget/inputdialog")
    local dialog
    dialog = InputDialog:new{
        title = title,
        input = current or "",
        buttons = {{
            {
                text = require("gettext")("Cancel"),
                id = "close",
                callback = function() UIManager:close(dialog) end,
            },
            {
                text = require("gettext")("Save"),
                is_enter_default = true,
                callback = function()
                    local value = dialog:getInputText() or ""
                    value = value:gsub("^%s+", ""):gsub("%s+$", "")
                    UIManager:close(dialog)
                    on_save(value)
                end,
            },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

return UI
