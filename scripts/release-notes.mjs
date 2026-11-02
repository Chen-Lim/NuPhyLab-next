import {createHash} from 'node:crypto';

export function releaseNotes(document,version){
  if(!/^\d+\.\d+\.\d+$/.test(version)||document?.version!==version)throw new Error('Release notes must match the package version');
  const sections=['zh-CN','en'].map(language=>{
    const items=document[language];
    if(!Array.isArray(items)||items.length===0||items.some(item=>typeof item!=='string'||!item.trim()||/[\r\n<>]|\[en\]|\[zh-CN\]|\]\]>/.test(item)||/^(TODO|TBD|待补充|占位)/i.test(item.trim())))
      throw new Error(`Real release notes are required for ${language}`);
    if(language==='en'&&items.some(item=>/[\u3400-\u9fff]/.test(item)))throw new Error('English release notes must be translated completely');
    return `NuPhy Lab ${version}\n\n${items.map(item=>'• '+item.trim()).join('\n')}`;
  });
  const text=`NUPHY-RELEASE-NOTES 1\nversion:${version}\n[zh-CN]\n${sections[0]}\n[en]\n${sections[1]}\n`;
  return {version,text,sha256:createHash('sha256').update(text).digest('hex')};
}

export function verifyReleaseFeed({xml,version,prefix,artifactName,artifactBytes,notes}){
  const items=xml.match(/<item>[\s\S]*?<\/item>/g)||[];
  const item=items.find(value=>value.includes(`<sparkle:version>${version}</sparkle:version>`));
  if(!item||!item.includes(`<sparkle:shortVersionString>${version}</sparkle:shortVersionString>`))throw new Error('Generated feed is missing this exact app version');
  const enclosure=item.match(/<enclosure\s[^>]*\/>/)?.[0]||'';
  if(!enclosure.includes(`url="${prefix}${artifactName}"`)||!enclosure.includes(`length="${artifactBytes}"`)||!enclosure.includes('sparkle:edSignature="'))throw new Error('Feed package metadata does not match the final artifact');
  if(!item.includes(notes.text.trim())||!item.includes('plain-text'))throw new Error('This version must embed its bilingual plain-text release notes');
  return true;
}

export function verifyPackageRelease({version,shortVersion,metadata,notes}){
  if(version!==notes.version||shortVersion!==notes.version||metadata?.version!==notes.version||
    metadata.releaseNotesVersion!==notes.version||metadata.releaseNotesSHA256!==notes.sha256)
    throw new Error('The signed app version and bundled release notes metadata must match these release notes');
  return true;
}
