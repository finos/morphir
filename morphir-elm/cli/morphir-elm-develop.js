#!/usr/bin/env node
"use strict";

// NPM imports
const path = require("path");
const util = require("util");
const fs = require("fs");
const readFile = util.promisify(fs.readFile);
const fsExists = util.promisify(fs.exists);
const writeFile = util.promisify(fs.writeFile);
const commander = require("commander");
const express = require("express");

// Set up Commander
const program = new commander.Command();
program
  .name("morphir-elm develop")
  .description(
    "Start up a web server and expose developer tools through a web UI"
  )
  .option("-p, --port <port>", "Port to bind the web server to.", "3000")
  .option("-o, --host <host>", "Host to bind the web server to.", "localhost")
  .option(
    "-i, --project-dir <path>",
    "Root directory of the project where morphir.json is located.",
    "."
  )
  .parse(process.argv);

const app = express();
const port = program.opts().port;


const webDir = path.join(__dirname, "web");



app.use(express.static(webDir, { index: false }));
app.use(express.json({limit: "100mb"}));

app.get("/", wrap(async (req, res, next) => {
  res.setHeader('Content-type', 'text/html')
  res.send(await indexHtmlWithVersion());
}));

createSimpleGetJsonApi(app, "morphir.json");
createSimpleGetJsonApi(app, "morphir-ir.json");
createSimpleGetJsonApi(app, "morphir-tests.json", "[]");

app.get(
  "/server/decorations",
  wrap(async (req, res, next) => {
    const configJsonContent = await getDecorationConfig();

    const decorationIDs = Object.keys(configJsonContent);
    let responseJson = {};

    for (const decorationID of decorationIDs) {
      const decorationFilePath = await getDecorationFilePath(decorationID)
      const irFilePath = path.join(
        program.opts().projectDir,
        configJsonContent[decorationID].ir
      );

      if (!(await fsExists(decorationFilePath))) {
        await writeFile(decorationFilePath, "{}");
      }
      const attrFileContent = await readFile(decorationFilePath);
      const irFileContent = await readFile(irFilePath);
      responseJson[decorationID] = {
        data: JSON.parse(attrFileContent.toString()),
        displayName: configJsonContent[decorationID].displayName,
        entryPoint: configJsonContent[decorationID].entryPoint,
        iR: JSON.parse(irFileContent.toString()),
      };
    }
    res.send(responseJson);
  })
);

app.post(
  "/server/update-decoration/:decorationID",
  wrap(async (req, res, next) => {
    const decorationID = req.params.decorationID
    await writeFile(await getDecorationFilePath(decorationID), JSON.stringify(req.body, null, 4))
    res.send(req.body);
  })
);

app.post(
  "/server/morphir-tests.json",
  wrap(async (req, res, next) => {
    const morphirTestsJsonPath = path.join(
      program.opts().projectDir,
      "morphir-tests.json"
    );
    var jsonContent = JSON.stringify(req.body, null, 4);
    await writeFile(morphirTestsJsonPath, jsonContent);
    const morphirTestsJsonContent = await readFile(morphirTestsJsonPath);
    const morphirTestsJson = JSON.parse(morphirTestsJsonContent.toString());
    res.send(morphirTestsJson);
  })
);

app.post(
  "/server/morphir-ir.json",
  wrap(async (req, res, next) => {
    const morphirIRJsonPath = path.join(
      program.opts().projectDir,
      "morphir-ir.json"
    );
    var jsonContent = JSON.stringify(req.body, null, 4);
    await writeFile(morphirIRJsonPath, jsonContent);
    const morphirIRJsonContent = await readFile(morphirIRJsonPath);
    const morphirIRJson = JSON.parse(morphirIRJsonContent.toString());
    res.send(morphirIRJson);
  })
);

app.get("*", wrap(async (req, res, next) => {
  res.setHeader('Content-type', 'text/html')
  res.send(await indexHtmlWithVersion());
}));

app.listen(port, program.opts().host, () => {
  console.log(
    `Developer server listening at http://${program.opts().host}:${port}`
  );
});


// --- Utility Functions ---

function createSimpleGetJsonApi(app, filePath, defaultContent) {
  app.get(
    "/server/" + filePath,
    wrap(async (req, res, next) => {
      const jsonPath = path.join(program.opts().projectDir, filePath);
      try {
        const jsonContent = await readFile(jsonPath);
        res.send(JSON.parse(jsonContent.toString()));
      } catch (err) {
        if (defaultContent && err.code === 'ENOENT') {
          // file does not exist, send default content
          res.send(defaultContent)
        } else {
          throw err
        }
      }
    })
  )
}


async function getMorphirConfig() {
  const filePath = path.join(program.opts().projectDir, "morphir.json")
  const fileContent = await readFile(filePath)
  return JSON.parse(fileContent.toString())
}

async function getDecorationConfig() {
  const morphirConfig = await getMorphirConfig()
  if (morphirConfig.decorations) {
    return morphirConfig.decorations
  } else {
    return []
  }
}

async function getDecorationFilePath(decorationID) {
  const decorationConfig = (await getDecorationConfig())[decorationID]
  let storageLocation = null
  if (decorationConfig.storageLocation) {
    storageLocation = decorationConfig.storageLocation
  } else {
    storageLocation = `${decorationID}.json`
  }
  return path.join(program.opts().projectDir, storageLocation)
}

async function indexHtmlWithVersion() {
  const packageJson = require(path.join(__dirname, '../package.json'))
  const _indexHtml = await readFile(path.join(webDir, "index.html"), 'utf8');
  return _indexHtml.replace('__VERSION_NUMBER__', packageJson.version.toString());

}

function wrap(fn) {
  return (...args) =>
    fn(...args).catch(args[2]);
}
