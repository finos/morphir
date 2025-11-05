package org.finos.morphir.cli

import com.github.ajalt.clikt.core.*
import java.net.URL 
import org.graalvm.polyglot.Context
import org.graalvm.polyglot.Source
import org.graalvm.polyglot.Value


class WasmRunner(val wasmFilePath: URL?) {
    fun run() {

        val mainModuleSource: Source
        if(wasmFilePath == null) {
            println("No WebAssembly file path provided.")
            val wat = """
                ;; wat2wasm add-two.wat -o add-two.wasm
                (module
                  (func (export "addTwo") (param i32 i32) (result i32)
                    local.get 0
                    local.get 1
                    i32.add
                  )
                )
            """.trimIndent()

            println("Using inline WebAssembly text format module.")
            mainModuleSource = Source.newBuilder("wasm", wat, "inline.wat").build()
        } 
        else {
            println("Using WebAssembly file at: $wasmFilePath")
            mainModuleSource = Source.newBuilder("wasm", wasmFilePath).build()
        }
        Context.create().use { context ->
            val mainModule = context.eval(mainModuleSource)
            val mainInstance = mainModule.newInstance()
            val addTwo = mainInstance.getMember("exports").getMember("add")
            val result = addTwo.execute(40, 2).asInt()
            println("Result of add(40, 2): $result")
        }

    }
}
