package org.finos.morphir.build
import just.semver.SemVer

import upickle.default.{ReadWriter => RW, macroRW}
import upickle.implicits.key 
import org.finos.morphir.build.elm.api.ElmPickler

final case class Version(underlying:SemVer) {
    override def toString:String = SemVer.render(underlying)
}
object Version {
    implicit val rw:RW[Version] = implicitly[RW[String]].bimap(
        v => SemVer.render(v.underlying),
        str => Version(SemVer.unsafeParse(str))
    )
    implicit val readWriter:ElmPickler.ReadWriter[Version] = implicitly[ElmPickler.ReadWriter[String]].bimap(
        v => SemVer.render(v.underlying),
        str => Version(SemVer.unsafeParse(str))
    )
}
