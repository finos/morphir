module Morphir.CodeModel.Versioning

open Morphir.Extensions

type Version =
    | FullSemanticVersion of Major: int * Minor: int * Patch: int * PreRelease: string option * Build: string option
    | MajorVersion of Major: int
    | MajorMinorVersion of Major: int * Minor: int
    | ThreePartVersion of Major: int * Minor: int * Patch: int
    | PreReleaseVersion of Major: int * Minor: int * Patch: int * PreRelease: string * Build: string option

and SemanticVersion =
    { Major: int
      Minor: int
      Patch: int
      PreRelease: string option
      Build: string option }

and PartialVersion =
    { Major: int option
      Minor: int option
      Patch: int option
      PreRelease: string option
      Build: string option }

    member x.Tupled() =
        (x.Major, x.Minor, x.Patch, x.PreRelease, x.Build)

type VersioningError =
    | InvalidVersionNumber of string
    | InvalidMajorVersion of string
    | InvalidMinorVersion of string
    | InvalidPatch of string
    | InvalidPreRelease of string
    | InvalidBuild of string
    | InvalidVersion of PartialVersion



let partialVersionToVersion (partialVersion: PartialVersion) : Result<Version, VersioningError> =
    match partialVersion.Tupled() with
    | (Some major, Some minor, Some patch, (Some(StringWithContent preRelease)), build) ->
        Ok(PreReleaseVersion(major, minor, patch, preRelease, build))
    | (Some major, Some minor, Some patch, None, None) -> Ok(ThreePartVersion(major, minor, patch))
    | (Some major, Some minor, Some patch, preRelease, build) ->
        Ok(FullSemanticVersion(major, minor, patch, preRelease, build))
    | (Some major, None, None, _, _) -> Ok(MajorVersion(major))
    | (Some major, Some minor, None, _, _) -> Ok(MajorMinorVersion(major, minor))
    | _ -> Error(InvalidVersion partialVersion)
