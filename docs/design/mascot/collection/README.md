# Collection de mascottes — 16 octobre 2026

Six nouveaux personnages complètent Veilleur, Éclaireur et Lutin : neuf mascottes,
chacune en noir sur fond clair et en blanc sur fond noir, soit dix-huit choix.

Les six PNG de ce dossier ont été générés avec l'outil Image Gen intégré.
Ce sont les références de création ; l'application embarque les contours vectoriels
et les exports Icon Composer. Les silhouettes blanches proviennent des mêmes
contours, avec les couleurs inversées dans les sources SVG : aucune déformation
ni nouvelle génération de la silhouette.

## Directions utilisées avec Image Gen

Contraintes communes : un seul personnage sur fond blanc, silhouette noire
connectée et centrée, exactement deux yeux ovales blancs séparés avec deux pupilles
noires entièrement contenues dans les yeux ; aplats purs, courbes douces et lisibilité
à 32 px. Aucun texte, ombre, texture, dégradé, bouche, nez, décoration ou cadre.
Composition carrée 1024 × 1024 demandée, silhouette dans la zone 180…844 sur chaque axe.

### Lapin

Fichier : `lapin.png`.

A compact rabbit forest spirit, broad rounded head/body as one silhouette with TWO long rounded upright ears; one ear bends gently outward. No inner-ear marks. Two large white oval eyes centered in the lower rounded part, black oval pupils looking slightly left. No whiskers, no nose, no mouth, no separate paws.

### Ourson

Fichier : `ourson.png`.

A friendly compact bear forest spirit, broad round head/body as ONE continuous silhouette with TWO small circular ears protruding at upper corners, short rounded base. No inner-ear marks, no snout, no mouth, no paws. Two large white oval eyes with black round pupils looking upward-right.

### Nuage

Fichier : `nuage.png`.

A wide squat cloud spirit, ONE continuous silhouette consisting of three big rounded top lobes and softly flattened convex bottom. Chunky, asymmetrically soft, not a weather pictogram. Two large vertical white oval eyes with black oval pupils looking left. No rain, limbs, mouth or separate objects.

### Flamme

Fichier : `flamme.png`.

A playful little flame spirit, ONE continuous smooth silhouette with a broad rounded base rising into three short soft flame tongues: large curved central tip and two smaller side tips. Cute and calm not aggressive. Two large white oval eyes low in the body, black pupils looking right. NO internal flame cutouts, no mouth, no separate flames.

### Goutte

Fichier : `goutte.png`.

A softly tilted teardrop spirit, ONE continuous smooth silhouette, round plump lower body, single short curved top point leaning to the right. Centered stable proportions. Two large white oval eyes in the rounded body, black pupils looking slightly left-down. No other features, no detached droplets, no arms or feet.

### Pollen

Fichier : `pollen.png`.

A friendly rounded five-point star seed spirit, ONE continuous smooth inflated silhouette with FIVE short broad rounded lobes, never sharp. Big central body, compact proportions. Two large white oval eyes, black pupils looking right. No additional stars, mouth, speckles or decoration.

## Sources et régénération

- Catalogue : `Resources/Brand/mascots.json`.
- Géométrie : `Resources/Brand/<id>.json`, tracée depuis les PNG.
- Calques noirs : `Resources/Brand/<id>/`.
- Mêmes calques blancs : `Resources/Brand/<id>-white/`.
- Document par défaut : `Resources/Lisiere.icon`.
- Documents alternatifs : `Resources/Brand/<Nom>.icon` et `<Nom>-white.icon`.
- Assets SwiftUI et aperçus du Dock : `Resources/Assets.xcassets/`.

```sh
python3 scripts/trace-mascots.py lapin ourson nuage flamme goutte pollen
node scripts/generate-mascots.mjs
node scripts/export-mascot-icons.mjs
make test
make build
```

Le générateur reprend la géométrie Bloub déjà utilisée dans le projet ; sa licence
MIT et l'attribution Jérémy Perret restent conservées.

## Comportement

Settings > Appearance conserve le style natif du panneau, avec une grille de trois
colonnes. Le sélecteur de couleurs change tous les aperçus et conserve le personnage
sélectionné. Les préférences `mascot` et `mascotPalette` sont indépendantes et
restaurées au lancement. L'ancien choix de mascotte reste valable ; la palette
par défaut est noire.

La palette choisie s'applique à l'accueil et au Dock. Pour garder le contraste,
les mascottes blanches ont un fond noir sur l'accueil ; les noires disposent d'un
fond clair quand l'app est en apparence sombre. Finder garde l'icône native Lutin.
