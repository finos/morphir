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
  const _changes = virtualFilesToFileChanges(...files);
  console.log("changes: ", _changes);
  //TODO: Load dependencies and such
  const loadOptions = {
    ...projectManifest,
    localDependencies: projectManifest.localDependencies || [],
    dependencies: projectManifest.dependencies || [],
    includes: options.include || [],
  };
  Dependencies.loadAllDependencies(loadOptions);
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
