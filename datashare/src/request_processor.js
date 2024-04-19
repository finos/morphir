const express = require('express');
const fs = require('fs');
const app = express();
const bodyParser = require('body-parser');

app.use(bodyParser.json());

app.post('/element', (req, res) => {
  const body = req.body;
  // Validate the element against the Data.schema.json schema
  // You can use a JSON schema validator library like Ajv for this

  saveToFile(body, (err) => {
    if (err) {
      console.error(err);
      res.status(500).send('Error saving element');
    } else {
      res.status(201).send('Element saved successfully');
    }
  });
});

app.post('/dataset', (req, res) => {
  const body = req.body;
  // Validate the dataset against the Data.schema.json schema
  // You can use a JSON schema validator library like Ajv for this

  saveToFile(body, (err) => {
    if (err) {
      console.error(err);
      res.status(500).send('Error saving dataset');
    } else {
      res.status(201).send('Dataset saved successfully');
    }
  });
});

function saveToFile(artifact, callback) {
  // Save as a JSON file in the data folder
  const items = artifact.id.split(':');
  const typ = items[0];
  const domain = items[1];
  const name = items[2];
  const folder = `data/${domain}`;
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
