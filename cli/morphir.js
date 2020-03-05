'use strict'

const worker = require('./Morphir.Elm.CLI').Elm.Morphir.Elm.CLI.init()


worker.ports.output.subscribe(res => {
    console.log(res)
})

worker.ports.input.send({foo: "bar"})