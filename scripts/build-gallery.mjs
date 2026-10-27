import { readFile, writeFile, mkdir, stat } from 'node:fs/promises';
import path from 'node:path';

const root = process.cwd();
const galleryDir = path.join(root, 'docs', 'gallery');
const assetDir = path.join(galleryDir, 'assets');
const manifestPath = path.join(galleryDir, 'manifest.json');
const dataPath = path.join(galleryDir, 'data.json');

await mkdir(assetDir, { recursive: true });
const items = JSON.parse(await readFile(manifestPath, 'utf8'));
const result = [];
const failures = [];

async function exists(file) {
  try {
    const info = await stat(file);
    return info.isFile() && info.size > 1024;
  } catch {
    return false;
  }
}

for (const item of items) {
  const filename = `${item.id}.webp`;
  const target = path.join(assetDir, filename);
  let ok = await exists(target);

  if (!ok) {
    for (let attempt = 1; attempt <= 4 && !ok; attempt += 1) {
      try {
        const response = await fetch(item.thumbnail_url, {
          headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/141.0 Safari/537.36',
            'Referer': item.post_url,
            'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8'
          }
        });
        const type = response.headers.get('content-type') || '';
        if (!response.ok || !type.startsWith('image/')) {
          throw new Error(`HTTP ${response.status} ${type}`);
        }
        const buffer = Buffer.from(await response.arrayBuffer());
        if (buffer.length < 1024) throw new Error(`image too small: ${buffer.length}`);
        await writeFile(target, buffer);
        ok = true;
        console.log(`downloaded ${filename} (${buffer.length} bytes)`);
      } catch (error) {
        console.warn(`attempt ${attempt} failed for ${item.id}: ${error.message}`);
        await new Promise(resolve => setTimeout(resolve, attempt * 1500));
      }
    }
  }

  if (ok) {
    result.push({
      id: item.id,
      caption: item.caption,
      image: `./assets/${filename}`,
      width: item.width,
      height: item.height,
      post_url: item.post_url,
      created_at: item.created_at
    });
  } else {
    failures.push(item.id);
  }
}

await writeFile(dataPath, JSON.stringify(result, null, 2) + '\n', 'utf8');
if (failures.length) {
  throw new Error(`Failed to download ${failures.length} image(s): ${failures.join(', ')}`);
}
console.log(`gallery ready: ${result.length} images`);
