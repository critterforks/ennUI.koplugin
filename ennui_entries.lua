-- ennui_entries.lua
-- Plugin entries: the picker (which plugins/folders appear) and the edit
-- screen (order with up/down arrows, rename, remove, folders).
--
-- Both work against a "container": { title, get() -> list, set(list),
-- allow_folder, secondary_button }. The top level edits Store's "entries";
-- a folder edits that one folder's own "items" list (one level deep only).

local Blitbuffer = require("ffi/blitbuffer")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local Button = require("ui/widget/button")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local LeftContainer = require("ui/widget/container/leftcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local _ = require("gettext")

local Plugins = require("ennui_plugins")
local Store = require("ennui_store")
local UI = require("ennui_ui")

local Screen = Device.screen

local Entries = {}

local function nextFolderId()
    local n = (tonumber(Store.get("folder_seq")) or 0) + 1
    Store.set("folder_seq", n)
    return "folder:" .. n
end

-- Edit screen ----------------------------------------------------------------------

local OrderScreen = InputContainer:extend{
    name = "ennui_order",
    covers_fullscreen = true,
    page = 1,
    pages = 1,
}

function OrderScreen:init()
    self.page = 1
    if Device:hasKeys() then
        self.key_events = { Close = { { Device.input.group.Back } } }
    end
    self:build()
end

function OrderScreen:button(text, width, callback)
    return Button:new{
        text = text,
        width = width,
        text_font_size = 24,
        text_font_bold = false,
        callback = callback,
        show_parent = self,
    }
end

function OrderScreen:persist(list)
    self.container.set(list)
end

function OrderScreen:build()
    if self[1] then
        pcall(function() self[1]:free() end)
        self[1] = nil
    end
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
    local pad = Screen:scaleBySize(28)
    local gap = Screen:scaleBySize(8)
    local btn_w = Screen:scaleBySize(58)
    local row_h = Screen:scaleBySize(70)
    local footer_row_h = Screen:scaleBySize(80)
    local entries = self.container.get()

    local title = TextWidget:new{
        text = self.container.title,
        face = Font:getFace("cfont", 28),
        max_width = sw - 2 * pad,
    }
    local hint = TextWidget:new{
        text = self.container.hint or _("Tap a name to rename it. Tap a folder's name to open it."),
        face = Font:getFace("cfont", 20),
        max_width = sw - 2 * pad,
        fgcolor = UI.DIM,
    }
    local reserved = pad + title:getSize().h + hint:getSize().h + Screen:scaleBySize(30)
        + footer_row_h * 2 + pad
    local per_page = math.max(1, math.floor((sh - reserved) / row_h))
    self.per_page = per_page
    self.pages = math.max(1, math.ceil(#entries / per_page))
    if self.page > self.pages then
        self.page = self.pages
    end

    local list = VerticalGroup:new{ align = "left" }
    list[#list + 1] = VerticalSpan:new{ width = pad }
    list[#list + 1] = title
    list[#list + 1] = hint
    list[#list + 1] = VerticalSpan:new{ width = Screen:scaleBySize(24) }
    if #entries == 0 then
        list[#list + 1] = TextWidget:new{
            text = _("No entries yet."),
            face = Font:getFace("cfont", 24),
            max_width = sw - 2 * pad,
            fgcolor = UI.DIM,
        }
    end

    local reorder_only = self.container.mode == "reorder"
    local text_w = reorder_only and (sw - 2 * pad - 2 * btn_w - 2 * gap) or (sw - 2 * pad - 3 * btn_w - 3 * gap)
    local first = (self.page - 1) * per_page + 1
    local last = math.min(#entries, self.page * per_page)
    for i = first, last do
        local entry = entries[i]
        local is_folder = entry.type == "folder"
        local label = (is_folder and "▸ " or "") .. (entry.label or entry.text or "?")
        local row = HorizontalGroup:new{ align = "center" }
        if reorder_only then
            row[#row + 1] = LeftContainer:new{
                dimen = Geom:new{ w = text_w, h = row_h },
                TextWidget:new{ text = label, face = Font:getFace("cfont", 24), max_width = text_w },
            }
        else
            row[#row + 1] = UI.TapRow:new{
                width = text_w,
                height = row_h,
                content = TextWidget:new{
                    text = label,
                    face = Font:getFace("cfont", 24),
                    max_width = text_w,
                },
                callback = function()
                    if is_folder then
                        Entries.openFolder(self.container.get(), entry, function() self:refresh() end)
                    else
                        self:rename(i)
                    end
                end,
            }
        end
        row[#row + 1] = HorizontalSpan:new{ width = gap }
        if i > 1 then
            row[#row + 1] = self:button("↑", btn_w, function() self:move(i, -1) end)
        else
            row[#row + 1] = HorizontalSpan:new{ width = btn_w }
        end
        row[#row + 1] = HorizontalSpan:new{ width = gap }
        if i < #entries then
            row[#row + 1] = self:button("↓", btn_w, function() self:move(i, 1) end)
        else
            row[#row + 1] = HorizontalSpan:new{ width = btn_w }
        end
        if not reorder_only then
            row[#row + 1] = HorizontalSpan:new{ width = gap }
            row[#row + 1] = self:button("×", btn_w, function() self:remove(i) end)
        end
        list[#list + 1] = row
    end

    local footer = VerticalGroup:new{ align = "left" }
    local usable = sw - 2 * pad - gap
    if not reorder_only then
        local main_row = HorizontalGroup:new{ align = "center" }
        if self.container.secondary_button then
            main_row[#main_row + 1] = self:button(_("Add or remove plugins"), math.floor(usable * 0.55), function()
                Entries.openPicker(self.container, function() self:refresh() end)
            end)
            main_row[#main_row + 1] = HorizontalSpan:new{ width = gap }
            main_row[#main_row + 1] = self:button(self.container.secondary_button.text, math.floor(usable * 0.45), function()
                self.container.secondary_button.action(function() self:refresh() end)
            end)
        else
            main_row[#main_row + 1] = self:button(_("Add or remove plugins"), usable, function()
                Entries.openPicker(self.container, function() self:refresh() end)
            end)
        end
        footer[#footer + 1] = main_row
        footer[#footer + 1] = VerticalSpan:new{ width = Screen:scaleBySize(10) }
    end
    footer[#footer + 1] = self:button(_("Done"), usable, function() UIManager:close(self) end)
    if self.pages > 1 then
        local page_row = HorizontalGroup:new{ align = "center" }
        page_row[#page_row + 1] = self:button("‹", btn_w, function() self:turnPage(-1) end)
        page_row[#page_row + 1] = HorizontalSpan:new{ width = gap }
        page_row[#page_row + 1] = TextWidget:new{
            text = string.format("%d / %d", self.page, self.pages),
            face = Font:getFace("cfont", 22),
        }
        page_row[#page_row + 1] = HorizontalSpan:new{ width = gap }
        page_row[#page_row + 1] = self:button("›", btn_w, function() self:turnPage(1) end)
        footer[#footer + 1] = page_row
    end

    local layers = OverlapGroup:new{ dimen = Geom:new{ w = sw, h = sh }, allow_mirroring = false }
    layers[#layers + 1] = FrameContainer:new{
        bordersize = 0, margin = 0, padding = 0, padding_left = pad,
        list,
    }
    layers[#layers + 1] = BottomContainer:new{
        dimen = Geom:new{ w = sw, h = sh },
        FrameContainer:new{
            bordersize = 0, margin = 0, padding = 0,
            padding_bottom = pad, padding_left = pad, padding_right = pad,
            footer,
        },
    }
    self[1] = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0, margin = 0, padding = 0,
        layers,
    }
end

function OrderScreen:refresh()
    self:build()
    UIManager:setDirty(self, "ui")
end

function OrderScreen:move(index, delta)
    local entries = self.container.get()
    local target = index + delta
    if target < 1 or target > #entries then
        return
    end
    entries[index], entries[target] = entries[target], entries[index]
    self:persist(entries)
    self.page = math.ceil(target / self.per_page)
    self:refresh()
end

function OrderScreen:remove(index)
    local entries = self.container.get()
    table.remove(entries, index)
    self:persist(entries)
    self:refresh()
end

function OrderScreen:rename(index)
    local entries = self.container.get()
    local entry = entries[index]
    if not entry then
        return
    end
    UI.askText(_("Rename (empty = original name)"), entry.label or entry.text or "", function(value)
        if value == "" or value == entry.text then
            entry.label = nil
        else
            entry.label = value
        end
        self:persist(entries)
        self:refresh()
    end)
end

function OrderScreen:turnPage(delta)
    self.page = (self.page - 1 + delta) % self.pages + 1
    self:refresh()
end

function OrderScreen:onClose()
    UIManager:close(self)
    return true
end

function OrderScreen:onCloseWidget()
    if self.on_close then
        pcall(self.on_close)
    end
end

-- Top-level entries -----------------------------------------------------------------

local function topContainer()
    return {
        title = _("Plugin entries"),
        get = function() return Store.get("entries", {}) end,
        set = function(list) Store.set("entries", list) end,
        secondary_button = {
            text = _("New folder"),
            action = function(refresh)
                UI.askText(_("Folder name"), "", function(value)
                    if value == "" then
                        return
                    end
                    local entries = Store.get("entries", {})
                    entries[#entries + 1] = { id = nextFolderId(), type = "folder", label = value, items = {} }
                    Store.set("entries", entries)
                    refresh()
                end)
            end,
        },
    }
end

function Entries.openOrder(on_close)
    UI.showFull(OrderScreen:new{ on_close = on_close, container = topContainer() })
end

-- Reorders a fixed set of home-screen sections (no add/remove/rename/folders).
-- `getList()` returns the current order as a list of keys; `setList(keys)`
-- saves a new order.
function Entries.openSectionOrder(getList, setList, titles, on_close)
    local container = {
        title = _("Section order"),
        hint = _("Reorder the sections shown on the home screen."),
        mode = "reorder",
        get = function()
            local out = {}
            for _i, key in ipairs(getList()) do
                out[#out + 1] = { id = key, text = titles[key] or key }
            end
            return out
        end,
        set = function(list)
            local keys = {}
            for _i, row in ipairs(list) do
                keys[#keys + 1] = row.id
            end
            setList(keys)
        end,
    }
    UI.showFull(OrderScreen:new{ on_close = on_close, container = container })
end

-- A folder's own contents. `top_list` is the top-level entries array that
-- `folder_entry` lives inside of, used only to persist changes.
function Entries.openFolder(top_list, folder_entry, on_close)
    folder_entry.items = folder_entry.items or {}
    local container = {
        title = folder_entry.label or folder_entry.text or _("Folder"),
        get = function() return folder_entry.items end,
        set = function(list) folder_entry.items = list; Store.set("entries", top_list) end,
        secondary_button = {
            text = _("Rename folder"),
            action = function(refresh)
                UI.askText(_("Folder name"), folder_entry.label or "", function(value)
                    if value ~= "" then
                        folder_entry.label = value
                        Store.set("entries", top_list)
                        refresh()
                    end
                end)
            end,
        },
    }
    UI.showFull(OrderScreen:new{ on_close = on_close, container = container })
end

-- Picker ------------------------------------------------------------------------------

function Entries.openPicker(container, on_close)
    local saved = container.get()
    local selected = {}
    for _i, entry in ipairs(saved) do
        if entry.type ~= "folder" then
            selected[entry.id] = true
        end
    end

    local rows = {
        { id = "__book", text = _("Resume current book") },
        { id = "__fm", text = _("File Manager") },
    }
    local known = { __book = true, __fm = true }
    for _i, found in ipairs(Plugins.scan()) do
        rows[#rows + 1] = { id = found.id, text = found.text }
        known[found.id] = true
    end
    -- Saved entries whose plugin isn't loaded right now stay listed so they can be removed.
    for _i, entry in ipairs(saved) do
        if entry.type ~= "folder" and not known[entry.id] then
            rows[#rows + 1] = { id = entry.id, text = (entry.text or entry.id) .. " (" .. _("unavailable") .. ")" }
        end
    end

    local items = {}
    for _i, row in ipairs(rows) do
        items[#items + 1] = {
            text = row.text,
            mandatory = selected[row.id] and "✓" or nil,
            action = function(m, item)
                local entries = container.get()
                if selected[row.id] then
                    for i = #entries, 1, -1 do
                        if entries[i].id == row.id then
                            table.remove(entries, i)
                        end
                    end
                    selected[row.id] = nil
                    item.mandatory = nil
                else
                    entries[#entries + 1] = { id = row.id, text = row.text }
                    selected[row.id] = true
                    item.mandatory = "✓"
                end
                container.set(entries)
                m:updateItems()
            end,
        }
    end
    UI.newMenu(_("Add or remove plugins"), items, on_close)
end

return Entries
