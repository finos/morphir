package morphir.rdf.nquads

import neotype.*
import morphir.rdf.ValidationResult
import morphir.rdf.nquads.internal.lexer
import parsley.Success
import parsley.Failure

case class NQuadsDocument private (
    firstStatement: NQuadsStatement,
    otherStatements: List[NQuadsStatement]
) {
  lazy val statements: Vector[NQuadsStatement] =
    (firstStatement :: otherStatements).toVector
}

object NQuadsDocument:
  def apply(
      statement: NQuadsStatement,
      otherStatements: NQuadsStatement*
  ): NQuadsDocument =
    NQuadsDocument(statement, otherStatements.toList)
