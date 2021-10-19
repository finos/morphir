'use strict';

const express = require('express');

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
