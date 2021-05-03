const { series, src, dest } = require('gulp');
const os = require('os')
const path = require('path')
const util = require('util')
const fs = require('fs')
const tmp = require('tmp')
const git = require('isomorphic-git')
const http = require('isomorphic-git/http/node')
const del = require('del')
const elmMake = require('node-elm-compiler').compile

const config = {
    morphirJvmVersion: '0.7.0',
    morphirJvmCloneDir: tmp.dirSync()
}

async function clean() {
    return del([
        'dist',
        'tests-integration/generated'
    ])
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
        makeDevServer,
        makeInsightAPI,
        makeTryMorphir
    )

exports.clean = clean;
exports.makeCLI = makeCLI;
exports.build = build;
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