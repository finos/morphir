// Verify the version reported by an installed release.
export function verifyReleaseVersion(output, version) {
  const reported = output.trim().split(/\r?\n/).at(-1);
  if (reported !== `morphir ${version}`) throw new Error(`release version mismatch: ${output}`);
  return reported;
}
