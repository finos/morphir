import {
  ElmCompilerOptions,
  MorphirProjectManifest,
  VirtualFile,
} from "./compiler/types";
import * as Dependencies from "./dependencies";
import {
  type FileChanges,
  type FileChange,
  calculateContentHash,
} from "./FileChanges";

export function compileVirtualFiles(
  files: VirtualFile[],
  projectManifest: MorphirProjectManifest,
  options: ElmCompilerOptions
) {
  const changes = virtualFilesToFileChanges(...files);
  //TODO: Load dependencies and such
  return {};
}

function virtualFilesToFileChanges(...files: VirtualFile[]): FileChanges {
  const fileChanges = new Map<string, FileChange>();
  files.forEach((file) => {
    const hash = calculateContentHash(file.content);
    fileChanges.set(file.path, { kind: "Insert", content: file.content, hash });
  });
  return fileChanges;
}
