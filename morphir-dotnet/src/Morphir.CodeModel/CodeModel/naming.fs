namespace Morphir.CodeModel

type CanonicalizedName =
    abstract member ToCanonicalString: string
    abstract member Segments: string list

and [<Struct>] Name =
    | RawName of RawText: string
    | Name of Segments: string list
    | CanonicalName of string

    override self.ToString() =
        match self with
        | RawName raw -> raw
        | Name segments -> String.concat " " segments //TODO: better follow Morphir naming
        | CanonicalName canonical -> canonical

and Path =
    | Path of Name list

    member self.toList() : Name list =
        match self with
        | Path names -> names

and QName =
    | QName of ModulePath: Path * LocalName: Name

    member self.ModulePathSegments: Name list =
        match self with
        | QName(Path names, _) -> names

and PackageName =
    | PackageName of Path

    static let toPath (PackageName path) : Path = path
    member this.ToPath() = toPath this

and ModuleName =
    | ModuleName of Path:Path

    member this.ToPath() =
        match this with
        | ModuleName path -> path

and QualifiedModuleName = QualifiedModuleName of QName

and FQName = FQName of PackageName: PackageName * ModuleName: ModuleName * LocalName: Name

and [<Struct>]Label<'T> = Label of Name

module Path =
    let inline toPath<'T when 'T : (member ToPath: unit -> Path)> (input: 'T) = input.ToPath()

module ModuleName =
    [<CompiledName("ToPath")>]
    let inline toPath ((ModuleName path) as moduleName) = path