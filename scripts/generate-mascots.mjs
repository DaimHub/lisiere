// Adapted from closedPath in jeremy-prt/bloub/src/bot/shape.ts,
// commit b4bb3c1b5f93c7b87a2e8d620f667c4093d97749.
// Copyright (c) 2026 Jérémy Perret, MIT. See Resources/Brand/LICENSE-bloub.txt.
// Lisière's artwork and sampled contours are independent of Bloub's avatar.
import { readFileSync, mkdirSync, writeFileSync, existsSync, unlinkSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';

const root = fileURLToPath(new URL('../', import.meta.url));
const brand = join(root, 'Resources/Brand');
const r2 = v => Math.round(v * 100) / 100;

function closedPath(points, tension = 1 / 6) {
  // Remove subpixel edge noise in the generated reference without changing its silhouette.
  points = points.map((_, i, all) => [0, 1].map(axis =>
    [1, 2, 4, 2, 1].reduce((sum, weight, j) => sum + all[(i + j - 2 + all.length) % all.length][axis] * weight, 0) / 10
  ));
  const n = points.length;
  if (n < 3) return '';
  let d = `M${points[0].map(r2).join(' ')}`;
  for (let i = 0; i < n; i++) {
    const p0 = points[(i - 1 + n) % n], p1 = points[i];
    const p2 = points[(i + 1) % n], p3 = points[(i + 2) % n];
    const c1 = p1.map((v, j) => v + (p2[j] - p0[j]) * tension);
    const c2 = p2.map((v, j) => v - (p3[j] - p1[j]) * tension);
    d += `C${[...c1, ...c2, ...p2].map(r2).join(' ')}`;
  }
  return `${d}Z`;
}

const svg = body => `<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">${body}</svg>\n`;
const catalog = JSON.parse(readFileSync(join(brand, 'mascots.json'), 'utf8'));
for (const { id: name } of catalog) {
  const geometry = JSON.parse(readFileSync(join(brand, `${name}.json`), 'utf8'));
  const layers = Object.fromEntries(['body', 'eyes', 'pupils'].map(part => [part,
    `<path fill="${part === 'eyes' ? '#FFFFFF' : '#000000'}" d="${geometry[part].map(p => closedPath(p)).join('')}"/>`
  ]));
  const sourceDir = join(brand, name);
  mkdirSync(sourceDir, { recursive: true });
  for (const [part, path] of Object.entries(layers)) writeFileSync(join(sourceDir, `${part}.svg`), svg(path));
  const full = svg(layers.body + layers.eyes + layers.pupils);
  const inverse = value => value.replace(/#FFFFFF|#000000/g, color => color === '#FFFFFF' ? '#000000' : '#FFFFFF');
  writeFileSync(join(sourceDir, `${name}.svg`), full);
  const whiteDir = join(brand, `${name}-white`);
  mkdirSync(whiteDir, { recursive: true });
  for (const [part, path] of Object.entries(layers)) writeFileSync(join(whiteDir, `${part}.svg`), inverse(svg(path)));
  writeFileSync(join(whiteDir, `${name}-white.svg`), inverse(full));

  for (const suffix of ['', '-white']) {
    const imageSet = join(root, 'Resources/Assets.xcassets', `Mascot-${name}${suffix}.imageset`);
    mkdirSync(imageSet, { recursive: true });
    writeFileSync(join(imageSet, `${name}${suffix}.svg`), suffix ? inverse(full) : full);
    writeFileSync(join(imageSet, 'Contents.json'), JSON.stringify({
      images: [{ filename: `${name}${suffix}.svg`, idiom: 'universal' }],
      info: { author: 'xcode', version: 1 },
      properties: { 'preserves-vector-representation': true }
    }, null, 2) + '\n');
    // Explicit palette choices replace the old automatic dark-mode recoloring.
    const oldDark = join(imageSet, `${name}-dark.svg`);
    if (existsSync(oldDark)) unlinkSync(oldDark);
  }
}
writeFileSync(join(root, 'Resources/Assets.xcassets/Contents.json'), JSON.stringify({ info: { author: 'xcode', version: 1 } }, null, 2) + '\n');
console.log(`Generated ${catalog.length} mascots in black and white, with aligned Icon Composer layers.`);
