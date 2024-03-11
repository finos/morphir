module Morphir.IR.KindOfName

/// <summary>
/// Type that represents what kind of thing a local name refers to. Is it a type, a constructor or a value?
/// </summary>
type KindOfName =
    | Type
    | Constructor
    | Value
