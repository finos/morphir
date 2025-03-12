package org.finos.morphir.cli

import com.github.ajalt.clikt.core.*
import com.github.ajalt.clikt.parameters.options.*
import com.github.ajalt.clikt.parameters.types.int

fun main(args: Array<String>) = Hello().main(args)

class Hello : CliktCommand() {
    val count: Int by option().int().default(1).help("Number of greetings")
    val name: String by option().prompt("Your name").help("The person to greet")

    override fun run() {
        repeat(count) {
            echo("Hello $name!")
        }
    }
}