var express = require("express")
var { createHandler } = require("graphql-http/lib/use/express")
var { buildSchema } = require("graphql")
var { ruruHTML } = require("ruru/server")
const fs = require('fs');
const path = require('path');
const { log } = require("console");

const baseDirArg = process.argv.includes('--baseDir') 
  ? process.argv[process.argv.indexOf('--baseDir') + 1] 
  : 'data/';

const baseDir = path.resolve(process.cwd(), baseDirArg);
log("Using base folder: " + baseDir);

// Define the GraphQL schema
const schemaFile = fs.readFileSync(path.join(__dirname, 'Data.schema.graphql'), 'utf8');
const schema = buildSchema(schemaFile);

//Implement the resolvers
const root = {
  dataset: ({ id }) => { return dataset(id); },
  datasets: () => { return datasets(); },
  element: ({ id }) => { return element(id); },
  elements: () => { datasets(); }, // TODO
};

function recursiveSearch(dir, pattern) {
  let results = [];

  fs.readdirSync(dir).forEach((file) => {
    const fullPath = path.resolve(dir, file);

    if (fs.statSync(fullPath).isDirectory()) {
      results = results.concat(recursiveSearch(fullPath, pattern));
    } else if (file.endsWith(pattern)) {
      results.push(fullPath);
    }
  });

  return results;
}

function urnToFile(urn) {
  return urnToFile(urn, undefined);
}

function urnToFile(urn, typ) {
  const items = urn.split(':');

  if(typ === undefined || typ == null) {
    typ = items[0];
  }

  const file = path.join(baseDir, `/${items[1]}`, `${items[2]}.${typ}.json`)
  return file;
}

function dataset(id) {
  const dataset = getJSONData(id, "dataset");
  return inflateDataset(dataset);
}

function datasets() {
  var files = recursiveSearch(baseDir, 'dataset.json');

  const datasets = files.map(file => {
    const dataset = inflate(file);
    return inflateDataset(dataset);
  });
  return datasets;
}

function inflateDataset(dataset) {
  const fields = dataset.fields.map(field => {
    const fieldUrn = `${dataset.id}#${field.name}`.replace("dataset:", ":");
    const fieldOverride = getJSONData("field" + fieldUrn, "field");

    if(fieldOverride !== undefined && fieldOverride !== null) {
      log("Found field override: " + field.id + " in " + dataset.id);
      field = fieldOverride;
    }

    if(field.element === undefined) 
    {
      const elementUrn = "element" + fieldUrn;
      const elmt = element(elementUrn);
      field.element = elmt;
    } 
    else if (typeof field.element === 'string') 
    {
      const elementUrn = field.element;
      const elmt = element(elementUrn);
      field.element = elmt;
    } 
    else 
    {
      const elmt = inflateElement(field.element);
      field.element = elmt;
    }
    
    if(field.element === undefined || field.element == null) {
      log("Setting " + field.name + " to nil in " + dataset.id);
      const elementUrn = "element:core:nil";
      const elmt = element(elementUrn);
      field.element = elmt;
    }

    return field;
  });

  dataset.fields = fields;

  return dataset;
}

function element(id) {
  var element = getJSONData(id, "element");

  if(!(element === undefined) && element !== null) {
    element = inflateElement(element);
  }

  return element;
}

function inflateElement(element) {
  const elementType = element.element_type;

  if (!(elementType === undefined) && typeof elementType === 'object') {
    if (elementType.hasOwnProperty('Number')) {
      elementType.__typename = 'NumberType';
    }
    else if(elementType.hasOwnProperty('Reference')) {
      elementType.__typename = 'ReferenceType';
      var refId = elementType.Reference.ref;
      var ref = inflateElement(getJSONData(refId, "element"));
      elementType.Reference.ref = ref;
    }
    else if (elementType.hasOwnProperty('Text')) {
      elementType.__typename = 'TextType';
    }
    else if (elementType.hasOwnProperty('Date')) {
      elementType.__typename = 'DateType';
    }
    else if (elementType.hasOwnProperty('Time')) {
      elementType.__typename = 'TimeType';
    }
    else if (elementType.hasOwnProperty('DateTime')) {
      elementType.__typename = 'DateTimeType';
    }
    else if (elementType.hasOwnProperty('Boolean')) {
      elementType.__typename = 'BooleanType';
      elementType.Bool = {};
    }
    else if (elementType.hasOwnProperty('Enum')) {
      elementType.__typename = 'EnumType';
    }

    const infoProperty = element.info;

    if(infoProperty === undefined) {
      const info = getJSONData(element.id, "element_info");
      element.info = info;
    }
  }

  return element;
}

function getJSONData(id) {
  return getJSONData(id);
}

function getJSONData(id, typ) {
  const file = urnToFile(id, typ);
  return inflate(file);
}

function inflate(file) {
  if (fs.existsSync(file)) {
    const data = fs.readFileSync(file);
    return JSON.parse(data);
  } else {
    return undefined;
  }
}

// Create an express server and a GraphQL endpoint
var app = express()

// Create and use the GraphQL handler.
app.all(
  "/graphql",
  createHandler({
    schema: schema,
    rootValue: root
    // rootValue: resolvers
  })
)

// Serve the GraphiQL IDE.
app.get("/", (_req, res) => {
  res.type("html")
  res.end(ruruHTML({ endpoint: "/graphql" }))
})

// Start the server at port
app.listen(4000)
console.log("Running a GraphQL API server at http://localhost:4000/graphql")
