//> using dep com.github.j-mie6::parsley:4.5.2
//> using dep "com.lihaoyi::pprint:0.9.0"

import parsley.Parsley.{atomic, many, some}
import parsley.character.{endOfLine, letter, hexDigit, oneOf, stringOfSome}
import parsley.syntax.character.{charLift, stringLift}
import parsley.character
import parsley.expr.chain

// LANGTAG	::=	'@' [a-zA-Z]+ ('-' [a-zA-Z0-9]+)*
val LANGTAG = {
  val asciiLowerChar = oneOf('a' to 'z')
  val asciiUpperChar = oneOf('A' to 'Z')
  val asciiChar = asciiLowerChar | asciiUpperChar
  val digit = oneOf('0' to '9')
  val alphaNumeric = asciiChar | digit
  val start = atomic('@' ~> some(asciiChar)).span
  val tail =
    atomic(many('-' ~> some(alphaNumeric))).span
  val langtag = atomic((start <~> tail)).span
  langtag
}

pprint.pprintln("---------------------------------------------")
pprint.pprintln(LANGTAG.parse("@en"))
pprint.pprintln(LANGTAG.parse("@en-GB01-oxendict-1997"))
pprint.pprintln(LANGTAG.parse("xyz"))

//pprint.pprintln(langtag.parse("@en"))
// pprint.pprintln(langtag.parse("@en-GB"))
// pprint.pprintln(langtag.parse("@en-Latn-GB"))
// pprint.pprintln(langtag.parse("@de-DE-u-co-phonebk"))
// pprint.pprintln(langtag.parse("@zh-cmn-Hans-CN-x-private03-1996"))
