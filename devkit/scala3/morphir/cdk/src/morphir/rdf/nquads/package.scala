package morphir.rdf.nquads
import neotype.*

type LangTag = LangTag.Type
object LangTag extends Newtype[String]:
  override inline def validate(value: String): ValidationResult =
    if value.matches("[a-zA-Z]+(-[a-zA-Z0-9]+)*") then true
    else s"Invalid language tag: $value"

type IriRef = IriRef.Type
object IriRef extends Newtype[String]:
  override inline def validate(value: String): ValidationResult =
    if value.matches("<[^<>'\"{}|^`\\x00-\\x20]*>") then true
    else s"Invalid IRI reference: $value"

type Hex = Hex.Type
object Hex extends Newtype[Char]:
  override inline def validate(value: Char): ValidationResult =
    if value.isDigit || (value >= 'A' && value <= 'F') || (value >= 'a' && value <= 'f')
    then true
    else s"Invalid hex character: $value"

class NQuadsParser()
