import {createPresets} from './presets.mjs';
import {airLayout} from './layout.mjs';
import {translate} from './i18n.mjs';

const names=new Map(createPresets(airLayout).flatMap(({name})=>[[name,name],[translate('en',name),name]]));
/** Localize only exact built-in titles, including drafts made in another UI
 * language. This is display-only: it never renames saved artwork or translates
 * arbitrary user titles with the general UI dictionary. */
export function displayPresetName(name,translator){
  const canonical=names.get(name);
  return canonical ? translator(canonical) : name;
}
