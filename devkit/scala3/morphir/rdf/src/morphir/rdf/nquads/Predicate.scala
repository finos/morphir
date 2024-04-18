package morphir.rdf.nquads

import neotype.*
import morphir.rdf.ValidationResult
import morphir.rdf.nquads.internal.lexer
import parsley.Success
import parsley.Failure

case class Predicate(iriRef: IriRef)