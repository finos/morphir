package morphir.sdk

import zio.test._
import morphir.testing.MorphirBaseSpec
object RegexSpec extends MorphirBaseSpec {

  val splitPattern: Regex.Regex =
    Maybe.withDefault(Regex.never)(Regex.fromString("""[^\w\s]+"""))

  val splitScenarios = Seq(
    ("morphir.sdk", List("morphir", "sdk")),
    ("morphir:sdk", List("morphir", "sdk"))
  )

  val wordPattern: Regex.Regex =
    Maybe.withDefault(Regex.never)(Regex.fromString("""([a-zA-Z][a-z]*|[0-9]+)"""))

  val findScenarios = Seq(
    ("Morphir", List("Morphir")),
    ("SDK", List("S", "D", "K")),
    ("camelCaseName", List("camel", "Case", "Name"))
  )

  def spec = suite("Regex Spec")(
    suite(s"""Regex.split with $splitPattern pattern""")(
      splitScenarios.map { case (testString, expectedOutput) =>
        test(s"""split("$testString") == $expectedOutput""") {
          assert(Regex.split(splitPattern)(testString))(
            Assertion.equalTo(expectedOutput)
          )
        }
      }: _*
    ),
    suite(s"""Regex.find with $wordPattern pattern""")(
      findScenarios.map { case (testString, expectedOutput) =>
        test(s"""find("$testString").map(_.match) == $expectedOutput""") {
          assert(
            Regex
              .find(wordPattern)(testString)
              .map(_._match)
          )(
            Assertion.equalTo(expectedOutput)
          )
        }
      }: _*
    )
  )
}
