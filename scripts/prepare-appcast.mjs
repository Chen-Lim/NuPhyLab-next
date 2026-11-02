// Prepare only. Publishing assets and then the feed is a separate release step.
import {readFile,mkdir,copyFile,writeFile,access,mkdtemp,rm} from 'node:fs/promises';
import {execFileSync} from 'node:child_process';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {releaseNotes,verifyReleaseFeed,verifyPackageRelease} from './release-notes.mjs';
import {tmpdir} from 'node:os';
const root=fileURLToPath(new URL('../',import.meta.url));
const [artifactArg,directoryArg]=process.argv.slice(2);
if(!artifactArg||!directoryArg)throw new Error('Usage: node scripts/prepare-appcast.mjs <notarized.dmg> <new-output-directory>');
const artifact=path.resolve(artifactArg),directory=path.resolve(directoryArg);
if(path.extname(artifact)!=='.dmg')throw new Error('Expected a signed, notarized DMG');
const config=JSON.parse(await readFile(path.join(root,'config/updates.json'),'utf8'));
const {version}=JSON.parse(await readFile(path.join(root,'package.json'),'utf8'));
if(!/^\d+\.\d+\.\d+$/.test(version))throw new Error('Release version must be stable semver');
if(!path.basename(artifact).includes(`-${version}-`))throw new Error('Final artifact filename must include the exact release version');
const notes=releaseNotes(JSON.parse(await readFile(path.join(root,`updates/release-notes/${version}.json`),'utf8')),version);
const bytes=await readFile(artifact);
const run=(file,args)=>execFileSync(file,args,{encoding:'utf8',stdio:['ignore','pipe','pipe']});
run('/usr/bin/codesign',['--verify','--strict',artifact]);
run('/usr/bin/xcrun',['stapler','validate',artifact]);
// Inspect the final immutable image read-only. The app is never launched, and
// no feed is prepared from notes changed after the app was signed.
const inspection=await mkdtemp(path.join(tmpdir(),'nuphylab-feed-inspect-'));
const mount=path.join(inspection,'volume');let mounted=false;
try {
  run('/usr/bin/hdiutil',['attach','-readonly','-nobrowse','-plist','-mountpoint',mount,artifact]);mounted=true;
  const app=path.join(mount,'NuPhy Lab.app');
  run('/usr/bin/codesign',['--verify','--strict',app]);
  const plist=path.join(app,'Contents/Info.plist');
  verifyPackageRelease({version:run('/usr/bin/plutil',['-extract','CFBundleVersion','raw','-o','-',plist]).trim(),
    shortVersion:run('/usr/bin/plutil',['-extract','CFBundleShortVersionString','raw','-o','-',plist]).trim(),
    metadata:JSON.parse(await readFile(path.join(app,'Contents/Resources/update-metadata.json'),'utf8')),notes});
} finally {
  if(mounted)run('/usr/bin/hdiutil',['detach',mount]);
  await rm(inspection,{recursive:true,force:true});
}
await mkdir(directory,{recursive:false});
const local=path.join(directory,path.basename(artifact));await copyFile(artifact,local);
await writeFile(path.join(directory,path.basename(artifact,'.dmg')+'.txt'),notes.text);
try {await access(path.join(root,'updates/appcast.xml'));await copyFile(path.join(root,'updates/appcast.xml'),path.join(directory,'appcast.xml'));} catch(error) {if(error.code!=='ENOENT')throw error;}
const bin=path.join(root,'vendor/sparkle/bin');
const prefix=`https://github.com/${config.repository}/releases/download/v${version}/`;
run(path.join(bin,'generate_appcast'),['--account',config.keychainAccount,'--download-url-prefix',prefix,
  '--maximum-deltas','0','--maximum-versions','1','--embed-release-notes','--link',`https://github.com/${config.repository}`,'--versions',version,directory]);
const feed=path.join(directory,'appcast.xml');
run(path.join(bin,'sign_update'),['--account',config.keychainAccount,'--verify',feed]);
const xml=await readFile(feed,'utf8');
verifyReleaseFeed({xml,version,prefix,artifactName:path.basename(artifact),artifactBytes:bytes.length,notes});
await writeFile(path.join(directory,'FEED_VERIFICATION.json'),JSON.stringify({version,feedURL:config.feedURL,
  downloadPrefix:prefix,bytes:bytes.length,sha256:createHash('sha256').update(bytes).digest('hex'),
  releaseNotesVersion:notes.version,releaseNotesSHA256:notes.sha256,releaseNotesEmbedded:true,
  signedFeedVerified:true,published:false},null,2)+'\n');
console.log(`Prepared verified update feed: ${feed}`);
