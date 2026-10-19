# Mesures de fluidité native — 19 octobre 2026

L'objectif est de suivre un écran à 120 Hz, soit une nouvelle image toutes les 8,33 ms, sans modifier l'apparence. Les captures ci-dessous mesurent les retards de présentation avec Instruments. Elles ne prouvent ni 120 images/s constantes ni une équivalence avec Chrome.

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
