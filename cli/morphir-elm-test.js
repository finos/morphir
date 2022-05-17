#!/usr/bin/env node

'use strict'

// NPM imports
const commander = require('commander')
const cli = require('./cli')

// For Colorful console Output
const chalk = require('chalk');

// logging
require('log-timestamp')

// Set up Commander
const program = new commander.Command()
program
    .name('morphir-elm test')
    .description('Start Testing the Models')
    .option('-p, --project-dir <path>', 'Root directory of the project where morphir.json is located.', '.')
    .parse(process.argv)

cli.test(program.opts().projectDir)
    .then(testResult => {
        if (testResult.length == 0) {
            console.log(chalk.purple("No TestCases found in morphir-tests.json file."))
        }
        else {
            for (let i = 0; i < testResult.length; i++) {
                const testObject = testResult[i]
                console.log(chalk.cyan(`Function Name - ${testObject["Function Name"]}`))
                console.log(chalk.yellow(`Total TestCases - ${testObject["Total TestCases"]}`))
                console.log(chalk.green(`Pass TestCases - ${testObject["Pass TestCases"]}\n`))

            }
        }
    })
    .catch((err) => {

        if (err instanceof Object && err.length >= 0) {
            for (let i = 0; i < err.length; i++) {
                const testObject = err[i]
                console.log(chalk.cyan(`Function Name - ${testObject["Function Name"]}`))
                console.log(chalk.yellow(`Total TestCases - ${testObject["Total TestCases"]}`))
                console.log(chalk.yellow(`Fail TestCases - ${testObject["Fail TestCases"]}\n`))
                const failTestCaseJson = testObject["Fail TestCases List"]
                for (let j = 0; j < failTestCaseJson.length; j++) {
                    const failTestOutputs = failTestCaseJson[j]
                    console.log(chalk.red(`Expected Output - ${failTestOutputs["Expected Output"]}`))
                    console.log(chalk.red(`Actual Output - ${failTestOutputs["Actual Output"]}\n`))
                }

            }
        } else {
            console.error(chalk.red(err))
        }


        process.exit(1)
    })
