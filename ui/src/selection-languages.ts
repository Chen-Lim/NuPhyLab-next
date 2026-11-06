// Persist codes, never translated display labels. Kept in parity with the
// native LabTranslationLanguage allowlist by the language contract tests.
export const translationLanguages = [
  {id:'zh-CN',label:'简体中文'}, {id:'zh-TW',label:'繁体中文'},
  {id:'en',label:'英语'}, {id:'ja',label:'日语'}, {id:'ko',label:'韩语'},
  {id:'fr',label:'法语'}, {id:'de',label:'德语'}, {id:'es',label:'西班牙语'},
  {id:'pt',label:'葡萄牙语'}, {id:'it',label:'意大利语'}, {id:'ru',label:'俄语'},
  {id:'ar',label:'阿拉伯语'}, {id:'hi',label:'印地语'}, {id:'th',label:'泰语'},
  {id:'vi',label:'越南语'}, {id:'id',label:'印度尼西亚语'},
] as const;
export type TranslationLanguage = typeof translationLanguages[number]['id'];
