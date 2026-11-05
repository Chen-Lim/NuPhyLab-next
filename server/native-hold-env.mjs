import path from 'node:path';
import {sanitizeMappingCommitSecret,mappingCommitEnvironmentName} from './native-mapping-env.mjs';

const privateNames = ['AIR_STUDIO_NATIVE_KEY_SECRET', 'AIR_STUDIO_NATIVE_HOLD_SECRET', 'AIR_STUDIO_NATIVE_HOLD_PATH',mappingCommitEnvironmentName];

export function sanitizeNativeHoldEnvironment(value) {
  const secret = value?.secret, filePath = value?.path;
  if (typeof secret !== 'string' || !/^[A-Za-z0-9+/]{43}=$/.test(secret) ||
      Buffer.from(secret, 'base64').length !== 32 || Buffer.from(secret, 'base64').toString('base64') !== secret ||
      typeof filePath !== 'string' || filePath.length > 2048 || filePath.includes('\0') ||
      !path.isAbsolute(filePath) || path.normalize(filePath) !== filePath) return null;
  return Object.freeze({secret, path: filePath});
}

// Capture once, before any subprocess starts. Subsequent children inherit none
// of these variables unless the dedicated HID helper explicitly receives them.
export function takeNativeHoldEnvironment(environment = process.env) {
  const value = sanitizeNativeHoldEnvironment({secret: environment.AIR_STUDIO_NATIVE_HOLD_SECRET, path: environment.AIR_STUDIO_NATIVE_HOLD_PATH});
  for (const name of privateNames) delete environment[name];
  return value;
}

export function helperProcessEnvironment(value, environment = process.env, mappingCommitSecret = null) {
  const result = {...environment};
  for (const name of privateNames) delete result[name];
  const pair = sanitizeNativeHoldEnvironment(value);
  if (pair) {
    result.AIR_STUDIO_NATIVE_HOLD_SECRET = pair.secret;
    result.AIR_STUDIO_NATIVE_HOLD_PATH = pair.path;
  }
  const mapping=sanitizeMappingCommitSecret(mappingCommitSecret);
  if(mapping)result[mappingCommitEnvironmentName]=mapping;
  return result;
}
