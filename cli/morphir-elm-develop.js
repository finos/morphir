#!/usr/bin/env node
'use strict'

// NPM imports
const path = require('path')
const util = require('util')
const fs = require('fs')
const readFile = util.promisify(fs.readFile)
const writeFile = util.promisify(fs.writeFile)
const commander = require('commander')
const express = require('express')
const csrf = require('csurf')
const cookieParser = require('cookie-parser')
const csrfProtection = csrf({ cookie: true})

// Set up Commander
const program = new commander.Command()
program
  .name('morphir-elm develop')
  .description('Start up a web server and expose developer tools through a web UI')
  .option('-p, --port <port>', 'Port to bind the web server to.', '3000')
  .option('-o, --host <host>', 'Host to bind the web server to.', '0.0.0.0')
  .option('-i, --project-dir <path>', 'Root directory of the project where morphir.json is located.', '.')
  .parse(process.argv)

const app = express()
const port = program.opts().port

const wrap = fn => (...args) => fn(...args).catch(args[2])

const webDir = path.join(__dirname, 'web')
const indexHtml = path.join(webDir, 'index.html')

const createSimpleGetJsonApi = (filePath) => {
  app.get('/server/' + filePath, wrap(async (req, res, next) => {
    const jsonPath = path.join(program.opts().projectDir, filePath)
    const jsonContent = await readFile(jsonPath)
    res.send(JSON.parse(jsonContent.toString()))
  }))
}

app.use(express.static(webDir))
app.use(express.json());
app.use(cookieParser())
app.use(csrfProtection)

app.get('/', (req, res) => {
  res.sendFile(indexHtml)
})

createSimpleGetJsonApi('morphir.json')
createSimpleGetJsonApi('morphir-ir.json')
createSimpleGetJsonApi('morphir-tests.json')

app.get('/server/attributesconf', wrap(async (req, res, next) => {
  const attributeName = req.params.attributename.toString()
  const configPath = path.join(program.opts().projectDir, attributeName + 'attributes.conf.json')
  const fileContent = await readFile(configPath)
  const jsonContent = JSON.parse(fileContent.toString())
  res.send(jsonContent)
}))

app.get('/server/attributefiles/:attribute', wrap(async (req, res, next) => {
  const attributeFilePath = path.join(program.opts().projectDir, req.params.attributename + '-attribute.json')
  const jsonContent = await readFile(attributeFilePath)
  res.send(JSON.parse(jsonContent.toString()))
}))

app.post('/server/updateattribute', wrap(async (req, res, next) => {
  const attributeFilePath = path.join(program.opts().projectDir, req.params.attributename + '-attribute.json')
  const jsonContent = await readFile(attributeFilePath)

  jsonContent[req.body.nodeId.toString()] = req.body.newAttribute.toString()
  await writeFile(attributeFilePath, jsonContent)

  const updatedJson = await readFile(morphirTestsJsonPath)
  res.send(JSON.parse(updatedJson.toString()))
}))

app.post('/server/morphir-tests.json', wrap(async (req, res, next) => {
  const morphirTestsJsonPath = path.join(program.opts().projectDir, 'morphir-tests.json')
  var jsonContent = JSON.stringify(req.body, null, 4)
  await writeFile(morphirTestsJsonPath, jsonContent)
  const morphirTestsJsonContent = await readFile(morphirTestsJsonPath)
  const morphirTestsJson = JSON.parse(morphirTestsJsonContent.toString())
  res.send(morphirTestsJson)
}))

app.get('*', (req, res) => {
  res.sendFile(indexHtml)
})

app.listen(port, program.opts().host, () => {
  console.log(`Developer server listening at http://${program.opts().host}:${port}`)
})
