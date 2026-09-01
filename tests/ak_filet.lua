package.path = (arg[0]:match("^(.*)/[^/]+$") or ".") .. "/?.lua;" .. package.path
local lib = require("lib_hs")
local ctl = lib.install()
local obj = dofile(arg[1])
local R = lib.runner()
local out = ctl.realPrint
io.write = function(s) out((s:gsub("\n$",""))) end
obj.showStateNotifications=false; obj.verboseLogging=false

local KEY = "ActivityKeeper.pendingRestore"
local function clean()
    ctl.store={}; ctl.shell={}; ctl.kbIndex=0
    obj.keyboardBacklightModified=false; obj.savedKeyboardBrightness=nil
    obj.lastKnownNonZeroKeyboardBrightness=nil
    obj.keyboardAutoBrightnessModified=false; obj.savedKeyboardAutoBrightness=nil
    obj.screenBrightnessModified=false; obj.savedScreenBrightness=nil; obj.savedScreenId=nil
    obj.lowPowerBatteryModified=false; obj.lowPowerACModified=false
    obj.lastPendingRestoreSignature=nil
    obj.keyboardBrightnessBackend="mac-brightnessctl"
    obj.keyboardBrightnessTool="/opt/homebrew/bin/mac-brightnessctl"
end

R.section("Consignation de l'état modifié")
clean()
obj.keyboardBacklightModified=true; obj.savedKeyboardBrightness=0.42
obj:persistPendingRestore()
R.check("enregistré dans hs.settings", ctl.store[KEY] ~= nil, true)
R.check("avec la valeur à rendre", ctl.store[KEY].savedKeyboardBrightness, 0.42)

R.section("Coût d'une consignation répétée")
local sets=0
local realSet = hs.settings.set
hs.settings.set = function(k,v) sets=sets+1; realSet(k,v) end
obj.lastPendingRestoreSignature = nil     -- premier passage sur cet état
for i=1,20 do obj:persistPendingRestore() end
R.check("20 appels identiques : 1 seule écriture", sets, 1)
sets=0; obj.savedKeyboardBrightness=0.77
obj:persistPendingRestore()
R.check("une vraie modification est écrite", sets, 1)
hs.settings.set = realSet

R.section("Capture asynchrone rattrapée par le tick")
clean(); ctl.kbSequence={0.0, 0.0, 0.42}
obj.isKeyboardBacklightEnabled=function() return true end
obj.isScreenDimmingEnabled=function() return false end
obj.isLowPowerModeEnabled=function() return false end
obj.isAutomaticLowPowerModeEnabled=function() return false end
obj.currentState=obj.STATE.KEEPALIVE
obj:applyEnergySavingState()
R.check("capture non finie au retour", obj.keyboardBacklightModified, false)
ctl.fireTimers()
R.check("capture aboutie", obj.keyboardBacklightModified, true)
R.check("valeur trouvée", obj.savedKeyboardBrightness, 0.42)
R.check("pas encore consignée", (ctl.store[KEY] or {}).savedKeyboardBrightness, nil)
ctl.idle = 200
obj.lastKeepAliveTime = os.time()
obj:checkIdleState()
R.check("toujours en vert", obj.currentState, obj.STATE.KEEPALIVE)
R.check("le tick a rattrapé la consignation", (ctl.store[KEY] or {}).savedKeyboardBrightness, 0.42)

R.section("Reprise après un arrêt brutal")
local saved = ctl.store[KEY]
clean(); ctl.store[KEY] = saved
obj.currentState = obj.STATE.OFF
ctl.shell = {}
R.check("la reprise agit même en OFF", obj:recoverPendingRestore(), true)
R.check("des commandes ont été émises", #ctl.shell > 0, true)
R.check("consigne effacée", ctl.store[KEY], nil)
R.check("rien à reprendre ensuite", obj:recoverPendingRestore(), false)

R.section("Enregistrement corrompu ou périmé")
clean()
ctl.store[KEY] = { keyboardBacklightModified=true, savedKeyboardBrightness="pas un nombre",
                   screenBrightnessModified=true, savedScreenBrightness={}, savedScreenId="abc" }
R.check("ne lève pas", pcall(function() obj:recoverPendingRestore() end), true)
R.check("valeur clavier assainie", obj.savedKeyboardBrightness, nil)
R.check("identifiant écran assaini", obj.savedScreenId, nil)

R.section("Hook d'arrêt")
clean()
R.check("aucun hook au départ", hs.shutdownCallback, nil)
obj:installShutdownGuard()
R.check("hook installé", type(hs.shutdownCallback), "function")
obj.keyboardBacklightModified=true; obj.savedKeyboardBrightness=0.33
ctl.store[KEY]={keyboardBacklightModified=true}
ctl.shell={}
ctl.shutdown()
R.check("le hook restaure", #ctl.shell > 0, true)
R.check("le hook efface la consigne", ctl.store[KEY], nil)
local prevCalled=false
hs.shutdownCallback = function() prevCalled=true end
obj.shutdownGuardInstalled=false
obj:installShutdownGuard()
ctl.shutdown()
R.check("hook préexistant chaîné", prevCalled, true)


------------------------------------------------------------
R.section("La fenêtre aveugle se referme dès la séquence finie")
------------------------------------------------------------
-- Elle durait une seconde entière alors que la séquence synthétique
-- dure environ 0,2 s. Une frappe arrivant à T+0,3 était jetée, et
-- l'inférence ne peut pas la rattraper — trop proche de la nôtre.
ctl.timeNow = nil
obj.syntheticEventSettleDelay = 0.15
-- Le raccourcissement n'est permis qu'une fois la marque prouvée.
obj.syntheticMarkWorks = true
ctl.now = 5000
obj:openSyntheticEventWindow()
R.check("ouverte pour toute la période de grâce",
    obj.syntheticEventIgnoreUntil, 5000 + obj.syntheticEventGracePeriod)
R.check("l'utilisateur est ignoré pendant ce temps",
    obj:isSyntheticEventWindow(), true)

ctl.now = 5000.2                       -- la séquence se termine
obj:closeSyntheticEventWindow()
R.check("refermée au temps de vol près",
    obj.syntheticEventIgnoreUntil, 5000.2 + 0.15)
ctl.now = 5000.4
R.check("l'utilisateur est de nouveau écouté",
    obj:isSyntheticEventWindow(), false)

R.section("Refermer n'allonge jamais la fenêtre")
ctl.now = 5000
obj:openSyntheticEventWindow()
local avant = obj.syntheticEventIgnoreUntil
ctl.now = 5000.95                      -- appel tardif, fin de fenêtre
obj:closeSyntheticEventWindow()
R.check("la fenêtre n'est pas repoussée",
    obj.syntheticEventIgnoreUntil, avant)

R.section("Un curseur déplacé prouve le retour de l'utilisateur")
-- Ce signal était jeté : si le curseur n'est plus où nous l'avons
-- laissé, personne d'autre que l'utilisateur n'a pu le bouger.
R.check("le code sait s'en servir",
    type(obj.deferRealUserActivity), "function")


------------------------------------------------------------
R.section("Curseur au bord de l'écran : le keep-alive ne ment plus")
------------------------------------------------------------
-- On demande original.x + 1. Au bord droit, macOS refuse et le curseur
-- reste où il est. Comparer à la position DEMANDÉE faisait alors
-- conclure, à chaque keep-alive, que l'utilisateur avait bougé la
-- souris : sortie du vert, puis retour au vert cinq secondes plus tard
-- puisque l'inactivité restait haute — une boucle de popups.
ctl.timeNow = nil
obj.currentState = obj.STATE.KEEPALIVE
obj.mouseMovePixels = 1
obj.mouseReturnDelay = 0.15
obj.isMouseEnabled = function() return true end

local function sequenceSouris()
    obj.realActivityPending = false
    ctl.timers = {}
    obj:sendMouseActivity()
    ctl.fireOnly(obj.mouseReturnDelay)
end

-- Bord d'écran : le déplacement est refusé.
ctl.mouseClamped = true
ctl.mousePosition = { x = 1511, y = 300 }
sequenceSouris()
R.check("déplacement refusé : aucune activité déduite",
    obj.realActivityPending, false)
R.check("l'application reste verte", obj.currentState, obj.STATE.KEEPALIVE)

-- Cas normal : le curseur bouge, puis personne n'y touche.
ctl.mouseClamped = false
ctl.mousePosition = { x = 400, y = 300 }
sequenceSouris()
R.check("personne n'a touché la souris : rien de déduit",
    obj.realActivityPending, false)
R.check("et le curseur est remis à sa place", ctl.mousePosition.x, 400)

-- L'utilisateur bouge vraiment la souris pendant notre séquence.
obj.realActivityPending = false
ctl.mousePosition = { x = 400, y = 300 }
ctl.timers = {}
obj:sendMouseActivity()
ctl.mousePosition = { x = 900, y = 500 }     -- l'utilisateur est revenu
ctl.fireOnly(obj.mouseReturnDelay)
R.check("un vrai déplacement est vu", obj.realActivityPending, true)
R.check("et le curseur n'est pas téléporté en arrière",
    ctl.mousePosition.x, 900)
ctl.fireOnly(0)
R.check("l'application repasse en jaune", obj.currentState, obj.STATE.MONITORING)


------------------------------------------------------------
R.section("Le journal nomme le chemin qui a fait sortir du vert")
------------------------------------------------------------
-- Cinq chemins peuvent faire sortir du vert. Le journal disait
-- seulement « Activité utilisateur réelle détectée » : impossible de
-- savoir lequel avait parlé, donc impossible de diagnostiquer une
-- sortie intempestive.
ctl.timeNow = nil
local function sortie(origine)
    obj.currentState = obj.STATE.KEEPALIVE
    ctl.printed = {}
    obj:handleRealUserActivity(true, origine)
    return table.concat(ctl.printed, " ")
end

R.check("origine du tap rapide",
    sortie("tap rapide"):find("origine : tap rapide", 1, true) ~= nil, true)
R.check("origine du tap ordinaire",
    sortie("tap ordinaire"):find("origine : tap ordinaire", 1, true) ~= nil, true)
R.check("origine de l'inférence",
    sortie("inference"):find("origine : inference", 1, true) ~= nil, true)
R.check("origine de la souris",
    sortie("souris deplacee"):find("origine : souris deplacee", 1, true) ~= nil, true)
R.check("origine inconnue signalée comme telle",
    sortie(nil):find("origine : inconnue", 1, true) ~= nil, true)
R.check("l'inactivité mesurée est jointe",
    sortie("inference"):find("inactivité", 1, true) ~= nil, true)

R.section("L'origine traverse le report")
obj.currentState = obj.STATE.KEEPALIVE
obj.realActivityPending = false
ctl.timers = {}
ctl.printed = {}
obj:deferRealUserActivity("tap rapide")
ctl.fireOnly(0)
R.check("elle survit au tour de boucle",
    table.concat(ctl.printed, " "):find("origine : tap rapide", 1, true) ~= nil, true)


------------------------------------------------------------
R.section("Nos propres événements sont reconnus à leur marque, pas à la montre")
------------------------------------------------------------
-- La fenêtre de grâce suppose que nos événements arrivent au tap avant
-- son échéance. Raccourcie à la fin de la séquence, elle laissait
-- passer ceux qui arrivaient en retard : ActivityKeeper réagissait à
-- lui-même et sortait du vert alors que personne n'avait touché la
-- machine — jaune, vert, jaune, vert.
ctl.timeNow = nil
ctl.markLost = false
ctl.postedEvents = {}
ctl.keyEvents = {}
obj.syntheticMarkWorks = false
obj.currentState = obj.STATE.KEEPALIVE
obj.fastReturnWatcherEnabled = true
obj.fastReturnThrottle = 0
obj.realActivityPending = false
obj.fastReturnWatcher = nil
ctl.eventtaps = {}
obj:createFastReturnWatcher()
local tapRapide2 = ctl.eventtaps[#ctl.eventtaps]

-- On émet un keep-alive clavier : les événements portent la marque.
obj.activityKey = "shift"
obj:postActivityKey()
R.check("un événement a été émis", #ctl.postedEvents > 0, true)
local notre = ctl.postedEvents[#ctl.postedEvents]
R.check("il porte notre marque",
    notre:getProperty("eventSourceUserData"), obj.syntheticMark)

-- Il arrive au tap BIEN APRÈS la fin de la fenêtre de grâce.
ctl.now = ctl.now + 60
obj.realActivityPending = false
tapRapide2.fn(notre)
R.check("la fenêtre de grâce est expirée", obj:isSyntheticEventWindow(), false)
R.check("mais il est reconnu comme le nôtre", obj.realActivityPending, false)
R.check("l'application reste verte", obj.currentState, obj.STATE.KEEPALIVE)
R.check("et le mécanisme est désormais prouvé", obj.syntheticMarkWorks, true)

R.section("Un vrai événement de l'utilisateur passe toujours")
local vrai = { getProperty = function() return nil end }
obj.realActivityPending = false
obj.lastFastReturnEventAt = 0
tapRapide2.fn(vrai)
R.check("il est bien vu", obj.realActivityPending, true)

R.section("Tant que la marque n'est pas prouvée, la fenêtre reste entière")
-- La raccourcir avant d'avoir la preuve, c'est reprendre le risque.
obj.syntheticMarkWorks = false
ctl.now = 6000
obj:openSyntheticEventWindow()
local pleine = obj.syntheticEventIgnoreUntil
ctl.now = 6000.2
obj:closeSyntheticEventWindow()
R.check("la fenêtre n'est pas raccourcie",
    obj.syntheticEventIgnoreUntil, pleine)

obj.syntheticMarkWorks = true
obj:closeSyntheticEventWindow()
R.check("une fois prouvée, elle l'est",
    obj.syntheticEventIgnoreUntil, 6000.2 + obj.syntheticEventSettleDelay)

R.section("Si la marque ne survit pas sur cette machine, on retombe sur la montre")
ctl.markLost = true
obj.syntheticMarkWorks = false
obj.currentState = obj.STATE.KEEPALIVE
ctl.postedEvents = {}
obj:postActivityKey()
local perdu = ctl.postedEvents[#ctl.postedEvents]
R.check("la marque est illisible", perdu:getProperty("eventSourceUserData"), nil)
R.check("le mécanisme n'est pas déclaré fonctionnel", obj.syntheticMarkWorks, false)
R.check("donc la fenêtre reste entière et protège",
    obj:isSyntheticEventWindow(), true)
ctl.markLost = false


R.section("Chaque événement émis met la référence à jour")
ctl.postedEvents = {}
obj.lastSyntheticAt = nil
obj.activityKey = "shift"
ctl.timeNow = 2000
obj:postActivityKey()
R.check("la touche de keep-alive est bien émise", #ctl.postedEvents > 0, true)

obj.lastSyntheticAt = nil
ctl.timeNow = 2100
obj:sendSystemKey("ILLUMINATION_DOWN")
R.check("la touche système aussi", #ctl.postedEvents > 0, true)

obj.lastSyntheticAt = nil
ctl.timeNow = 2200
ctl.mouseClamped = false
ctl.mousePosition = { x = 400, y = 300 }
obj.isMouseEnabled = function() return true end
obj:sendMouseActivity()
R.check("le déplacement de souris aussi", #ctl.postedEvents > 0, true)
ctl.timeNow = nil


------------------------------------------------------------
R.section("Nos événements sont reconnus au pid qui les a postés")
------------------------------------------------------------
-- Journal réel : « Activité utilisateur réelle détectée (origine : tap
-- rapide, inactivité 0.0 s) » deux secondes après le passage au vert,
-- sans que personne ne touche la machine — et aucune ligne confirmant
-- la marque. eventSourceUserData ne survivait donc pas à la livraison.
--
-- eventSourceUnixProcessID, lui, est renseigné par le système au moment
-- de la livraison : nos événements portent le pid de Hammerspoon, une
-- vraie frappe vient du serveur de fenêtres et n'en porte jamais.
ctl.timeNow = nil
ctl.markLost = true          -- la marque manuelle ne survit pas
ctl.pidLost = false
obj.processID = nil
obj.syntheticMarkWorks = false
obj.currentState = obj.STATE.KEEPALIVE
obj.fastReturnWatcherEnabled = true
obj.fastReturnThrottle = 0
obj.realActivityPending = false
obj.fastReturnWatcher = nil
ctl.eventtaps = {}
ctl.postedEvents = {}
obj:createFastReturnWatcher()
local tapPid = ctl.eventtaps[#ctl.eventtaps]

obj.activityKey = "shift"
obj:postActivityKey()
local notre2 = ctl.postedEvents[#ctl.postedEvents]
R.check("la marque manuelle est bien perdue",
    notre2:getProperty("eventSourceUserData"), nil)
R.check("mais le pid émetteur est là",
    notre2:getProperty("eventSourceUnixProcessID"), 4321)

-- Livré bien après la fenêtre de grâce, comme lors d'un blocage du
-- thread principal.
ctl.now = ctl.now + 60
obj.realActivityPending = false
tapPid.fn(notre2)
R.check("la fenêtre de grâce est expirée", obj:isSyntheticEventWindow(), false)
R.check("il est quand même reconnu comme le nôtre",
    obj.realActivityPending, false)
R.check("l'application reste verte", obj.currentState, obj.STATE.KEEPALIVE)
R.check("et la reconnaissance est confirmée", obj.syntheticMarkWorks, true)

R.section("Une vraie frappe ne porte pas notre pid")
local frappe = { getProperty = function(_, k)
    if k == "eventSourceUnixProcessID" then return 0 end
    return nil
end }
obj.realActivityPending = false
obj.lastFastReturnEventAt = 0
tapPid.fn(frappe)
R.check("elle est bien vue", obj.realActivityPending, true)

R.section("Si le pid n'est pas renseigné, la marque prend le relais")
ctl.pidLost = true
ctl.markLost = false
obj.processID = nil
obj.currentState = obj.STATE.KEEPALIVE
ctl.postedEvents = {}
obj:postActivityKey()
local notre3 = ctl.postedEvents[#ctl.postedEvents]
ctl.now = ctl.now + 60
obj.realActivityPending = false
obj.lastFastReturnEventAt = 0
tapPid.fn(notre3)
R.check("reconnu par la marque", obj.realActivityPending, false)
ctl.pidLost = false
ctl.markLost = false


------------------------------------------------------------
R.section("La règle de sortie ne peut pas se déclencher sur nos propres événements")
------------------------------------------------------------
-- C'est l'invariant, et il faut qu'il reste vrai : nos keep-alives
-- remettent l'horloge d'inactivité de macOS à zéro. Donc une
-- inactivité faible implique un keep-alive récent. Les deux fenêtres
-- — activité de moins de realActivityReturnIdleThreshold, ET dernier
-- keep-alive de plus de postKeepAliveIdleIgnorePeriod — ne peuvent
-- être vraies ensemble que pour une activité qui n'est pas la nôtre.
--
-- Une version a remplacé cela par une comparaison directe entre
-- l'horloge et l'âge de nos événements. Mesuré sur la machine, trois
-- fois de suite à trente secondes du passage au vert :
--   « inactivité 26,0 s, notre dernier événement remonte à 29 s »
-- Trois secondes d'écart systématique. ActivityKeeper ressortait du
-- vert tout seul toutes les trente secondes.
R.check("le seuil couvre le décalage mesuré",
    obj:effectiveIdleIgnorePeriod()
        >= obj.realActivityReturnIdleThreshold + obj.idleRuleSkewAllowance, true)

local function sortirait(idle, depuisKeepAlive)
    -- reproduit exactement la condition de checkIdleState
    return idle <= obj.realActivityReturnIdleThreshold
        and depuisKeepAlive > obj:effectiveIdleIgnorePeriod()
end

-- Notre keep-alive remet l'horloge à zéro : idle et depuis avancent
-- ensemble. Aucun instant ne satisfait les deux fenêtres.
local faussePositive = false
for depuis = 0, 60 do
    if sortirait(depuis, depuis) then faussePositive = true end
end
R.check("aucun instant ne déclenche sur nos propres événements",
    faussePositive, false)

-- Même avec un écart systématique de plusieurs secondes entre notre
-- horodatage et celui de macOS — le cas qui a cassé l'inférence.
faussePositive = false
for depuis = 0, 60 do
    for ecart = 0, 5 do
        if sortirait(math.max(0, depuis - ecart), depuis) then
            faussePositive = true
        end
    end
end
R.check("ni même avec un décalage de cinq secondes", faussePositive, false)

-- Et un vrai retour est bien vu.
R.check("un vrai retour, lui, sort du vert", sortirait(1, 30), true)


------------------------------------------------------------
R.section("Une configuration trop courte est relevée, pas subie")
------------------------------------------------------------
-- L'utilisateur avait 6 et 8 dans son init.lua : deux secondes de
-- tolérance pour un décalage réel de trois. Corriger le défaut du Spoon
-- n'aurait rien changé pour lui — sa valeur l'aurait écrasé. L'invariant
-- est donc appliqué à l'exécution.
obj.realActivityReturnIdleThreshold = 6
obj.idleRuleSkewAllowance = 6
obj.postKeepAliveIdleIgnorePeriod = 8      -- la valeur qui posait problème
obj.idleIgnorePeriodWarned = nil
ctl.printed = {}
R.check("la valeur est relevée", obj:effectiveIdleIgnorePeriod(), 12)
R.check("et le relèvement est expliqué",
    table.concat(ctl.printed, " "):find("prend ses propres", 1, true) ~= nil, true)

ctl.printed = {}
obj:effectiveIdleIgnorePeriod()
R.check("mais dit une seule fois", #ctl.printed, 0)

obj.postKeepAliveIdleIgnorePeriod = 20
R.check("une valeur suffisante est respectée", obj:effectiveIdleIgnorePeriod(), 20)

R.section("Avec l'invariant, aucun décalage plausible ne déclenche")
obj.postKeepAliveIdleIgnorePeriod = 15
local faussePositive2 = false
for depuis = 0, 120 do
    for ecart = 0, obj.idleRuleSkewAllowance do
        if depuis - ecart <= obj.realActivityReturnIdleThreshold
            and depuis > obj:effectiveIdleIgnorePeriod() then
            faussePositive2 = true
        end
    end
end
R.check("aucun instant, aucun décalage jusqu'à six secondes",
    faussePositive2, false)

R.finish()
