package org.finos.morphir.lang.elm

import kyo.*
import kyo.Result
import metaconfig.{pprint as _, *}
import metaconfig.generic.*
import neotype.*
import org.finos.morphir.*
import org.finos.morphir.config.{given, *}
import org.finos.morphir.api.MajorVersionNumber
import org.finos.morphir.api.MinorVersionNumber
import org.finos.morphir.api.PatchVersionNumber
import metaconfig.Configured.Ok
import metaconfig.Configured.NotOk
import neotype.*
import neotype.interop.jsoniter.{given, *}
import com.github.plokhotnyuk.jsoniter_scala.macros.*
import com.github.plokhotnyuk.jsoniter_scala.core.*
import com.github.plokhotnyuk.jsoniter_scala.macros.JsonCodecMaker.*
import io.bullet.borer.Json

type ElmDependencyMap = ElmDependencyMap.Type

object ElmDependencyMap extends Subtype[Map[ElmPackageName, ElmPackageVersion]]:
  given confDecoder: ConfDecoder[ElmDependencyMap] =
    ConfDecoder[Map[String, ElmPackageVersion]]
      .transformKeys[ElmPackageName](key => ElmPackageName.parseAsConfigured(key))
      .map(unsafeMake(_))

  given jsonValueCodec: JsonValueCodec[ElmDependencyMap] =
    subtypeCodec[Map[ElmPackageName, ElmPackageVersion], ElmDependencyMap]
end ElmDependencyMap
