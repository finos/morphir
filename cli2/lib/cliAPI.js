"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.dockerize = exports.make = void 0;
const cli_1 = __importDefault(require("./cli"));
function make(dir, opts) {
    cli_1.default.make(dir, opts)
        .then((ir) => {
        if (ir) {
            console.log(`Writing file ${opts.output}.`);
            cli_1.default.writeFile(opts.output, ir)
                .then(() => {
                console.log('Done.');
            })
                .catch((err) => {
                console.error(`Could not write file: ${err}`);
            });
        }
    })
        .catch((err) => {
        if (err.code == 'ENOENT') {
            console.error(`Could not find file at '${err.path}'`);
        }
        else {
            if (err instanceof Error) {
                console.error(err);
            }
            else {
                console.error(`Error: ${JSON.stringify(err, null, 2)}`);
            }
        }
        process.exit(1);
    });
}
exports.make = make;
function dockerize(dir, opts) {
    cli_1.default.writeDockerfile(dir, opts)
        .then(() => {
        console.log("Dockerfile Created Successfully");
    })
        .catch((err) => {
        if (err.code == 'ENOENT') {
            console.error(`Could not find file at '${err.path}'`);
        }
        else {
            if (err instanceof Error) {
                console.error(err);
            }
            else {
                console.error(`Error: ${JSON.stringify(err, null, 2)}`);
            }
        }
        process.exit(1);
    });
}
exports.dockerize = dockerize;
