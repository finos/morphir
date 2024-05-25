import cli from './cli'


export function make(dir: string, opts: any) {
    cli.make(dir, opts)
    .then((ir: string | undefined) => {
        if (ir) {
            console.log(`Writing file ${opts.output}.`)
            cli.writeFile(opts.output, ir)
                .then(() => {
                    console.log('Done.')
                })
                .catch((err: any) => {
                    console.error(`Could not write file: ${err}`)
                })
        }
    })
    .catch((err: { code: string; path: any }) => {
        if (err.code == 'ENOENT') {
            console.error(`Could not find file at '${err.path}'`)
        } else {
            if (err instanceof Error) {
                console.error(err)
            } else {
                console.error(`Error: ${JSON.stringify(err, null, 2)}`)
            }
        }
        process.exit(1)
    })
}

export function dockerize(dir: string, opts: any) {
    cli.writeDockerfile(dir, opts)
    .then(() => {
        console.log("Dockerfile Created Successfully");
    })
    .catch((err: { code: string; path: any }) => {
        if (err.code == 'ENOENT') {
            console.error(`Could not find file at '${err.path}'`)
        } else {
            if (err instanceof Error) {
                console.error(err)
            } else {
                console.error(`Error: ${JSON.stringify(err, null, 2)}`)
            }
        }
        process.exit(1)
    })
}