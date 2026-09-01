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
R.section("Sortie du vert : la frappe avalée par la fenêtre synthétique")
------------------------------------------------------------
-- Le scénario mesuré chez l'utilisateur :
--
--   T      keep-alive envoyé, fenêtre synthétique ouverte 1 s
--   T+0,3  l'utilisateur tape — le tap ignore, c'est la fenêtre
--   T+8    l'idle redevient consultable (postKeepAliveIdleIgnorePeriod)
--   T+10   idle vaut 10 s, plus que realActivityReturnIdleThreshold (6)
--   ...    l'utilisateur ne tape plus : plus aucun événement
--
-- L'application restait verte indéfiniment. La nouvelle règle ne
-- compare plus l'inactivité à un seuil fixe, mais à l'âge de NOTRE
-- dernier événement : si l'horloge de macOS est plus récente que lui,
-- c'est que quelqu'un d'autre a agi.
obj.currentState = obj.STATE.KEEPALIVE
obj.keepaliveExitMargin = 2
obj.keepaliveEnteredAt = 1000
obj.lastKeepAliveTime = 1000

-- Personne n'a rien fait : l'inactivité suit notre keep-alive.
ctl.timeNow = 1010
ctl.idle = 10
R.check("aucune activité : on reste vert",
    obj:realActivitySinceOurLastEvent(), false)

-- L'utilisateur a tapé à T+3 puis s'est arrêté : inactivité 7 s, notre
-- keep-alive remonte à 10 s. Plus récent que nous, donc c'est lui.
ctl.idle = 7
R.check("frappe manquée par le tap : rattrapée quand même",
    obj:realActivitySinceOurLastEvent(), true)

-- L'ancienne règle ne l'aurait pas vue : 7 s dépasse le seuil de 6.
R.check("l'ancien seuil aurait échoué",
    7 <= obj.realActivityReturnIdleThreshold, false)

-- Ce que l'inférence ne peut PAS voir : une activité trop proche de la
-- nôtre. Elle est indiscernable par construction — c'est la fermeture
-- anticipée de la fenêtre aveugle qui couvre ce cas, pas ce filet.
ctl.idle = 9.7
R.check("activité à 0,3 s de la nôtre : hors de portée de l'inférence",
    obj:realActivitySinceOurLastEvent(), false)

R.section("La marge protège des conclusions hâtives")
ctl.idle = 0
ctl.timeNow = 1001
R.check("juste après notre keep-alive : on ne conclut rien",
    obj:realActivitySinceOurLastEvent(), false)

ctl.timeNow = 1010
ctl.idle = 8.5
R.check("dans la marge : on ne conclut pas non plus",
    obj:realActivitySinceOurLastEvent(), false)
ctl.idle = 7.5
R.check("au-delà de la marge : on conclut",
    obj:realActivitySinceOurLastEvent(), true)

R.section("Entrée au vert sans keep-alive encore envoyé")
-- Sans la borne d'entrée, « aucun keep-alive » vaudrait référence à
-- l'époque, et l'application ressortirait du vert immédiatement.
obj.lastKeepAliveTime = nil
obj.keepaliveEnteredAt = 1000
ctl.timeNow = 1005
ctl.idle = 125            -- inactif depuis longtemps, c'est pour ça qu'on est vert
R.check("on vient de passer au vert : rien à déduire",
    obj:realActivitySinceOurLastEvent(), false)
ctl.idle = 0.5            -- l'utilisateur revient avant le premier keep-alive
R.check("mais un vrai retour est vu",
    obj:realActivitySinceOurLastEvent(), true)

R.section("Hors du vert, la règle ne s'applique pas")
obj.currentState = obj.STATE.MONITORING
R.check("en jaune : rien", obj:realActivitySinceOurLastEvent(), false)
obj.currentState = obj.STATE.OFF
R.check("éteint : rien", obj:realActivitySinceOurLastEvent(), false)

R.section("Le filet tourne en vert et s'arrête en sortant")
obj.currentState = obj.STATE.MONITORING
obj.fastReturnWatcherEnabled = false
ctl.everyTimers = {}
obj:setState(obj.STATE.KEEPALIVE)
R.check("un filet bat pendant le vert", obj.keepaliveExitTimer ~= nil, true)
R.check("à la bonne cadence",
    ctl.everyTimers[#ctl.everyTimers].delay, obj.keepaliveExitCheckInterval)
R.check("l'instant d'entrée est noté", obj.keepaliveEnteredAt ~= nil, true)
obj:setState(obj.STATE.MONITORING)
R.check("il s'arrête en sortant", obj.keepaliveExitTimer, nil)
R.check("et la référence est effacée", obj.keepaliveEnteredAt, nil)

R.section("Aucun timer ne survit à l'arrêt")
obj:setState(obj.STATE.KEEPALIVE)
R.check("filet actif", obj.keepaliveExitTimer ~= nil, true)
obj:stop()
R.check("libéré à l'arrêt du Spoon", obj.keepaliveExitTimer, nil)
obj.fastReturnWatcherEnabled = true


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


------------------------------------------------------------
R.section("Nos touches de rétroéclairage ne sont pas l'utilisateur")
------------------------------------------------------------
-- Le keep-alive n'est pas notre seul événement. disableKeyboardBacklight
-- et restoreKeyboardBacklight postent des touches système, et
-- forceKeyboardBacklightOffAfterKeepAlive s'exécute à des instants sans
-- rapport avec le dernier keep-alive. Toutes remettent à zéro l'horloge
-- d'inactivité de macOS.
--
-- L'inférence comparait cette horloge au dernier KEEP-ALIVE. Une touche
-- de rétroéclairage postée trente secondes plus tard remettait donc
-- l'horloge à zéro alors que la référence datait de trente secondes :
-- l'inférence concluait « quelqu'un d'autre a agi ». Puis l'inactivité
-- remontait, on repassait au vert — surveillance, actif, surveillance,
-- actif, sans que personne ne touche la machine.
obj.currentState = obj.STATE.KEEPALIVE
obj.keepaliveExitMargin = 2
obj.keepaliveEnteredAt = 1000
obj.lastKeepAliveTime = 1000
obj.lastSyntheticAt = 1000

-- Trente secondes plus tard, rien ne s'est passé.
ctl.timeNow = 1030
ctl.idle = 30
R.check("rien à déduire", obj:realActivitySinceOurLastEvent(), false)

-- Nous postons une touche système de rétroéclairage : macOS remet son
-- horloge à zéro. Le dernier keep-alive, lui, remonte toujours à 30 s.
obj:markSynthetic({ setProperty = function(e) return e end })
ctl.idle = 0.2
R.check("notre propre touche n'est pas l'utilisateur",
    obj:realActivitySinceOurLastEvent(), false)

-- Et un vrai retour reste vu, une fois passée la marge.
ctl.timeNow = 1040
ctl.idle = 0.5
R.check("un vrai retour est toujours détecté",
    obj:realActivitySinceOurLastEvent(), true)

R.section("Chaque événement émis met la référence à jour")
ctl.postedEvents = {}
obj.lastSyntheticAt = nil
obj.activityKey = "shift"
ctl.timeNow = 2000
obj:postActivityKey()
R.check("la touche de keep-alive compte", obj.lastSyntheticAt, 2000)

obj.lastSyntheticAt = nil
ctl.timeNow = 2100
obj:sendSystemKey("ILLUMINATION_DOWN")
R.check("la touche système aussi", obj.lastSyntheticAt, 2100)

obj.lastSyntheticAt = nil
ctl.timeNow = 2200
ctl.mouseClamped = false
ctl.mousePosition = { x = 400, y = 300 }
obj.isMouseEnabled = function() return true end
obj:sendMouseActivity()
R.check("le déplacement de souris aussi", obj.lastSyntheticAt, 2200)
ctl.timeNow = nil

R.finish()
