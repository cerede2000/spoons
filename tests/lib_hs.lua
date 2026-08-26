-- Bouchon hs partagé par les suites. Renvoie une table de contrôle.
local M = {}

local function path_escape(p)
    return (tostring(p):gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%1"))
end

function M.install(opts)
    opts = opts or {}
    local ctl = {
        store = {}, shell = {}, printed = {}, timers = {}, canvases = {},
        screens = { { x=0, y=0, w=1512, h=944, fullH=982, id=1, brightness=0.9 } },
        menuBarFrame = { x = 1200, y = 0, w = 30, h = 24 },
        interfaceStyle = nil,
        idle = 0, now = 1000,
        kbSequence = { 0.0 }, kbIndex = 0,
        axCalls = 0, axMode = "ok", killed = {}, deadCalls = {},
        runningApps = {}, powerFn = nil, windowFilterEvents = {}, keyEvents = {},
        -- WindowSwitcher
        everyTimers = {}, eventtaps = {}, modifierRaw = 524288,
        mousePosition = { x = 400, y = 300 },
        allWindows = {}, filterWindows = nil, filtersCreated = 0, filtersDeleted = 0,
        snapshotIDs = {}, snapshotFails = {}, tasks = {},
        files = {}, dirs = {}, removed = {}, launchedApps = {}, osExec = {},
        focused = {}, unminimized = {}, unhidden = {},
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
        timer = { secondsSinceEpoch = function() return ctl.now end,
                  doAfter = function(d, fn)
                      local t = { delay=d, fn=fn, stopped=false }
                      t.stop = function() t.stopped = true end
                      table.insert(ctl.timers, t); return t end,
                  doEvery = function(d, fn)
                      local t = { delay=d, fn=fn, stopped=false, every=true }
                      t.stop = function() t.stopped = true end
                      table.insert(ctl.everyTimers, t); return t end },
        eventtap = { new = function(types, fn)
                        local t = { running=false, types=types, fn=fn }
                        t.start=function() t.running=true end
                        t.stop=function() t.running=false end
                        table.insert(ctl.eventtaps, t)
                        return t end,
                     checkKeyboardModifiers = function()
                        return { _raw = ctl.modifierRaw } end,
                     event = {
                        types = setmetatable({}, {__index=function(_,k) return k end}),
                        newKeyEvent = function(mods, key, isDown)
                            return { post = function()
                                table.insert(ctl.keyEvents, { key = key, down = isDown })
                            end }
                        end,
                        newMouseEvent = function() return { post = function() end } end,
                     } },
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
        fs = {
            attributes = function(p, field)
                if ctl.files[p] then
                    if field == "modification" then return ctl.files[p].mtime or 1 end
                    return { mode = "file" }
                end
                if ctl.dirs[p] then
                    if field == "modification" then return ctl.dirs[p].mtime or 1 end
                    return { mode = "directory" }
                end
                if p:match("homebrew") then return { mode = "file" } end
                return nil
            end,
            mkdir = function(p) ctl.dirs[p] = { mtime = 1 }; return true end,
            dir = function(p)
                local names = {}
                for path in pairs(ctl.dirs) do
                    local rest = path:match("^" .. path_escape(p) .. "/([^/]+)$")
                    if rest then names[#names+1] = rest end
                end
                local i = 0
                return function() i = i + 1; return names[i] end, { _dir = p }
            end,
        },
        host = { idleTime=function() return ctl.idle end,
                 interfaceStyle=function() return ctl.interfaceStyle end },
        battery = { percentage=function() return 80 end, powerSource=function() return "AC Power" end },
        application = setmetatable({
            runningApplications = function() return ctl.runningApps end,
            get = function(key)
                for _, a in ipairs(ctl.runningApps) do
                    if a._bundle == key or a._name == key then return a end
                end
                return nil
            end,
            applicationsForBundleID = function(b)
                local r = {}
                for _, a in ipairs(ctl.runningApps) do
                    if a._bundle == b and not a._dead then r[#r+1] = a end
                end
                return r
            end,
            watcher = setmetatable({ new = function(fn) ctl.appWatcherFn = fn
                    return { start=function() end, stop=function() end } end },
                { __index = function(_, k) return k end }),
        }, {}),
        window = {
            allWindows = function() return ctl.allWindows end,
            focusedWindow = function() return ctl.focusedWindow end,
            _orderedwinids = function() return ctl.orderedIDs or {} end,
            snapshotForID = function(id)
                if ctl.snapshotFails[id] then return nil end
                if ctl.snapshotIDs[id] == nil then ctl.snapshotIDs[id] = 0 end
                ctl.snapshotIDs[id] = ctl.snapshotIDs[id] + 1
                return { _snapshot = id }
            end,
            filter = setmetatable({
            new = function(arg) local f = { events = {}, predicate = (type(arg)=="function") and arg or nil }
                ctl.filtersCreated = ctl.filtersCreated + 1
                f.subscribe = function(_, e, cb) f.events[e] = cb; ctl.windowFilterEvents[e] = cb; return f end
                f.unsubscribe = function() return f end
                f.keepActive = function() f.kept = true; return f end
                f.setCurrentSpace = function(_, v) f.currentSpace = v; return f end
                f.delete = function() ctl.filtersDeleted = ctl.filtersDeleted + 1; return f end
                f.getWindows = function(_, sort)
                    f.lastSort = sort
                    local source = ctl.filterWindows or ctl.allWindows
                    if not f.predicate then return source end
                    local r = {}
                    for _, w in ipairs(source) do if f.predicate(w) then r[#r+1] = w end end
                    return r
                end
                ctl.lastFilter = f
                return f end },
            { __index = function(_, k) return k end }) },
        hotkey = { bind=function() return { delete=function() end } end },
        mouse = { absolutePosition=function()
                      return { x = ctl.mousePosition.x, y = ctl.mousePosition.y } end,
                  setAbsolutePosition=function(p) ctl.mousePosition = p end },
        notify = { new=function() return { send=function() end } end },
        alert = { show=function(m) table.insert(ctl.printed, "ALERT:" .. tostring(m)) end },
        caffeinate = { set=function() end, declareUserActivity=function() return 1 end,
                       watcher = setmetatable({ new=function(fn) ctl.powerFn = fn
                                       return {start=function() end, stop=function() end} end },
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
                c.replaceElements = function(_, ...) c.elements = {...}; c.replaced = (c.replaced or 0) + 1; return c end
                c.frame = function(_, f) if f then c.rect = f end return c.rect end
                c.mouseCallback = function(_, fn) c.mouseFn = fn; return c end
                c.canvasMouseEvents = function(_, ...) c.mouseEvents = {...}; return c end
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
        image = {
            imageFromPath = function(p) if ctl.files[p] then return { _path = p } end return nil end,
            imageFromAppBundle = function(b) return { _bundle = b } end,
            imageFromName = function(nm) return { _name = nm } end,
        },
        hash = { SHA256 = function(v) return ("%064x"):format(#tostring(v)) end },
        task = { new = function(cmd, cb, args)
            local t = { cmd = cmd, args = args, cb = cb, started = false }
            t.start = function() t.started = true; table.insert(ctl.tasks, t)
                if cmd == "/usr/bin/open" then table.insert(ctl.launchedApps, args) end
                return true end
            t.terminate = function() t.terminated = true end
            return t end },
        openConsole = function() end,
        reload = function() end,
        autoLaunch = function() return false end,
        inspect = function(x) return tostring(x) end,
    }
    setmetatable(hs, {
        __newindex = function(t,k,v) if k=="shutdownCallback" then shutdownCb=v else rawset(t,k,v) end end,
        __index = function(t,k) if k=="shutdownCallback" then return shutdownCb end end,
    })
    _G.hs = hs

    -- WindowSwitcher fait require("hs.canvas") et consorts.
    local realRequire = require
    ctl.realRequire = realRequire
    _G.require = function(name)
        local short = tostring(name):match("^hs%.(.+)$")
        if not short then return realRequire(name) end
        local node = hs
        for part in short:gmatch("[^%.]+") do
            if type(node) ~= "table" then return nil end
            node = node[part]
        end
        return node
    end

    -- Systeme de fichiers virtuel : les suites WindowSwitcher ecrivent
    -- des requetes de capture, on ne veut pas toucher au disque.
    if opts.virtualFS then
        local realOpen, realRemove, realRename = io.open, os.remove, os.rename
        ctl.realOpen = realOpen
        io.open = function(path, mode)
            mode = mode or "r"
            if mode:match("[wa]") then
                local buf = {}
                return {
                    write = function(_, s) buf[#buf+1] = tostring(s) end,
                    close = function() ctl.files[path] = { data = table.concat(buf), mtime = 1 } end,
                }
            end
            local entry = ctl.files[path]
            if not entry then return nil end
            return {
                read = function(_, fmt)
                    if fmt == "*a" or fmt == "a" then return entry.data end
                    return entry.data
                end,
                lines = function()
                    local pos = 1
                    return function()
                        if pos > #entry.data then return nil end
                        local stop = entry.data:find("\n", pos, true)
                        local line
                        if stop then line = entry.data:sub(pos, stop - 1); pos = stop + 1
                        else line = entry.data:sub(pos); pos = #entry.data + 1 end
                        return line
                    end
                end,
                close = function() end,
            }
        end
        os.remove = function(p) ctl.removed[#ctl.removed+1] = p; ctl.files[p] = nil; return true end
        os.rename = function(a, b)
            if not ctl.files[a] then return nil end
            ctl.files[b] = ctl.files[a]; ctl.files[a] = nil; return true
        end
        os.execute = function(cmd) table.insert(ctl.osExec, cmd); return true end
        ctl.restoreFS = function() io.open = realOpen; os.remove = realRemove; os.rename = realRename end
    end
    ctl.fireTimers = function()
        local again = true
        while again do again=false
            local snap = ctl.timers; ctl.timers = {}
            for _,t in ipairs(snap) do if not t.stopped then t.fn(); again=true end end
        end
    end
    ctl.shutdown = function() if shutdownCb then shutdownCb() end end
    ctl.power = function(event) if ctl.powerFn then ctl.powerFn(event) end end
    ctl.fireOnly = function(delay)
        local snap = ctl.timers; ctl.timers = {}
        for _, t in ipairs(snap) do
            if not t.stopped and (delay == nil or t.delay == delay) then t.fn()
            elseif not t.stopped then table.insert(ctl.timers, t) end
        end
    end
    return ctl
end


------------------------------------------------------------
-- Fabriques fenêtres / applications
------------------------------------------------------------

-- kind : 1 = application du Dock, 0 = agent, -1 = daemon
function M.app(ctl, opts)
    local a = {
        _name = opts.name, _bundle = opts.bundle, _kind = opts.kind or 1,
        _windows = opts.windows or {}, _dead = false,
    }
    a.name       = function() if a._dead then ctl.deadCalls[#ctl.deadCalls+1]="name" return nil end return a._name end
    a.bundleID   = function() if a._dead then ctl.deadCalls[#ctl.deadCalls+1]="bundleID" return nil end return a._bundle end
    a.kind       = function() if a._dead then ctl.deadCalls[#ctl.deadCalls+1]="kind" return nil end return a._kind end
    a.pid        = function() return opts.pid or 4242 end
    a.allWindows = function()
        if a._dead then ctl.deadCalls[#ctl.deadCalls+1]="allWindows" return {} end
        ctl.axCalls = ctl.axCalls + 1
        if ctl.axMode == "vide" then return {} end
        if ctl.axMode == "erreur" then error("AX muette") end
        return a._windows
    end
    a.kill = function() table.insert(ctl.killed, a._name); return true end
    a._hidden = opts.hidden == true
    a.isHidden = function() return a._hidden end
    a.unhide = function() a._hidden = false; table.insert(ctl.unhidden, a._name); return true end
    return a
end

-- role/visible/standard reproduisent ce que macOS renvoie réellement :
-- une fenêtre réduite perd son subrole standard.
function M.window(opts)
    local w = {}
    w.id          = function() return opts.id end
    w.role        = function() return opts.role or "AXWindow" end
    w.isVisible   = function() if opts.visible == nil then return true end return opts.visible end
    w.isStandard  = function() if opts.standard == nil then return true end return opts.standard end
    w.isMinimized = function() return opts.minimized == true end
    w.application = function()
        if opts.appUnreadable then error("AX muette") end
        return opts.app
    end
    w.title       = function() return opts.title or "" end
    w.subrole     = function() return opts.subrole or "AXStandardWindow" end
    w.frame       = function() return opts.frame or { x=0, y=0, w=800, h=600 } end
    w.unminimize  = function() table.insert(ctl_of(w), "unminimize") end
    w.focus       = function() end
    w._opts       = opts
    return w
end

-- La fabrique window n'a pas acces a ctl ; on route les traces par opts.
function ctl_of(w)
    w._trace = w._trace or {}
    return w._trace
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
