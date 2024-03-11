[<AutoOpen>]
module Morphir.Live.Stores

open Fun.Blazor

type IShareStore with
    member store.IsDark = store.CreateCVal("IsDark", true)
    
type GlobalStore with
    end
