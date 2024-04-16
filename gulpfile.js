const { series, parallel, src, dest } = require('gulp');
const concat = require('gulp-concat');
const os = require('os')
const path = require('path')
const util = require('util')
const fs = require('fs')
const tmp = require('tmp')
const git = require('isomorphic-git')
const { request: delegate } = require('isomorphic-git/http/node')
const { HttpProxyAgent, HttpsProxyAgent } = require('hpagent')
const del = require('del')
const elmMake = require('node-elm-compiler').compile
const execa = require('execa');
const shell = require('shelljs')
const mocha = require('gulp-mocha');
const ts = require('gulp-typescript');
const { isExpressionWithTypeArguments } = require('typescript');
const mainTsProject = ts.createProject('./tsconfig.json')
const cliTsProject = ts.createProject('./cli2/tsconfig.json')
const readFile = util.promisify(fs.readFile)

async function request ({ url, method, headers, body }) {
    const proxy = url.startsWith('https:')
      ? { Agent: HttpsProxyAgent, url: process.env.https_proxy }
      : { Agent: HttpProxyAgent, url: process.env.http_proxy }
    const agent = proxy.url ? new proxy.Agent({ proxy: proxy.url }) : undefined
    return delegate({ url, method, agent, headers, body })
  }

const http = { request };

const config = {
    morphirJvmVersion: '0.18.2',
    morphirJvmCloneDir: tmp.dirSync()
}

const stdio = 'inherit';

async function clean() {
    del(['tests-integration/reference-model/Dockerfile'])
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
    const sdkFiles = path.join(config.morphirJvmCloneDir.name, 'morphir/sdk/**')
    return src(sdkFiles).pipe(dest('redistributable/Scala/sdk'))
}

async function cleanupMorphirJVM() {
    return del(config.morphirJvmCloneDir.name + '/**', { force: true });
}

function checkElmDocs() {
    return elmMake([], { docs: "docs.json" })
}

function make(rootDir, source, target) {
    return elmMake([source], { cwd: path.join(process.cwd(), rootDir), output: target }) // // nosemgrep : path-join-resolve-traversal
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

async function makeComponents() {
    return src(['./cli/web/insight.js', './cli/web/morphir-insight-element.js']).pipe(concat('insight.js')).pipe(dest('./cli/web/'))
}

const buildCLI2 =
    parallel(
        compileCli2Ts,
        makeCLI2
    )

const buildMorphirAPI2 = async ()=>{
    try {
        await morphirElmMakeRunOldCli('.', './morphir-ir.json', {typesOnly: true})
        await morphirElmGen('./morphir-ir.json', './lib/generated', 'TypeScript')
        src('./lib/sdk/**/*')
        .pipe(dest('./lib/generated/morphir/sdk'))
       return await execa('npx tsc', ['--project',path.join('.','lib','tsconfig.json')])
    } catch (error) {
        console.error("Error building morphir API 2", error);
        return error
    }

}

const build =
    series(
        checkElmDocs,
        makeCLI,
        makeDevCLI,
        buildCLI2,
        buildMorphirAPI2,
        makeDevServer,
        makeDevServerAPI,
        makeInsightAPI,
        makeComponents,
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

function morphirElmMakeRunOldCli(projectDir, outputPath, options = {}) {
    args = ['./cli/morphir-elm.js', 'make', '-f', '-p', projectDir, '-o', outputPath]
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

// Generate the IR for the Json Schema mdel
function morphirElmMakeJsonSchema(projectDir, outputPath, options = {}) {
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

// Test the json-schema-gen command.
async function morphirJsonSchemaGen(inputPath, outputDir, target) {
    args = ['./cli2/lib/morphir-json-schema-gen.js', 'json-schema-gen', '-i', inputPath, '-o', outputDir, '-t', target]
    console.log("Running: " + args.join(' '));
    try {
        await execa('node', args, {stdio})
    } catch (err) {
        console.log("Error running json-schema-gen command", err);
        throw(err)
    }
}


function morphirDockerize(projectDir, options = {}) {
    let command = 'dockerize'
    let funcLocation = './cli2/lib/morphir-dockerize.js'
    let projectDirFlag = '-p'
    let overwriteDockerfileFlag = '-f'
    let projectDirArgs = [projectDirFlag, projectDir]
    args = [
        funcLocation,
        command,
        projectDirArgs.join(' '),
        overwriteDockerfileFlag
    ]
    console.log("Running: " + args.join);
    return execa('node', args, { stdio })
}


async function testUnit(cb) {
    await execa('elm-test');
}

async function compileCli2Ts() {
    src('./cli2/*.ts').pipe(cliTsProject()).pipe(dest('./cli2/lib/'))
}


async function compileMain2Ts() {
    src('./lib/main.ts').pipe(cliTsProject()).pipe(dest('./cli2/lib/main.js'))
}

function testIntegrationClean() {
    return del([
        'tests-integration/generated',
        'tests-integration/reference-model/morphir-ir.json',
        'tests-integration/json-schema/model/dist',
        'tests-integration/json-schema/model/morphir-ir.json'
    ])
}


async function testIntegrationMake(cb) {

    await morphirElmMake(
        './tests-integration/reference-model',
        './tests-integration/generated/refModel/morphir-ir.json')

    await morphirElmMakeRunOldCli(
        './tests-integration/reference-model',
        './tests-integration/generated/refModel/morphir-ir.json')

    await morphirElmMakeJsonSchema(
        './tests-integration/json-schema/model',
        './tests-integration/json-schema/model/morphir-ir.json')
}

async function testIntegrationDockerize() {
    await morphirDockerize(
        './tests-integration/reference-model',
    )
}

async function testIntegrationJsonSchemaGen() {
    await morphirJsonSchemaGen(
        './tests-integration/json-schema/model/morphir-ir.json',
        './tests-integration/json-schema/model/dist',
        'JsonSchema'
    )
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
            console.error("Skipping testIntegrationBuildSpark as `mill` build tool isn't available.");
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
            console.error("Skipping testIntegrationTestSpark as `mill` build tool isn't available.");
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


async function testCreateCSV(cb) {
    if (!shell.which('bash')) {
        console.log("Automatically creating CSV files is not available on this platform");
    } else {
        code_no = shell.exec('bash ./create_csv_files.sh', { cwd: './tests-integration/spark/elm-tests/tests' }).code
        if (code_no != 0) {
            console.error('ERROR: CSV files cannot be created')
            return false;
        }
    }
}

testIntegrationSpark = series(
    testIntegrationMakeSpark,
    testIntegrationGenSpark,
    testIntegrationBuildSpark,
    testIntegrationTestSpark,
)

testIntegration = series(
    testIntegrationClean,
    testIntegrationMake,
    testCreateCSV,
    parallel(
        testIntegrationMorphirTest,
        //testIntegrationSpark,
        series(
            testIntegrationGenScala,
            testIntegrationBuildScala,
        ),
        series(
            testIntegrationGenTypeScript,
            testIntegrationTestTypeScript,
        ),
    ),testIntegrationDockerize,
     testIntegrationJsonSchemaGen
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

// Make sure all dependencies are permitted in highly-restricted environments as well
async function checkPackageLockJson() {
    const packageLockJson = JSON.parse((await readFile('package-lock.json')).toString())
    const hasRuntimeDependencyOnPackage = (packageName) => {
        const runtimeDependencyInPackages =
            packageLockJson.packages
            && packageLockJson.packages[`node_modules/${packageName}`]
            && !packageLockJson.packages[`node_modules/${packageName}`].dev
        const runtimeDependencyInDependencies =
            packageLockJson.dependencies
            && packageLockJson.dependencies[packageName]
            && !packageLockJson.dependencies[packageName].dev
        return runtimeDependencyInPackages || runtimeDependencyInDependencies
    }
    if (hasRuntimeDependencyOnPackage('binwrap')) {
        throw Error('Runtime dependency on binwrap was detected!')
    }
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
        // testMorphirIR,
    )

const csvfiles = series(
    testCreateCSV,
)

exports.clean = clean;
exports.makeCLI = makeCLI;
exports.makeDevCLI = makeDevCLI;
exports.buildCLI2 = buildCLI2;
exports.compileMain2Ts = compileMain2Ts;
exports.build = build;
exports.test = test;
exports.csvfiles = csvfiles;
exports.testIntegration = testIntegration;
exports.testIntegrationSpark = testIntegrationSpark;
exports.testMorphirIR = testMorphirIR;
exports.testMorphirIRTypeScript = testMorphirIR;
exports.checkPackageLockJson = checkPackageLockJson;
exports.default =
    series(
        clean,
        checkPackageLockJson,
        series(
            cloneMorphirJVM,
            copyMorphirJVMAssets,
            cleanupMorphirJVM
        ),
        build
    );
