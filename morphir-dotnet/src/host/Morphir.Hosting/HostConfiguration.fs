namespace Morphir.Host

open System

type Location =
    | Local of Path: string
    | Remote of LocationUri : Uri

type HostConfiguration =
    { Extensions: HostExtensionsConfiguration }
    static let countVowelsExtensionLocation = Uri("https://github.com/extism/plugins/releases/latest/download/count_vowels.wasm") |> Remote
    static member Default = { Extensions = {ExtensionsSearchLocations = [countVowelsExtensionLocation] } }
and HostExtensionsConfiguration =
    { ExtensionsSearchLocations: Location list }
    
module HostConfiguration =
    let Default = HostConfiguration.Default