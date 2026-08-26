-- WindowSwitcher : collecte, descripteurs, filtrage, ordre.
package.path = (arg[0]:match("^(.*)/[^/]+$") or ".") .. "/?.lua;" .. package.path
local lib = require("lib_hs")
local ctl = lib.install({ virtualFS = true })
local obj = dofile(arg[1])
local R = lib.runner()
local out = ctl.realPrint
io.write = function(s) out((s:gsub("\n$",""))) end
obj.verboseLogging = false
obj.showNotifications = false
obj.screenCaptureHelperEnabled = false
obj.defaultCompleteWithAllWindows = obj.completeWithAllWindows

local function app(name, bundle, opts)
    opts = opts or {}
    opts.name, opts.bundle = name, bundle
    local a = lib.app(ctl, opts)
    table.insert(ctl.runningApps, a)
    return a
end

local function win(id, application, opts)
    opts = opts or {}
    opts.id, opts.app = id, application
    return lib.window(opts)
end

local safari  = app("Safari", "com.apple.Safari")
local mail    = app("Mail", "com.apple.mail")
local control = app("Control Center", "com.apple.controlcenter")

------------------------------------------------------------
R.section("Un descripteur ne résout l'application qu'une fois")
------------------------------------------------------------
local calls = 0
local counted = win(1, safari, { title = "Page" })
counted.application = function() calls = calls + 1 return safari end

obj:beginDescriptorPass()
local d = obj:describeWindow(counted)
obj:windowBundleID(counted)
obj:windowAppName(counted)
obj:isWindowHidden(counted)
obj:windowTitle(counted)
obj:endDescriptorPass()

R.check("une seule résolution pour cinq accès", calls, 1)
R.check("bundle lu", d.bundleID, "com.apple.Safari")
R.check("nom lu", d.appName, "Safari")
R.check("titre affiché composé", d.displayTitle, "Safari - Page")

R.section("Hors passe, chaque appel repaie le prix")
calls = 0
obj:describeWindow(counted)
obj:describeWindow(counted)
R.check("pas de cache hors passe", calls, 2)

------------------------------------------------------------
R.section("Une application illisible ne fait pas disparaître la fenêtre")
------------------------------------------------------------
obj.loadedExcludedBundleIDs = { ["com.apple.controlcenter"] = true }
local muette = win(2, safari, { title = "Fantôme", appUnreadable = true })
obj:beginDescriptorPass()
local dm = obj:describeWindow(muette)
R.check("application non résolue", dm.appResolved, false)
R.check("la fenêtre reste proposée", obj:isDescriptorAllowed(dm), true)
obj:endDescriptorPass()

R.section("Les exclusions par bundle continuent de s'appliquer")
obj:beginDescriptorPass()
R.check("Control Center exclu", obj:isWindowAllowed(win(3, control)), false)
R.check("Safari accepté", obj:isWindowAllowed(win(4, safari)), true)
obj:endDescriptorPass()

R.section("Les autres critères de rejet sont intacts")
obj:beginDescriptorPass()
R.check("fenêtre trop petite rejetée",
    obj:isWindowAllowed(win(5, safari, { frame = { x=0, y=0, w=10, h=10 } })), false)
R.check("rôle non autorisé rejeté",
    obj:isWindowAllowed(win(6, safari, { subrole = "AXUnknown" })), false)
R.check("rôle illisible accepté (échec ouvert)",
    obj:isWindowAllowed(win(7, safari, { subrole = false })), true)
obj:endDescriptorPass()

obj.includeMinimized = false
obj:beginDescriptorPass()
R.check("réduite rejetée quand l'option est fausse",
    obj:isWindowAllowed(win(8, safari, { minimized = true })), false)
obj:endDescriptorPass()
obj.includeMinimized = true

obj.includeHidden = false
local cachee = app("Notes", "com.apple.Notes", { hidden = true })
obj:beginDescriptorPass()
R.check("masquée rejetée quand l'option est fausse",
    obj:isWindowAllowed(win(9, cachee)), false)
obj:endDescriptorPass()
obj.includeHidden = true

------------------------------------------------------------
R.section("Le filtre est créé une fois et conservé")
------------------------------------------------------------
ctl.filtersCreated, ctl.filtersDeleted = 0, 0
obj.windowFilterInstance = nil
local f1 = obj:ensureWindowFilter()
local f2 = obj:ensureWindowFilter()
local f3 = obj:ensureWindowFilter()
R.check("un seul filtre construit pour trois appels", ctl.filtersCreated, 1)
R.check("toujours le même objet", f1 == f3, true)
R.check("maintenu actif (keepActive)", f1.kept, true)

R.section("Changer d'espaces reconstruit le filtre, et un seul")
obj.includeOtherSpaces = false
local f4 = obj:ensureWindowFilter()
R.check("filtre reconstruit", ctl.filtersCreated, 2)
R.check("l'ancien est supprimé, pas abandonné", ctl.filtersDeleted, 1)
R.check("restreint à l'espace courant", f4.currentSpace, true)
obj.includeOtherSpaces = true
obj:ensureWindowFilter()

------------------------------------------------------------
R.section("Collecte : déduplication et ordre")
------------------------------------------------------------
local w10 = win(10, safari, { title = "Onglet A" })
local w11 = win(11, mail,   { title = "Boîte" })
local w12 = win(12, safari, { title = "Onglet B" })
local w13 = win(13, control)

ctl.filterWindows = { w10, w11 }             -- ordre MRU du filtre
ctl.allWindows    = { w12, w10, w13, w11 }   -- seconde passe, en vrac
ctl.orderedIDs    = { 12, 10, 11 }           -- profondeur WindowServer

obj.completeWithAllWindows = true
local collected = obj:collectWindows()
R.check("quatre candidats, un exclu, aucun doublon", #collected, 3)
R.check("MRU du filtre préservée en tête", collected[1].id, 10)
R.check("deuxième du filtre ensuite", collected[2].id, 11)
R.check("la fenêtre trouvée en second passage suit", collected[3].id, 12)

R.section("La queue est rangée par profondeur, pas au hasard")
local w14 = win(14, mail, { title = "Brouillon" })
ctl.filterWindows = { w10 }
ctl.allWindows    = { w14, w12 }   -- 14 avant 12 dans l'énumération
ctl.orderedIDs    = { 10, 12, 14 } -- mais 12 est devant 14 à l'écran
collected = obj:collectWindows()
R.check("tête inchangée", collected[1].id, 10)
R.check("la plus en avant d'abord", collected[2].id, 12)
R.check("la plus en arrière ensuite", collected[3].id, 14)

------------------------------------------------------------
R.section("Régression : le filtre ignore les fenêtres réduites au démarrage")
-- Dans window_filter.lua, une application n'est inscrite que si
-- app:focusedWindow() répond ; sinon elle part dans une échelle de
-- réessais dont seul le dernier force l'inscription, 4,2 s plus tard.
-- Une application dont toutes les fenêtres sont réduites n'a pas de
-- fenêtre focalisée : elle est absente du filtre pendant ce délai.
-- La seconde passe est ce qui la rattrape.
------------------------------------------------------------
R.check("seconde passe active d'origine", obj.defaultCompleteWithAllWindows, true)

local reduite = win(15, mail, { title = "Réduite", minimized = true })
obj.completeWithAllWindows = true
ctl.filterWindows = { w10 }                  -- le filtre ne la connaît pas encore
ctl.allWindows    = { w10, reduite }
ctl.orderedIDs    = { 10 }                   -- une réduite n'est pas dans l'ordre z
collected = obj:collectWindows()
R.check("elle est là dès le premier switch", #collected, 2)
R.check("le filtre garde la tête", collected[1].id, 10)
R.check("la réduite est rattrapée", collected[2].id, 15)

R.section("Sans seconde passe, elle manquerait")
obj.completeWithAllWindows = false
collected = obj:collectWindows()
R.check("une seule fenêtre, la réduite a disparu", #collected, 1)
ctl.filterWindows = { w10, w11 }
ctl.allWindows = { w12, w13, w14 }
collected = obj:collectWindows()
R.check("deux fenêtres seulement", #collected, 2)
obj.completeWithAllWindows = true

------------------------------------------------------------
R.section("Largeur de libellé : caractères et non octets")
------------------------------------------------------------
local accentue = win(20, safari, { title = "Préférences Système" })
local plain    = win(21, safari, { title = "Preferences Systeme" })
obj:beginDescriptorPass()
local da, dp = obj:describeWindow(accentue), obj:describeWindow(plain)
R.check("même longueur visuelle, même largeur",
    obj:estimatedLabelWidth(da), obj:estimatedLabelWidth(dp))
R.check("largeur mémorisée dans le descripteur", da.labelWidth ~= nil, true)
obj:endDescriptorPass()

------------------------------------------------------------
R.section("Le fichier d'exclusions n'est relu que s'il change")
------------------------------------------------------------
local path = "/tmp/ws-test-ignored.txt"
obj.ignoredBundlesFile = path
ctl.files[path] = { data = "# commentaire\n\ncom.example.un\n", mtime = 100 }
local reads = 0
local realRead = obj.readIgnoredBundlesFile
obj.readIgnoredBundlesFile = function(self) reads = reads + 1 return realRead(self) end

obj.loadedExcludedBundleIDs = nil
obj.ignoredBundlesSignature = nil
obj:refreshIgnoredBundles()
obj:refreshIgnoredBundles()
obj:refreshIgnoredBundles()
R.check("une seule lecture pour trois appels", reads, 1)
R.check("bundle du fichier pris en compte",
    obj.loadedExcludedBundleIDs["com.example.un"], true)

ctl.files[path].mtime = 200
obj:refreshIgnoredBundles()
R.check("relu quand la date change", reads, 2)
obj:refreshIgnoredBundles(true)
R.check("relu de force sur demande", reads, 3)
obj.readIgnoredBundlesFile = realRead

R.finish()
