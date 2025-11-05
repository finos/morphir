package org.finos.morphir.cli
import com.github.ajalt.clikt.core.*
import com.github.ajalt.clikt.parameters.options.* 
import java.net.URL 

class Morphir:CliktCommand() {
    val wasmFilePath by option(
        "--wasm-file",
        help = "Path to the WebAssembly file to be executed."
    )

    override fun run() {        
        echo("Welcome to Morphir CLI!")
        val wasmFilePath: URL? = if (this.wasmFilePath != null) {
            URL(this.wasmFilePath)
        } else {
            null
        }
        WasmRunner(wasmFilePath).run()
    }
}


fun main(args: Array<String>) {
    Morphir().main(args)
}