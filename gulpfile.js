const { series, parallel, src, dest } = require('gulp');
const os = require('os')
const path = require('path')
const util = require('util')
const fs = require('fs')
const tmp = require('tmp')
const git = require('isomorphic-git')
const http = require('isomorphic-git/http/node')
const del = require('del')
const elmMake = require('node-elm-compiler').compile
const execa = require('execa');
const mocha = require('gulp-mocha');
const ts = require('gulp-typescript');
const tsProject = ts.createProject('./cli2/tsconfig.json')

const config = {
    morphirJvmVersion: '0.8.3',
    morphirJvmCloneDir: tmp.dirSync()
}

const stdio = 'inherit';

async function clean() {
    return del(['dist'])
}

async function cloneMorphirJVM() {
    return await git.clone({
        fs,
        http,
        dir: config.morphirJvmCloneDir.name,
        url: 'https://github.com/finos/morphir-jvm',
        ref: `tags/v${config.morphirJvmVersion}`,
        singleBranch: true
    })
}

function copyMorphirJVMAssets() {
    const sdkFiles = path.join(config.morphirJvmCloneDir.name, 'morphir/sdk/core/src*/**')
    return src([sdkFiles]).pipe(dest('redistributable/Scala/sdk'))
}

async function cleanupMorphirJVM() {
    return del(config.morphirJvmCloneDir.name + '/**', { force: true });
}

function checkElmDocs() {
    return elmMake([], { docs: "docs.json" })
}

function make(rootDir, source, target) {
    return elmMake([source], { cwd: path.join(process.cwd(), rootDir), output: target })
}

function makeCLI() {
    return make('cli', 'src/Morphir/Elm/CLI.elm', 'Morphir.Elm.CLI.js')
}

function makeCLI2() {
    return make('cli2', 'src/Morphir/Elm/CLI.elm', 'Morphir.Elm.CLI.js')
}

function makeDevCLI() {
    return make('cli', 'src/Morphir/Elm/DevCLI.elm', 'Morphir.Elm.DevCLI.js')
}

function makeDevServer() {
    return make('cli', 'src/Morphir/Web/DevelopApp.elm', 'web/index.js')
}

function makeDevServerAPI() {
    return make('cli', 'src/Morphir/Web/DevelopApp.elm', 'web/insightapp.js')
}

function makeInsightAPI() {
    return make('cli', 'src/Morphir/Web/Insight.elm', 'web/insight.js')
}

function makeTryMorphir() {
    return make('cli', 'src/Morphir/Web/TryMorphir.elm', 'web/try-morphir.html')
}

const buildCLI2 =
    parallel(
        compileCli2Ts,
        makeCLI2
    )

const build =
    series(
        checkElmDocs,
        makeCLI,
        makeDevCLI,
        buildCLI2,
        makeDevServer,
        makeDevServerAPI,
        makeInsightAPI,
        makeTryMorphir
    )


function morphirElmMake(projectDir, outputPath, options = {}) {
    args = ['./cli/morphir-elm.js', 'make', '-p', projectDir, '-o', outputPath]
    if (options.typesOnly) {
        args.push('--types-only')
    }
    console.log("Running: " + args.join(' '));
    return execa('node', args, { stdio })
}

function morphirElmMake2(projectDir, outputPath, options = {}) {
    args = ['./cli2/lib/morphir.js', 'make', '-p', projectDir, '-o', outputPath]
    if (options.typesOnly) {
        args.push('--types-only')
    }
    console.log("Running: " + args.join(' '));
    return execa('node', args, { stdio })
}

function morphirElmGen(inputPath, outputDir, target) {
    args = ['./cli/morphir-elm.js', 'gen', '-i', inputPath, '-o', outputDir, '-t', target]
    console.log("Running: " + args.join(' '));
    return execa('node', args, { stdio })
}




async function testUnit(cb) {
    await execa('elm-test');
}

async function compileCli2Ts() {
    src('./cli2/*.ts').pipe(tsProject()).pipe(dest('./cli2/lib/'))
}

function testIntegrationClean() {
    return del([
        'tests-integration/generated',
        'tests-integration/reference-model/morphir-ir.json'
    ])
}


async function testIntegrationMake(cb) {
    await morphirElmMake(
        './tests-integration/reference-model',
        './tests-integration/generated/refModel/morphir-ir.json')
}

async function testIntegrationMorphirTest(cb) {
    src('./tests-integration/generated/refModel/morphir-ir.json')
        .pipe(dest('./tests-integration/reference-model/'))
    await execa(
        'node',
        ['./cli/morphir-elm.js', 'test', '-p', './tests-integration/reference-model'],
        { stdio },
    )
}

async function testIntegrationGenScala(cb) {
    await morphirElmGen(
        './tests-integration/generated/refModel/morphir-ir.json',
        './tests-integration/generated/refModel/src/scala/',
        'Scala')
}

async function testIntegrationBuildScala(cb) {
    // try {
    //     await execa(
    //         'mill', ['__.compile'],
    //         { stdio, cwd: 'tests-integration' },
    //     )
    // } catch (err) {
    //     if (err.code == 'ENOENT') {
    console.log("Skipping testIntegrationBuildScala as `mill` build tool isn't available.");
    //     } else {
    //         throw err;
    //     }
    // }
}

async function testIntegrationMakeSpark(cb) {
    await morphirElmMake(
        './tests-integration/spark/model',
        './tests-integration/generated/sparkModel/morphir-ir.json')
}

async function testIntegrationGenSpark(cb) {
    await morphirElmGen(
        './tests-integration/generated/sparkModel/morphir-ir.json',
        './tests-integration/generated/sparkModel/src/spark/',
        'Spark')
}

async function testIntegrationBuildSpark(cb) {
     try {
         await execa(
             'mill', ['__.compile'],
             { stdio, cwd: 'tests-integration' },
         )
     } catch (err) {
         if (err.code == 'ENOENT') {
    console.log("Skipping testIntegrationBuildSpark as `mill` build tool isn't available.");
         } else {
             throw err;
         }
     }
}

async function testIntegrationTestSpark(cb) {
     try {
         await execa(
             'mill', ['spark.test'],
             { stdio, cwd: 'tests-integration' },
         )
     } catch (err) {
         if (err.code == 'ENOENT') {
    console.log("Skipping testIntegrationTestSpark as `mill` build tool isn't available.");
         } else {
             throw err;
         }
     }
}

// Generate TypeScript API for reference model.
async function testIntegrationGenTypeScript(cb) {
    await morphirElmGen(
        './tests-integration/generated/refModel/morphir-ir.json',
        './tests-integration/generated/refModel/src/typescript/',
        'TypeScript')
}

// Compile generated Typescript API and run integration tests.
function testIntegrationTestTypeScript(cb) {
    return src('tests-integration/typescript/TypesTest-refModel.ts')
        .pipe(mocha({ require: 'ts-node/register' }));
}

testIntegrationSpark = series(
    testIntegrationMakeSpark,
    testIntegrationGenSpark,
    testIntegrationBuildSpark,
    testIntegrationTestSpark,
)

const testIntegration = series(
    testIntegrationClean,
    testIntegrationMake,
    parallel(
        testIntegrationMorphirTest,
	testIntegrationSpark,
        series(
            testIntegrationGenScala,
            testIntegrationBuildScala,
        ),
        series(
            testIntegrationGenTypeScript,
            testIntegrationTestTypeScript,
        ),
    )
)


async function testMorphirIRMake(cb) {
    await morphirElmMake('.', 'tests-integration/generated/morphirIR/morphir-ir.json',
        { typesOnly: true })
}

// Generate TypeScript API for Morphir.IR itself.
async function testMorphirIRGenTypeScript(cb) {
    await morphirElmGen(
        './tests-integration/generated/morphirIR/morphir-ir.json',
        './tests-integration/generated/morphirIR/src/typescript/',
        'TypeScript')
}

// Compile generated Typescript API and run integration tests.
function testMorphirIRTestTypeScript(cb) {
    return src('tests-integration/typescript/CodecsTest-Morphir-IR.ts')
        .pipe(mocha({ require: 'ts-node/register' }));
}

testMorphirIR = series(
    testMorphirIRMake,
    testMorphirIRGenTypeScript,
    testMorphirIRTestTypeScript,
)


const test =
    parallel(
        testUnit,
        testIntegration,
        testMorphirIR,
    )

exports.clean = clean;
exports.makeCLI = makeCLI;
exports.makeDevCLI = makeDevCLI;
exports.buildCLI2 = buildCLI2;
exports.build = build;
exports.test = test;
exports.testIntegration = testIntegration;
exports.testIntegrationSpark = testIntegrationSpark;
exports.testMorphirIR = testMorphirIR;
exports.testMorphirIRTypeScript = testMorphirIR;
exports.default =
    series(
        clean,
        series(
            cloneMorphirJVM,
            copyMorphirJVMAssets,
            cleanupMorphirJVM
        ),
        build
    );
