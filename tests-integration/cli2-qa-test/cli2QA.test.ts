import * as irUtils from './ir-utils'

const path = require('path')
const util = require('util')
const fs = require('fs')
const readFile = fs.readFileSync
const mkdir = fs.mkdirSync
const rmdir = util.promisify(fs.rm)
const cli2 = require('../../cli2/lib/cli')
const cli = require('../../cli/cli')
const writeFile = util.promisify(fs.writeFile)

// utility function for joining strings with newlines
const join = (...rest: string[]): string => rest.join('\n')

describe('Testing morphir-elm make and morphir make command', () => {
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
		const IR2 = await cli2.make(PATH_TO_PROJECT, CLI_OPTIONS)
		const IR2WithoutDeps = irUtils.removePackageDependencies(JSON.parse(IR2))
		expect(JSON.stringify(IR2WithoutDeps)).toBe(JSON.stringify(IR)) 
	})

	test('should create an IR with no types when no types are found in elm file', async () => {
		await writeFile(
			path.join(PATH_TO_PROJECT, 'src/Package', 'Rentals.elm'),
			join(
				'module Package.Rentals exposing (logic)',
				'',
				'logic: String -> String',
				'logic level =',
				`   String.append "Player level: " level`
			)
		)

		const IR = await cli.make(PATH_TO_PROJECT, CLI_OPTIONS)
		const IR2 = await cli2.make(PATH_TO_PROJECT, CLI_OPTIONS)
		const IR2WithoutDeps = irUtils.removePackageDependencies(JSON.parse(IR2))
		expect(JSON.stringify(IR2WithoutDeps)).toBe(JSON.stringify(IR)) 
	})

	test('should create an IR with no values when no values are found in elm file', async () => {
		await writeFile(
			path.join(PATH_TO_PROJECT, 'src/Package', 'Rentals.elm'),
			join('module Package.Rentals exposing (Action)', '', 'type Action', `   = Rent`, `   | Return`)
		)

        const IR = await cli.make(PATH_TO_PROJECT, CLI_OPTIONS)
		const IR2 = await cli2.make(PATH_TO_PROJECT, CLI_OPTIONS)
        const IR2WithoutDeps = irUtils.removePackageDependencies(JSON.parse(IR2))
		expect(JSON.stringify(IR2WithoutDeps)).toBe(JSON.stringify(IR)) 
	})

	test('should create an IR with correct types and values', async () => {
		await writeFile(
			path.join(PATH_TO_PROJECT, 'src/Package', 'Rentals.elm'),
			join(
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
		const IR2 = await cli2.make(PATH_TO_PROJECT, CLI_OPTIONS)
        const IR2WithoutDeps = irUtils.removePackageDependencies(JSON.parse(IR2))
		expect(JSON.stringify(IR2WithoutDeps)).toBe(JSON.stringify(IR)) 
	})

	test('should create an IR with only types when typesOnly is set to true', async () => {
		await writeFile(
			path.join(PATH_TO_PROJECT, 'src/Package', 'Rentals.elm'),
			join(
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
		);
		const IR = await cli.make(PATH_TO_PROJECT, CLI_OPTIONS)
		const IR2 = await cli2.make(PATH_TO_PROJECT, CLI_OPTIONS)
        const IR2WithoutDeps = irUtils.removePackageDependencies(JSON.parse(IR2))
		expect(JSON.stringify(IR2WithoutDeps)).toBe(JSON.stringify(IR)) 
	});

	test('should contain all two non-dependent but exposed modules', async () => {
		await writeFile(
			path.join(PATH_TO_PROJECT, 'morphir.json'),
			JSON.stringify({ ...morphirJSON, exposedModules: ['Rentals', 'RentalTypes'] })
		)
		await writeFile(
			path.join(PATH_TO_PROJECT, 'src/Package', 'Rentals.elm'),
			join(
				'module Package.Rentals exposing (..)',
				'',
				'logic: String -> String',
				'logic level =',
				`   String.append "Player level: " level`
			)
		)
		await writeFile(
			path.join(PATH_TO_PROJECT, 'src/Package', 'RentalTypes.elm'),
			join('module Package.RentalTypes exposing (..)', '', 'type Action', `   = Rent`, `   | Return`)
		)
		const IR = await cli.make(PATH_TO_PROJECT, CLI_OPTIONS)
		const IR2 = await cli2.make(PATH_TO_PROJECT, CLI_OPTIONS)
        const IR2WithoutDeps = irUtils.removePackageDependencies(JSON.parse(IR2))
		expect(JSON.stringify(IR2WithoutDeps)).toBe(JSON.stringify(IR)) 
	})

	test('should contain only required modules', async () => {
		await writeFile(
			path.join(PATH_TO_PROJECT, 'src/Package', 'Rentals.elm'),
			join(
				'module Package.Rentals exposing (..)',
				'',
				'logic: String -> String',
				'logic level =',
				`   String.append "Player level: " level`
			)
		)
		await writeFile(
			path.join(PATH_TO_PROJECT, 'src/Package', 'RentalTypes.elm'),
			join('module Package.RentalTypes exposing (..)', '', 'type Action', `   = Rent`, `   | Return`)
		)
		const IR = await cli.make(PATH_TO_PROJECT, CLI_OPTIONS)
		const IR2 = await cli2.make(PATH_TO_PROJECT, CLI_OPTIONS)
        const IR2WithoutDeps = irUtils.removePackageDependencies(JSON.parse(IR2))
		expect(JSON.stringify(IR2WithoutDeps)).toBe(JSON.stringify(IR)) 
	})

	test('should have private scope if module not exposed', async () => {
		await writeFile(
			path.join(PATH_TO_PROJECT, 'src/Package', 'Rentals.elm'),
			join(
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
			join('module Package.RentalTypes exposing (..)', '', 'type Action', `   = Rent`, `   | Return`)
		)
		const IR = await cli.make(PATH_TO_PROJECT, CLI_OPTIONS)
		const IR2 = await cli2.make(PATH_TO_PROJECT, CLI_OPTIONS)
        const IR2WithoutDeps = irUtils.removePackageDependencies(JSON.parse(IR2))
		expect(JSON.stringify(IR2WithoutDeps)).toBe(JSON.stringify(IR)) 
	})

	test('should update rentals with new type', async () => {
		await writeFile(
			path.join(PATH_TO_PROJECT, 'src/Package', 'Rentals.elm'),
			join('module Package.Rentals exposing (..)', '', 'type Type = Type String')
		)
		let IR = await cli.make(PATH_TO_PROJECT, CLI_OPTIONS)
		let IR2 = await cli2.make(PATH_TO_PROJECT, CLI_OPTIONS)
        let IR2WithoutDeps = irUtils.removePackageDependencies(JSON.parse(IR2))
		expect(JSON.stringify(IR2WithoutDeps)).toBe(JSON.stringify(IR)) 

		//update the module with a new type
		await writeFile(path.join(PATH_TO_PROJECT, 'morphir-ir.json'), JSON.stringify(JSON.parse(IR)))
		await writeFile(
			path.join(PATH_TO_PROJECT, 'src/Package', 'Rentals.elm'),
			join('module Package.Rentals exposing (..)', '', 'type Type = Type String', 'type Foo = Foo')
		)
		IR = await cli.make(PATH_TO_PROJECT, CLI_OPTIONS)
		IR2 = await cli2.make(PATH_TO_PROJECT, CLI_OPTIONS)
        IR2WithoutDeps = irUtils.removePackageDependencies(JSON.parse(IR2))
		expect(JSON.stringify(IR2WithoutDeps)).toBe(JSON.stringify(IR)) 

		//update the module with a new type and delete an existing type
		await writeFile(path.join(PATH_TO_PROJECT, 'morphir-ir.json'), JSON.stringify(JSON.parse(IR)))
		await writeFile(
			path.join(PATH_TO_PROJECT, 'src/Package', 'Rentals.elm'),
			join('module Package.Rentals exposing (..)', '', 'type Bar = Bar String', 'type Foo = Foo')
		)
		IR = await cli.make(PATH_TO_PROJECT, CLI_OPTIONS)
		IR2 = await cli2.make(PATH_TO_PROJECT, CLI_OPTIONS)
        IR2WithoutDeps = irUtils.removePackageDependencies(JSON.parse(IR2))
		expect(JSON.stringify(IR2WithoutDeps)).toBe(JSON.stringify(IR)) 
	})

	test('should update rentals with new value', async () => {
		await writeFile(
			path.join(PATH_TO_PROJECT, 'src/Package', 'Rentals.elm'),
			join('module Package.Rentals exposing (..)', '', 'level = 1')
		)
		let IR = await cli.make(PATH_TO_PROJECT, CLI_OPTIONS)
		let IR2 = await cli2.make(PATH_TO_PROJECT, CLI_OPTIONS)
        let IR2WithoutDeps = irUtils.removePackageDependencies(JSON.parse(IR2))
		expect(JSON.stringify(IR2WithoutDeps)).toBe(JSON.stringify(IR)) 

		//update the module with a new value
		await writeFile(path.join(PATH_TO_PROJECT, 'morphir-ir.json'), JSON.stringify(JSON.parse(IR)))
		await writeFile(
			path.join(PATH_TO_PROJECT, 'src/Package', 'Rentals.elm'),
			join(
				'module Package.Rentals exposing (..)',
				'',
				'level = 1',
				'',
				'logic l = ',
				`   String.append "Player level: " l`
			)
		)
		IR = await cli.make(PATH_TO_PROJECT, CLI_OPTIONS)
		IR2 = await cli2.make(PATH_TO_PROJECT, CLI_OPTIONS)
        IR2WithoutDeps = irUtils.removePackageDependencies(JSON.parse(IR2))
		expect(JSON.stringify(IR2WithoutDeps)).toBe(JSON.stringify(IR)) 

		//update the module with a new value and delete an existing value
		await writeFile(path.join(PATH_TO_PROJECT, 'morphir-ir.json'), JSON.stringify(JSON.parse(IR)))
		await writeFile(
			path.join(PATH_TO_PROJECT, 'src/Package', 'Rentals.elm'),
			join(
				'module Package.Rentals exposing (..)',
				'',
				'playerName = "Frank"',
				'',
				'logic l =',
				'   String.append "Player level: " l'
			)
		)
		IR = await cli.make(PATH_TO_PROJECT, CLI_OPTIONS)
		IR2 = await cli2.make(PATH_TO_PROJECT, CLI_OPTIONS)
        IR2WithoutDeps = irUtils.removePackageDependencies(JSON.parse(IR2))
		expect(JSON.stringify(IR2WithoutDeps)).toBe(JSON.stringify(IR)) 
	})
})
