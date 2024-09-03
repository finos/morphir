package org.finos.morphir.services

import org.finos.morphir.Path
import kyo.{Path as _, *}

trait System:
    def env(variable: => String): Option[String] < (IO & Abort[SecurityException])        
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
        def envs: Map[String, String] < (IO & Abort[SecurityException]) = 
            val effect = IO(sys.env)
            Abort.catching[SecurityException](effect)            
        