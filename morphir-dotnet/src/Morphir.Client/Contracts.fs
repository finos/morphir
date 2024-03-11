module Morphir.Client.Contracts

open System.Collections.Generic
open System.Threading.Tasks
open Morphir.CodeModel

[<RequireQualifiedAccess>]
module Methods =
    [<Literal>]
    let Version = "morphir/version"

type TextRange =
    { StartLine: int
      StartColumn: int
      EndLine: int
      EndColumn: int }

type DiagnosticSeverity =
    | Error = 1
    | Warning = 2
    | Information = 3
    | Hint = 4

[<NoComparison>]
type Diagnostic =
    { Message: string
      Severity: DiagnosticSeverity
      SourcePath: string option
      Range: TextRange option }

type CompilationResult =
    | ClassicIR of string
    | IR of string
    | Failure

[<NoComparison>]
type CompileDocumentRequest =
    { SourceCode: string
      FilePath: string
      Config: IReadOnlyDictionary<string, string> option }

[<NoComparison>]
type CompilationResponse =
    { CompilationResult: CompilationResult
      Diagnostics: Diagnostic list }

type PushDistribution =
    { Package: string
      Version: Versioning.Version }

type MorphirService =
    interface
        abstract member VersionAsync: unit -> Task<string>
        abstract member CompileAsync: CompileDocumentRequest -> Task<CompilationResponse>
    end
