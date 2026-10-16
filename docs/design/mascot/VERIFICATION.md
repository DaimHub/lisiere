# Vérification des mascottes — 16 octobre 2026

Le contrôle initial ci-dessous porte sur les trois premières mascottes. La collection
étendue à neuf personnages et deux palettes est vérifiée dans la dernière section.

## Livraison

- Lutin, proposition 3, comme icône native par défaut dans `Resources/Lisiere.icon`.
- Document créé et ouvert dans Apple Icon Composer ; corps, yeux et pupilles en calques SVG séparés.
- Veilleur et Éclaireur disponibles avec Lutin dans Settings > Appearance > Mascot & Dock Icon.
- Choix partagé entre page de nouvel onglet et icône du Dock, enregistré dans la préférence `mascot`.
- Release installée dans `/Applications/Lisiere.app`, avec le Lutin sélectionné à la fin.

## Résultats

- `make test` : 113 tests, aucun échec. Cela inclut le chargement des six ressources, la préférence persistante,
  le repli vers Lutin, les notices et l'icône natives compilées, ainsi que le changement effectif de
  `NSApplication.applicationIconImage` et la restauration de l'image par défaut.
- `make smoke` : compilation Release, signature stricte et maintien du processus pendant le test de démarrage.
- Après l'ajout des crédits, compilation finale et `codesign --verify --deep --strict` sur la copie installée.
- Binaire installé identique à celui de la Release vérifiée.
- Dans l'app installée : sélection de chacun des trois personnages, changement immédiat sur la page de nouvel
  onglet, état sélectionné accessible, puis relancement avec Éclaireur toujours présent et sélectionné.
- Inspection native de l'accueil, du sélecteur et du panneau À propos ; pas de prototype web.
- Icône Default inspectée dans Composer et dans son export compilé ; export Dark inspecté séparément.
- Une fenêtre et ses deux onglets conservés. Historique identique octet pour octet avant/après la vérification.

## Portée

L'API AppKit personnalise l'icône du Dock pendant l'exécution. Finder et l'application fermée gardent le Lutin.
Le changement de l'image AppKit a été testé ; une capture visuelle du Dock lui-même n'a pas pu être obtenue
avec le contrôleur d'interface. L'interface de l'app a été inspectée dans son apparence claire actuelle.

Captures et journaux locaux dans `.build/design/verification/` (ignorés par Git).
Les trois concepts raster sont conservés dans `black-options/`, sans être embarqués dans l'app.

## Extension : neuf personnages et deux palettes

- Six créations Image Gen supplémentaires : Lapin, Ourson, Nuage, Flamme, Goutte et Pollen.
- Neuf silhouettes, chacune en noir sur fond clair et en blanc sur fond noir, soit dix-huit icônes Composer.
- Les contours SVG sont strictement identiques entre palettes ; seules les couleurs changent.
- `make test` : 114 tests, aucun échec. Les 36 assets sont chargés ; les 18 rendus AppKit sont distincts,
  et revenir au Lutin noir restaure l'icône native. Préférences personnage/couleur testées séparément.
- `make smoke` : Release compilée, signature stricte valide et démarrage réussi.
- Copie installée identique à la Release vérifiée ; signature stricte vérifiée à nouveau après installation.
- Inspection de la grille entière dans la Release installée, dans les deux palettes, y compris la dernière ligne.
- Pollen blanc sélectionné et visible sur l'accueil ; même personnage et même palette retrouvés après relancement.
- Passage de la palette blanche à la noire sans perte du personnage sélectionné, vérifié dans les réglages.
- Deux onglets conservés et historique identique octet pour octet. Choix final rétabli : Lutin noir.
- Captures et journaux dans `.build/design/collection-verification/` ; aperçu de la palette blanche dans
  `collection/settings-white.png` ; prompts et provenance dans `collection/README.md`.

La limite Finder/Dock et la portée de la capture du Dock décrites plus haut restent applicables.

## Correction : accueil sans fond de mascotte

- Suppression du fond ajouté par `NewTabView` pour toutes les mascottes et les deux palettes.
- Les 18 SVG `Mascot-*` contiennent uniquement le corps, les yeux et les pupilles, sans fond.
- Compilation Release réussie et `codesign --verify --deep --strict` valide.
- Lutin noir puis blanc inspectés sur la page de nouvel onglet en apparence claire : aucun carré derrière la mascotte.
- Contrôle dans une copie du binaire Release avec un identifiant de bundle isolé ; l'application installée,
  ses profils et ses préférences n'ont pas été remplacés. L'apparence sombre n'a pas été inspectée visuellement.
- Journal et capture dans `.build/design/transparent-mascots/` (ignorés par Git).
