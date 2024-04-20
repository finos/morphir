const express = require('express');
const fs = require('fs');
const path = require('path');
const app = express();
const bodyParser = require('body-parser');
const { log } = require('console');

const baseDirArg = process.argv.includes('--baseDir') 
  ? process.argv[process.argv.indexOf('--baseDir') + 1] 
  : 'data/';

const baseDir = path.resolve(process.cwd(), baseDirArg);
log("Using base folder: " + baseDir);

if(!fs.existsSync(baseDir)) {
  fs.mkdirSync(baseDir);
}

console.log("Using base folder: " + baseDir);

app.use(bodyParser.json());

app.post('/element', (req, res) => {
  const body = req.body;
  processRequest(body, 'element', req, res);
});

app.post('/dataset', (req, res) => {
  const body = req.body;
  processRequest(body, 'dataset', req, res);
});

function processRequest(body, artifactType, req, res) {
  // Validate the element against the Data.schema.json schema
  // You can use a JSON schema validator library like Ajv for this

  saveToFile(body, (err) => {
    if (err) {
      console.error(err);

      const event = {
        "not_created": {
          "type" : artifactType,
          "element" : body
        }
      };

      res.status(500).send(JSON.stringify(event));
    } else {

      const event = {
        "created": {
          "type" : artifactType,
          "element" : body
        }
      };

      res.status(201).send(JSON.stringify(event));
    }
  });
}

function saveToFile(artifact, callback) {
  // Save as a JSON file in the data folder
  const items = artifact.id.split(':');
  const typ = items[0];
  const domain = items[1];
  const name = items[2];
  const folder = `${basedir}/${domain}`;
  const fileName = folder + `/${name}.${typ}.json`;
  const json = JSON.stringify(artifact);

  if(!fs.existsSync(folder)) {
    fs.mkdirSync(folder);
  }

  fs.writeFile(fileName, json, callback);
}

app.listen(3000, () => {
  console.log('Server is running on port 3000');
});
