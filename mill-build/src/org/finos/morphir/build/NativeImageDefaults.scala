package org.finos.morphir.build
import mill._, mill.scalalib._

import io.github.alexarchambault.millnativeimage.NativeImage

trait NativeImageDefaults extends NativeImage with JavaModule {
  def nativeImageClassPath    = runClasspath()
  def nativeImageGraalVmJvmId = "graalvm-java22:22.0.2"
  def nativeImageOptions = Seq(
    "--no-fallback",
    "--enable-url-protocols=http,https",
    "-Djdk.http.auth.tunneling.disabledSchemes=",
    "-H:+UnlockExperimentalVMOptions",
    "-H:Log=registerResource:5",
    "-H:+BuildReport"
  ) ++ (if (sys.props.get("os.name").contains("Linux")) Seq("--static") else Seq.empty)
}
