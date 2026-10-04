-- EnnUI: a minimal, text-based home screen for KOReader.
--
-- The home screen opens whenever KOReader's file browser is created (at startup and
-- every time a book is closed) and sits on top of it. It cannot be closed by the user;
-- the file browser is reachable only through a "File Manager" entry you add yourself,
-- and KOReader's top menu can always be pulled down from the top edge.
--
-- On closing a book, EnnUI builds its screen right away (onCloseDocument), before the
-- file browser reappears, and reacts the instant the file browser is shown (onShow) —
-- so showing EnnUI is nearly always just a single paint. A "Loading EnnUI…" splash covers
-- the (now rare) slower fallback path; it isn't force-repainted, so on the fast path its
-- own pixels never actually reach the screen — Home simply replaces it before anything
-- forces a physical refresh.
--
-- Safety nets: any error while building or showing the screen leaves the normal file
-- browser in place; the splash closes itself after 5 seconds if nothing replaces it; and
-- if a previous start never finished drawing the home screen it is skipped once (open it
-- again from the top menu: Tools > ennUI).

local Dispatcher = require("dispatcher")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
local _ = require("gettext")

local Store = require("ennui_store")

local EnnUI = WidgetContainer:extend{
    name = "ennui",
    is_doc_only = false,
}

function EnnUI:onDispatcherRegisterActions()
    Dispatcher:registerAction("ennui_home", {
        category = "none",
        event = "EnnUIHome",
        title = _("ennUI: home screen"),
        general = true,
    })
end

function EnnUI:init()
    -- The file browser has no document; a book reader does.
    self.is_fm = self.ui ~= nil and self.ui.document == nil
    pcall(function() self:onDispatcherRegisterActions() end)
    if self.ui and self.ui.menu and self.ui.menu.registerToMainMenu then
        pcall(function() self.ui.menu:registerToMainMenu(self) end)
    end
    if self.is_fm then
        local ok, err = pcall(function() self:autoOpen() end)
        if not ok then
            logger.err("ennui: startup failed:", tostring(err))
        end
    end
end

-- If KOReader dispatches an "onShow" event to a widget's own registered
-- modules at the moment the widget itself is shown, this fires right then —
-- tighter than the nextTick fallback in autoOpen() below, which still covers
-- things if onShow turns out not to fire here (showHome() is safe to call
-- twice: the second call is a no-op once Home.instance is set).
function EnnUI:onShow()
    if self.is_fm then
        self:showHome()
    end
end

function EnnUI:autoOpen()
    if Store.on("boot_pending", false) then
        -- Last time the home screen was shown it never finished drawing. Skip it once.
        Store.set("boot_pending", false)
        UIManager:nextTick(function()
            local InfoMessage = require("ui/widget/infomessage")
            UIManager:show(InfoMessage:new{
                text = _("ennUI was skipped because it didn't finish loading last time. Open it from the top menu: Tools > ennUI."),
                timeout = 8,
            })
        end)
        return
    end
    UIManager:nextTick(function() self:showHome() end)
end

-- Shows the home screen on top of the (now-visible) file browser: reuses an
-- already-built instance from onCloseDocument if there is one, so this is
-- just a paint rather than a full build.
function EnnUI:showHome()
    if not self.is_fm then
        return
    end
    local FileManager = package.loaded["apps/filemanager/filemanager"]
    if not (FileManager and FileManager.instance) then
        return
    end
    local ok_load, Home = pcall(require, "ennui_home")
    if not ok_load then
        logger.err("ennui: could not load the home screen:", tostring(Home))
        Store.set("boot_pending", false)
        return
    end
    if Home.instance then
        return
    end
    Store.set("boot_pending", true)
    local ok, err = pcall(function()
        if Home.pending then
            Home.instance, Home.pending = Home.pending, nil
        else
            Home.instance = Home:new{}
        end
        UIManager:show(Home.instance, "full")
        UIManager:scheduleIn(0.5, function()
            if Home.instance then
                UIManager:setDirty(Home.instance, "ui")
            end
        end)
        local ok_splash, Splash = pcall(require, "ennui_splash")
        if ok_splash then
            Splash.hide()
        end
    end)
    if not ok then
        logger.err("ennui: could not show the home screen:", tostring(err))
        Home.instance = nil
        Store.set("boot_pending", false)
    end
end

-- If the file browser goes away (a book opens, or KOReader is exiting), the home
-- screen goes with it; otherwise it would keep KOReader from quitting.
function EnnUI:onCloseWidget()
    if not self.is_fm then
        return
    end
    local Home = package.loaded["ennui_home"]
    if Home and Home.instance then
        Home.instance:close()
    end
end

-- Fires as a book closes, before the file browser reappears. Shows a splash
-- right away and builds the real home screen in the background, so that by
-- the time the file browser is ready, showing EnnUI is nearly instant.
function EnnUI:onCloseDocument()
    if self.is_fm then
        return
    end
    local ok, err = pcall(function()
        require("ennui_splash").show()
        local Home = require("ennui_home")
        if not Home.instance and not Home.pending then
            Home.prebuild()
        end
    end)
    if not ok then
        logger.err("ennui: onCloseDocument failed:", tostring(err))
    end
end

-- Gesture / menu action: go to the home screen.
function EnnUI:onEnnUIHome()
    if self.is_fm then
        self:showHome()
    else
        -- Closing the book triggers onCloseDocument above, which shows EnnUI.
        pcall(function()
            require("ennui_splash").show()
            local Home = require("ennui_home")
            if not Home.instance and not Home.pending then
                Home.prebuild()
            end
            self.ui:onClose()
        end)
    end
    return true
end

-- Opens EnnUI's settings, from the home screen or from anywhere else in KOReader.
function EnnUI:openSettings()
    local Home = package.loaded["ennui_home"]
    if Home and Home.instance then
        Home.instance:openSettings()
        return
    end
    require("ennui_settings").open(nil)
end

function EnnUI:addToMainMenu(menu_items)
    menu_items.ennui = {
        text = _("ennUI"),
        sorting_hint = "tools",
        callback = function()
            UIManager:nextTick(function() self:onEnnUIHome() end)
        end,
    }
end

return EnnUI
