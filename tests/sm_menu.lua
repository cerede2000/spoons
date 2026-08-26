package.path = (arg[0]:match("^(.*)/[^/]+$") or ".") .. "/?.lua;" .. package.path
local lib = require("lib_hs")
local ctl = lib.install()
local obj = dofile(arg[1])
local R = lib.runner()
local out = ctl.realPrint
io.write = function(s) out((s:gsub("\n$",""))) end
obj.showNotifications = false

local function find(menu, pattern)
    for _, e in ipairs(menu or {}) do
        if type(e.title)=="string" and e.title:match(pattern) then return e end
    end
end
local function sub1(entry)
    if type(entry)~="table" or type(entry.menu)~="table" then
        return {title="<pas de sous-menu>", checked="<absent>", disabled="<absent>", fn=function() end}
    end
    return entry.menu[1]
end

local iconState = { AK = true }
local started = {}
local spoons = {
    { id="AK", label="ActivityKeeper", defaultEnabled=true,
      start=function() started.AK=true end, stop=function() started.AK=false end,
      icon={ get=function() return iconState.AK end, set=function(v) iconState.AK=v end } },
    { id="WS", label="Window Switcher", defaultEnabled=true,
      start=function() started.WS=true end, stop=function() started.WS=false end },
}
obj:registerSpoons(spoons)
obj:loadEnabledSpoons()

R.section("Structure du menu")
local menu = obj:buildMenu()
local ak, ws = find(menu, "^ActivityKeeper"), find(menu, "^Window Switcher")
R.check("entrée présente", ak ~= nil, true)
R.check("reste cliquable", type(ak.fn), "function")
R.check("reste cochée comme avant", ak.checked, true)
R.check("sous-menu ajouté", type(ak.menu), "table")
R.check("intitulé du sous-menu", sub1(ak).title, "Icone barre des menus")
R.check("état de l'icône reflété", sub1(ak).checked, true)
R.check("Spoon sans icône : pas de sous-menu", ws.menu, nil)

R.section("Bascule de l'icône")
sub1(ak).fn()
R.check("icône masquée", iconState.AK, false)
R.check("menu reconstruit à jour", sub1(find(obj:buildMenu(), "^ActivityKeeper")).checked, false)
R.check("le Spoon reste actif", obj:isEnabled(spoons[1]), true)
sub1(find(obj:buildMenu(), "^ActivityKeeper")).fn()
R.check("icône réaffichable", iconState.AK, true)

R.section("Sous-menu grisé quand le Spoon est arrêté")
obj:setSpoonEnabled(spoons[1], false)
local m3 = obj:buildMenu()
R.check("entrée décochée", find(m3, "^ActivityKeeper").checked, false)
R.check("contrôle d'icône désactivé", sub1(find(m3, "^ActivityKeeper")).disabled, true)
obj:setSpoonEnabled(spoons[1], true)

R.section("Accesseurs d'icône défensifs")
R.check("déclaration incomplète ignorée",
        obj:hasIconControl({id="B", icon={get="pas une fonction"}}), false)
local raising = { id="R", icon={ get=function() error("boum") end, set=function() error("boum") end } }
R.check("get qui plante : false, pas d'erreur", obj:isIconVisible(raising), false)
R.check("set qui plante : absorbé", pcall(function() obj:setIconVisible(raising, true) end), true)

R.finish()
