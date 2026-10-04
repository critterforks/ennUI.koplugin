-- ennui_wallpaper.lua
-- Wallpaper for the home screen. The image is rendered once into a screen-sized bitmap
-- and cached, so opening the home screen only copies it to the screen.
-- Options: enable, image, fit (fit / fill / stretch / original size), and lighten.

local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local Store = require("ennui_store")

local Screen = Device.screen

local Wallpaper = {}

Wallpaper.FITS = { "fit", "fill", "stretch", "original" }

local cache = { key = nil, bb = nil }

function Wallpaper.release()
    if cache.bb then
        pcall(function() cache.bb:free() end)
    end
    cache.bb, cache.key = nil, nil
end

function Wallpaper.enabled()
    local on = Store.get("wallpaper_on")
    if on == nil then
        on = Store.get("wallpaper_mode") == "image" -- setting name used by the first version
    end
    return on == true
end

function Wallpaper.path()
    local path = Store.get("wallpaper_path")
    if type(path) == "string" and lfs.attributes(path, "mode") == "file" then
        return path
    end
    return nil
end

function Wallpaper.fit()
    local fit = Store.get("wallpaper_fit", "fit")
    for _i, name in ipairs(Wallpaper.FITS) do
        if name == fit then
            return fit
        end
    end
    return "fit"
end

function Wallpaper.lighten()
    local value = tonumber(Store.get("wallpaper_lighten", 0)) or 0
    return math.max(0, math.min(99, value))
end

-- Image size without decoding it fully (falls back to a full decode).
local function probe(path)
    local ok_pic, pic = pcall(require, "ffi/pic")
    if ok_pic and pic then
        local ok_doc, doc = pcall(pic.openDocument, path)
        if ok_doc and doc then
            local w, h = doc.width, doc.height
            pcall(function() doc:close() end)
            if w and h and w > 0 and h > 0 then
                return w, h
            end
        end
    end
    local ok_ri, RenderImage = pcall(require, "ui/renderimage")
    if ok_ri and RenderImage then
        local ok_bb, bb = pcall(RenderImage.renderImageFile, RenderImage, path, false, nil, nil)
        if ok_bb and bb then
            local w, h = bb:getWidth(), bb:getHeight()
            bb:free()
            return w, h
        end
    end
    return nil
end

local function newCanvas(w, h, color)
    local bb_type = Blitbuffer.TYPE_BB8
    if Screen.bb and Screen.bb.getType then
        local ok, t = pcall(Screen.bb.getType, Screen.bb)
        if ok and t then
            bb_type = t
        end
    end
    local canvas = Blitbuffer.new(w, h, bb_type)
    canvas:paintRect(0, 0, w, h, color)
    return canvas
end

local function render(path, fit, sw, sh)
    local ImageWidget = require("ui/widget/imagewidget")
    local base = Blitbuffer.COLOR_WHITE

    local ew, eh = probe(path)
    if not ew then
        fit = "fit" -- unknown size: proportional fit is the only safe choice
    end

    local canvas = newCanvas(sw, sh, base)

    local function widget(opts)
        opts.alpha = true
        opts.file_do_cache = false
        return ImageWidget:new(opts)
    end

    if fit == "fill" then
        local scale = math.max(sw / ew, sh / eh)
        local fw, fh = math.ceil(ew * scale), math.ceil(eh * scale)
        local tmp = newCanvas(fw, fh, base)
        local img = widget{ file = path, width = fw, height = fh, scale_factor = 0 }
        img:paintTo(tmp, 0, 0)
        img:free()
        canvas:blitFrom(tmp, 0, 0, math.floor((fw - sw) / 2), math.floor((fh - sh) / 2), sw, sh)
        tmp:free()
    elseif fit == "original" then
        local tmp = newCanvas(ew, eh, base)
        local img = widget{ file = path, width = ew, height = eh, scale_factor = 1 }
        img:paintTo(tmp, 0, 0)
        img:free()
        local cw, ch = math.min(ew, sw), math.min(eh, sh)
        canvas:blitFrom(tmp,
            math.max(0, math.floor((sw - ew) / 2)), math.max(0, math.floor((sh - eh) / 2)),
            math.max(0, math.floor((ew - sw) / 2)), math.max(0, math.floor((eh - sh) / 2)),
            cw, ch)
        tmp:free()
    elseif fit == "stretch" then
        -- Scaled to exactly the screen size, distorting the picture if needed.
        local RenderImage = require("ui/renderimage")
        local raw = RenderImage:renderImageFile(path, false, sw, sh)
        if not raw then
            error("could not decode " .. tostring(path))
        end
        local scaled = raw
        if raw:getWidth() ~= sw or raw:getHeight() ~= sh then
            scaled = raw:scale(sw, sh)
            raw:free()
        end
        local img = widget{ image = scaled, width = sw, height = sh, scale_factor = 1 }
        img:paintTo(canvas, 0, 0)
        img:free()
    else
        local img = widget{ file = path, width = sw, height = sh, scale_factor = 0 }
        img:paintTo(canvas, 0, 0)
        img:free()
    end

    return canvas
end

-- Returns { bb = <screen-sized bitmap>, lighten = 0..0.99 } or nil when there is no wallpaper.
function Wallpaper.get(sw, sh)
    if not Wallpaper.enabled() then
        Wallpaper.release()
        return nil
    end
    local path = Wallpaper.path()
    if not path then
        Wallpaper.release()
        return nil
    end
    local fit = Wallpaper.fit()
    local mtime = lfs.attributes(path, "modification") or 0
    local key = table.concat({ path, tostring(mtime), fit, sw, sh }, "|")

    if cache.bb and cache.key == key then
        return { bb = cache.bb, lighten = Wallpaper.lighten() / 100 }
    end
    Wallpaper.release()
    local ok, result = pcall(render, path, fit, sw, sh)
    if not ok or not result then
        logger.warn("ennui: could not prepare the wallpaper:", tostring(result))
        return nil
    end
    cache.bb, cache.key = result, key
    return { bb = cache.bb, lighten = Wallpaper.lighten() / 100 }
end

return Wallpaper
