import * as platformPath from 'node:path';

/** Test resolved paths using the platform's drive and separator rules. */
export function isWithin(root: string, target: string, paths = platformPath) {
  const member = paths.relative(root, target);
  return member !== '' && member !== '..' &&
    !member.startsWith('..' + paths.sep) && !paths.isAbsolute(member);
}

/** Exclude dependency members without excluding ancestors of the supplied root. */
export function includeDependencyPath(root: string, target: string, excluded: ReadonlySet<string>, paths = platformPath) {
  const member = paths.relative(root, target);
  if (member === '') return true;
  return isWithin(root, target, paths) &&
    !member.split(paths.sep).some(part => excluded.has(part));
}
