import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {releaseNotes,verifyReleaseFeed,verifyPackageRelease} from '../scripts/release-notes.mjs';
const version='3.2.1',document={version,'zh-CN':['修复实际问题。'],en:['Fix the actual problem.']};
test('release notes require the exact version and meaningful Chinese and English entries',()=>{
  const notes=releaseNotes(document,version);
  assert.match(notes.text,/version:3\.2\.1\n\[zh-CN\]/);assert.match(notes.text,/\n\[en\]\n/);assert.match(notes.sha256,/^[a-f0-9]{64}$/);
  for(const value of [{...document,version:'3.2.0'},{...document,en:[]},{...document,'zh-CN':['TODO later']},{...document,en:['[en]\nInjected']},{...document,en:['<script>bad</script>']},{...document,en:['English mode 中文残留']}])assert.throws(()=>releaseNotes(value,version));
});
test('prepared feed must bind exact app version, immutable artifact metadata and signed embedded notes',()=>{
  const notes=releaseNotes(document,version),prefix='https://example.test/v3.2.1/',artifactName='NuPhyLab-3.2.1-macOS.dmg',artifactBytes=123;
  const xml=`<item><sparkle:version>${version}</sparkle:version><sparkle:shortVersionString>${version}</sparkle:shortVersionString><description sparkle:format="plain-text"><![CDATA[${notes.text.trim()}]]></description><enclosure url="${prefix}${artifactName}" length="123" sparkle:edSignature="fixture"/></item>`;
  const input={xml,version,prefix,artifactName,artifactBytes,notes};assert.equal(verifyReleaseFeed(input),true);
  for(const change of [{version:'3.2.2'},{artifactBytes:124},{artifactName:'wrong.dmg'},{notes:releaseNotes({...document,en:['A different release.']},version)},{xml:xml.replace('plain-text','html')},{xml:xml.replace('sparkle:edSignature','unsigned')}])assert.throws(()=>verifyReleaseFeed({...input,...change}));
});
test('the packaged app must contain the same version and notes fingerprint as its later feed',()=>{
  const notes=releaseNotes(document,version),metadata={version,releaseNotesVersion:version,releaseNotesSHA256:notes.sha256};
  const input={version,shortVersion:version,metadata,notes};assert.equal(verifyPackageRelease(input),true);
  for(const change of [{version:'3.2.0'},{shortVersion:'3.2.0'},{metadata:null},{metadata:{...metadata,releaseNotesVersion:'3.2.0'}},{metadata:{...metadata,releaseNotesSHA256:'wrong'}}])assert.throws(()=>verifyPackageRelease({...input,...change}));
});
test('current release has real bilingual notes and feed preparation never publishes',async()=>{
  const pkg=JSON.parse(await readFile(new URL('../package.json',import.meta.url),'utf8'));
  const notes=releaseNotes(JSON.parse(await readFile(new URL(`../updates/release-notes/${pkg.version}.json`,import.meta.url),'utf8')),pkg.version);
  assert.ok(notes.text.includes('NuPhy Lab '+pkg.version));
  const script=await readFile(new URL('../scripts/prepare-appcast.mjs',import.meta.url),'utf8');
  assert.match(script,/--embed-release-notes/);assert.match(script,/verifyReleaseFeed/);assert.match(script,/published:false/);assert.doesNotMatch(script,/git push|gh release|upload/);
});
