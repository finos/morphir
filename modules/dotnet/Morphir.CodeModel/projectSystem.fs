namespace Morphir.CodeModel.ProjectSystem

type ProjectName = string
type SourceDirectoryPath = string
type LocalDependency =
    | LocalDependency of string
type Dependency =
    | Dependency of string

type EntryPoint =
    | FQName of string
    //|FQNameUrl of string

type IRLocation = IRLocation of string
type StorageLocation = StorageLocation of string

type DecorationInfo =
    {
        DisplayName: string
        EntryPoint: EntryPoint
        IR: IRLocation
        StorageLocation: StorageLocation
    }

type MorphirProject = {
    Name: ProjectName
    SourceDirectory: SourceDirectoryPath
    LocalDependencies: LocalDependency list
    Dependencies: Dependency list
    Decorations: Map<string, DecorationInfo>
}

//TODO: Flesh out the MorphirManifest type
type MorphirManifest = MorphirManifest