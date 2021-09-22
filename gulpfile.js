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

const config = {
    morphirJvmVersion: '0.7.1',
    morphirJvmCloneDir: tmp.dirSync()
}

const stdio = 'inherit';

async function clean() {
    return del([ 'dist' ])
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

function make(rootDir, source, target) {
    return elmMake([source], { cwd: path.join(process.cwd(), rootDir), output: target })
}

function makeCLI() {
    return make('cli', 'src/Morphir/Elm/CLI.elm', 'Morphir.Elm.CLI.js')
}

function makeDevCLI() {
    return make('cli', 'src/Morphir/Elm/DevCLI.elm', 'Morphir.Elm.DevCLI.js')
}

function makeDevServer() {
    return make('cli', 'src/Morphir/Web/DevelopApp.elm', 'web/index.html')
}

function makeInsightAPI() {
    return make('cli', 'src/Morphir/Web/Insight.elm', 'web/insight.js')
}

function makeTryMorphir() {
    return make('cli', 'src/Morphir/Web/TryMorphir.elm', 'web/try-morphir.html')
}


const build =
    series(
        makeCLI,
        makeDevCLI,
        makeDevServer,
        makeInsightAPI,
        makeTryMorphir
    )


async function testUnit(cb) {
    await execa('elm-test');
}

function testIntegrationClean() {
    return del([
        'tests-integration/generated',
        'tests-integration/reference-model/morphir-ir.json'
    ])
}

async function testIntegrationMake(cb) {
    await execa(
        'node',
        [
            './cli/morphir-elm.js', 'make',
             '-p', './tests-integration/reference-model',
             '-o', './tests-integration/generated/morphir-ir.json'
        ],
        { stdio },
    )
}

async function testIntegrationMorphirTest(cb) {
    src('./tests-integration/generated/morphir-ir.json')
        .pipe(dest('./tests-integration/reference-model/'))
    await execa(
        'node',
        ['./cli/morphir-elm.js', 'test', '-p', './tests-integration/reference-model'],
        { stdio },
    )
}

async function testIntegrationGenScala(cb) {
    await execa(
        'node',
        [
            './cli/morphir-elm.js', 'gen',
            '-i', './tests-integration/generated/morphir-ir.json',
            '-o', './tests-integration/generated/refModel/src/scala/',
            '-t', 'Scala'
        ],
        { stdio },
    )
}

async function testIntegrationBuildScala(cb) {
    await execa(
        'mill', ['__.compile'],
        { stdio, cwd: 'tests-integration' },
    )
}

const testIntegration = series(
        testIntegrationClean,
        testIntegrationMake,
        parallel(
            testIntegrationMorphirTest,
            series(
                testIntegrationGenScala,
                testIntegrationBuildScala,
            ),
        )
    )

const test =
    parallel(
        testUnit,
        testIntegration,
    )

exports.clean = clean;
exports.makeCLI = makeCLI;
exports.makeDevCLI = makeDevCLI;
exports.build = build;
exports.test = test;
exports.testIntegration = testIntegration;
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
