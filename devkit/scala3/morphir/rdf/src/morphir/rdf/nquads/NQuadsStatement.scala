package morphir.rdf.nquads

import neotype.*
import morphir.rdf.ValidationResult
import morphir.rdf.nquads.internal.lexer
import parsley.Success
import parsley.Failure

case class NQuadsStatement(
    subject: Any,
    predicate: Predicate,
    obj: Any,
    graph: Option[Any]
):
  inline def `object`: Any = obj
