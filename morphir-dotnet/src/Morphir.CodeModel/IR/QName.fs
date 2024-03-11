module Morphir.IR.QName

open Morphir.IR.Name
open Morphir.IR.Path
open Morphir.SDK

type QName = QName of modulePath: Path * localName: Name

let qName (modulePath: Path) (localName: Name) = QName(modulePath, localName)

/// Turn a qualified name into a tuple.
let toTuple (QName(path, name) as qName) = (path, name)

/// Turn a tuple into a qualified name.
let fromTuple =
    function
    | (path, name) -> QName(path, name)

/// Create a qualified name.
let fromName modulePath localName = QName(modulePath, localName)

/// Get the module path part of a qualified name.
let getModulePath (QName(modulePath, _) as qName) = modulePath

/// Get the local name part of a qualified name.
let getLocalName (QName(_, localName) as qName) = localName

/// Turn a QName into a string using ':' as a separator between module and local names.
let toString (QName(moduleName, localName) as qName) =
    String.join ":" [ Path.toString Name.toTitleCase "." moduleName; Name.toCamelCase localName ]
