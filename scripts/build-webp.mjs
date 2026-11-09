import {readdir, mkdir, rm} from 'node:fs/promises';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import path from 'node:path';
const run = promisify(execFile);

// Pinned upstream sources; no Homebrew or runtime downloads.
export async function buildWebP(target) {
  const root = 'vendor/libwebp', output = 'bin/webp';
  await mkdir(output, {recursive:true});
  const sources = [];
  for (const directory of ['src/enc','src/dec','src/dsp','src/utils','sharpyuv']) {
    for (const name of (await readdir(`${root}/${directory}`)).sort()) {
      if (name.endsWith('.c')) sources.push(`${root}/${directory}/${name}`);
    }
  }
  const objects = sources.map(file => path.join(output, file.slice(root.length+1).replaceAll('/', '_')+'.o'));
  let next = 0;
  await Promise.all(Array.from({length:4}, async () => {
    while (next < sources.length) {
      const index = next++;
      await run('clang', ['-target',target,'-O2','-DNDEBUG','-DWEBP_USE_THREAD','-fvisibility=hidden','-I',root,
        '-c',sources[index],'-o',objects[index]]);
    }
  }));
  const library = 'bin/libwebp.a';
  await rm(library,{force:true});
  await run('/usr/bin/libtool',['-static','-o',library,...objects]);
  return library;
}
