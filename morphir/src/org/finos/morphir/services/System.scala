package org.finos.morphir.services

import org.finos.morphir.Path
import kyo.{Path as _, *}

trait System:
  def env(variable: => String): Option[String] < (IO & Abort[SecurityException])
  def envOrElse(variable: => String, alt: => String): String < (IO & Abort[SecurityException])
  def envOrOption(variable: => String, alt: => Option[String]): Option[String] < (IO & Abort[SecurityException])
  def envs: Map[String, String] < (IO & Abort[SecurityException])

object System:
  val layer: Layer[System, Any] =
    Layer {
      SystemLive
    }

  object SystemLive extends System:
    def env(variable: => String): Option[String] < (IO & Abort[SecurityException]) =
      val effect = IO(sys.env.get(variable))
      Abort.catching[SecurityException](effect)
    def envOrElse(variable: => String, alt: => String): String < (IO & Abort[SecurityException]) =
      val effect = IO(sys.env.getOrElse(variable, alt))
      Abort.catching[SecurityException](effect)
    def envOrOption(variable: => String, alt: => Option[String]): Option[String] < (IO & Abort[SecurityException]) =
      val effect = IO(sys.env.get(variable).orElse(alt))
      Abort.catching[SecurityException](effect)
    def envs: Map[String, String] < (IO & Abort[SecurityException]) =
      val effect = IO(sys.env)
      Abort.catching[SecurityException](effect)
