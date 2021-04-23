#!/usr/bin/env node
'use strict'

// NPM imports
const path = require('path')
const util = require('util')
const fs = require('fs')
const readFile = util.promisify(fs.readFile)
const commander = require('commander')
const express = require('express')

// Set up Commander
const program = new commander.Command()
program
  .name('morphir-elm develop')
  .description('Start up a web server and expose developer tools through a web UI')
  .option('-p, --port <port>', 'Port to bind the web server to.', '3000')
  .option('-i, --project-dir <path>', 'Root directory of the project where morphir.json is located.', '.')
  .parse(process.argv)

const app = express()
const port = program.port

const wrap = fn => (...args) => fn(...args).catch(args[2])

const webDir = path.join(__dirname, 'web')
const indexHtml = path.join(webDir, 'index.html')

app.get('/', (req, res) => {
  res.sendFile(indexHtml)
})

app.use(express.static(webDir))

app.get('/server/morphir.json', wrap(async (req, res, next) => {
  const morphirJsonPath = path.join(program.projectDir, 'morphir.json')
  const morphirJsonContent = await readFile(morphirJsonPath)
  const morphirJson = JSON.parse(morphirJsonContent.toString())
  res.send(morphirJson)
}))

app.get('/server/morphir-ir.json', wrap(async (req, res, next) => {
  const morphirJsonPath = path.join(program.projectDir, 'morphir-ir.json')
  const morphirJsonContent = await readFile(morphirJsonPath)
  const morphirJson = JSON.parse(morphirJsonContent.toString())
  res.send(morphirJson)
}))

app.get('/server/morphir-tests.json', wrap(async (req, res, next) => {
  const morphirTestsJsonPath = path.join(program.projectDir, 'morphir-tests.json')
  const morphirTestsJsonContent = await readFile(morphirTestsJsonPath)
  const morphirTestsJson = JSON.parse(morphirTestsJsonContent.toString())
  res.send(morphirTestsJson)
}))

app.get('*', (req, res) => {
  res.sendFile(indexHtml)
})

app.listen(port, () => {
  console.log(`Developer server listening at http://localhost:${port}`)
})
