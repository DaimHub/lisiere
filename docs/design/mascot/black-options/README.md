# Lisière — explorations de mascotte noire

Date : 16 octobre 2026. David a retenu la proposition 3, le Lutin, comme icône par défaut.
Les numéros correspondent à l'ordre d'affichage des images dans le chat.
Ces trois fichiers sont les concepts raster générés avec l'outil Image Gen intégré.
Les sources vectorielles et les documents Icon Composer se trouvent dans `Resources/`.

| Proposition | Fichier | Direction |
| --- | --- | --- |
| 1 | [option-1.png](option-1.png) | Le Veilleur : silhouette verticale arrondie, deux petits pieds |
| 2 | [option-2.png](option-2.png) | L'Éclaireur : esprit asymétrique orienté vers l'avant |
| 3 | [option-3.png](option-3.png) | Le Lutin : silhouette large, deux petites pointes, regard curieux |

## Références et réalisation

Le dépôt retrouvé est [jeremy-prt/bloub](https://github.com/jeremy-prt/bloub),
commit `b4bb3c1b5f93c7b87a2e8d620f667c4093d97749`, sous licence MIT.
Sa fonction `closedPath` dans `src/bot/shape.ts` est la base géométrique utilisée
par CaloIO et WakeIO. Leurs fichiers de licence et leurs sources locales ont été
consultés. Les propositions utilisent l'icône CaloIO comme référence visuelle.

Les contours des trois propositions sont échantillonnés par `scripts/trace-mascots.py`,
puis lissés avec cette base par `scripts/generate-mascots.mjs`. Les calques corps,
yeux et pupilles restent séparés. La licence MIT accompagne les sources et l'app.

`Resources/Lisiere.icon` a été créé dans Apple Icon Composer, puis ses trois calques
SVG ont été importés. La composition conserve une mascotte noire opaque, des yeux
blancs et un fond neutre. Les variantes Veilleur et Éclaireur partagent ce document
de référence ; leurs documents sont dans `Resources/Brand/`.

`scripts/export-mascot-icons.mjs` exporte les trois aperçus avec l'outil natif
`ictool` d'Icon Composer. Xcode compile `Lisiere.icon` en véritable icône d'app.
Les réglages Appearance proposent les trois mascottes pour la page de nouvel
onglet et le Dock. Le choix est enregistré et réappliqué au lancement. L'icône du
Finder reste le Lutin : `NSApplication.applicationIconImage` personnalise seulement
l'icône de l'application en cours d'exécution.

Pour régénérer après une modification des contours ou du document Composer :

```sh
node scripts/generate-mascots.mjs
node scripts/export-mascot-icons.mjs
make test
make build
```

La première proposition verte a été refusée et n'est pas intégrée au projet Xcode.

## Prompts de direction

Contraintes communes : logo original pour Lisière, navigateur macOS natif ;
image carrée, personnage unique centré ; silhouette noire, grands yeux blancs
avec pupilles noires ; fond blanc cassé ; aplats simples, lisibles à 32 px ;
aucun texte, aucune couleur, aucun dégradé, aucune ombre, aucun accessoire végétal.
Référence jointe : `CaloIO/assets/images/caloio_icon_1024.png`.

1. **Le Veilleur** : corps et tête en une silhouette verticale en arche douce,
   deux petits pieds séparés par une encoche ; pupilles vers le haut à droite ;
   calme et curieux ; sans bras, oreilles, bouche ni accessoire.
2. **L'Éclaireur** : petite comète ou esprit de forêt asymétrique, corps arrondi
   orienté vers la droite, queue courte intégrée au contour en bas à gauche,
   pointe douce en haut à droite ; grands yeux regardant vers l'avant.
3. **Le Lutin** : corps large et compact, deux pointes arrondies aux coins
   supérieurs, courbe peu profonde entre elles, joues et base rondes ; grands
   yeux, pupilles vers la gauche ; sans moustaches, nez, bouche ni fourrure.

Les concepts raster sont conservés comme références du choix, sans être embarqués dans l'app.
