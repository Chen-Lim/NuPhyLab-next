export const mappingCommitEnvironmentName='AIR_STUDIO_MAPPING_COMMIT_SECRET';
export function sanitizeMappingCommitSecret(value) {
  return typeof value==='string'&&/^[A-Za-z0-9+/]{43}=$/.test(value)&&Buffer.from(value,'base64').length===32&&
    Buffer.from(value,'base64').toString('base64')===value?value:null;
}
// Capture before takeNativeHoldEnvironment clears all native private names.
// This derived key is for the HID helper alone; it signs no Host input/hold.
export function takeMappingCommitSecret(environment=process.env) {
  const value=sanitizeMappingCommitSecret(environment[mappingCommitEnvironmentName]);
  delete environment[mappingCommitEnvironmentName];return value;
}
