import argv from 'node:process';

function run(args: string[]) {
  console.log(args)
}

run(argv.argv);
