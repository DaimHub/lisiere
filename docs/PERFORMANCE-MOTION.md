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

## Résultats avant / après

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
