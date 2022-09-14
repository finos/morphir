'use strict';

const express = require('express');
var path = require('path');

// Constants
const PORT = 8080;
const HOST = '0.0.0.0';


// App
const fs = require('fs');
const transp = require('morphir-bsq-transpiler');


const app = express(); 
app.use(express.json({limit: '50mb'}));

// Endpoints
app.get('/', (req, res) => {
    res.send('Hello World');
});

app.post('/insight', function (request, response) {
    console.log("IR:");
    const ir = JSON.stringify(request.body);

    var options = {
        root: path.join(__dirname)
    };

    var irFile = 'web/morphir-ir.json';

    fs.writeFile(irFile, ir, function (err) {
      if (err) return console.log(err);
      else
            console.log('Wrote:', irFile);
    });

    var fileName = 'web/index.html';
    response.sendFile(fileName, options, function (err) {
        if (err) {
            next(err);
        } else {
            console.log('Sent:', fileName);
        }
    });
});



app.get('/insight', (req, res) => {
    var options = {
        root: path.join(__dirname)
    };
    var fileName = 'web/index.html';
    res.sendFile(fileName, options, function (err) {
        if (err) {
            next(err);
        } else {
            console.log('Sent:', fileName);
        }
    });
});


app.get('/insight.html', (req, res) => {
    var options = {
        root: path.join(__dirname)
    };
    var fileName = 'web/insight.html';
    res.sendFile(fileName, options, function (err) {
        if (err) {
            next(err);
        } else {
            console.log('Sent:', fileName);
        }
    });
});


app.get('/insight.js', (req, res) => {
    var options = {
        root: path.join(__dirname)
    };
    var fileName = 'web/insight.js';
    res.sendFile(fileName, options, function (err) {
        if (err) {
            next(err);
        } else {
            console.log('Sent:', fileName);
        }
    });
});



app.get('/server/morphir-ir.json', (req, res) => {
    var options = {
        root: path.join(__dirname)
    };
    var fileName = 'web/morphir-ir.json';
    res.sendFile(fileName, options, function (err) {
        if (err) {
            next(err);
        } else {
            console.log('Sent:', fileName);
        }
    });
});



app.get('/assets/2020_Morphir_Logo_Icon_WHT.svg', (req, res) => {
    var options = {
        root: path.join(__dirname)
    };
    var fileName = 'web/assets/2020_Morphir_Logo_Icon_WHT.svg';
    res.sendFile(fileName, options, function (err) {
        if (err) {
            next(err);
        } else {
            console.log('Sent:', fileName);
        }
    });
});



app.post('/verify', function (request, response) {
    console.log("IR:");
    const ir = request.body;
    
    try {
        transp.bosque_check_ir(ir, (err, data) => {
            if(err) {
                console.log("err:");
                console.log(err);
                response.send(err); 
            }
            else if(data) {
                console.log("data:");
                console.log(data);
                response.send(data); 
            }
            else {
                response.send('OK'); 
            }
        });
    } catch (ex) {
        response.send(ex);
    }
});

app.listen(PORT, HOST);
console.log(`Running on http://${HOST}:${PORT}`);
