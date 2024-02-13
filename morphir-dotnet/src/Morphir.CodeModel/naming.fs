namespace Morphir.CodeModel

type CanonicalizedName =
    abstract member ToCanonicalString: string
    abstract member Segments: string list

type Name =
    | RawName of RawText: string
    | Name of Segments: string list
    | CanonicalName of string

    override self.ToString() =
        match self with
        | RawName raw -> raw
        | Name segments -> String.concat "." segments //TODO: better follow Morphir naming
        | CanonicalName canonical -> canonical

type Path =
    | Path of Name list

    member self.toList() : Name list =
        match self with
        | Path names -> names

type QName =
    | QName of Namespace: Path * LocalName: Name

    member self.NamespaceSegments: Name list =
        match self with
        | QName(Path names, _) -> names

type PackageName = PackageName of QName

type ModuleName = ModuleName of Path
type QualifiedModuleName = QualifiedModuleName of QName

type FQName = FQName of PackageName: PackageName * ModuleName: ModuleName * LocalName: Name


type Label<'T> = Label of Name
