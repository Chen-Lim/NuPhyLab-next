// Fixed counters/enums only. Never carry target labels, text, URLs or process IDs
// through an error, even if a future native adapter accidentally includes them.
const enums={
  enableStatus:['already-enabled','requested','unsupported','failed'],
  limitReason:['none','nodes','depth','children','time'],
  actionReadiness:['warming','ready','unavailable','unknown'],
  activationResponse:['not-requested','accepted','unsupported','denied','failed'],
  scopeKind:['none','document','focused-input','owned-input'],
  focusSource:['none','application','document','owned'],
  focusStage:['unknown','missing','outside-document','container','editable-missing','scope-rejected','ready'],
  focusRole:['none','text-area','text-field','web-area','group','scroll-area','window','button','search-field','secure-field','other'],
  focusAction:['none','requested','confirmed','failed','cancelled']
};
const counters=['visitedNodes','webAreasSeen','trustedWebAreas','missingURLWebAreas','rejectedURLWebAreas','buttonCount','menuCount','matchCount','elapsedMs','warmupRemainingMs','focusDepth'];
export function controlDiagnostic(value) {
  if(!value||typeof value!=='object')return undefined;
  const result={};
  for(const [key,allowed] of Object.entries(enums))if(allowed.includes(value[key]))result[key]=value[key];
  for(const key of counters)if(Number.isInteger(value[key])&&value[key]>=0&&value[key]<=4096)result[key]=value[key];
  for(const key of ['scanLimited','focusHasDocument','focusHasWindow'])if(typeof value[key]==='boolean')result[key]=value[key];
  return Object.keys(result).length?result:undefined;
}
