import { isRecord, workbenchError } from '../../../types/data.ts';
import { strToU8, zipSync } from 'fflate';
import { verifiedArtifactDownloads, type ArtifactDownloadRegistry } from './artifact-registry.ts';

// Keep original relative project paths; reject ambiguous or escaping paths.
export function artifactBytes(artifacts: unknown, registry: ArtifactDownloadRegistry = verifiedArtifactDownloads, complete = false) {
  if (!Array.isArray(artifacts) || !artifacts.length) throw new Error('There are no generated files to download.');
  if (artifacts.some(artifact => isRecord(artifact) && ('verifiedArtifact' in artifact || artifact.encoding === 'verified-bytes'))) {
    // A mixed/forged/stale set fails here; it never falls back to preview strings.
    return registry.bytes(artifacts, complete);
  }
  const files = Object.create(null) as Record<string, Uint8Array<ArrayBuffer>>;
  const names = new Set<string>();
  for (const artifact of artifacts) {
    if (!isRecord(artifact)) throw new Error('A generated file has invalid content.');
    const { path, content, binary } = artifact;
    if (typeof path !== 'string' || !path || /[\\:\0]/.test(path) || path.startsWith('/') ||
        path.split('/').some(part => !part || part === '.' || part === '..')) {
      throw new Error('A generated file has an invalid project path.');
    }
    const folded = path.toLowerCase();
    if (names.has(folded) || [...names].some(name => name.startsWith(folded + '/') || folded.startsWith(name + '/'))) {
      throw new Error('Generated file paths conflict.');
    }
    if (typeof content !== 'string' || typeof binary !== 'boolean') throw new Error('A generated file has invalid content.');
    let bytes;
    if (binary) {
      if (artifact.encoding !== 'base64') throw new Error('This host does not declare an encoding for binary file downloads.');
      if (!/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(content)) throw new Error('Invalid binary file encoding.');
      const decoded = atob(content);
      if (btoa(decoded) !== content) throw new Error('Invalid binary file encoding.');
      bytes = Uint8Array.from(decoded, character => character.charCodeAt(0));
    } else bytes = strToU8(content);
    names.add(folded);
    files[path] = bytes;
  }
  return files;
}

function inventoryBytes(artifacts: unknown, registry: ArtifactDownloadRegistry = verifiedArtifactDownloads, complete = false) {
  if (!isRecord(artifacts) || !Array.isArray(artifacts.files) || !Array.isArray(artifacts.directories)) return artifactBytes(artifacts, registry, complete);
  if (artifacts.files.length > 4096 || artifacts.directories.length > 4096) throw new Error('Original tree exceeds the inventory budget.');
  const files = artifactBytes(artifacts.files, registry, complete);
  const names = new Set(Object.keys(files).map(path => path.toLowerCase()));
  for (const directory of artifacts.directories) {
    if (typeof directory !== 'string' || !directory || /[\\:\0]/.test(directory) || directory.startsWith('/') || directory.split('/').some(part => !part || part === '.' || part === '..')) throw new Error('Invalid original directory path.');
    const folded = directory.toLowerCase();
    if (names.has(folded) || [...names].some(name => folded.startsWith(name + '/'))) throw new Error('Original directory conflicts with a file.');
    files[directory + '/'] = new Uint8Array(0);
  }
  return files;
}

export function projectArchive(artifacts: unknown, registry: ArtifactDownloadRegistry = verifiedArtifactDownloads) {
  return zipSync(inventoryBytes(artifacts, registry, true), { level: 0, mtime: new Date(1980, 0, 1) });
}

export function downloadArtifacts(artifacts: unknown, project: boolean) {
  try {
    const files = inventoryBytes(artifacts, verifiedArtifactDownloads, project);
    const name = project ? 'morphir-project.zip' : Object.keys(files)[0]!.split('/').at(-1)!;
    const bytes = project ? zipSync(files, { level: 0, mtime: new Date(1980, 0, 1) }) : Object.values(files)[0]!;
    const url = URL.createObjectURL(new Blob([bytes], { type: project ? 'application/zip' : 'application/octet-stream' }));
    const link = document.createElement('a');
    link.href = url; link.download = name;
    document.body.append(link);
    try { link.click(); } finally { link.remove(); }
    setTimeout(() => URL.revokeObjectURL(url), 1000);
    return '';
  } catch (error) { return workbenchError(error).message || 'Generated file download failed.'; }
}
