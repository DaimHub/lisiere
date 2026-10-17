# Optimisations de performance — 17 octobre 2026

Base : `5d149f5` (`main`). Branche de travail : `codex/performance-five`.

## Changements

1. **Détection des formulaires** : une analyse initiale du document, puis uniquement les sous-arbres ajoutés et les changements des attributs `type` / `disabled`. Le suivi s'arrête dès la détection d'un champ de mot de passe. Les formulaires ajoutés dynamiquement restent reconnus.
2. **Trousseau** : les opérations Security passent sur un acteur dédié, commun aux profils. L'interface n'attend plus une lecture synchrone du trousseau. Les redirections et fermetures de pop-up attendent toujours la décision de sauvegarde ; une fermeture explicite invalide les réponses tardives. Les secrets ne sont pas mis en cache par cette optimisation.
3. **Suggestions** : index de recherche réutilisé, normalisation des textes une seule fois par révision, sélection des six meilleurs résultats sans trier tous les candidats. Préparation et recherche hors du MainActor. Le classement, les favoris et les règles de complétion sont conservés. Les résultats obsolètes sont écartés ; une complétion tardive ne remplace pas une composition IME ni un curseur déplacé.
4. **Historique** : un seul regroupement en cache, invalidé à chaque modification et selon requête, calendrier et locale. Le survol appartient désormais à chaque ligne. Les styles, dimensions, textes et actions restent les mêmes.
5. **Démarrage des profils** : la découverte des sessions ne crée plus les contextes complets des profils inutilisés (WebKit, historique, favicons et bloqueur). Le contexte adopte la même session lorsqu'un profil est effectivement ouvert.

Aucun changement des délais de suspension, de la conservation des données, de la qualité des pages, des animations ou des ressources graphiques.

## Mesures

Microbenchmark Swift compilé avec `-O`, Apple M3 Pro, macOS 27. Médiane de sept passages, URLs synthétiques uniques, sans favoris. Comparaison avec le code extrait de `5d149f5`. Ces mesures portent sur les algorithmes, pas sur le temps de chargement des sites ou les FPS de l'application.

| Pages | Recherche « doc » avant / après | Sans correspondance avant / après | Regroupement historique avant / cache |
| ---: | ---: | ---: | ---: |
| 1 000 | 3,02 / 0,14 ms | 4,15 / 1,04 ms | 2,41 / 0,0009 ms |
| 10 000 | 30,94 / 1,39 ms | 42,66 / 10,92 ms | 17,36 / 0,0009 ms |
| 50 000 | 262,22 / 10,37 ms | 259,12 / 56,77 ms | 77,67 / 0,0008 ms |

La construction froide de l'index, mesurée avec une première recherche, coûte respectivement 2,27 / 24,67 / 178,87 ms. Elle s'exécute hors du fil d'interface ; elle est réutilisée tant que l'historique et les favoris ne changent pas. Les premiers affichages et les requêtes inédites d'historique doivent toujours calculer leur regroupement.

Les fichiers locaux de reproduction et résultats sont dans `.build/performance/benchmark.py`, `Benchmark.swift` et `benchmark.csv` (non versionnés). Lancer `python3 .build/performance/benchmark.py` depuis ce checkout pour reproduire la comparaison.

## Validation initiale des optimisations

- `make test` : 218 tests Debug réussis. 218 tests en configuration Release : réussis. L'hôte XCTest autorise l'injection et désactive temporairement sandbox/hardened runtime ; ces réglages ne servent pas à la Release livrée.
- Comparaison de l'ancien et du nouvel algorithme : 1 800 pages, titres Unicode, favoris, égalités, plusieurs limites et dates de classement.
- WebKit réel : détection initiale et dynamique, 40 mutations indépendantes sans nouvelle analyse du document, sauvegarde/mise à jour, redirection, fermeture de pop-up et fermeture pendant une lecture lente.
- Profils : mêmes sessions, aucune création de magasin WebKit pour la seule découverte des sessions, isolation des cookies/stockages/cache et restauration.
- Historique : invalidation après changement de titre, suppression, requête et calendrier.

Les deux rapports de crash transmis pendant le travail venaient de l'hôte Debug `io.github.daimhub.lisiere.perftests`. Une surcharge globale d'identifiant avait aussi remplacé celui du bundle de ressources Hugeicons. L'isolation a été limitée aux cibles application/tests dans le projet généré ; aucune icône ni solution de repli visuelle n'a été modifiée. Les essais suivants démarrent correctement. Des exécutions Debug intermédiaires ont aussi été interrompues par une terminaison normale de l'hôte avant la fin des tests ; elles ne comptent pas comme validations réussies.

## Release initiale vérifiée en isolation

- `make build DERIVED_DATA=/Users/davidnikolic/Library/Developer/Xcode/DerivedData/LisierePerformance` : réussi.
- Bundle : `/Users/davidnikolic/Library/Developer/Xcode/DerivedData/LisierePerformance/Build/Products/Release/Lisiere.app`.
- `codesign --verify --deep --strict` : réussi. Sandbox et hardened runtime actifs ; exception locale Sparkle conforme au projet. Aucun bundle XCTest embarqué dans cette Release.
- Copie de contrôle : `.build/performance/Lisiere-Performance-QA.app`, identifiant `io.github.daimhub.lisiere.performanceqa`. Copiée avec les liens symboliques des frameworks, puis resignée avec les mêmes entitlements. Ressources graphiques identiques au bundle construit.
- `scripts/smoke-launch.sh` sur cette copie protégée : démarrage réussi, processus vivant après cinq secondes. Plusieurs lancements et redémarrages contrôlés ensuite par l'interface native.
- Inspection native sur 50 000 visites synthétiques : rendu de la nouvelle page, liste de suggestions, flèches haut/bas, complétion sélectionnée, Entrée immédiate, Échap avec et sans résultat, filtrage et ouverture de l'historique.
- Deux profils QA : URLs distinctes, conservation du formulaire non envoyé pendant le changement de profil, restauration du profil actif et du profil conservé en arrière-plan après fermeture propre. Historique toujours limité à 50 000 visites.
- Écran Mots de passe verrouillé inspecté. Les sauvegardes, mises à jour, origines autorisées et opérations du trousseau sont exercées par les tests Release avec des données temporaires.

Cette validation initiale utilisait une copie QA avec ses propres données. À cette étape, l'application de `/Applications`, le profil personnel et les modifications concurrentes du checkout principal n'avaient pas été remplacés ; la branche n'avait pas été fusionnée.

Limites : pas de mesure des FPS ni du gain global de batterie/RAM ; les temps ci-dessus sont des microbenchmarks. Pas de comparaison pixel par pixel, de validation physique Touch ID, de connexion à des comptes réels, de passkeys ou de notarisation Developer ID. Les parcours contrôlés n'ont montré aucune régression visuelle ou fonctionnelle.

## Intégration sur main et installation

Sur demande explicite, les cinq optimisations ont été fusionnées avec les derniers changements de `main`, puis avec l'illustration officielle Home01 encore en attente dans le checkout principal. Les cinq fichiers Home01 ont été sauvegardés et comparés par SHA-256 avant intégration. Le commit applicatif construit est `e4c8b80` ; la documentation de livraison est ajoutée ensuite.

- Nouvelle validation de l'ensemble intégré : 218 tests Debug et 218 tests Release réussis, sans échec.
- `make build` avec Derived Data dédié `LisierePerformanceIntegrated` : réussi. Signature stricte, sandbox et hardened runtime vérifiés ; aucun hôte XCTest embarqué.
- Démarrage de cinq secondes réussi sur une copie QA isolée avec les protections de la Release.
- Fermeture propre de l'ancienne application ; sauvegarde du conteneur `Data`, des préférences externes et de l'ancien bundle. Les 10 089 fichiers/liens du manifeste de données sont identiques avant et immédiatement après le remplacement.
- `/Applications/Lisiere.app` remplacé avec retour arrière prévu en cas d'échec ; son contenu correspond exactement au bundle Release construit. Signature stricte et lancement natif vérifiés sur ce chemin exact.
- Au premier lancement, historique, sessions, profils et préférences sont inchangés. Le contrôle natif retrouve le même onglet actif, les favoris et le rendu initial, puis vérifie le passage entre les deux profils et le retour au profil initial.
- Après ce passage, tous les historiques, favoris, préférences, URLs, titres, sélections et sessions conservées restent présents. Seul l'état d'interaction WebKit d'une session est renouvelé ; les fichiers WebKit temporaires peuvent évoluer normalement pendant la navigation.

L'ancienne application, les données, les manifestes et les rapports de tests sont conservés dans `~/Library/Application Support/LisiereBuildBackups/main-performance-20261017-165622/`. Les données du trousseau n'ont pas été exportées ni réinitialisées.
