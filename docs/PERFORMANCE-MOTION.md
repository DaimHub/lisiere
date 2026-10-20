# Mesures de fluidité native — 19–20 octobre 2026

L'objectif est de suivre un écran à 120 Hz, soit une nouvelle image toutes les 8,33 ms, sans modifier l'apparence. Les captures ci-dessous mesurent les retards de présentation avec Instruments. Elles ne prouvent ni 120 images/s constantes ni une équivalence avec Chrome.

## Compromis retenu le 20 octobre

À la demande de David, les essais d'optimisation s'arrêtent après une dernière capture.
La version retenue est celle de `stage21-host-focus-release` : conservation bornée des
pages et espaces de profils, réduction des recalculs, du travail de géométrie et de la
recherche des destinataires du focus. Le design reste inchangé. Les variantes ultérieures
sans gain suffisamment confirmé sont retirées du code.

Les captures valides de cette version donnent encore des pics de **25 à 33,3 ms entre
onglets web**. Aucun retard n'est détecté dans les séquences rapides entre deux profils
web déjà chargés. Les profils avec accueil atteignent 33,3 ms et la création/fermeture
d'onglets atteint 58,3 à 66,7 ms dans les captures citées plus bas. Ce sont des observations
sur ces parcours, pas des plafonds garantis ni une mesure de FPS.

Le compromis conserve les améliorations vérifiées sans annoncer 120 fps partout.
Les sources restent dans le worktree `animation-120hz` ; la Release de validation est
`.build/motion/stage21-host-focus-release/Lisiere.app`.

La validation finale du code restauré passe **356 tests XCTest**, sans échec ni test
ignoré, et **12 tests d'outillage**. La signature stricte du binaire Release est valide.
Les copies QA protégées passent chacune **92 contrôles de parcours et 10 de restauration**,
en mode standard puis avec Réduire les animations. Les journaux sont conservés sous
`.build/motion/compromise-final-*`. Ces vérifications fonctionnelles ne prouvent pas
une cadence constante et ne remplacent pas une comparaison instrumentée avec Chrome.

Sur demande explicite, cette même Release est ensuite installée dans
`/Applications/Lisiere.app` le 20 octobre. L'ancien binaire et les données sont sauvegardés
avant un échange atomique des applications. Les manifestes de 144 028 entrées concordent
avant la première relance et le bundle installé correspond à la Release validée.
La signature stricte et les parcours protégés repassent sur des copies du bundle installé :
92 contrôles de parcours et 10 de restauration dans chacun des deux modes d'animation.

L'inspection de l'application personnelle confirme les profils Perso (3 onglets) et Pro
(10 onglets), puis revient à Pro. Registre des profils, historique et préférences conservent
leurs valeurs ; les deux sessions ne changent que leur `interactionState` WebKit.
Les entrées supprimées après relance appartiennent toutes au cache réseau. Les cookies,
le stockage local et les statistiques WebKit évoluent avec les pages restaurées ; aucune
sauvegarde n'est réappliquée sur ces données vivantes. Le trousseau n'est pas modifié par
l'installation. La sauvegarde est dans
`~/Library/Application Support/Lisiere Release Backups/20261020-153650-optimized` ;
les preuves sont dans `.build/motion/install-optimized-20261020/verification.json`.

## Causes et corrections

- La mascotte utilisait un `TimelineView` limité à 30 mises à jour/s. Son déplacement et son clignement passent par Core Animation, avec une préférence pour la fréquence maximale de l'écran. Les illustrations transparentes, l'amplitude, les durées et le suivi du pointeur sont conservés. Les animations s'arrêtent lorsque la vue est détachée ou que Réduire les animations est actif.
- Le dégradé de l'accueil était limité à 15 mises à jour/s. Il conserve les mêmes couleurs et points de contrôle. SwiftUI interpole maintenant le mouvement entre des destinations mises à jour une fois par seconde. Cet intervalle concerne les destinations, pas la cadence des images affichées. La trajectoire lente est une approximation linéaire de la même fonction sinusoïdale.
- Les états de recherche, de chargement et d'erreur sont observés dans des vues locales, au lieu de recalculer toute la fenêtre.
- L'hôte WebKit ne programme plus une seconde réconciliation sur la file principale pour chaque mise à jour SwiftUI. La réconciliation reste nécessaire lors d'un remplacement ou transfert de page.

Aucun plafond global explicite à 60 images/s n'a été trouvé dans le code. Enlever simplement les limites des `TimelineView` augmentait les retards de l'accueil : cela a été mesuré puis remplacé par les corrections ci-dessus.

## Protocole reproductible

```sh
make build DERIVED_DATA="$HOME/Library/Developer/Xcode/DerivedData/LisiereAnimation120"
python3 scripts/profile-motion.py \
  "$HOME/Library/Developer/Xcode/DerivedData/LisiereAnimation120/Build/Products/Release/Lisiere.app" \
  --output .build/motion/nouvelle-capture
```

La commande prépare une copie Release signée avec une identité QA unique. Elle conserve le sandbox et le hardened runtime, utilise des profils vierges et un serveur HTTP local, et ne touche pas au navigateur personnel. La fenêtre de 1000 × 700 points reste visible et active. Chaque scénario comporte dix actions espacées de 300 ms, puis 500 ms de stabilisation. L'accueil est observé pendant la même durée, sans action. Un contrôle positif bloque volontairement le thread principal pendant cinq animations ; la capture échoue si Instruments ne détecte pas ces blocages. Elle échoue également si la fenêtre perd le focus ou si un scénario sort de l'intervalle enregistré.

Machine : MacBook Pro M3 Pro, écran signalant une fréquence maximale de 120 Hz. Instruments : Hitches pour la comparaison finale, avec Time Profiler en option (`--time-profiler`) pour rechercher les causes. Les comparaisons doivent utiliser les mêmes instruments. Les builds et les tests sont arrêtés pendant les captures. La référence est le code de `9757745`, auquel seul le pilote QA de mesure a été ajouté. Les traces brutes restent dans `.build/motion/`, hors Git.

L'instrument « Core Animation FPS » a été essayé séparément. Instruments le désactive sur macOS avec le message : `Disabled because macOS does not have an FPS metric for Core Animation.` Cette capture n'est pas utilisée comme résultat valide.

## Première étape : accueil et observation locale

Capture finale avec Hitches seul : `baseline-light` puis `final-light`. Les deux contrôles positifs détectent les blocages de 100 ms et toutes les phases gardent le focus. Les valeurs sont des retards cumulés sur chaque séquence, puis le plus grand retard individuel ; ce ne sont pas des FPS.

| Scénario | Cumul avant (ms) | Cumul après (ms) | Maximum avant (ms) | Maximum après (ms) |
|---|---:|---:|---:|---:|
| Accueil animé | 433.3 | 25.0 | 16.7 | 8.3 |
| Dossiers horizontaux | 75.0 | 100.0 | 16.7 | 8.3 |
| Dossiers latéraux | 100.0 | 125.0 | 16.7 | 16.7 |
| Changement d’onglet | 283.3 | 316.7 | 41.7 | 58.3 |
| Nouvel onglet / fermeture | 466.7 | 200.0 | 41.7 | 50.0 |
| Recherche dans la page | 341.7 | 300.0 | 50.0 | 33.3 |
| Changement de profil | 883.3 | 641.7 | 58.3 | 50.0 |

Le gain le plus net concerne l’accueil : 32 retards avant, 3 après, avec environ 94 % de retard cumulé en moins dans cette capture. L’ouverture/fermeture d’onglets et les profils progressent sur le cumul. Les dossiers et les changements d’onglet ne montrent pas de gain global stable ; le maximum des changements d’onglet augmente dans cette paire de captures. Aucun résultat n’est masqué dans le tableau.

Les répétitions précédentes avec Time Profiler confirment le gain de l’accueil mais montrent une forte variabilité des autres transitions. Elles ont aussi permis de rejeter la simple suppression des limites 15/30 et la conservation permanente du champ de recherche. Des pics de 50–58 ms persistent : l’objectif de 120 images/s constantes sur toute l’interface n’est pas atteint.

## Validation fonctionnelle

- XCTest : 334 tests réussis, aucun échec ni test ignoré. Les nouveaux tests couvrent la conservation de la page WebKit et des données de formulaire pendant les ouvertures de recherche, l'isolation de l'observation et l'arrêt/reprise des animations natives.
- Outillage : 12 tests, dont le filtrage des événements Instruments par processus, les références XML, les bornes de capture et le refus d'une fenêtre inactive.
- Release : compilation et `codesign --verify --deep --strict` réussis.
- `make smoke` : 92 contrôles de parcours et 10 de restauration, réussis en mode normal puis avec Réduire les animations.
- Inspection native de la copie Release : accueil clair/sombre, deux palettes transparentes de la mascotte, recherche avec résultat surligné, fermeture de recherche et ouverture/fermeture d’un onglet sans perte du formulaire.
- Le premier passage XCTest a expiré pendant une interruption de session dans quatre tests de fenêtres. Le passage complet suivant, machine maintenue éveillée, est celui retenu ci-dessus.

## Limites

Ces séquences courtes automatisent les mêmes mutations que les interactions natives ; elles ne mesurent pas toute la latence entre un geste physique et l'affichage. Le défilement de sites réels, les gestes continus au trackpad, les écrans externes et une comparaison instrumentée avec Chrome restent à mesurer. Un retard de 8,33 ms est déjà une image manquée à 120 Hz, pas la preuve d'une image affichée en 8,33 ms. Les transitions d'onglets et de profils restent les principaux points à améliorer.


## Deuxième étape : changements d’onglet et de profil

La suite de l’audit part de `c072fa8`, avec le même pilote QA enrichi de deux scénarios :
passage entre deux pages web déjà chargées, puis entre deux profils affichant chacun une page web.
`--extended` active ces scénarios. Les horodatages de chaque action et le temps de sa mutation synchrone
sont conservés dans `phases.json` ; ce temps de mutation n’est pas un temps de présentation.

Corrections apportées :

- Chaque fenêtre conserve au maximum les interfaces de son profil actif et du profil précédent.
  Les modèles de profil étaient déjà conservés auparavant. Les palettes, le fondu de 220 ms, les dimensions
  et les composants natifs restent les mêmes. Les vues cachées ne reçoivent ni interaction ni accès clavier
  via l’ancien champ d’adresse. Les panneaux temporaires sont fermés lorsque leur profil est quitté.
- Le choix de thème a un seul propriétaire natif : AppKit applique l’apparence de la fenêtre et SwiftUI reçoit
  la palette résolue via l’environnement. L’ancien `preferredColorScheme` réimposait un thème explicite après
  qu’AppKit avait rendu la main au système, entraînant une seconde invalidation de l’apparence. Le matériau
  du fond reçoit explicitement cette même palette : un ancêtre d’hébergement SwiftUI peut conserver son
  propre thème. Le retour clair/sombre est couvert par un test du matériau natif hébergé.
- L’accueil et l’hôte de page gardent leur identité. La mascotte et le fond s’arrêtent quand l’accueil est caché.
- L’hôte natif garde au maximum le conteneur de la page courante et celui de la page précédente. La précédente
  est masquée ; son WebKit peut toujours être suspendu, fermé ou transféré. Les références de suivi sont faibles.
  Aucun WebKit supplémentaire n’est créé pour ce cache. Les captures d’aperçu ignorent les vues cachées.
- La sélection ne demande plus de défilement lorsque l’onglet tient déjà entièrement dans son viewport.
  Une géométrie absente ou un onglet partiellement masqué conserve le comportement de défilement habituel.
- L’observation de la sélection, du contenu et de la barre d’outils est séparée pour éviter de reconstruire
  tout le corps de la fenêtre. Une sélection de profil ne republie pas une liste de profils inchangée.

Le compromis mémoire est borné à deux interfaces par fenêtre et deux conteneurs de page par hôte.
Il évite la destruction/reconstruction répétée ; il ne conserve pas les WebKit d’onglets suspendus ou fermés.
Les profils, données de formulaire et magasins WebKit restent isolés.

Deux hypothèses ont été écartées par mesure : désactiver les captures d’aperçu ne réduisait pas les pics,
et remplacer le fondu SwiftUI par un hôte natif avec Core Animation n’apportait pas de gain stable.
Ces prototypes ne font pas partie du changement final.

Le contrôle natif a également révélé deux précautions propres aux vues conservées : le moniteur de
balayage d’un profil masqué doit consulter immédiatement l’activité du modèle, et les descendants
accessibles de l’accueil masqué doivent être exclus. Le second point utilise le comportement
[`AccessibilityChildBehavior.ignore`](https://developer.apple.com/documentation/swiftui/accessibilitychildbehavior/ignore)
sur le contenu du défilement, sans supprimer son graphe visuel.

### Mesures finales de la deuxième étape

Référence : `switch-final-before-1` et `switch-final-before-2` (`c072fa8` avec le même pilote QA).
Version corrigée : `switch-delivery-after-1` et `switch-delivery-after-2`, sur le même binaire Release.
Les quatre contrôles positifs détectent les cinq blocages volontaires de 100 ms ; les fenêtres restent
actives pendant toutes les phases. Hitches seul, aucun build ou test en parallèle.

Le cumul est la **moyenne des deux séquences de dix actions**. Le maximum est le pire retard individuel
des deux captures. Ces valeurs décrivent des retards de présentation, pas des temps de calcul ni des FPS.

| Scénario | Cumul moyen avant (ms) | Cumul moyen après (ms) | Maximum avant (ms) | Maximum après (ms) |
|---|---:|---:|---:|---:|
| Accueil animé | 0.0 | 4.2 | 0.0 | 8.3 |
| Dossiers horizontaux | 104.2 | 91.7 | 108.3 | 83.3 |
| Dossiers latéraux | 179.2 | 45.8 | 16.7 | 8.3 |
| Onglet accueil ↔ page web | 262.5 | 108.3 | 66.7 | 33.3 |
| Nouvel onglet / fermeture | 225.0 | 200.0 | 50.0 | 50.0 |
| Recherche dans la page | 304.2 | 312.5 | 58.3 | 50.0 |
| Profil accueil ↔ page web | 666.7 | 229.2 | 58.3 | 58.3 |
| Onglet web ↔ web | 308.3 | 308.3 | 33.3 | 41.7 |
| Profil web ↔ web | 845.8 | 370.8 | 58.3 | 33.3 |

Dans ces répétitions, les retards cumulés baissent d’environ **59 %** pour accueil ↔ page web,
**66 %** pour les profils accueil ↔ page web et **56 %** pour les profils web ↔ web.
Les cumuls individuels des profils web sont de 1116,7 puis 575,0 ms avant, contre 366,7 puis 375,0 ms après :
la variabilité de la référence interdit d’en faire une garantie générale. Une capture intermédiaire,
avant le dernier ajustement de palette au démarrage, donnait encore 575 ms après correction.

Le changement entre deux onglets web ne progresse pas sur le cumul ; son maximum atteint encore 41,7 ms.
Les profils accueil/web gardent un pic de 58,3 ms, et les dossiers horizontaux un pic isolé de 83,3 ms.
La recherche ne montre pas de gain stable. **L’objectif de 120 images/s sur toute l’interface n’est pas
atteint.** Le budget de 8,33 ms et la comparaison instrumentée avec Chrome restent des critères non validés.
Les corrections réduisent des coûts identifiés, elles ne démontrent pas une cadence universelle.

### Validation de la deuxième étape

- Suite complète : **340 tests réussis**, zéro échec, zéro test ignoré
  (`Debug-20261019-213947.xcresult`). Après le dernier ajustement de la palette système au démarrage,
  les 30 tests d’apparence et de fenêtres de profil passent à nouveau.
- Outillage de mesure : 12 tests réussis. Les mutations synchrones, la présence du focus et les
  limites temporelles des scénarios sont enregistrées séparément des retards Instruments.
- Dernière Release : compilation et signature stricte réussies. Parcours de démarrage et restauration :
  **92 + 10 contrôles**, en mode normal puis avec Réduire les animations
  (`switch-startup-palette-smoke/standard` et `switch-startup-palette-smoke/reduced`).
- Contrôle natif : même fenêtre entre profils clair et sombre, retour au thème système, accueil et page web,
  restitution du formulaire non envoyé, focus d’adresse sur nouvel onglet et recherche dans la page.
  Le contenu de l’accueil masqué disparaît bien de l’arbre d’accessibilité. Aucun parcours VoiceOver complet
  ni geste physique continu au trackpad n’est revendiqué.
- Les caches sont testés pour leur limite de deux éléments, la libération du WebKit suspendu,
  le transfert entre fenêtres, l’arrêt des animations cachées et l’exclusion des moniteurs du profil inactif.
- Le navigateur personnel et Chrome n’ont pas été modifiés. La copie QA possède sa propre identité
  et ses propres profils. Cette branche n’est ni intégrée à `main` ni installée dans `/Applications`.

## Troisième étape : focus natif et visibilité des profils

Référence conservée : `5eef16b`, binaire copié dans `.build/motion/5eef16b-release/Lisiere.app`.
La capture CPU `remaining-before-cpu` attribue 109 ms de CPU échantillonné à
`PageHostView.attachContent` sur dix sélections web/web. L'essentiel passe par
`NSView.nextValidKeyView` : masquer la page qui possède encore le focus force AppKit à parcourir
les répondants SwiftUI de toute la fenêtre. Dans le premier correctif `remaining-focus-cpu`,
rendre le focus avant le masquage ramène ce chemin à 10 ms. Cette paire diagnostique démontre
le coût évité ; elle ne mesure ni une cadence d'images ni le gain total du correctif final.

Le code final transfère le focus à la page entrante avant de masquer l'ancienne, ou libère le focus
si ce transfert est impossible. Un test avec contrôle positif vérifie que masquer directement
une vue focalisée déclenche la recherche AppKit, puis que le changement via l'hôte l'évite.
Fermer des suggestions déjà absentes ne modifie plus inutilement l'état de la fenêtre.

`remaining-direct-cpu` confirme aussi que les deux pages de profils restaient déclarées `visible`
par WebKit après le fondu, y compris celle du profil masqué. L'hôte masque maintenant ses propres
conteneurs natifs après **500 ms** d'inactivité. Le fondu conserve ses **220 ms** ; ce délai évite de
changer la visibilité native juste avant certains retours rapides. Le retour annule le masquage
et réactive immédiatement la page. Réduire les animations masque sans attendre. Les tests couvrent
le retour rapide, une mise à jour en arrière-plan, le refus du focus pour un profil inactif et
la reprise de la mascotte. Aucun WebKit n'est recréé pour cette opération.

Les deux captures finales confirment `active_page_visibility = visible`,
`parked_page_visibility = hidden` et `parked_native_hidden = true`.
Les icônes, couleurs, dimensions et durées des animations visibles sont conservées.

### Mesures finales après déverrouillage

Environnement : macOS 27.0 (26A428), écran déclaré à 120 Hz, fenêtre QA 1000 × 700.
Même protocole Hitches seul, pages locales statiques, dix actions espacées de 300 ms et 500 ms
de stabilisation après la dernière attente. Aucun build, test ou contrôle UI concurrent.
Le masquage de 500 ms est donc inclus dans l'intervalle mesuré, pas repoussé hors de la capture.
Tous les contrôles de focus et les blocages volontaires de 100 ms sont détectés.

Références : `remaining-final-before-1` à `remaining-final-before-4` (**quatre captures**).
Version retenue : `remaining-focused-settled-1` et `remaining-focused-settled-2` (**deux captures**).
Agrégat : `.build/motion/remaining-accepted-comparison.json`. Le cumul est la moyenne par séquence
de dix actions ; le maximum est le pire retard de toutes les répétitions de chaque version.
Ces valeurs sont des retards de présentation Instruments, pas des temps CPU ni des FPS.

| Scénario | Cumul moyen avant (ms) | Cumul moyen après (ms) | Maximum avant (ms) | Maximum après (ms) |
|---|---:|---:|---:|---:|
| Accueil animé | 8.3 | 4.2 | 8.3 | 8.3 |
| Dossiers horizontaux | 29.2 | 29.2 | 33.3 | 8.3 |
| Dossiers latéraux | 29.2 | 33.3 | 25.0 | 25.0 |
| Onglet accueil ↔ page web | 175.0 | 162.5 | 33.3 | 33.3 |
| Nouvel onglet / fermeture | 229.2 | 254.2 | 58.3 | 58.3 |
| Recherche dans la page | 287.5 | 283.3 | 50.0 | 50.0 |
| Profil accueil ↔ page web | 245.8 | 187.5 | 50.0 | 58.3 |
| Onglet web ↔ web | 312.5 | 279.2 | 33.3 | 33.3 |
| Profil web ↔ web | 343.7 | 300.0 | 41.7 | 33.3 |

Sur ces échantillons, les cumuls baissent d'environ **11 % pour les onglets web**, **13 % pour
les profils web** et **24 % pour les profils accueil/web**. Les distributions se recouvrent :
les profils web varient de 283,3 à 416,7 ms avant et de 283,3 à 316,7 ms après. Il ne s'agit pas
d'une garantie statistique ni d'un gain uniforme. Le pic web/web des onglets reste à 33,3 ms.
Le pic accueil/web des profils augmente de 50 à 58,3 ms ; le cumul nouvel onglet/fermeture augmente
d'environ 11 %. Ces régressions et pics restent à résoudre.

Les sondes JavaScript sont exécutées après les intervalles mesurés, avec un délai maximal natif
pour qu'un processus web suspendu ne bloque pas la capture. Sur deux séries de 120 intervalles,
`requestAnimationFrame` donne une moyenne de **16,63 et 16,65 ms**, médiane 17 ms, p95 18 ms :
environ **60 callbacks/s** sur cet écran 120 Hz. Ce résultat ne mesure pas la présentation réelle
des images ni la cadence des animations natives. Il correspond à la politique WebKit décrite
pour les mises à jour JavaScript, distinctes des animations accélérées
([explication WebKit](https://webkit.github.io/explainers/animation-frame-rate/)).
La [demande d'API WKWebView pour le 120 Hz](https://bugs.webkit.org/show_bug.cgi?id=294338)
reste ouverte ; aucune API privée ni modification des réglages de Safari n'a été introduite.

**120 images/s partout n'est pas atteint.** Le défilement de sites réels, les gestes continus au
trackpad et une comparaison instrumentée avec Chrome ne sont pas validés par ces pages statiques.
Les diagnostics CPU précédents pointent encore la composition et les mises à jour du graphe SwiftUI
pendant les fondus de profils ; ce coût est distinct de la cadence JavaScript de WebKit.

### Essais non retenus

La composition groupée du fondu et le déplacement anticipé du focus dans le contrôleur de profils
n'apportaient pas de gain stable. Les wrappers d'observation par carte/dossier et la suppression
de l'environnement inactif du profil ont également été retirés après les répétitions. Avec ces
expériences, `remaining-final-after-2` atteignait 616,7 ms cumulés entre profils web et
`remaining-settled-after-1` 808,3 ms. Le délai de 500 ms seul ne suffisait donc pas ; la variante
finale conserve l'environnement inactif existant et les composants d'onglets de la référence.
`remaining-focused-after-1/2` documentent la variante intermédiaire à 250 ms.
La capture `remaining-visibility-cpu`, interrompue pendant le verrouillage, reste invalide.

### Validation finale

- Suite complète finale : **342 tests réussis**, zéro échec et zéro test ignoré,
  résultat `Debug-20261019-225150.xcresult` (`remaining-accepted-tests.log`).
  Les quatre tests de fenêtres précédemment bloqués par le verrouillage passent.
- Outillage : **12 tests réussis** (`remaining-accepted-tooling.log`).
- Release finale compilée (`remaining-focused-settled-build.log`) et signature stricte vérifiée.
  Démarrage/restauration : **92 + 10 contrôles réussis dans chacun des deux modes** normal et
  Réduire les animations (`remaining-accepted-smoke/standard` et `/reduced`).
- Inspection native de `.build/motion/remaining-focused-settled-2/Lisiere QA.app` : mêmes contrôles,
  même fenêtre entre profils, accueil avec mascotte transparente, absence de l'accueil masqué dans
  l'arbre d'accessibilité des pages web. Le brouillon du premier profil reste présent après passage
  par un autre onglet et un autre profil ; celui du second profil est aussi conservé. Après un
  aller-retour de profil et son masquage, la saisie
  reprend dans le bon formulaire. Recherche dans la page, création/fermeture d'onglet et focus
  d'adresse sur un nouvel onglet vérifiés. Les variantes clair/sombre avaient été inspectées à
  l'étape précédente ; l'inspection finale utilise le thème système clair.
- Les retours rapides et l'annulation d'un masquage différé sont couverts par les tests natifs.
  Pas de parcours VoiceOver complet ni de mesure physique continue au trackpad.
- Chrome, le navigateur personnel et leurs données n'ont pas été modifiés. La copie QA possède
  sa propre identité et ses propres profils. Cette étape reste dans le worktree
  `codex/animation-120hz`, sans intégration à `main` ni installation dans `/Applications`.

## Quatrième étape : supprimer les écritures disque de la transition

La référence de cette étape est le résultat final de la troisième étape, conservé dans
`.build/motion/stage3-release/Lisiere.app`. La capture `stage4-clean-before-1`, sans autre copie QA
ouverte, confirme des maxima de 33,3 ms entre onglets web, 33,3 ms entre profils web, 41,7 ms
entre profils accueil/web et 50 ms pour l'ouverture/fermeture d'onglets. Le contrôle positif et
le focus sont valides. Ces valeurs sont une répétition de référence, pas un nouveau résultat corrigé.

### Expériences de rendu écartées

- Déplacer le dégradé animé de l'accueil dans un `NSHostingView` indépendant conserve son aspect,
  mais `stage4-mesh-after-1` ne réduit pas les pics web/web (33,3 ms) et augmente le cumul des
  profils accueil/web de 175 à 241,7 ms dans cette paire. Le changement n'est pas conservé.
- Remplacer le fondu SwiftUI par un fondu Core Animation de 220 ms sur des surfaces de profils
  indépendantes passe 24 tests ciblés, mais `stage4-native-after-1` augmente le pic accueil/web
  à 66,7 ms et le cumul web/web à 391,7 ms. Le prototype et ses tests sont retirés des sources.
- Un essai gardant l'ordre des profils dans `ForEach` est conservé uniquement comme expérience
  dans `.build/motion/stage4-stacking-release`. Sa capture est invalide : le Mac s'est verrouillé,
  et toutes les phases ont perdu le focus. Aucun gain n'en est déduit ; le changement n'est pas
  conservé dans les sources en attendant une mesure valide.
- `stage4-before-cpu` aide à localiser le travail sur le thread principal mais n'est pas une
  référence quantitative : une autre copie QA animée était encore ouverte. L'essai de l'instrument
  SwiftUI a expiré pendant le traitement de la trace et ne constitue pas une mesure exploitable.

### Corrections en cours de validation

`ProfileStore.select` écrivait atomiquement `Profiles.plist` sur le thread principal à chaque
changement de profil. Les fenêtres demandent maintenant une écriture asynchrone via le `StoreFile`
existant. La sélection en mémoire reste immédiate ; une fermeture normale vide la dernière sélection.
La création, le renommage et les marques de suppression restent synchrones et passent par la même
file sérialisée : une ancienne sélection ne peut pas remplacer un manifeste plus récent. Une écriture
en échec utilise le bandeau et l'action de nouvelle tentative déjà présents dans l'interface.

`PersistenceStatus.record` publiait également les succès répétés (`nil` vers `nil`) dans son état
observé. Les fenêtres consultent cet état pour leur bandeau d'erreur. Un état identique n'est plus
publié ; une nouvelle erreur et sa résolution continuent de déclencher la mise à jour.

Les 22 tests ciblés de profils et de stockage passent. Ils couvrent une écriture volontairement
bloquée sans attente du thread principal, l'ordre sélection/renommage/suppression, la sauvegarde à
la fermeture, le disque plein et la nouvelle tentative, la préservation d'un manifeste illisible,
et la notification des changements réels de l'état de persistance.

La suite complète exécute 345 tests : 341 réussissent et quatre tests `TabWindowDragTests`
échouent pendant le verrouillage (21 assertions, dont l'attente d'une fenêtre reconnue au premier
plan par le serveur de fenêtres). Ce passage n'est pas une validation complète verte. Les 12 tests
d'outillage passent. Les quatre tests de fenêtres doivent être repris sur le Mac déverrouillé.

La Release compile et sa signature stricte est valide. Le parcours protégé passe 92 contrôles puis
10 contrôles de restauration, en mode normal et avec Réduire les animations. Ces contrôles
programmatiques passent pendant le verrouillage et ne remplacent pas l'inspection native ni la
mesure du rendu. Preuves : `.build/motion/stage4-persistence-evidence/verification.json` et
`.build/motion/stage4-persistence-smoke/`. Aucune intégration à `main` ni installation dans
`/Applications` n'est effectuée.

**Validation de fluidité encore en attente après déverrouillage.** Ces corrections ne prouvent pas
120 images/s et aucun gain sur les pics de présentation n'est annoncé sans nouvelle capture valide.


### Reprise sur le Mac déverrouillé

Les quatre tests de fenêtres repassent (`stage4-persistence-unlocked-drag-tests.log`).
Deux paires de captures Hitches intercalées, `stage4-unlocked-before-1/2` et
`stage4-persistence-after-1/2`, confirment un gain sur la mutation des profils web :
**5,73 vers 2,11 ms en moyenne**. En revanche, les retards de présentation ne baissent pas :
leur cumul moyen passe de 275 à 325 ms pour dix changements de profils web, et de 279,2 à
300 ms pour les onglets web. Le correctif disque retire une attente évitable du thread principal,
mais ne constitue donc pas une correction des pics de rendu à lui seul.

L'inspection de la copie `stage4-persistence-smoke/standard/Lisiere QA.app` confirme le brouillon
non envoyé après un retour d'onglet et de profil, le retour du focus au formulaire, la recherche,
et le focus d'adresse du nouvel onglet. L'accueil et la mascotte transparente gardent leur aspect.

Une seconde correction conserve les entrées de l'accueil masqué lors des changements entre
pages web. `RetainedStartPage` compare l'identité du navigateur et des favoris ainsi que la
visibilité ; il reçoit le nouvel onglet dès que l'accueil redevient visible. Les observations
internes des préférences et des favoris restent actives. La visibilité d'accessibilité est
transmise explicitement afin qu'un ancien onglet conservé ne rende pas l'accueil masqué accessible.
Les deux captures `stage4-retained-home-after-1/2` donnent les valeurs suivantes :

| Scénario (10 actions) | Cumul moyen référence étape 3 | Cumul moyen avec persistance + accueil conservé | Pic référence / corrigé |
| --- | ---: | ---: | ---: |
| Onglets accueil/web | 187,5 ms | 125,0 ms | 33,3 / 33,3 ms |
| Onglets web/web | 279,2 ms | 229,2 ms | 33,3 / 33,3 ms |
| Profils accueil/web | 262,5 ms | 187,5 ms | 50,0 / 58,3 ms |
| Profils web/web | 275,0 ms | 304,2 ms | 33,3 / 33,3 ms |

Dans ces deux premières captures, le cumul des onglets web est inférieur d'environ 18 % à la
référence de l'étape 3 (24 % face à la persistance seule). Ce résultat n'est pas un gain stable
démontré : une troisième capture du même binaire figé (`stage4-retained-home-after-3`) donne
266,7 ms pour les onglets web et 900 ms pour les profils web, sans changement de code. Les pics
respectifs restent 33,3 et 41,7 ms. Les profils web n'ont toujours pas de gain démontré. Le pic
accueil/web de 58,3 ms reste présent ; ces courtes séries ne permettent pas de conclure à une cadence stable.
Le contrôle positif et le focus sont valides dans toutes ces captures.

Le parcours natif de `stage4-retained-home-after-2/Lisiere QA.app` vérifie deux formulaires
conservés, l'absence de l'accueil masqué dans l'arbre d'accessibilité et une navigation depuis
le bouton Recherche de l'accueil vers le bon onglet. Le test natif de conservation des pages
couvre désormais aussi deux pages web successives. **345 tests passent**, sans échec ni test
ignoré, dans `stage4-retained-home-full-tests.log` / `Debug-20261019-235600.xcresult`.

Les essais suivants sont retirés : ordre stable des profils avec z-index variable
(`stage4-stacking-unlocked-1`, cumul profils web 450 ms), observation des menus par wrappers
(`stage4-command-sections-after-1`, 1 133,3 ms), cartes d'onglets équatables
(`stage4-tab-card-after-1`, aucun gain net), animation structurelle des profils limitée aux
insertions/évictions (`stage4-profile-scope-after-1`, pic web 41,7 ms). Les mesures et les
expériences rejetées sont regroupées dans `.build/motion/stage4-unlocked-experiments.json`.
Le diagnostic `stage4-persistence-cpu`, avec une seule copie QA ouverte, situe encore l'essentiel
du coût dans les mises à jour du graphe SwiftUI et les passes de disposition natives.

Le diagnostic court `stage4-swiftui-short.trace` montre de nombreuses petites mises à jour,
sans fonction de vue isolée expliquant à elle seule les pics. Des libellés de hiérarchie sont
incohérents dans l'export ; seules les causes explicitement rattachées aux types Browser sont
exploitées. Les variantes d'isolation supplémentaires (contenu de page, carte d'onglet complète,
projection du type de page) sont retirées faute de gain démontré. Les différences d'une capture
unique ne suffisent pas à leur attribuer une régression, compte tenu de la variabilité observée.

Un contrôle de la machine après cette variation ne trouve aucun enregistreur ni compilateur
résiduel, aucun mode économie d'énergie et aucun avertissement thermique. Le Mac fonctionne sur
batterie. Ces observations ne suffisent pas à expliquer la variation ni à garantir la cadence.

Le scénario étendu utilisait la même URL pour les deux onglets web. L'option `--distinct-urls`
ajoute des adresses distinctes sur la même page locale afin d'inclure la mise à jour du champ
d'adresse. Le binaire confirme cette option dans `ready.json` et le rapport indique le workload ;
le script refuse une ancienne Release qui ne reconnaît pas l'option. Comparer uniquement des
captures du même workload et avec les mêmes instruments.

La première capture à adresses distinctes (`stage4-distinct-before-1`) est **rejetée** : perte
du focus dès le contrôle positif. Le contrôle natif confirme que le Mac s'est reverrouillé.
Elle ne sert donc à aucune comparaison. Le scénario mesure maintenant aussi l'occlusion native
de la fenêtre au début, après chaque action et à la fin ; une phase masquée invalide le rapport,
même si le processus conserve le focus. Les 12 tests d'outillage passent avec ce garde-fou.

Une variante déplace le texte d'adresse depuis le `State` de toute la fenêtre vers un objet
observé par le champ. Elle compile et le test natif à adresses distinctes passe. Faute de capture
valide, elle reste **hors du code retenu**, dans
`.build/motion/stage4-address-scope-only.patch` et `stage4-address-scope-release/Lisiere.app`.
Le nouveau test reste dans la suite : il vérifie l'adresse affichée, l'identité du champ et le
focus après activation du profil. Les 24 tests ciblés de profils et de suggestions passent sur
le code retenu (`stage4-retained-home-address-tests.log`). La suite complète précédente reste
la validation de 345 tests ; ce nouveau test porte la suite à 346, sans nouveau passage complet
annoncé pendant le verrouillage.

La Release retenue, avec les garde-fous de mesure, est figée dans
`.build/motion/stage4-final-release/Lisiere.app`. Sa compilation et sa signature stricte passent.
Les parcours protégés de `stage4-final-smoke/standard` et `/reduced` passent chacun 92 contrôles
puis 10 contrôles de restauration. Le contrôle natif confirme encore le verrouillage après ces
vérifications : le gain du champ isolé et la stabilité à 120 images/s restent non validés.
Les seuls changements visuels sont ceux déjà inspectés : aucune modification du design n'est
introduite par cette étape. Aucune installation personnelle, intégration à `main` ou publication.


## Cinquième étape : comparaison intercalée et accueil sans WebKit

La reprise du 20 octobre utilise des URL distinctes et rejette les captures où la fenêtre perd
le focus ou devient masquée. Les captures `stage5-distinct-after-2` et `stage5-distinct-after-2-retry` sont rejetées ; les autres
séries citées ci-dessous ont un contrôle positif, un focus et une visibilité valides.

Les variantes isolant davantage le champ d'adresse puis la sélection de chaque carte d'onglet
sont **retirées**. Leurs premières mesures semblaient meilleures, mais les anciennes Releases
figées obtiennent ensuite les mêmes résultats : zéro retard détecté sur les dix changements
d'onglets web et environ 75–83 ms cumulés sur les dix changements de profils web, avec des pics
à 8,33 ms. `stage5-original-reference-repeat` reproduit ces résultats sans aucune des deux variantes.
Il serait donc incorrect d'attribuer cette amélioration à ces modifications de code.

`--native-page-control` ajoute deux contrôles de diagnostic après les scénarios ordinaires :
un échange direct des mêmes pages natives avec sélection d'interface constante, puis le même
échange avec le travail normal de capture d'aperçu. Les deux ne détectent aucun retard dans
`stage5-preview-control-1`. Ce résultat local ne prouve pas que WebKit ou les aperçus sont toujours
gratuits ; il sépare leur coût de celui des changements du graphe d'interface dans ce scénario.

Un coût évitable est confirmé dans le code : chaque nouvel accueil natif construisait immédiatement
un `WKWebView`. Les onglets d'accueil créés, dupliqués ou restaurés et les nouveaux panneaux vides
restent désormais sans WebKit jusqu'à la première navigation. Ils ne sont pas considérés comme
suspendus. La configuration utilisée à la navigation vient du navigateur propriétaire : magasin
WebKit, apparence, mots de passe et bloqueur de contenu. Les fenêtres ouvertes par une page
continuent de recevoir immédiatement la configuration WebKit de leur ouvreur.

Avec le même pilote v1 et Hitches seul, la création synchrone moyenne passe de **9,45 puis
11,48 ms** dans `stage5-find-after-1` et `stage5-lazy-before-repeat` à **0,30 ms** dans
`stage5-lazy-after-1` (maximum 0,86 ms). Le cumul de présentation sur dix ouvertures/fermetures
passe de 333,3 et 275,0 ms à 200,0 ms ; le pic passe de 50,0 et 41,7 ms à 25,0 ms.
Il s'agit d'un échantillon corrigé entre deux références, pas d'une garantie de cadence.

Le pilote v2 utilise désormais `showFindBar` et `closeFindBar`, comme les commandes de l'interface,
au lieu de modifier directement le booléen de visibilité. Il inclut ainsi la restitution du focus.
`interaction_driver_version` est conservé dans `ready.json` et `summary.json` ; une ancienne
Release sans ce champ est identifiée v1. Les résultats de recherche v1 et v2 ne sont pas
interchangeables. Les versions du pilote, instruments et workload doivent accompagner toute comparaison.


La conservation du champ natif de recherche est finalement **retirée**. Les deux captures v2
`stage5-command-after-1/2` réduisent un peu le cumul (200 et 183,3 ms contre 216,7 ms dans chacune
des références), mais conservent un pic de 50 ms, contre 33,3 et 41,7 ms pour les références.
Les variations des autres scénarios ne permettent pas de lui attribuer un bénéfice stable.
Le champ d'adresse, la projection de sélection et la recherche conservée ne font donc pas
partie de la version retenue.

Un test de durée de vie révèle ensuite que l'accueil masqué peut garder l'objet d'un onglet
web fermé. Le test échoue sans la variante de recherche (`stage5-delivery-full-tests.log`),
puis passe avec la correction : l'accueil masqué reçoit un onglet nul et le seul booléen
nécessaire à son mode d'affichage. Il conserve ses préférences et favoris observables sans
posséder l'ancienne page. Le forçage de l'accueil malgré la préférence « page vide » et son
retour entre espaces de travail sont également couverts. Les neuf tests de pages passent,
puis la suite complète : **351 tests**, zéro échec et zéro test ignoré
(`stage5-verified-full-tests.log`). Les 12 tests d'outillage passent également.


## Sixième étape : éviter la réapplication d'une icône de Dock identique

`Mascot.applyDockIcon` réassignait `NSApp.applicationIconImage` à chaque activation de profil,
y compris lorsque mascotte et palette restaient identiques. Une garde mémorise le nom de l'icône
appliquée et ne saute que cette répétition. Un choix différent et le retour à l'icône du bundle
continuent de fonctionner ; aucune image supplémentaire n'est mise en cache.

Les captures v2 `stage6-dock-before-1/2` et `stage6-dock-after-1/2` sont valides, avec URL distinctes,
Hitches seul et aucune compilation concurrente. Le temps synchrone moyen des profils web passe
au total de **2,407 à 2,090 ms**, soit environ 13 % de moins. **Le rendu ne s'améliore pas** : les
cumuls passent de 350 et 908,3 ms à 608,3 et 1133,3 ms. Le pic reste dans l'intervalle 33,3–41,7 ms.
La dérive de la référence inchangée interdit d'attribuer ces différences de rendu à la garde.
Elle évite un travail inutile, mais ne résout pas les pics de présentation.

Les 22 tests de mascottes et de fenêtres de profils passent après cette modification, notamment
les 18 variantes d'icônes et le retour à l'icône par défaut. La Release compile et sa signature
stricte est valide. Les données détaillées sont dans `.build/motion/stage6-dock-comparison.json`.


Les parcours Release de `stage6-dock-smoke/standard` et `/reduced` passent chacun **92 + 10
contrôles**. Le contrôle natif de la copie standard vérifie la première navigation depuis un
accueil sans WebKit, deux brouillons conservés entre onglets et profils, le retour du focus
au formulaire après fermeture de la recherche, et l'absence de l'accueil masqué dans l'arbre
accessible. La mascotte transparente et le design natif sont inchangés. La copie QA et son
serveur local sont fermés après inspection ; le navigateur personnel n'est pas modifié.
Le bilan vérifiable est conservé dans `.build/motion/stage6-verification.json`.


## Septième étape : contrôler la demande de cadence native

L'option QA `--display-link-control` utilise l'API publique `NSView.displayLink(target:selector:)`
et demande une plage dont minimum, maximum et préférence sont la fréquence maximale de l'écran.
Les intervalles des horodatages et de la livraison des callbacks sont conservés séparément dans
chaque phase. **Ce ne sont pas des FPS présentés.** La demande de cadence fait partie de la
condition expérimentale, pas d'un observateur neutre. Elle n'est jamais activée dans l'app normale.
La Release confirme sa prise en charge ; le script refuse le drapeau sur un ancien binaire.

La compilation et la signature stricte passent, ainsi que les 12 tests d'outillage.
La capture `stage7-request-120` est **rejetée** : perte du focus dès le contrôle positif.
Le contrôle natif confirme ensuite le verrouillage du Mac et l'échec du déverrouillage automatique.
La capture par défaut qui devait suivre n'a donc pas démarré. Aucun résultat de cette capture
ne démontre une cadence ou un gain. Les deux captures restent à reprendre après déverrouillage.
Le bilan est enregistré dans `.build/motion/stage7-verification.json`.

Après déverrouillage, `stage7-request-120-unlocked` et `stage7-default-cadence-unlocked`
sont valides : même binaire, pilote v2, URL distinctes, Hitches seul, fenêtre active et visible.
La demande explicite produit un intervalle médian de callbacks natifs de **8,33 ms** dans
toutes les phases. Elle ne supprime pas les retards de présentation : les pics web/web restent
**33,3 ms** pour les onglets et pour les profils, dans les deux captures. Les cumuls respectifs
sont 275/325 ms avec la demande et 216,7/333,3 ms par défaut. Une seule paire ne permet pas
d'attribuer les autres variations à cette demande. Le JavaScript de la page reste autour de
17 ms par callback. Aucun display link permanent n'est ajouté à la version normale.

## Huitième étape : isoler le travail SwiftUI au déclenchement

`stage7-current-cpu` confirme le contrôle natif : changer seulement les pages, avec ou sans
capture d'aperçu, atteint un pic de 8,3 ms, contre 33,3 ms avec les mises à jour de l'interface.
Les échantillons du thread principal restent dominés par le graphe SwiftUI et sa disposition.
Le contrôle `stage8-without-commands` retire uniquement les menus applicatifs dans la copie QA.
Il garde un pic de 33,3 ms entre onglets et 41,7 ms entre profils. Les menus ne suffisent donc
pas à expliquer ces pics ; aucune fonction de menu n'est supprimée de l'app normale.

Une variante sépare ensuite chaque espace dans un hôte natif et applique le même fondu de
220 ms avec Core Animation. Contrairement à l'ancien essai, son contenu est équatable et
l'observation de l'activité est séparée de la valeur de la fenêtre. Les 27 tests ciblés passent,
et le poids des échantillons du thread principal dans les changements de profils web baisse
de 976 à 427 ms. Cela ne suffit pas : les deux paires Hitches seul `stage8-surface-before-1/2`
et `stage8-surface-after-1/2` gardent des pics de 33,3 ms entre onglets. Les profils passent
de 33,3 à 41,7 ms au maximum, avec des cumuls moyens presque identiques (375 et 370,8 ms).
La variante est **retirée** : le gain de travail pendant le fondu ne résout pas le pic initial.
Les sources et la Release d'essai restent dans `.build/motion/stage8-surface-candidate` et
`stage8-surface-release`, hors de la version retenue.

Le pilote QA peut désormais omettre la navigation, les onglets horizontaux ou les deux avec
`--omit-chrome`. La suppression intervient uniquement avant les scénarios web étendus,
après le contrôle positif, et conserve la taille des régions. Les captures exposent
`omitted_chrome`, `omits_commands` et le type du premier répondant en fin de scénario.
Ces contrôles ne sont pas des validations de l'interface complète.

La première capture par région, `stage8-no-navigation-cpu`, est rejetée pour perte du focus
dès `detector-control`. Le contrôle natif confirme un nouveau verrouillage du Mac et l'échec
du déverrouillage automatique. Les contrôles sans onglets et avec interface complète n'ont
pas démarré. Aucun résultat de cette capture n'est utilisé pour décider d'une optimisation.

Le binaire de diagnostic `stage8-chrome-control-release` compile et sa signature stricte passe.
Les 12 tests d'outillage et les parcours protégés `stage8-chrome-smoke/standard` et `/reduced`
passent (92 contrôles de parcours et 10 de restauration chacun). Ces parcours automatisés
ne remplacent ni les captures de cadence avec une fenêtre active ni l'inspection visuelle.
Le bilan des essais, y compris la variante retirée, est dans `.build/motion/stage8-comparison.json`.

Après déverrouillage, les trois captures `stage8-{no-navigation,no-tabs,full-chrome}-unlocked`
terminent sur le même binaire, avec Time Profiler et Hitches. La fenêtre reste active et
le premier répondant est `BrowserWebView` dans les deux scénarios web.

| Interface mesurée | Onglets web : cumul / pic | Profils web : cumul / pic |
| --- | --- | --- |
| Complète | 291,7 / 33,3 ms | 325 / 33,3 ms |
| Sans navigation | 250 / 25 ms | 258,3 / 33,3 ms |
| Sans barre d'onglets | 183,3 / 25 ms | 283,3 / 33,3 ms |
| Sans les deux (`stage9-no-chrome`) | 75 / 16,7 ms | 166,7 / 25 ms |

Le dernier contrôle conserve des régions vides aux mêmes dimensions. Le changement natif
de page, sans sélection du modèle, atteint 8,3 ms de pic avec et sans aperçu. Le poids des
échantillons du thread principal passe de 313 à 171 ms entre onglets quand les deux barres
sont absentes ; entre profils, il reste à 876 ms contre 1010 ms avec l'interface complète.
Cela localise une contribution de l'interface au retard, sans établir qu'une barre unique
en soit la cause ni qu'il faille la supprimer. Ces contrôles partiels ne prouvent pas 120 fps.

## Neuvième étape : vérification des causes d'invalidation

Trois essais supplémentaires sont retirés après mesure sur le même parcours étendu, avec
adresses distinctes et Time Profiler :

- `stage9-address-cpu` isole la chaîne d'adresse dans un objet observable. Le pic entre
  onglets reste à 33,3 ms ; le poids des échantillons du thread principal est de 337 ms,
  contre 313 ms dans la référence complète.
- `stage9-focus-cpu` transmet le contrôleur de fenêtre stable aux commandes, qui observent
  ensuite son navigateur courant. Les profils web restent à 41,7 ms de pic, avec 1071 ms
  d'échantillons du thread principal. Cette piste ne justifie pas un changement retenu.
- `stage9-context-cpu` remplace le menu contextuel SwiftUI par une action d'accessibilité
  ouvrant le menu AppKit existant. Le pic entre onglets reste à 33,3 ms et le cumul des
  retards des profils web augmente à 1108,3 ms. Le menu existant est rétabli.

Ces captures isolées servent à rejeter des pistes sans gain démontré ; elles ne constituent
pas une comparaison statistique de chaque variation. Les résultats sont conservés dans
`.build/motion/stage9-comparison.json`.

Un second essai du conteneur natif confie aussi le filtrage des interactions et la visibilité
d'accessibilité à ce conteneur, au lieu de les propager deux fois dans SwiftUI. La capture CPU
réduit le poids des échantillons des profils web de 1010 à 336 ms, mais les deux paires
intercalées ne confirment pas une réduction des pics :

| Capture Hitches seul | Onglets web : pic | Profils web : pic | Profils d'accueil : pic |
| --- | --- | --- | --- |
| Référence 1 | 33,3 ms | 33,3 ms | 50 ms |
| Variante 1 | 41,7 ms | 33,3 ms | 41,7 ms |
| Référence 2 | 33,3 ms | 41,7 ms | 33,3 ms |
| Variante 2 | 33,3 ms | 33,3 ms | 58,3 ms |

La variante est retirée ; ses sources restent dans `.build/motion/stage9-surface-candidate`.
Le pilote ajoute `--swiftui-body` pour enregistrer et exporter les recalculs de vues SwiftUI,
avec l'instrument `View Body (Legacy)` indiqué dans le rapport. L'instrument moderne
`SwiftUI` a bloqué à la finalisation de `stage9-swiftui` ; cette trace est inutilisable.
Le contrôle `stage9-view-body` termine correctement. Il totalise 30,1 ms d'intervalles
`body` sur dix changements d'onglet web et 10,7 ms sur dix changements de profil web.
Il révèle aussi 71 évaluations de `TabItem` pendant les dix changements d'onglet.
Ces intervalles ne mesurent pas toute la disposition ni le rendu. Ce mode est diagnostique :
ses durées ne se comparent pas aux captures Hitches seul.

## Dixième étape : réduire les mises à jour sans modifier les cartes

Le sélecteur natif d'icônes ne réassigne plus son apparence, sa teinte, sa sélection ni sa
taille intrinsèque lorsque leurs valeurs sont identiques. Un test vérifie vingt mises à jour
identiques sans invalidation de taille, puis le redimensionnement après changement de libellé.
Cette correction supprime du travail inutile ; elle ne constitue pas une mesure de cadence.

Chaque onglet possède une projection de son rôle dans la barre : actif, partenaire de vue
partagée ou arrière-plan. Le modèle ne modifie que les rôles réellement changés. `TabItem`
lit cette projection dans sa propre vue ; les en-têtes de groupe la lisent dans leur style.
La sélection ne dépend donc plus de l'identifiant actif lu par toutes les cartes du `ForEach`.
Les tests couvrent aussi la vue partagée, le déplacement, l'épinglage et la fermeture.

La capture `stage10-rows-body` mesure vingt évaluations de `TabItem` pour dix changements
d'onglet web, contre 71 dans `stage9-view-body`. Le total passe de 1359 à 741 évaluations
de vues et de 30,08 à 22,21 ms d'intervalles `body`. Les pics de présentation restent
cependant à 33,3 ms entre onglets. Ces nombres ne démontrent pas 120 images affichées par seconde.

Les essais `stage10-boundary` (effacement de type de `WindowSection`) et `stage10-sizing`
(taille proposée explicite du conteneur de page) n'ont pas supprimé les pics et sont retirés.
Les conteneurs de vues supplémentaires des essais `stage10-selection` et `stage10-toolbar`
sont aussi retirés : la projection reste directement observée par les vues existantes.
La suite complète a passé 353 tests avant cette simplification, puis les 26 tests ciblés
du modèle, des dimensions et du mouvement de la barre passent sur la version simplifiée.

## Onzième étape : soumettre le fondu avant les notifications de sélection

`ProfileDeck` conserve les deux espaces dans des hôtes natifs distincts. Contrairement aux
essais précédents, le contrôleur lance leur fondu de 220 ms avant de notifier SwiftUI du
changement de modèle. Le conteneur soumet alors sa transaction Core Animation, une fois
par changement vers un espace déjà rendu, avec une préférence pour la cadence maximale
de l'écran. Les interactions et l'accessibilité du profil sortant sont immédiatement bloquées.
Un profil absent du cache conserve le parcours normal de création. Le modèle, les magasins
et les pages WebKit gardent leurs propriétaires.

Les deux paires intercalées Hitches seul utilisent la même charge, dix changements et des
adresses distinctes. Le détecteur positif passe et la fenêtre reste active et visible :

| Capture | Profils web : cumul / pic | Onglets web : cumul / pic |
| --- | --- | --- |
| `stage11-deck-reference1` | 333,3 / 33,3 ms | 250 / 33,3 ms |
| `stage11-deck-candidate1` | 16,7 / 16,7 ms | 291,7 / 33,3 ms |
| `stage11-deck-reference2` | 633,3 / 41,7 ms | 250 / 33,3 ms |
| `stage11-deck-candidate2` | 25 / 25 ms | 258,3 / 33,3 ms |

Chaque variante produit un seul retard dans la phase des profils web, au premier changement
vers la page précédemment masquée. Le gain se répète, mais les premiers changements et les
profils contenant une page d'accueil restent à améliorer. Les 28 tests ciblés passent :
continuité et inversion du fondu, Réduire les animations, ordre natif, filtrage des interactions,
éviction et lancement de la présentation avant les notifications. L'inspection native et
la suite complète de cette nouvelle architecture restent nécessaires avant livraison.

L'appel à `CATransaction.flush()` est limité à cette transition déjà préparée. Il ne constitue
pas une boucle de rendu. La [documentation Apple](https://developer.apple.com/documentation/quartzcore/catransaction/flush%28%29)
conseille normalement de laisser la boucle d'événements soumettre les transactions ; ici,
le changement est motivé par les mesures comparatives et nécessite la vérification visuelle
des transitions entre apparences et des champs en cours d'édition.

L'essai `stage12-card-candidate` place chaque carte dans un petit `NSHostingView` séparé.
Le pic entre onglets web reste à 41,7 ms. Cette variante est retirée, sans modifier les cartes
ni leurs interactions dans la version retenue.

### Réveil et contrôle natif de l'intégration

`stage13-wake-candidate` réactive les conteneurs des pages visibles du profil entrant avant
de soumettre le fondu. Le modèle reste inactif pendant cette préparation ; les onglets
suspendus ne sont pas chargés et les panneaux non sélectionnés restent masqués. Les 29 tests
ciblés passent. La première capture ne détecte aucun retard dans la phase des profils web.
Le contrôle QA `--profile-idle-control` ajoute ensuite 800 ms entre les changements de profil,
afin de vérifier le réveil après mise au repos à chaque retour, et pas seulement au premier.
Son indicateur figure dans le rapport ; ses résultats se comparent uniquement au même parcours.

**Ces premiers résultats du conteneur natif précèdent sa validation visuelle.** L'inspection
de `stage13-native`, comparée à `stage13-native-reference`, révèle un retrait supplémentaire
de 32 points au sommet de la fenêtre ainsi que les commandes du profil inactif encore exposées
par SwiftUI dans l'arbre d'accessibilité. Ces binaires d'essai ne sont donc pas livrables et
leurs mesures doivent être répétées après correction de la géométrie.

Le conteneur extérieur ignore désormais le même retrait supérieur que `BrowserWindow`.
Le masquage d'accessibilité reste aussi appliqué dans SwiftUI : le filtrage natif ne suffit
pas pour ses éléments virtuels. Le nouvel hôte reçoit explicitement les valeurs publiques
nécessaires, avec un pont dédié pour `OpenWindowAction` et `OpenSettingsAction`, au lieu
de recopier tout le contexte interne de l'hôte parent. Les autres préférences système sont
résolues par son propre `NSHostingView`.

La Release `stage16-accessibility-release` passe ensuite 356 tests XCTest, les 12 tests
d'outillage et la signature stricte. Les parcours protégés standard et Réduire les animations
passent chacun 92 contrôles de parcours et 10 de restauration.

L'inspection native de `stage16-native` confirme les positions d'origine, les boutons
désactivés, l'absence des commandes du profil masqué dans l'arbre d'accessibilité, le brouillon
conservé après retour d'onglet et de profil, ainsi que le focus rendu au formulaire après
fermeture de la recherche. L'ouverture des réglages depuis le nouvel hôte et le menu
d'actions différé fonctionnent. Ce contrôle externe de l'arbre d'accessibilité est distinct
des tests unitaires des propriétés natives ; il ne constitue pas une session VoiceOver complète.

Les nouvelles captures Hitches seul, après correction de l'intégration, donnent :

| Capture | Profils web : nombre / cumul / pic | Onglets web : pic |
| --- | --- | --- |
| `stage16-current-cadence`, intervalle 300 ms | 0 / 0 / 0 ms | 33,3 ms |
| `stage16-idle-cadence`, intervalle 800 ms | 1 / 8,3 / 8,3 ms | 33,3 ms |

Les deux captures gardent une fenêtre active et visible et détectent le contrôle positif.
Les pauses de 800 ms dépassent le délai de mise au repos des pages : le second contrôle
vérifie donc leur réveil répété. Il ne suffit pas à prouver une cadence affichée constante
de 120 fps. Les profils avec accueil atteignent encore 33,3/50 ms dans ces captures ;
la recherche et la création/fermeture d'onglet gardent aussi des pics. L'objectif global
reste ouvert. Le bilan exact de cette version est dans `.build/motion/stage16-verification.json`.

### Taille proposée du conteneur de profils

`stage17-remaining-cpu` et `stage18-sizing-cpu` comparent le même parcours avec Time
Profiler. Le conteneur natif accepte désormais directement les propositions finies de
largeur et de hauteur : ses deux espaces remplissent le viewport et ne déterminent pas
sa taille intrinsèque. Les propositions non finies conservent le comportement par défaut.

Sur dix changements de profil avec accueil, le poids inclusif échantillonné de
`RootGeometry` passe de 501 à 11 ms ; entre onglets web, de 89 à 4 ms. Le poids total
du thread principal de ces deux phases passe respectivement de 1364 à 1236 ms et
de 402 à 321 ms. Ces valeurs cumulées de diagnostic ne sont pas des durées d'image.
Le pic des onglets web reste à 33,3 ms ; aucun retard n'est détecté pour les profils web
dans cette capture. Le gain de géométrie ne suffit donc pas à valider 120 fps.

La Release `stage18-sizing-release` passe les 30 tests ciblant les pages, profils,
conteneurs et barres de fenêtre, la signature stricte, ainsi que 92 contrôles de parcours
et 10 de restauration dans chacun des deux modes d'animation. Le contrôle natif
`stage18-native` vérifie l'agrandissement puis le rétablissement de la fenêtre, ainsi
que le même redimensionnement en vue partagée avec une page locale et l'accueil.
Les barres conservent leur placement et les deux panneaux remplissent la nouvelle taille.
Cette optimisation est conservée ; les pics restants restent à traiter.

Les contrôles `stage19-current-bodies` et `stage19-navigation-bodies` essaient ensuite
des boutons de navigation équatables, avec résolution des actions et de l'historique
au moment du clic. Les évaluations de vues des dix changements d'onglet web passent
de 649 à 481, mais leurs durées cumulées restent proches de 20 ms et le pic à 33,3 ms.
Le cumul des retards passe de 266,7 à 275 ms. Cette extraction est retirée.

`stage20-focus-cpu` essaie une remise directe du focus au champ d'adresse existant,
avant la mise à jour de son représentable SwiftUI. Les pics restent à 33,3 ms pour
les onglets web et les profils avec accueil, et à 58,3 ms pour la création/fermeture.
Le travail échantillonné baisse légèrement, sans gain suffisant sur les pics.
Cette variante est également retirée ; ses sources et son binaire restent hors Git
dans `.build/motion/stage20-focus-candidate` et `stage20-focus-release`.

### Recherche des destinataires du focus

Time Profiler montre qu'AppKit interroge `NSHostingView.acceptsFirstResponder` lors
des changements de focus et du recalcul des zones déplaçables de la fenêtre. La réponse
par défaut recherche les contrôles du graphe SwiftUI. L'hôte d'un espace Lisière contient
toujours son champ d'adresse : il répond désormais directement selon son activité.
SwiftUI conserve le parcours du focus et la gestion des contrôles.

Dans `stage21-host-focus-cpu`, le poids inclusif de `FocusBridge.hostAcceptsFirstResponder`
passe de 29 à 4 ms pour dix changements d'onglet web, et de 170 à 73 ms pour la recherche.
Le thread principal des onglets web passe de 321 à 284 ms. Le pic baisse de 33,3 à 25 ms.
La paire suivante, sans Time Profiler, confirme ce pic :

| Capture Hitches seul | Onglets web : cumul / pic | Profils web : cumul / pic |
| --- | --- | --- |
| `stage21-reference-cadence` | 258,3 / 33,3 ms | 0 / 0 ms |
| `stage21-candidate-cadence` | 216,7 / 25 ms | 0 / 0 ms |

Le changement est conservé après 30 tests ciblés, signature stricte et deux parcours
protégés de 92 + 10 contrôles. Le contrôle natif `stage21-native` exerce Tab/Maj-Tab
entre adresse et formulaire, Cmd-L après retour de profil, Cmd-T, la recherche avec
surlignage et sa fermeture avec Échap. Les brouillons restent distincts après retour
d'onglet et de profil ; seul le profil actif figure dans l'arbre d'accessibilité.
Ce parcours ne remplace pas un contrôle complet avec VoiceOver ou trackpad physique.

Le pic de 25 ms reste au-dessus de l'objectif ; la création/fermeture d'onglets atteint
encore 58,3 ms dans la capture retenue. Le bilan est enregistré dans
`.build/motion/stage21-comparison.json`. Aucun résultat ne prouve encore 120 fps
sur toute l'interface.

`stage22-address-size-cpu` teste une largeur proposée explicite pour le champ d'adresse,
avec sa hauteur de texte native. Le pic des onglets web remonte à 33,3 ms, avec 283,3 ms
de retard cumulé, contre 25 ms et 216,7 ms dans `stage21-host-focus-cpu`. L'essai est retiré.

### Panneau de recherche natif : essai retiré

La variante `stage23-find-host-sizing-release` conserve le contenu SwiftUI de la recherche
dans un panneau AppKit qui anime son propre calque. Onze tests ciblés passent ; le contrôle
natif vérifie aussi le redimensionnement « Not Found », le retour à la largeur normale et
le retour du clavier au formulaire. Le poids des échantillons du thread principal passe
de 1 180 à 616 ms sur dix actions de recherche dans les captures CPU.

La paire Hitches seul ne confirme toutefois pas de réduction des pics :

| Scénario | Référence Stage 21 : cumul / pic | Variante Stage 23 : cumul / pic |
| --- | --- | --- |
| Recherche | 325 / 33,3 ms | 316,7 / 33,3 ms |
| Onglets web | 266,7 / 33,3 ms | 266,7 / 33,3 ms |
| Profils web | 0 / 0 ms | 0 / 0 ms |
| Création/fermeture | 200 / 66,7 ms | 166,7 / 75 ms |
| Profils avec accueil | 175 / 33,3 ms | 258,3 / 33,3 ms |

Les captures `stage23-reference-cadence` et `stage23-candidate-cadence` sont valides
(contrôle positif, fenêtre active et visible). La référence atteint de nouveau 33,3 ms
entre onglets : **25 ms n'est donc pas un plafond stable**. Le panneau natif est retiré,
car son gain CPU ne justifie pas ici la complexité supplémentaire de focus et de disposition
sans amélioration des pics visés. Ses sources et ses mesures sont conservées dans
`.build/motion/stage23-find-host-candidate-source` et `stage23-comparison.json`.

### Présentation anticipée des pages : essais retirés

La variante Stage 24 présente directement la page déjà en cache avant la réconciliation
SwiftUI et force la présentation Core Animation. Dans `stage24-candidate-cadence-1`,
le pic des onglets web descend à 16,7 ms, pour 133,3 ms de retard cumulé.
Cependant, cette présentation intervient avant la mise à jour des projections de sélection
du modèle. Une réentrée de SwiftUI pourrait alors observer une sélection incohérente.
Cette variante n'est pas retenue.

Stage 25 rétablit d'abord la cohérence du modèle, puis présente la page en cache.
La dernière capture autorisée, `stage25-final-cadence`, est valide : le contrôle positif
est détecté et la fenêtre reste active et visible. Les onglets web atteignent 25 ms,
pour 216,7 ms de retard cumulé. Ce résultat reste dans la plage déjà mesurée sur
la version Stage 21 ; il ne justifie pas le mécanisme de présentation supplémentaire.
Les sources de Stage 21 sont donc restaurées.

Cette dernière capture utilise des intervalles de 800 ms entre profils et détecte un
retard de 16,7 ms entre profils web. Ce résultat appartient à la variante retirée ; il
ne constitue pas une validation du réveil des pages pour la version retenue. Les captures
`stage24-reference-cadence-2` et `stage25-coherent-cadence-1`, invalidées par la perte
de focus, ne servent à aucune conclusion de performance.

Les sources expérimentales sont conservées hors Git dans
`.build/motion/stage24-early-page-candidate-source` et
`.build/motion/stage25-coherent-page-candidate-source`. Le bilan de décision est dans
`.build/motion/stage25-compromise.json`. Aucun de ces mécanismes expérimentaux ne reste
dans les sources finales.
