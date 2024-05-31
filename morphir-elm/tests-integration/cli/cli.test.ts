import * as irUtils from '../ts-test-utils/ir-utils'

const path = require('path')
const util = require('util')
const fs = require('fs')
const readFile = fs.readFileSync
const mkdir = fs.mkdirSync
const rmdir = util.promisify(fs.rm)
const cli = require('../../cli/cli')
const writeFile = util.promisify(fs.writeFile)

// utility function for joining strings with newlines
const concat = (...rest: string[]): string => rest.join('\n')

describe('Testing Morphir-elm make command', () => {
	const PATH_TO_PROJECT: string = path.join(__dirname, 'temp/project')
	const CLI_OPTIONS = { typesOnly: false }
	const morphirJSON = {
		name: 'Package',
		sourceDirectory: 'src',
		exposedModules: ['Rentals']
	}

	beforeAll(async () => {
		// create the folders to house test data
		await mkdir(path.join(PATH_TO_PROJECT, '/src/Package'), { recursive: true })
	})

	afterAll(async () => {
		await rmdir(path.join(__dirname, 'temp'), { recursive: true })
	})

	beforeEach(async () => {
		await writeFile(path.join(PATH_TO_PROJECT, 'morphir.json'), JSON.stringify(morphirJSON))
	})

	test('should create an IR with no modules when no elm files are found', async () => {
		const IR = await cli.make(PATH_TO_PROJECT, CLI_OPTIONS)
		expect(IR.distribution[3].modules).toMatchObject([])
	})

	test('should create an IR with no types when no types are found in elm file', async () => {
		await writeFile(
			path.join(PATH_TO_PROJECT, 'src/Package', 'Rentals.elm'),
			concat(
				'module Package.Rentals exposing (logic)',
				'',
				'logic: String -> String',
				'logic level =',
				`   String.append "Player level: " level`
			)
		)

		const IR = await cli.make(PATH_TO_PROJECT, CLI_OPTIONS)
		const rentalsModule = IR.distribution[3].modules[0]
		expect(rentalsModule[1].value.types).toMatchObject([])
	})

	test('should create an IR with no values when no values are found in elm file', async () => {
		await writeFile(
			path.join(PATH_TO_PROJECT, 'src/Package', 'Rentals.elm'),
			concat('module Package.Rentals exposing (Action)', '', 'type Action', `   = Rent`, `   | Return`)
		)

		const IR = await cli.make(PATH_TO_PROJECT, CLI_OPTIONS)
		const rentalsModule = IR.distribution[3].modules[0]
		expect(rentalsModule[1].value.values).toMatchObject([])
	})

	test('should create an IR with both types and values', async () => {
		await writeFile(
			path.join(PATH_TO_PROJECT, 'src/Package', 'Rentals.elm'),
			concat(
				'module Package.Rentals exposing (..)',
				'',
				'type Action',
				`   = Rent`,
				`   | Return`,
				'',
				'logic: String -> String',
				'logic level =',
				`   String.append "Player level: " level`
			)
		)
		const IR = await cli.make(PATH_TO_PROJECT, CLI_OPTIONS)
		const rentalsModule = IR.distribution[3].modules[0]
		expect(rentalsModule[1].value.values).not.toMatchObject([])
		expect(rentalsModule[1].value.types).not.toMatchObject([])
	})

	test('should create an IR with only types when typesOnly is set to true', async () => {
		await writeFile(
			path.join(PATH_TO_PROJECT, 'src/Package', 'Rentals.elm'),
			concat(
				'module Package.Rentals exposing (..)',
				'',
				'type Action',
				`   = Rent`,
				`   | Return`,
				'',
				'logic: String -> String',
				'logic level =',
				`   String.append "Player level: " level`
			)
		)
		const IR = await cli.make(PATH_TO_PROJECT, { typesOnly: true })
		const rentalsModule = IR.distribution[3].modules[0]
		expect(rentalsModule[1].value.values).toMatchObject([])
		expect(rentalsModule[1].value.types).not.toMatchObject([])
	})

	test('should contain all two non-dependent but exposed modules', async () => {
		await writeFile(
			path.join(PATH_TO_PROJECT, 'morphir.json'),
			JSON.stringify({ ...morphirJSON, exposedModules: ['Rentals', 'RentalTypes'] })
		)
		await writeFile(
			path.join(PATH_TO_PROJECT, 'src/Package', 'Rentals.elm'),
			concat(
				'module Package.Rentals exposing (..)',
				'',
				'logic: String -> String',
				'logic level =',
				`   String.append "Player level: " level`
			)
		)
		await writeFile(
			path.join(PATH_TO_PROJECT, 'src/Package', 'RentalTypes.elm'),
			concat('module Package.RentalTypes exposing (..)', '', 'type Action', `   = Rent`, `   | Return`)
		)
		const IR = await cli.make(PATH_TO_PROJECT, { typesOnly: true })
		const modules = IR.distribution[3].modules
		expect(modules).toHaveLength(2)
	})

	test('should contain only required modules', async () => {
		await writeFile(
			path.join(PATH_TO_PROJECT, 'src/Package', 'Rentals.elm'),
			concat(
				'module Package.Rentals exposing (..)',
				'',
				'logic: String -> String',
				'logic level =',
				`   String.append "Player level: " level`
			)
		)
		await writeFile(
			path.join(PATH_TO_PROJECT, 'src/Package', 'RentalTypes.elm'),
			concat('module Package.RentalTypes exposing (..)', '', 'type Action', `   = Rent`, `   | Return`)
		)
		const IR = await cli.make(PATH_TO_PROJECT, { typesOnly: true })
		const modules = IR.distribution[3].modules
		expect(modules).toHaveLength(1)
	})

	test('should have private scope if module not exposed', async () => {
		await writeFile(
			path.join(PATH_TO_PROJECT, 'src/Package', 'Rentals.elm'),
			concat(
				'module Package.Rentals exposing (..)',
				'import Package.RentalTypes exposing (Action)',
				'',
				'logic: String -> String',
				'logic level =',
				`   String.append "Player level: " level`
			)
		)
		await writeFile(
			path.join(PATH_TO_PROJECT, 'src/Package', 'RentalTypes.elm'),
			concat('module Package.RentalTypes exposing (..)', '', 'type Action', `   = Rent`, `   | Return`)
		)
		const IR = await cli.make(PATH_TO_PROJECT, { typesOnly: true })
		const modules: Array<[Array<Array<string>>, any]> = IR.distribution[3].modules
		const parseModuleName = (name: Array<Array<string>>): string =>
			name.map(part => part.map(s => s[0].toUpperCase() + s.substring(1)).join('')).join('.')

		const rentalTypeModule = modules.find(module => parseModuleName(module[0]) === 'RentalTypes')
		expect(rentalTypeModule[1].access).toMatch(/[Pp]rivate/)
	})

	test('should fail to update type', async () => {
		await writeFile(
			path.join(PATH_TO_PROJECT, 'src/Package', 'Rentals.elm'),
			concat(
				'module Package.Rentals exposing (..)',
				'import Package.RentalTypes exposing (..)',
				'',
				'type alias RentType = Rent'
			)
		)
		await writeFile(
			path.join(PATH_TO_PROJECT, 'src/Package', 'RentalTypes.elm'),
			concat(
				'module Package.RentalTypes exposing (..)',
				'',
				'type Rent = New | Renew',
				'',
				'type Action = Rentage'
			)
		)
		const IR = await cli.make(PATH_TO_PROJECT, CLI_OPTIONS)

		// make type private
		await writeFile(path.join(PATH_TO_PROJECT, 'morphir-ir.json'), JSON.stringify(IR))
		await writeFile(
			path.join(PATH_TO_PROJECT, 'src/Package', 'RentalTypes.elm'),
			concat(
				'module Package.RentalTypes exposing (Action)',
				'',
				'type Rent = New | Renew',
				'',
				'type Action = Rentage'
			)
		)

		await expect(cli.make(PATH_TO_PROJECT, CLI_OPTIONS)).rejects.toBeInstanceOf(Array)
	})
})
