package org.finos.morphir.config
import kyo.*
import org.finos.morphir.testing.*
import metaconfig.{pprint as _, *}
import metaconfig.sconfig.*
import zio.test.{Result as _, *}
object ConfigSpec extends MorphirSpecDefault:
  def spec = suite("ConfigSpec")(
    preludeSuite,
    workspaceMembersSuite
  )

  def workspaceMembersSuite = suite("Workspace Members")(
    test("Workspace should be able to be loaded") {
      val workspaceFilePath       = os.resource / "org" / "finos" / "morphir" / "config" / "workspace-01.conf"
      val contents: String        = os.read(workspaceFilePath)
      val input: metaconfig.Input = Input.String(contents)
      val result                  = MorphirConfig.parseInput(input)
      pprint.log(result)
      assertTrue(
        result.isSuccess,
        result.value.get.containsWorkspace == true,
        result.value.get.workspaceProjects == IndexedSeq("common", "project-01", "project-02")
      )
    }
  )

  def preludeSuite = suite("Prelude")(
    test("Should be able to convert an Either[Throwable, A] to a Configured[A] with a success result") {
      val result: Either[Throwable, Int] = Right(42)
      val configured: Configured[Int]    = result.toConfigured()
      assertTrue(configured == Configured.Ok(42))
    },
    test("Should be able to convert an Either[Throwable, A] to a Configured[A] with a failure result") {
      val result: Either[Throwable, Int] = Left(new Throwable("An error occurred"))
      val configured: Configured[Int]    = result.toConfigured()
      assertTrue(configured == Configured.exception(new Throwable("An error occurred")))
    },
    test("Should be able to convert an Either[String, A] to a Configured[A] with a success result") {
      val result: Either[String, Int] = Right(42)
      val configured: Configured[Int] = result.toConfigured()
      assertTrue(configured == Configured.Ok(42))
    },
    test("Should be able to convert an Either[String, A] to a Configured[A] with a failure result") {
      val result: Either[String, Int] = Left("An error occurred")
      val configured: Configured[Int] = result.toConfigured()
      assertTrue(configured == Configured.error("An error occurred"))
    },
    test("Should be able to convert a Result[Throwable, A] to a Configured[A] with a success result") {
      val result: Result[Throwable, Int] = Result.success(42)
      val configured: Configured[Int]    = result.toConfigured()
      assertTrue(configured == Configured.Ok(42))
    },
    test("Should be able to convert a Result[Throwable, A] to a Configured[A] with a failure result") {
      val result: Result[Throwable, Int] = Result.fail(new Throwable("An error occurred"))
      val configured: Configured[Int]    = result.toConfigured()
      assertTrue(configured == Configured.exception(new Throwable("An error occurred")))
    },
    test("Should be able to convert a Result[Throwable, A] with a panic to a Configured[A] with a failure result") {
      val result: Result[Throwable, Int] = Result.panic(new Throwable("Oh No!!!!"))
      val configured: Configured[Int]    = result.toConfigured()
      assertTrue(configured == Configured.exception(new Throwable("Oh No!!!!")))
    },
    test("Should be able to convert a Result[String, A] to a Configured[A] with a success result") {
      val result: Result[String, Int] = Result.success(42)
      val configured: Configured[Int] = result.toConfigured()
      assertTrue(configured == Configured.Ok(42))
    },
    test("Should be able to convert a Result[String, A] to a Configured[A] with a failure result") {
      val result: Result[String, Int] = Result.fail("An error occurred")
      val configured: Configured[Int] = result.toConfigured()
      assertTrue(configured == Configured.error("An error occurred"))
    },
    suite("ConfDecoder[Map[String,?]]")(
      test("Should be able to transform keys successfully when all are valid") {
        case class Key(value: String)
        val decoder: ConfDecoder[Map[String, Int]] = ConfDecoder[Map[String, Int]]
        val input                                  = Conf.parseString("a: 1\nb: 2\nc: 3")
        val expected: Map[Key, Int]                = Map(Key("a") -> 1, Key("b") -> 2, Key("c") -> 3)
        val newDecoder: ConfDecoder[Map[Key, Int]] = decoder.transformKeys((key: String) => Configured.Ok(Key(key)))
        val actual: Configured[Map[Key, Int]]      = newDecoder.read(input)
        assertTrue(actual == Configured.Ok(expected))
      },
      test("Should fail if any transform fails") {
        case class Key(value: String):
          def parse: Configured[Key] =
            if value == "b" then Configured.error("b is not allowed") else Configured.Ok(this)
        val decoder: ConfDecoder[Map[String, Int]] = ConfDecoder[Map[String, Int]]
        val input                                  = Conf.parseString("a: 1\nb: 2\nc: 3")
        val newDecoder: ConfDecoder[Map[Key, Int]] = decoder.transformKeys((key: String) => Key(key).parse)
        val actual: Configured[Map[Key, Int]]      = newDecoder.read(input)
        assertTrue(actual == Configured.error("b is not allowed"))
      },
      test("Should fail with all errors when multiple keys fail") {
        case class Key(value: String):
          def parse: Configured[Key] = value match
            case "b" => Configured.error("b is not allowed")
            case "c" => Configured.error("c is not allowed")
            case _   => Configured.Ok(this)
        val decoder: ConfDecoder[Map[String, Int]] = ConfDecoder[Map[String, Int]]
        val input                                  = Conf.parseString("a: 1\nb: 2\nc: 3\nd: 4")
        val newDecoder: ConfDecoder[Map[Key, Int]] = decoder.transformKeys((key: String) => Key(key).parse)
        val actual: Configured[Map[Key, Int]]      = newDecoder.read(input)
        val expectedError = ConfError.message("c is not allowed").combine(ConfError.message("b is not allowed"))
        assertTrue(actual == Configured.NotOk(expectedError))
      }
    )
  )
