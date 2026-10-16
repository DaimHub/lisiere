// Export the native Icon Composer documents used by the mascot picker and Dock.
// Run after generate-mascots.mjs on a Mac with Xcode and Icon Composer installed.
import { copyFileSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';

const root = fileURLToPath(new URL('../', import.meta.url));
const resources = join(root, 'Resources');
const developer = execFileSync('xcode-select', ['-p'], { encoding: 'utf8' }).trim();
const ictool = join(developer, '../Applications/Icon Composer.app/Contents/Executables/ictool');
const master = JSON.parse(readFileSync(join(resources, 'Lisiere.icon/icon.json'), 'utf8'));

const catalog = JSON.parse(readFileSync(join(resources, 'Brand/mascots.json'), 'utf8'));
for (const { id: name, title } of catalog) {
  for (const suffix of ['', '-white']) {
    const isDefault = name === 'lutin' && !suffix;
    const document = isDefault ? join(resources, 'Lisiere.icon') : join(resources, 'Brand', `${title}${suffix}.icon`);
    mkdirSync(join(document, 'Assets'), { recursive: true });
    for (const part of ['body', 'eyes', 'pupils']) {
      copyFileSync(join(resources, 'Brand', `${name}${suffix}`, `${part}.svg`), join(document, 'Assets', `${part}.svg`));
    }
    if (!isDefault) {
      const copy = structuredClone(master);
      copy.groups[0].name = `${title}${suffix ? ' — White' : ''}`;
      if (suffix) {
        copy.fill = { solid: 'extended-srgb:0.00000,0.00000,0.00000,1.00000' };
        copy.groups[0].shadow.opacity = 0;
      }
      writeFileSync(join(document, 'icon.json'), JSON.stringify(copy, null, 2) + '\n');
    }
    const imageSet = join(resources, 'Assets.xcassets', `Dock-${name}${suffix}.imageset`);
    mkdirSync(imageSet, { recursive: true });
    execFileSync(ictool, [document, '--export-image', '--output-file', join(imageSet, `${name}${suffix}.png`),
      '--platform', 'macOS', '--rendition', 'Default', '--width', '1024', '--height', '1024', '--scale', '1']);
    writeFileSync(join(imageSet, 'Contents.json'), JSON.stringify({
      images: [{ filename: `${name}${suffix}.png`, idiom: 'universal' }],
      info: { author: 'xcode', version: 1 }
    }, null, 2) + '\n');
    console.log(`Exported ${title}${suffix} with Icon Composer.`);
  }
}
