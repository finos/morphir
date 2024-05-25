import FileSystemModule from 'fs'
import chalk from 'chalk'
import path from 'path'
import { promisify } from 'util'
import { Command } from 'commander'
import inquirer, { Answers, Question } from 'inquirer'

const exists = promisify(FileSystemModule.exists)
const writeFile = promisify(FileSystemModule.writeFile)
const readFile = promisify(FileSystemModule.readFile)
const mkdir = promisify(FileSystemModule.mkdir)

interface InitAnswers extends Answers {
	name: string
	type: string
	dir: string
}

interface CreateDirAnswer extends Answers {
	shouldCreate: boolean
}

const program = new Command()
program
	.name('morphir init')
	.description('Launches an interactive session to initialize a new morphir project.')
	.parse(process.argv)

console.log(chalk.blue('-- NEW MORPHIR PROJECT ---------------------------------------\n'))

console.log("I'll create a new morphir project for you, you just need to provide some details.\n")
inquirer
	.prompt<InitAnswers>([
		{
			type: 'list',
			name: 'type',
			message: 'Select project type',
			choices: ['Business Model', 'Decoration Schema'],
			default: 0
		},
		{
			type: 'input',
			name: 'name',
			message: 'Project Name (no spaces)',
			default: 'Demo',
			validate(input: string) {
				// prevent spaces, leading digits and a leading lowercase.
				if (input.includes(' '))
					return `You can't have spaces in there. You could try: ${getSuggestions(input)}`
				if (input.match(/^\d/)) return `Project name can't start with a number`
				if (input[0] === input[0].toLowerCase()) return `It can't start with a lowercase character`
				return true
			}
		},
		{
			type: 'input',
			name: 'dir',
			message: 'Where do you want to create it? (use `.` for current directory)',
			default(answer: { name: string }) {
				return `./${answer.name}`
			}
		}
	])
	.then(async (answers: InitAnswers) => {
		const { name, dir } = answers

		console.log()
		console.log(chalk.blue(`Creating your new morphir project\n`))

		const projectPath = path.resolve(dir)

		// check if there's a morphir.json at the directory
		if (await exists(path.join(projectPath, 'morphir.json'))) {
			console.log(chalk.blue(`The path you specified already contains a morphir project. Exiting.`))
			process.exit(0)
		}

		// ask to create a new dir if it doesn't exist
		if (!(await exists(projectPath))) {
			try {
				const { shouldCreate }: CreateDirAnswer = await inquirer.prompt<CreateDirAnswer>([
					{
						type: 'confirm',
						message: `The directory you provided doesn't exist. Do you want me to create a new directory at\n"${projectPath}"?`,
						name: 'shouldCreate',
						default: false
					}
				])

				if (shouldCreate) await mkdir(projectPath)
				else {
					console.log(
						chalk.blue(
							'Cannot create new project because the specified directory does not exists. Exiting.'
						)
					)
					process.exit(0)
				}
			} catch (e: unknown) {
				console.log(chalk.red(`Failed to create directory: ${projectPath}`))
				console.error(e)
				process.exit(1)
			}
		}

		// create the the morphir.json
		const morphirJson = JSON.stringify(
			{
				name: name,
				sourceDirectory: 'src'
			},
			null,
			4
		)
		const morphirJsonPath = path.join(projectPath, 'morphir.json')
		try {
			await writeFile(morphirJsonPath, morphirJson)
		} catch (error) {
			console.log(chalk.red(`Could not create morphir.json`))
			console.error(error)
			process.exit(1)
		}

		// create the src directory
		const srcDir = path.join(projectPath, 'src')
		try {
			mkdir(srcDir)
		} catch (error) {
			console.log(chalk.red(`Failed to create directory: ${srcDir}`))
			console.error(error)
			process.exit(1)
		}

		console.log()
		console.log(chalk.blue('-- ALL DONE --------------------------------------------------\n'))
	})

/**
 * Creates suggestions for use based on their inputs.
 * Performs some basic string cleanup before creating combinations.
 *
 * @param input original user input
 * @returns comma separated string of suggestions.
 */
function getSuggestions(input: string): string {
	const noLeadingDigits = input.replace(/^(\d*\s*\d*)/, '').trim()
	const capitalized = noLeadingDigits[0].toUpperCase() + noLeadingDigits.substring(1)
	const suggestions = new Set([capitalized.replace(' ', ''), capitalized.replace(' ', '.')])
	return [...suggestions].join(', ')
}
