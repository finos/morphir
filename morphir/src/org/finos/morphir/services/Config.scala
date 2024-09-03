package org.finos.morphir.services
import org.finos.morphir.Path
import kyo.{Path as _, *}
import org.finos.morphir.VirtualPath

trait Config:
  def morphirHomeDir: Path

object Config:
  final case class Live(morphirHomeDir: Path) extends Config
  object Live
  // private def makeLayer =
  //     defer {
  //         val system = await(Env.get[Sys])
  //         val
  //     }
  // val layer: Layer [Config, System] =
  //     Layer {
  //         Env.get[Sys].map { sys =>
  //         val morphirHomeDir = sys.env.map(_.getOrElse("MORPHIR_HOME", "~/").map(VirtualPath.parse(_)))

  //         }
  //     }
