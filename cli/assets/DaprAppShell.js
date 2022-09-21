const express = require('express')
const bodyParser = require('body-parser')
const calc = require('./Main').Elm.Main.init({})
require('isomorphic-fetch')

//Config 
const APP_PORT = 3000
const DAPR_HTTP_PORT = 3500
const INPUT_TOPIC = 'A'
const OUTPUT_TOPIC = 'B'
const STATE_STORE_NAME = 'statestore'
//Config End

const stateStoreUrl = `http://localhost:${DAPR_HTTP_PORT}/v1.0/state/${STATE_STORE_NAME}`
const eventPublishUrl = `http://localhost:${DAPR_HTTP_PORT}/v1.0/publish/${OUTPUT_TOPIC}`

const app = express() // nosemgrep 

app.use(bodyParser.json({ type: 'application/*+json' }))

app.listen(APP_PORT, () => { console.log("Server running on port 3000") })

app.get('/dapr/subscribe', (_req, res) => {
    res.json([INPUT_TOPIC]);
});

app.post(`/${INPUT_TOPIC}`, (req, res) => {
    handleCommand(req.body.data, stateStoreUrl)
        .then(stateCmd => {
            console.log(`Sending command to calculation: ${JSON.stringify(stateCmd)}`)
            calc.ports.stateCommandPort.send(stateCmd)
        })
    res.sendStatus(200)
})

calc.ports.stateEventPort.subscribe(
    (data) => {
        console.log(`Data received from calculation : ${JSON.stringify(data)}`)
        const stateSaveResp = saveState(data.stateEvent.key, data.stateEvent.state, stateStoreUrl)
        const publishEventResp = publishEvent(data.stateEvent.key, data.stateEvent.event, eventPublishUrl)
    }
)

const handleCommand =
    async function (cmdJson, stateStoreUrl) {
        const key = cmdJson.key
        const stateValueResp = await fetch(`${stateStoreUrl}/${key}`)
        var stateValue = null
        if (stateValueResp.ok) {
            try {
                stateValue = await stateValueResp.json()
            } catch (error) {
                stateValue = null
            }
            console.log(`Retrieved state : ${JSON.stringify(stateValue)}`)
        } else {
            console.log(`Error occured while loading state: ${stateValueResp.statusText}`)
        }
        const msg =
            {
                msg: { key: key, state: stateValue, command: cmdJson.command }
            }
        return msg
    }

const saveState =
    async function (keyJson, stateJson, stateStoreUrl) {
        nextState =
            [{
                key: keyJson,
                value: stateJson
            }]
        const resp =
            await fetch(stateStoreUrl, {
                method: 'POST',
                headers: {
                    "Content-type": "application/json"
                },
                body: JSON.stringify(nextState)
            })
        return resp
    }

const publishEvent =
    async function (keyJson, eventJson, eventPublishUrl) {
        const eventToPub = { key: keyJson, event: eventJson }
        const resp =
            await fetch(eventPublishUrl, {
                method: 'POST',
                headers: {
                    "Content-type": "application/json"
                },
                body: JSON.stringify(eventToPub)
            })
        resp
    }