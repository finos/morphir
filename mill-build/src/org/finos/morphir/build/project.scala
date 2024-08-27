package org.finos.morphir.build
import mill._ 

trait MorphirBaseProject extends Module {
    def projectName:T[String]           = T{ projectNameParts().mkString("-") }
    def projectNameParts:T[Seq[String]] = T{ millModuleSegments.parts }
}