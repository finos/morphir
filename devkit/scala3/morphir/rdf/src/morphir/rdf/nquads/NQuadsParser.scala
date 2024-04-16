package morphir.rdf.nquads

import neotype.*
import java.io.IOException

class NQuadsParser(options: NQuadsParserSettings) {
  import NQuadsParser.*
  def parse(input: String): ParseResult = {
    ParseResult.succeed(NQuadsDocument.NQuadsDoc())
  }
}

object NQuadsParser:
  val defaultSettings: NQuadsParserSettings = NQuadsParserSettings()

  def parse(input: String)(using parser: NQuadsParser): ParseResult =
    parser.parse(input)

  enum ParsingError:
    case IOError(message: String, cause: Option[IOException])

  type ParseResult = ParseResult.Type
  object ParseResult extends Newtype[Either[ParsingError, NQuadsDocument]]:
    def succeed(doc: NQuadsDocument): ParseResult = ParseResult(Right(doc))
    object Valid:
      def unapply(result: ParseResult): Option[NQuadsDocument] =
        result.unwrap.toOption

  extension (result: ParseResult)
    def isValid: Boolean = result.unwrap.isRight
    def isInvalid: Boolean = result.unwrap.isLeft
end NQuadsParser

case class NQuadsParserSettings()
