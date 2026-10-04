-- ennui_splash.lua
-- A trivial "Loading EnnUI…" screen. It uses no user settings and decodes no
-- images, so it is always fast to build and paint. Shown for a moment while
-- the real home screen (which may need to decode a book cover) gets ready.

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local InputContainer = require("ui/widget/container/inputcontainer")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local Screen = Device.screen

local Splash = InputContainer:extend{
    name = "ennui_splash",
    covers_fullscreen = true,
}

function Splash:init()
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
    self[1] = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0, margin = 0, padding = 0,
        CenterContainer:new{
            dimen = Geom:new{ w = sw, h = sh },
            TextWidget:new{
                text = _("Loading ennUI…"),
                face = Font:getFace("cfont", 28),
            },
        },
    }
end

-- Back / close requests do nothing; the real home screen replaces this shortly.
function Splash:onClose()
    return true
end

Splash.active = nil -- the currently-shown splash instance, if any

function Splash.hide()
    if Splash.active then
        UIManager:close(Splash.active)
        Splash.active = nil
    end
end

-- Builds and shows a splash widget, returning it. It is NOT force-repainted:
-- it only joins the normal paint queue, so if the real home screen replaces
-- it before anything else forces a physical refresh (the fast path, when
-- KOReader offers an onShow signal — see main.lua), the splash's own pixels
-- never actually reach the screen, and no extra flash is added on top of
-- Home's own refresh. If nothing replaces it quickly (the slower fallback
-- path), it still becomes visible at the next natural repaint, and a 5-second
-- safety timeout closes it on its own so a failure elsewhere can never leave
-- the screen stuck on "Loading EnnUI…".
function Splash.show()
    if Splash.active then
        return Splash.active
    end
    local widget = Splash:new{}
    Splash.active = widget
    UIManager:show(widget, "full")
    UIManager:scheduleIn(5, function()
        if Splash.active == widget then
            Splash.hide()
        end
    end)
    return widget
end

return Splash
