-- Bouchon hs partagé par les suites. Renvoie une table de contrôle.
local M = {}

function M.install(opts)
    opts = opts or {}
    local ctl = {
        store = {}, shell = {}, printed = {}, timers = {}, canvases = {},
        screens = { { x=0, y=0, w=1512, h=944, fullH=982, id=1, brightness=0.9 } },
        menuBarFrame = { x = 1200, y = 0, w = 30, h = 24 },
        interfaceStyle = nil,
        idle = 0,
        kbSequence = { 0.0 }, kbIndex = 0,
    }

    local function screenObj(t)
        local o = {}
        o.id = function() return t.id end
        o.frame = function() return { x=t.x, y=t.y+24, w=t.w, h=t.h } end
        o.fullFrame = function() return { x=t.x, y=t.y, w=t.w, h=t.fullH } end
        o.getBrightness = function() return t.brightness end
        o.setBrightness = function(_, v) t.brightness = v end
        return o
    end

    local realPrint = print
    ctl.realPrint = realPrint
    _G.print = function(...) table.insert(ctl.printed, table.concat({...}, " ")) end

    local shutdownCb = nil
    local hs
    hs = {
        settings = { get=function(k) return ctl.store[k] end,
                     set=function(k,v) ctl.store[k]=v end },
        timer = { secondsSinceEpoch = function() return 1000 end,
                  doAfter = function(d, fn)
                      local t = { delay=d, fn=fn, stopped=false }
                      t.stop = function() t.stopped = true end
                      table.insert(ctl.timers, t); return t end,
                  doEvery = function() return { stop=function() end } end },
        eventtap = { new = function()
                        local t = { running=false }
                        t.start=function() t.running=true end
                        t.stop=function() t.running=false end
                        return t end,
                     event = { types = setmetatable({}, {__index=function(_,k) return k end}) } },
        screen = { mainScreen=function() return screenObj(ctl.screens[1]) end,
                   allScreens=function()
                       local r={} for _,t in ipairs(ctl.screens) do r[#r+1]=screenObj(t) end return r end },
        execute = function(cmd)
            table.insert(ctl.shell, cmd)
            if cmd:match("%-a") then return "Auto-brightness is: Enabled", true, "exit", 0 end
            if cmd:match("custom") then return "", true, "exit", 0 end
            if cmd:match("lowpowermode") then return "", true, "exit", 0 end
            if cmd:match("[0-9]%.[0-9][0-9][0-9][0-9]") then return "", true, "exit", 0 end
            ctl.kbIndex = ctl.kbIndex + 1
            local v = ctl.kbSequence[math.min(ctl.kbIndex, #ctl.kbSequence)]
            return string.format("Current brightness: %.2f", v), true, "exit", 0
        end,
        fs = { attributes=function(p) if p:match("homebrew") then return {mode="file"} end end },
        host = { idleTime=function() return ctl.idle end,
                 interfaceStyle=function() return ctl.interfaceStyle end },
        battery = { percentage=function() return 80 end, powerSource=function() return "AC Power" end },
        hotkey = { bind=function() return { delete=function() end } end },
        mouse = { absolutePosition=function() return {x=400,y=300} end },
        notify = { new=function() return { send=function() end } end },
        alert = { show=function(m) table.insert(ctl.printed, "ALERT:" .. tostring(m)) end },
        caffeinate = { set=function() end,
                       watcher = setmetatable({ new=function() return {start=function() end, stop=function() end} end },
                                              { __index=function(_,k) return k end }) },
        styledtext = { new=function(txt, attrs) return { _text=txt, _attrs=attrs } end },
        drawing = { getTextDrawingSize=function(st)
            local txt = type(st)=="table" and st._text or tostring(st)
            return { w = #txt * 7, h = 16 } end },
        canvas = {
            new = function(rect)
                local c = { rect=rect, elements={}, shown=false, deleted=false,
                            level_=nil, behaviors=nil, clickAct=nil }
                c.appendElements = function(_, ...) for _,e in ipairs({...}) do table.insert(c.elements, e) end return c end
                c.level = function(_, l) c.level_ = l; return c end
                c.behaviorAsLabels = function(_, b) c.behaviors = b; return c end
                c.clickActivating = function(_, f) c.clickAct = f; return c end
                c.show = function(_, d) c.shown = true; c.fadeIn = d; return c end
                c.hide = function(_, d) c.shown = false; return c end
                c.delete = function(_, d) c.deleted = true; c.shown = false end
                c.isShowing = function() return c.shown end
                table.insert(ctl.canvases, c); return c
            end,
            windowLevels = setmetatable({}, {__index=function(_,k) return k end}),
            windowBehaviors = setmetatable({}, {__index=function(_,k) return k end}),
        },
        menubar = { new=function(inBar)
            local m = { inMenuBar = (inBar ~= false) }
            for _,k in ipairs({"setTitle","setMenu","setClickCallback","setTooltip","popupMenu","delete"}) do
                m[k] = function() return m end end
            m.frame = function() if m.inMenuBar then return ctl.menuBarFrame end return nil end
            m.returnToMenuBar = function() m.inMenuBar = true; return m end
            m.removeFromMenuBar = function() m.inMenuBar = false; return m end
            return m end },
        autoLaunch = function() return false end,
        inspect = function(x) return tostring(x) end,
    }
    setmetatable(hs, {
        __newindex = function(t,k,v) if k=="shutdownCallback" then shutdownCb=v else rawset(t,k,v) end end,
        __index = function(t,k) if k=="shutdownCallback" then return shutdownCb end end,
    })
    _G.hs = hs
    ctl.fireTimers = function()
        local again = true
        while again do again=false
            local snap = ctl.timers; ctl.timers = {}
            for _,t in ipairs(snap) do if not t.stopped then t.fn(); again=true end end
        end
    end
    ctl.shutdown = function() if shutdownCb then shutdownCb() end end
    return ctl
end

function M.runner()
    local R = { failed=0, total=0 }
    function R.check(name, got, expected)
        R.total = R.total + 1
        local ok = (got == expected)
        if not ok then R.failed = R.failed + 1 end
        io.write(string.format("%-4s %-58s attendu=%-8s obtenu=%s\n",
            ok and "OK" or "FAIL", name, tostring(expected), tostring(got)))
    end
    function R.section(t) io.write("\n--- " .. t .. " ---\n") end
    function R.finish()
        io.write(string.format("\n=> %d/%d cas passent\n", R.total-R.failed, R.total))
        os.exit(R.failed == 0 and 0 or 1)
    end
    return R
end

return M
