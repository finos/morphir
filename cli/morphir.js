'use strict'

const worker = require('./Morphir.Elm.CLI').Elm.Morphir.Elm.CLI.init()


worker.ports.decodeError.subscribe(res => {
    console.error(res)
})

worker.ports.packageDefinitionFromSourceResult.subscribe(res => {
    console.log(JSON.stringify(res))
})


const packageInfo = {
    name: "morphir/sdk",
    exposedModules: ["A"]
}

const sourceFiles = [
    { path: "A.elm"
    , content: "module A exposing (..)"
    }
]

worker.ports.packageDefinitionFromSource.send([packageInfo, sourceFiles])