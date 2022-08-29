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

async function getAttributeConfigJson() {
  const configPath = path.join(program.opts().projectDir,'attributes.conf.json')
  const fileContent = await readFile(configPath)
  return JSON.parse(fileContent.toString())
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

app.get('/server/csrf', csrfProtection, function(req, res) {
  // Generate a tocken and send it to the view
  res.send({ csrfToken: req.csrfToken() })
})

app.get('/server/attributes', wrap(async (req, res, next) => {
  const configJsonContent = await getAttributeConfigJson()

  const attributeNames = Object.keys(configJsonContent)
  let responseJson = {}

  for (const attrName of attributeNames){
    const attrFilePath = path.normalize(configJsonContent[attrName].filePath)
    const attrFileContent = await readFile(attrFilePath)
    responseJson[attrName] = JSON.parse(attrFileContent.toString())
  };
  res.send(responseJson)
}))


app.post('/server/updateattribute', wrap(async (req, res, next) => {
  const configJsonContent = await getAttributeConfigJson()
  const attrFilePath = path.normalize(configJsonContent[req.params.attributename].filePath)
  const jsonContent = await readFile(attrFilePath)

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
