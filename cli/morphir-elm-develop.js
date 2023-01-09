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
  .option("-o, --host <host>", "Host to bind the web server to.", "0.0.0.0")
  .option(
    "-i, --project-dir <path>",
    "Root directory of the project where morphir.json is located.",
    "."
  )
  .parse(process.argv);

const app = express();
const port = program.opts().port;

const wrap =
  (fn) =>
  (...args) =>
    fn(...args).catch(args[2]);


async function indexHtmlWithVersion () {
  const packageJson = require(path.join(__dirname, '../package.json'))
  const _indexHtml = await readFile (path.join(webDir, "index.html"), 'utf8');
  return _indexHtml.replace('__VERSION_NUMBER__', packageJson.version.toString());

}
const webDir = path.join(__dirname, "web");

const createSimpleGetJsonApi = (filePath) => {
  app.get(
    "/server/" + filePath,
    wrap(async (req, res, next) => {
      const jsonPath = path.join(program.opts().projectDir, filePath);
      const jsonContent = await readFile(jsonPath);
      res.send(JSON.parse(jsonContent.toString()));
    })
  );
};


async function getAttributeConfigJson() {
  const configPath = path.join(
    program.opts().projectDir,
    "attributes.conf.json"
  );
  try {
    const fileContent = await readFile(configPath);
    return JSON.parse(fileContent.toString());
  } catch (ex) {
    console.error(ex);
    return {};
  }
}

app.use(express.static(webDir, {index: false}));
app.use(express.json());

app.get("/", wrap (async (req, res, next) => {
  res.setHeader('Content-type', 'text/html')
  res.send(await indexHtmlWithVersion());
}));

createSimpleGetJsonApi("morphir.json");
createSimpleGetJsonApi("morphir-ir.json");
createSimpleGetJsonApi("morphir-tests.json");

app.get(
  "/server/attributes",
  wrap(async (req, res, next) => {
    const configJsonContent = await getAttributeConfigJson();

    const attributeIds = Object.keys(configJsonContent);
    let responseJson = {};

    for (const attrId of attributeIds) {
      const attrFilePath = path.join(
        program.opts().projectDir,
        "attributes",
        attrId + ".json"
      );
      const irFilePath = path.join(
        program.opts().projectDir,
        configJsonContent[attrId].ir
      );

      if (!(await fsExists(attrFilePath))) {
         await writeFile(attrFilePath, "{}");
      }
      const attrFileContent = await readFile(attrFilePath);
      const irFileContent = await readFile(irFilePath);
      responseJson[attrId] = {
         data: JSON.parse(attrFileContent.toString()),
         displayName: configJsonContent[attrId].displayName,
         entryPoint: configJsonContent[attrId].entryPoint,
         iR: JSON.parse(irFileContent.toString()),
      };
    }
    res.send(responseJson);
  })
);

app.post(
  "/server/updateattribute/:attrId",
  wrap(async (req, res, next) => {
    const attrFilePath = path.join(
      program.opts().projectDir,
      "attributes",
      req.params.attrId + ".json"
    );

    await writeFile(attrFilePath, JSON.stringify(req.body, null, 4));

    const updatedJson = await readFile(attrFilePath);
    res.send(updatedJson);
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

app.get("*", wrap (async (req, res, next) => {
  res.setHeader('Content-type', 'text/html')
  res.send(await indexHtmlWithVersion());
}));

app.listen(port, program.opts().host, () => {
  console.log(
    `Developer server listening at http://${program.opts().host}:${port}`
  );
});
