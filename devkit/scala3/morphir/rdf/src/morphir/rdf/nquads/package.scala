package morphir.rdf.nquads

import neotype.*
import morphir.rdf.ValidationResult
import morphir.rdf.nquads.internal.lexer
import parsley.Success
import parsley.Failure

type LangTag = LangTag.Type
object LangTag extends Newtype[String]:
  override inline def validate(value: String): ValidationResult =
    if value.matches("[a-zA-Z]+(-[a-zA-Z0-9]+)*") then true
    else s"Invalid language tag: $value"

  def parse(value: String): Either[String, LangTag] =
    lexer.LANGTAG.parse(value).map(unsafeMake(_)).toEither

type Hex = Hex.Type
object Hex extends Newtype[Char]:
  override inline def validate(value: Char): ValidationResult =
    if value.isDigit || (value >= 'A' && value <= 'F') || (value >= 'a' && value <= 'f')
    then true
    else s"Invalid hex character: $value"

