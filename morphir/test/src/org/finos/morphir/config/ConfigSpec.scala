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
    }
  )
