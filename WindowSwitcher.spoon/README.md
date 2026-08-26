# WindowSwitcher.spoon

Spoon Hammerspoon pour remplacer un switcher de fenetres type Windows Alt+Tab, AltTab ou BetterCmdTab.

## Installation

Copier le dossier `WindowSwitcher.spoon` dans :

```text
~/.hammerspoon/Spoons/
```

Puis ajouter dans `~/.hammerspoon/init.lua` :

```lua
hs.loadSpoon("WindowSwitcher")

spoon.WindowSwitcher:bindHotkeys({
    forward = {
        {"alt"},
        "tab"
    },
    backward = {
        {"alt", "shift"},
        "tab"
    },
})

spoon.WindowSwitcher:start()
```

## Raccourcis

- `Option + Tab` : fenetre suivante.
- `Option + Maj + Tab` : fenetre precedente.
- Relacher les modificateurs : selectionne et active la fenetre.
- `Echap` : ferme le switcher sans rien activer, le focus reste ou il etait.

## Fonctionnalites

- Switch par fenetre, pas seulement par application.
- Tri par derniere fenetre focussee.
- Vue en grille compacte, proche de BetterCmdTab/AltTab/Windows.
- Panneau clair, translucide, centre, avec marge de securite autour de l'ecran.
- Captures reelles via `hs.window.snapshotForID`, puis helper ScreenCaptureKit si necessaire.
- Filtre de fenetres permanent : `hs.window.filter` n'est monte qu'une fois, au demarrage.
- Une seule resolution d'application par fenetre et par session, portee par un descripteur.
- Fin de session detectee par un eventtap `flagsChanged`, sans sondage clavier.
- Ordre de profondeur lu au WindowServer via `hs.window._orderedwinids()`.
- Application masquee par Cmd+H demasquee avant l'activation.
- Fallback propre avec grande icone d'application centree si macOS refuse une capture.
- Affichage immediat : les captures ScreenCaptureKit sont chargees en arriere-plan.
- Selection souris : survol pour selectionner, clic pour activer directement la fenetre.
- Apercu de la fenetre selectionnee, a sa taille et a sa place reelles, sous le panneau.
- Pastilles d'etat sur la vignette : fenetre reduite, application masquee.
- `Echap` annule la session sans rien activer.
- Feux de fermeture et de reduction redessines d'apres le systeme, sur la vignette visee.
- Restauration des fenetres minimisees avant focus.
- Inclusion des fenetres minimisees et cachees par defaut.
- Inclusion des autres Spaces par defaut, dans les limites des API macOS exposees a Hammerspoon.
- Exclusion par bundle ID via `ignored-bundles.txt`.
- Activation/desactivation possible via `SpoonManager`.
- Rendu via un seul `hs.canvas`, pour eviter de creer/detruire beaucoup d'objets graphiques a chaque switch.
- Anti-rebond clavier via `stepThrottleSeconds`, pour eviter les sauts de selection.

## Options utiles

```lua
spoon.WindowSwitcher.maxColumns = 4
spoon.WindowSwitcher.maxRows = 3
spoon.WindowSwitcher.maxPanelWidthRatio = 0.78
spoon.WindowSwitcher.maxPanelHeightRatio = 0.62
spoon.WindowSwitcher.screenMargin = 64
spoon.WindowSwitcher.previewMaxWidth = 300
spoon.WindowSwitcher.previewMaxHeight = 190
spoon.WindowSwitcher.snapshotCacheSeconds = 20
spoon.WindowSwitcher.snapshotCacheMaxEntries = 200
spoon.WindowSwitcher.screenCaptureHelperEnabled = true
spoon.WindowSwitcher.instantVisibleSnapshots = true
spoon.WindowSwitcher.maxConcurrentScreenCaptures = 2
spoon.WindowSwitcher.screenCapturePixelHeight = 420
spoon.WindowSwitcher.screenCaptureFailureBackoffSeconds = 5
spoon.WindowSwitcher.screenCaptureRequestTimeoutSeconds = 6.5
spoon.WindowSwitcher.logScreenCaptureFailures = true
spoon.WindowSwitcher.stepThrottleSeconds = 0.06
spoon.WindowSwitcher.completeWithAllWindows = true
spoon.WindowSwitcher.modifierSafetyInterval = 0.35
spoon.WindowSwitcher.redrawCoalesceSeconds = 0.05
spoon.WindowSwitcher.mouseActivationDistance = 6
spoon.WindowSwitcher.mouseIdleSeconds = 1.6
spoon.WindowSwitcher.screenCaptureGiveUpAfter = 3
spoon.WindowSwitcher.focusReassertDelay = 0.12
spoon.WindowSwitcher.snapshotBudgetSeconds = 0.045
spoon.WindowSwitcher.showStateBadges = true
spoon.WindowSwitcher.showAudioBadges = true
spoon.WindowSwitcher.showCloseButton = true
spoon.WindowSwitcher.showMinimizeButton = true
spoon.WindowSwitcher.enableCloseKey = true
spoon.WindowSwitcher.enableMinimizeKey = true
spoon.WindowSwitcher.trafficLightSize = 19
spoon.WindowSwitcher.helperLaunchMode = "task"
spoon.WindowSwitcher.helperIdleGraceSeconds = 6
spoon.WindowSwitcher.enableCancelKey = true
spoon.WindowSwitcher.enableWindowPreview = true
spoon.WindowSwitcher.previewDelay = 0.65
spoon.WindowSwitcher.previewOnKeyboard = true
```

### Pastilles d'etat

Une pastille dans le coin de la vignette signale une fenetre reduite
(`⤓`), une application masquee par Cmd+H (`⦸`), une application qui
joue du son (`♪`), qui capte le micro (`◉`), ou une fenetre posee sur
un autre bureau (`⧉`).

Les deux premieres viennent du descripteur deja construit pour filtrer
la fenetre : elles ne coutent qu'un element de dessin.

Les deux autres viennent du service, par l'API publique CoreAudio des
objets de processus (`kAudioProcessPropertyIsRunningOutput` et
`IsRunningInput`, macOS 14.4+). Une seule demande par session, qui ne
touche ni le disque ni ScreenCaptureKit.

`showAudioBadges = false` supprime la demande **et** les pastilles.

L'inventaire est demande au demarrage puis a chaque session, et son
resultat est conserve d'une session a l'autre. Quand le service est
froid il met environ une demi-seconde a repondre : un switch tres bref
se termine avant, et les pastilles paraissent alors a la session
suivante. C'est le prix de l'extinction du service entre deux switchs ;
allonger `helperIdleGraceSeconds` les rend immediates, au prix de 31 Mo
residents.

#### Le pid qui joue n'est pas celui de la fenetre

CoreAudio renvoie le processus qui **produit** le son, pas celui qui
possede la fenetre. Un navigateur joue depuis un processus auxiliaire :
Edge annonce le pid 1396 alors que sa fenetre appartient au pid 621.
Sans remonter la filiation, aucune pastille ne pouvait correspondre.

Le service renvoie donc le pid **et ses ancetres**, jusqu'a `launchd`
exclu : `out=1396,621`. Le switcher cherche simplement le pid de sa
fenetre dans l'ensemble. Decider cote service lequel des ancetres est
"l'application" n'aurait pas ete fiable, certains auxiliaires
s'enregistrant eux-memes comme applications.

Le micro, lui, est souvent capte par un processus systeme sans parent
applicatif — `corespeechd` pour la dictee — qui n'appartient a aucune
fenetre et ne porte donc aucune pastille. C'est correct.

```lua
spoon.WindowSwitcher:audioStatus()
```

Dit ou en est l'inventaire sans rien changer : pastilles actives ou non,
service en marche ou arrete, demande en vol, et la liste des processus
qui jouent et qui captent.

### Bureaux

Une vignette ne disait pas si sa fenetre se trouve sur le bureau
courant. En plein ecran, ou avec plusieurs bureaux, une bonne part de
la grille pointait vers des fenetres invisibles ici sans que rien ne le
signale. La pastille `⧉` le dit.

#### Pourquoi cette question-la est sure

Le meme WindowServer avait ete pris en defaut dans LastWindowQuits :
interroge sur l'**existence** d'une fenetre, il garde une fenetre
fermee comme une vivante tant que son application tourne, ce qui avait
rendu des applications infermables.

La question posee ici est differente : « ou est cette fenetre »,
et le switcher ne liste que des fenetres vivantes. Verifie sur cette
machine :

```
CGSGetActiveSpace                      1
Current Space (ManagedSpaceID)         1
CGSCopySpacesForWindows(Claude 1441)   [1]      -> ici
CGSCopySpacesForWindows(Notes 2035)    [204]    -> autre bureau
```

Les trois API partagent la meme numerotation, ce qui autorise la
comparaison directe.

#### La liste vide est le cas majoritaire

Sur 40 fenetres relevees, la plupart — panneaux, fenetres reduites,
fenetres d'applications masquees — repondent une liste **vide** : le
WindowServer ne situe que ce qui a une presence. Les compter comme
« ailleurs » aurait pastille presque toute la grille. Une absence de
reponse vaut donc « ici » : ni pastille, ni deplacement, ni
regroupement.

#### Une fenetre reduite garde son bureau

```
ouverte, visible   spaces=[1]
REDUITE (Dock)     spaces=[1]
restauree          spaces=[1]
```

`unminimize` la rend a son bureau d'origine : qui tabule dessus se
retrouve ailleurs. Elle porte donc les **deux** pastilles, `▼` et `⧉`,
et le mode `"bring"` la deplace comme les autres.

Une version precedente les ecartait, en supposant qu'une fenetre reduite
n'appartenait plus a aucun bureau. C'etait faux.

#### On ne peut pas faire venir une fenetre a soi

C'est ce que promet [Sanyam-G/switch](https://github.com/Sanyam-G/switch) :
amener la fenetre sur le bureau courant plutot que d'y aller. Mesure
faite sur cette machine, meme binaire, memes permissions :

| | ma fenetre | fenetre d'une autre application |
|---|---|---|
| `CGSMoveWindowsToManagedSpace` | **reussi** | echec |
| `SLSSetWindowListWorkspace` | **echec 1006** | echec |

Deux raisons independantes, chacune suffisante.

**Un processus ne deplace que ses propres fenetres.** Dock.app detient
la seule connexion au window server autorisee a le faire pour les
autres. C'est precisement pour cela que yabai injecte une extension
dans Dock.app, ce qui exige de desactiver SIP. Le service de capture
n'y changerait rien : c'est un processus ordinaire lui aussi.

**Et l'appel de Hammerspoon ne fonctionne plus.** Depuis macOS 14.5,
`hs.spaces.moveWindowToSpace` passe par `SLSSetWindowListWorkspace`,
qui renvoie 1006 et ne fait rien — meme sur la fenetre du processus
appelant — tout en renvoyant `true`. D'ou, dans le journal :
`l'API a dit oui, la fenetre n'a pas bouge`.

Sanyam-G/switch appelle la meme fonction avec sa propre connexion et
**ne verifie jamais le resultat** :

```swift
let cid = CGSMainConnectionID()
CGSMoveWindowsToManagedSpace(cid, ids, currentSpace)
```

Le deplacement echoue, puis leur `app.activate()` laisse macOS basculer
de bureau. L'utilisateur arrive a sa fenetre sans savoir lequel des deux
chemins a servi.

Le switcher ne s'y essaie donc pas : macOS bascule, avec son animation
native. La verification du focus attend `crossSpaceFocusDelay` (0,7 s)
au lieu du delai ordinaire, verifier pendant la bascule trouvant le
focus sur la fenetre precedente.

#### Autres reglages

```lua
spoon.WindowSwitcher.showSpaceBadges = true     -- la pastille
spoon.WindowSwitcher.currentSpaceFirst = false  -- grouper le bureau courant devant
spoon.WindowSwitcher.includeOtherSpaces = true  -- lister les autres bureaux
spoon.WindowSwitcher.crossSpaceFocusDelay = 0.7 -- attente de la bascule
```

`currentSpaceFirst` place les fenetres du bureau courant avant les
autres en preservant l'ordre d'usage a l'interieur de chaque groupe.
Desactive par defaut : l'ordre par usage recent reste ce qu'on attend
d'un Alt+Tab.

#### Pourquoi l'inventaire ne passe pas par `hs.spaces.activeSpaces()`

Cette fonction passe par `activeSpaceOnScreen()`, qui remplace l'UUID de
l'ecran par la chaine `"Main"` quand
`NSScreen.screensHaveSeparateSpaces` vaut faux — puis cherche un ecran
nomme `"Main"` dans une liste qui n'en contient que des UUID. Mesure :

```
NSScreen.screensHaveSeparateSpaces = false
hs.screen:getUUID()                = 37D8832A-2D66-...
Display Identifier                 = 37D8832A-2D66-...
```

Elle renvoie `nil`, et **tout ce qui concerne les bureaux s'eteignait
sans un mot** des que l'option « Les moniteurs ont des espaces separes »
etait decochee.

`data_managedDisplaySpaces()` donne la meme information sans cette
identification d'ecran, en un seul appel — celui-la meme dont
`activeSpaces()` se sert une fois par ecran. Le repli sur l'API
documentee reste en place si la lecture directe disparait un jour.

`hs.spaces` repose sur les API privees de SkyLight. S'il devient
indisponible, tout ce qui precede s'efface et le switcher continue.

### Fenetres que macOS refuse de capturer

Certaines fenetres ne seront jamais capturables. Le panneau
**Enregistrement de l'ecran** des Reglages Systeme, par exemple, renvoie
`SCStreamErrorDomain Code=-3811` a chaque tentative.

Le delai d'attente ordinaire de cinq secondes faisait reessayer a chaque
switch, en journalisant a chaque fois. Apres
`screenCaptureGiveUpAfter` echecs consecutifs, la fenetre est mise de
cote pour `screenCaptureGiveUpBackoffSeconds`, et l'abandon est
journalise une seule fois. Elle affiche alors l'icone de son
application, ce qui est le bon repli. Une capture qui finit par reussir
efface l'ardoise.

**La camera n'a pas d'equivalent.** CMIO expose les peripheriques, pas
l'application qui les utilise : macOS reserve cette attribution au
voyant du Centre de controle. La contourner demanderait des API privees.

**Couper le son d'une application n'est pas possible** par l'API
publique. CoreAudio expose six proprietes par processus, toutes
informatives, et aucune n'est modifiable. Les applications qui y
parviennent installent un pilote audio virtuel, c'est-a-dire une
extension systeme.

Chaque nature a sa couleur pleine, un glyphe blanc et un lisere clair
qui la detache du fond. Une pastille sombre translucide sur une vignette
sombre ne se voyait pas.

```lua
spoon.WindowSwitcher.badges.minimized.glyph = "▼"
spoon.WindowSwitcher.badges.minimized.color = { red = 0.98, green = 0.62, blue = 0.09, alpha = 0.97 }
```

`showStateBadges = false` retire les pastilles de fenetre,
`showAudioBadges = false` celles du son.

### Fermer et reduire

Les deux feux apparaissent **en haut a gauche** de la vignette visee, a
la place et dans l'ordre qu'ils occupent sur une fenetre macOS, et
seulement quand la souris est en jeu : au clavier ils n'auraient aucune
cible, et affiches sur toutes les tuiles ils encombreraient la grille.
Les pastilles d'etat sont donc posees a droite, de droite a gauche.

Ce ne sont pas des glyphes de police mais les boutons du systeme
redessines. Toutes les constantes viennent de mesures faites sur une
vraie fenetre, capturee a 2x avec l'etat survole force :

| | fermer | reduire |
|---|---|---|
| remplissage | `#EC6765` | `#F2CA44` |
| lisere | `#E73935` clair, `#DD2F2C` sombre | `#EFBA0B` / `#E5B102` |
| symbole | le remplissage assombri de moitie, exactement | idem |
| etendue visible | 50 % du disque | 57 % |
| epaisseur du trait | 14,7 % du disque | idem |
| bouts | arrondis | arrondis |
| ecart entre centres | 1,64 fois le diametre | |

Le remplissage et le symbole sont identiques en theme clair et sombre ;
seul le lisere bouge un peu.

Deux details qui font la difference a l'oeil : le symbole n'a pas de
couleur propre, c'est le disque multiplie par 0,5 — verifie canal par
canal sur les deux boutons et les deux themes ; et les bouts arrondis
depassent des extremites du trait de la moitie de son epaisseur, si bien
que le trait doit etre plus court d'une epaisseur entiere que l'etendue
visible.

Leurs cibles de clic sont posees apres celle de la tuile, donc elles
recoivent le clic en premier — sans quoi elles activeraient la fenetre.

Ils apparaissent des que la souris bouge franchement, **y compris quand
elle survole la tuile deja visee** : dans ce cas la selection ne change
pas, donc rien ne serait redessine sans un rendu explicite.

Ils s'effacent apres `mouseIdleSeconds` de silence de la souris, et
reviennent au mouvement suivant. Survoler un feu repousse cet
effacement, sans quoi il disparaitrait sous le pointeur au moment de
cliquer. Mettre ce delai a `0` les laisse affiches jusqu'a la fin de la
session.

Au clavier, `W` ferme la fenetre visee et `M` la reduit. Fermer retire
la tuile et termine la session s'il n'en reste aucune ; reduire la garde
en place, invalide sa vignette et fait apparaitre sa pastille.

Si l'application refuse la fermeture, la tuile reste en place et le
motif est journalise.

```lua
spoon.WindowSwitcher.showCloseButton = false
spoon.WindowSwitcher.showMinimizeButton = false
spoon.WindowSwitcher.enableCloseKey = false
spoon.WindowSwitcher.enableMinimizeKey = false
```

### Annuler

`Echap` ferme le switcher sans rien activer : le focus reste exactement
ou il etait. La touche est consommee, l'application dessous ne la voit
pas.

C'est un eventtap et non un `hs.hotkey` : pendant un `Option+Tab` les
modificateurs sont enfonces, et un raccourci declare sans modificateur
ne se declencherait jamais. Le tap ne tourne que pendant une session.

### Apercu de la fenetre

Survoler une vignette, ou s'arreter dessus au clavier, redessine la
fenetre selectionnee **a sa taille et a sa place reelles**, au-dessus
des autres fenetres. Plus besoin de deviner laquelle se cache derriere
laquelle.

L'apercu s'affiche sous le panneau du switcher, jamais par-dessus : la
grille reste lisible et cliquable. Un liseré aux couleurs de la
selection le delimite, ce qui le rend visible meme lorsqu'il recouvre
exactement une fenetre deja au premier plan.

`previewDelay` est le temps d'arret avant qu'un apercu apparaisse, et il
est **remis a zero a chaque changement de tuile**. Tant qu'on parcourt la
grille, rien ne s'affiche ; un apercu deja visible disparait des le
premier saut et ne revient que lorsqu'on s'arrete pour de bon.

L'apercu accompagne donc une hesitation, jamais une navigation.

Mettre `previewOnKeyboard = false` reserve l'apercu au survol souris.

Une fenetre dont le cadre depasse l'ecran est reduite en conservant ses
proportions ; une fenetre sans cadre exploitable est centree.

La finesse de l'apercu depend de la capture disponible. Les fenetres
visibles sont capturees en pleine resolution par le WindowServer. Les
fenetres reduites passent par le service, a la hauteur fixee par
`screenCapturePixelHeight` (420 par defaut) : monter cette valeur donne
un apercu plus net, au prix de captures plus lourdes.

### Temps de la premiere ouverture

`hs.window.snapshotForID` est synchrone. Capturer douze tuiles avant le
premier affichage, c'est le temps de fabrication que l'on ressent a la
premiere ouverture, quand aucun cache n'est encore chaud.

`snapshotBudgetSeconds` borne ce que l'on s'autorise avant d'afficher.
Les tuiles sont rechauffees en partant de la selection, puis de proche
en proche : si le budget ne suffit pas, ce n'est jamais la tuile qu'on
regarde qui attend. Les autres arrivent au rendu suivant, sans bloquer.

L'augmenter donne plus de vignettes reelles des la premiere image, au
prix d'une ouverture plus lente ; le reduire fait apparaitre l'icone de
l'application le temps d'un rendu.

### Mesurer

```lua
spoon.WindowSwitcher:benchmark()
```

Construit une session complete sans l'afficher et detaille dans la
console le temps de chaque etape : collecte, geometrie, captures, rendu.
Le cache est vide d'office, pour reproduire la premiere ouverture ;
`benchmark(false)` le conserve.

### La seconde passe d'inventaire

`completeWithAllWindows` commande une seconde passe, faite avec
`hs.window.allWindows()` : un balayage d'accessibilite de toutes les
applications lancees. C'est l'operation la plus couteuse d'une session,
et elle **n'est pas facultative**.

Le filtre `hs.window.filter` a deux angles morts, tous deux lisibles
dans `window_filter.lua` :

1. Une application n'y entre que si `app:focusedWindow()` repond. Sinon
   elle part dans une echelle de reessais de 0,2 s a 1,2 s dont seul le
   dernier force l'inscription, soit **4,2 s au total**. Une application
   dont toutes les fenetres sont reduites n'a pas de fenetre focalisee :
   elle est absente du filtre pendant les quatre premieres secondes
   suivant un rechargement de Hammerspoon.

2. A l'inscription, le filtre n'enumere que l'espace courant
   (`getCurrentSpaceAppWindows`), avec un `TODO` explicite en commentaire
   sur l'impossibilite de faire mieux.

La 0.9.0 avait desactive cette passe en supposant qu'un filtre permanent
suffisait. C'etait faux : au premier `Option+Tab` suivant un
rechargement, les fenetres reduites manquaient et n'apparaissaient qu'au
switch suivant. Retabli en 0.10.3.

```lua
spoon.WindowSwitcher.completeWithAllWindows = false   -- plus rapide, incomplet
```

Le panneau est toujours calcule depuis le contenu puis limite par `maxPanelWidthRatio`, `maxPanelHeightRatio` et `screenMargin`, donc il ne doit jamais prendre tout l'ecran.

Les fenetres reduites utilisent le helper `window-capture-helper` fourni avec le Spoon pour obtenir une capture ScreenCaptureKit, comme les switchers natifs modernes. Si macOS ne fournit pas de capture exploitable, le Spoon affiche l'icone de l'app au centre de l'apercu au lieu d'une vignette noire.

Si macOS demande une permission "Enregistrement de l'ecran", l'accorder pour Hammerspoon ou pour le helper affiche. Sans cette permission, le switcher continue de fonctionner avec le fallback icone.

## Exclusions

Les bundle IDs ignores se configurent dans le fichier voisin :

```text
~/.hammerspoon/Spoons/WindowSwitcher.spoon/ignored-bundles.txt
```

Format :

```text
com.apple.controlcenter
com.apple.notificationcenterui
pro.bettercmdtab.BetterCmdTab
```

Une ligne par bundle ID. Les lignes vides et les commentaires commencant par `#` sont ignores.

Ne pas ajouter `com.hammerspoon.Hammerspoon` ici si tu veux voir la console Hammerspoon dans le switcher.

## Trouver un bundle ID

Depuis la console Hammerspoon, la console devient souvent l'app active. Chercher donc l'application par nom :

```lua
app = hs.application.find("Microsoft Outlook")
print(app:name(), app:bundleID())
```

```lua
app = hs.application.find("Microsoft Teams")
print(app:name(), app:bundleID())
```

## Notes BetterCmdTab

BetterCmdTab va plus loin qu'un script Hammerspoon : il combine WindowServer, Accessibility, ScreenCaptureKit et quelques API privees pour retrouver les fenetres, les onglets natifs, l'ordre exact, puis lever la fenetre cible.

Cette version Hammerspoon vise le coeur du besoin : un switcher Option+Tab par fenetre avec grille d'apercus reels et restauration des fenetres minimisees, sans processus externe permanent.

Pour tester proprement, quitter BetterCmdTab ou changer son raccourci, sinon il peut intercepter `Option + Tab` avant Hammerspoon.


## Le helper de capture

`WindowSwitcherCapture.app` est un service ScreenCaptureKit lance a la
demande. Le Spoon lui parle par fichiers, dans un repertoire de session
protege par un secret tire de `/dev/urandom` et regenere a chaque
demarrage. Le helper verifie la version du protocole, le jeton, le
secret, et refuse d'ecrire ailleurs que dans le sous-repertoire
`captures/` de la session.

Le service se termine seul apres 30 secondes sans requete. Le Spoon le
detecte par son identifiant de bundle et le relance a la demande.

### Duree de vie du service

Mesure sur une machine Apple Silicon : le service au repos occupe
**31 Mo residents** et environ 0,5 % de processeur, et un demarrage a
froid coute **500 ms** jusqu'a la premiere reponse.

Il s'arrete tout seul apres 30 s sans requete. Comme l'inventaire audio
lui est demande a chaque switch, ce delai le laisserait en vie
pratiquement toute la journee. Le Spoon l'arrete donc lui-meme des qu'il
n'a plus rien a faire, apres `helperIdleGraceSeconds`.

Une rafale de switchs rapproches reutilise le meme processus ; un switch
isole paie un relancement, qui n'est sur le chemin critique de rien
puisque captures et inventaire sont asynchrones. Mettre ce delai a `0`
rend la main a l'auto-extinction du service.

### Emplacement des fichiers

Depuis la 0.11.0, la base est `$TMPDIR/WindowSwitcher`, le repertoire
temporaire propre a l'utilisateur (`/var/folders/.../T/`), deja en 0700
et hors de portee des autres comptes.

Auparavant c'etait `/tmp/WindowSwitcher`. `/tmp` est inscriptible par
tous en mode 1777 : il suffisait de creer le repertoire de base avant
Hammerspoon, en le laissant ouvert en lecture, pour recevoir toutes les
captures qui y passeraient ensuite. Le Spoon efface l'ancien
emplacement au demarrage, apres avoir verifie qu'il lui appartient.

Chaque repertoire est verifie avant usage : il doit nous appartenir,
n'etre ouvert ni au groupe ni aux autres, et ne pas etre un lien
symbolique. Si la verification echoue, **aucune capture n'est
demandee** : le switcher continue avec les icones d'application et le
motif est journalise.

### Portee de l'autorisation

Jusqu'a la 0.12.0 le service etait lance par `open -gj -n`, ce qui le
**detache** : son processus responsable etait `launchd`, il portait donc
sa propre identite TCC. N'importe quel processus du compte pouvait
lancer cette application avec son propre repertoire de session et
obtenir des captures. Le secret n'y changeait rien : il protege le
repertoire d'une session contre une injection exterieure, pas contre un
appelant qui fournit le sien.

Depuis la 0.13.0, `helperLaunchMode = "task"` lance le service comme
**enfant de Hammerspoon**. macOS attribue les acces TCC au processus
responsable : le service herite alors de l'autorisation de Hammerspoon
au lieu d'en porter une propre. Un binaire lance par un autre processus
est responsable de lui-meme, donc sans autorisation, donc sans capture.

```lua
spoon.WindowSwitcher.helperLaunchMode = "open"   -- ancien comportement
```

Si les vignettes de fenetres reduites cessent de fonctionner apres la
bascule, c'est que l'attribution par parent ne s'applique pas sur cette
version de macOS : repasser en `"open"` et reaccorder l'autorisation au
helper.

### Reconstruire le binaire

```bash
./build-helper.sh
```

Le script compile le binaire simple et celui du bundle `.app`, signe le
bundle, et depose l'empreinte de la source compilee dans
`window-capture-helper.sha256`.

Le binaire est signe ad hoc, donc chaque compilation change son
`cdhash`. **Avec `helperLaunchMode = "task"`, cela n'a plus
d'importance** : le service n'a plus d'identite TCC propre, il herite de
celle de Hammerspoon. Verifie en pratique — une capture reussit
immediatement apres une recompilation, sans rien reaccorder.

En mode `"open"`, en revanche, le service porte sa propre autorisation
et il faut la reaccorder apres chaque compilation.

Le binaire compile et le bundle `.app` ne sont pas versionnes ici : la
signature ad hoc est propre a la machine qui l'a produite.

Au demarrage, le Spoon compare l'empreinte de la source presente a celle
deposee a la compilation : un durcissement ecrit dans le `.swift` ne
doit pas donner l'illusion d'etre actif.

La comparaison portait auparavant sur les **dates de modification**.
C'etait un mauvais juge : copier le Spoon suffisait a rendre le `.swift`
plus recent que le binaire sans qu'une seule ligne ait change, et
l'avertissement reclamait alors une recompilation pour rien. Ce qui
compte est le contenu, pas la date.

Sans empreinte deposee — installation anterieure a `build-helper.sh` —
le Spoon retombe sur les dates, en signalant que le constat peut venir
d'une simple copie.

Compiler avec `-parse-as-library`, le fichier utilisant `@main` :

```bash
swiftc -O -parse-as-library window-capture-helper.swift \
  -o WindowSwitcherCapture.app/Contents/MacOS/window-capture-helper
codesign --force --sign - \
  --identifier local.hammerspoon.WindowSwitcherCapture WindowSwitcherCapture.app
```

Le protocole est passe en version 4 : le Spoon et le binaire doivent
etre mis a jour ensemble, sinon toutes les requetes sont refusees avec
`bad request version`.
