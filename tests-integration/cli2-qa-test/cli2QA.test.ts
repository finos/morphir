import * as irUtils from '../ts-test-utils/ir-utils'

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
const concat = (...rest: string[]): string => rest.join('\n')

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

	afterEach(async () => {
		const irExists = await util.promisify(fs.exists)(path.join(PATH_TO_PROJECT, 'morphir-ir.json'))
		if (irExists) await util.promisify(fs.rm)(path.join(PATH_TO_PROJECT, 'morphir-ir.json'))
	})

	test('should create an IR with no modules when no elm files are found', async () => {
		const IR = await cli.make(PATH_TO_PROJECT, CLI_OPTIONS)
		const IR2 = await cli2.make(PATH_TO_PROJECT, CLI_OPTIONS)
		expect(JSON.stringify(JSON.parse(IR2))).toBe(JSON.stringify(IR))
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
		const IR2 = await cli2.make(PATH_TO_PROJECT, CLI_OPTIONS)
		expect(JSON.stringify(JSON.parse(IR2))).toBe(JSON.stringify(IR))
	})

	test('should create an IR with no values when no values are found in elm file', async () => {
		await writeFile(
			path.join(PATH_TO_PROJECT, 'src/Package', 'Rentals.elm'),
			concat('module Package.Rentals exposing (Action)', '', 'type Action', `   = Rent`, `   | Return`)
		)

		const IR = await cli.make(PATH_TO_PROJECT, CLI_OPTIONS)
		const IR2 = await cli2.make(PATH_TO_PROJECT, CLI_OPTIONS)
		expect(JSON.stringify(JSON.parse(IR2))).toBe(JSON.stringify(IR))
	})

	test('should create an IR with correct types and values', async () => {
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
		const IR2 = await cli2.make(PATH_TO_PROJECT, CLI_OPTIONS)
		expect(JSON.stringify(JSON.parse(IR2))).toBe(JSON.stringify(IR))
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
		const IR2 = await cli2.make(PATH_TO_PROJECT, { typesOnly: true })
		expect(JSON.stringify(JSON.parse(IR2))).toBe(JSON.stringify(IR))
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
		const IR = await cli.make(PATH_TO_PROJECT, CLI_OPTIONS)
		const IR2 = await cli2.make(PATH_TO_PROJECT, CLI_OPTIONS)
		expect(JSON.stringify(JSON.parse(IR2))).toBe(JSON.stringify(IR))
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
		const IR = await cli.make(PATH_TO_PROJECT, CLI_OPTIONS)
		const IR2 = await cli2.make(PATH_TO_PROJECT, CLI_OPTIONS)
		expect(JSON.stringify(JSON.parse(IR2))).toBe(JSON.stringify(IR))
	})

	test('should have private scope if module not exposed', async () => {
		await writeFile(
			path.join(PATH_TO_PROJECT, 'src/Package', 'Rentals.elm'),
			concat(
				'module Package.Rentals exposing (..)',
				'import Package.RentalTypes exposing (Action)',
				'',
				'type alias New = Action',
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
		const IR = await cli.make(PATH_TO_PROJECT, CLI_OPTIONS)
		const IR2 = await cli2.make(PATH_TO_PROJECT, CLI_OPTIONS)
		expect(JSON.stringify(JSON.parse(IR2))).toBe(JSON.stringify(IR))
	})

	test('should update rentals with new type', async () => {
		await writeFile(
			path.join(PATH_TO_PROJECT, 'src/Package', 'Rentals.elm'),
			concat('module Package.Rentals exposing (..)', '', 'type Type = Type String')
		)
		let IR = await cli.make(PATH_TO_PROJECT, CLI_OPTIONS)
		let IR2 = await cli2.make(PATH_TO_PROJECT, CLI_OPTIONS)
		expect(JSON.stringify(JSON.parse(IR2))).toBe(JSON.stringify(IR))

		//update the module with a new type
		await writeFile(path.join(PATH_TO_PROJECT, 'morphir-ir.json'), JSON.stringify(JSON.parse(IR2)))
		await writeFile(
			path.join(PATH_TO_PROJECT, 'src/Package', 'Rentals.elm'),
			concat('module Package.Rentals exposing ()', '', 'type Type = Type String', 'type Foo = Foo')
		)
		IR = await cli.make(PATH_TO_PROJECT, CLI_OPTIONS)
		IR2 = await cli2.make(PATH_TO_PROJECT, CLI_OPTIONS)
		expect(JSON.stringify(JSON.parse(IR2))).toBe(JSON.stringify(IR))

		//update the module with a new type and delete an existing type
		await writeFile(path.join(PATH_TO_PROJECT, 'morphir-ir.json'), JSON.stringify(JSON.parse(IR2)))
		await writeFile(
			path.join(PATH_TO_PROJECT, 'src/Package', 'Rentals.elm'),
			concat('module Package.Rentals exposing (Bar)', '', 'type Bar = Bar String', 'type Foo = Foo')
		)
		IR = await cli.make(PATH_TO_PROJECT, CLI_OPTIONS)
		IR2 = await cli2.make(PATH_TO_PROJECT, CLI_OPTIONS)
		expect(JSON.stringify(JSON.parse(IR2))).toBe(JSON.stringify(IR))
	})

	test('should update rentals with new value', async () => {
		await writeFile(
			path.join(PATH_TO_PROJECT, 'src/Package', 'Rentals.elm'),
			concat('module Package.Rentals exposing (..)', '', 'level = 1')
		)
		let IR = await cli.make(PATH_TO_PROJECT, CLI_OPTIONS)
		let IR2 = await cli2.make(PATH_TO_PROJECT, CLI_OPTIONS)
		expect(JSON.stringify(JSON.parse(IR2))).toBe(JSON.stringify(IR))

		//update the module with a new value
		await writeFile(path.join(PATH_TO_PROJECT, 'morphir-ir.json'), JSON.stringify(JSON.parse(IR2)))
		await writeFile(
			path.join(PATH_TO_PROJECT, 'src/Package', 'Rentals.elm'),
			concat(
				'module Package.Rentals exposing (..)',
				'',
				'level = 1',
				'',
				'logic : String -> String',
				'logic l = ',
				`   String.append "Player level: " l`
			)
		)
		IR = await cli.make(PATH_TO_PROJECT, CLI_OPTIONS)
		IR2 = await cli2.make(PATH_TO_PROJECT, CLI_OPTIONS)

		expect(JSON.stringify(JSON.parse(IR2))).toBe(JSON.stringify(IR))

		//update the module with a new value and delete an existing value
		await writeFile(path.join(PATH_TO_PROJECT, 'morphir-ir.json'), JSON.stringify(JSON.parse(IR2)))
		await writeFile(
			path.join(PATH_TO_PROJECT, 'src/Package', 'Rentals.elm'),
			concat(
				'module Package.Rentals exposing (..)',
				'',
				'playerName = "Frank"',
				'',
				'logic : String -> String',
				'logic l =',
				'   String.append "Player level: " l'
			)
		)
		IR = await cli.make(PATH_TO_PROJECT, CLI_OPTIONS)
		IR2 = await cli2.make(PATH_TO_PROJECT, CLI_OPTIONS)
		expect(JSON.stringify(JSON.parse(IR2))).toBe(JSON.stringify(IR))
	})

	test.skip('should update value access appropriately', async () => {
		await writeFile(
			path.join(PATH_TO_PROJECT, 'src/Package', 'Rentals.elm'),
			concat(
				'module Package.Rentals exposing (..)',
				'',
				'level = 1',
				'',
				'logic : String -> String',
				'logic l = ',
				`   String.append "Player level: " l`
			)
		)
		let IR = await cli.make(PATH_TO_PROJECT, CLI_OPTIONS)
		let IR2 = await cli2.make(PATH_TO_PROJECT, CLI_OPTIONS)
		expect(JSON.stringify(JSON.parse(IR2))).toBe(JSON.stringify(IR))

		//update the value access
		await writeFile(path.join(PATH_TO_PROJECT, 'morphir-ir.json'), JSON.stringify(JSON.parse(IR2)))
		await writeFile(
			path.join(PATH_TO_PROJECT, 'src/Package', 'Rentals.elm'),
			concat(
				'module Package.Rentals exposing (logic)',
				'',
				'level = 1',
				'',
				'logic : String -> String',
				'logic l = ',
				`   String.append "Player level: " l`
			)
		)
		IR = await cli.make(PATH_TO_PROJECT, CLI_OPTIONS)
		IR2 = await cli2.make(PATH_TO_PROJECT, CLI_OPTIONS)
		expect(JSON.stringify(JSON.parse(IR2))).toBe(JSON.stringify(IR))
	})

	test('should update type access appropraitely', async () => {
		await writeFile(
			path.join(PATH_TO_PROJECT, 'src/Package', 'Rentals.elm'),
			concat(
				'module Package.Rentals exposing (..)',
				'',
				'type MyType = New',
				'',
				'logic : String -> String',
				'logic l = ',
				`   String.append "Player level: " l`
			)
		)
		let IR = await cli.make(PATH_TO_PROJECT, CLI_OPTIONS)
		let IR2 = await cli2.make(PATH_TO_PROJECT, CLI_OPTIONS)
		expect(JSON.stringify(JSON.parse(IR2))).toBe(JSON.stringify(IR))

		//update the type access
		await writeFile(path.join(PATH_TO_PROJECT, 'morphir-ir.json'), JSON.stringify(JSON.parse(IR2)))
		await writeFile(
			path.join(PATH_TO_PROJECT, 'src/Package', 'Rentals.elm'),
			concat(
				'module Package.Rentals exposing (logic)',
				'',
				'type MyType = New',
				'',
				'logic : String -> String',
				'logic l = ',
				`   String.append "Player level: " l`
			)
		)
		IR = await cli.make(PATH_TO_PROJECT, CLI_OPTIONS)
		IR2 = await cli2.make(PATH_TO_PROJECT, CLI_OPTIONS)
		expect(JSON.stringify(JSON.parse(IR2))).toBe(JSON.stringify(IR))
	})

	test('should update constructor access appropraitely', async () => {
		await writeFile(
			path.join(PATH_TO_PROJECT, 'src/Package', 'Rentals.elm'),
			concat(
				'module Package.Rentals exposing (..)',
				'',
				'type User = New | Existing',
				'',
				'logic : String -> String',
				'logic l = ',
				`   String.append "Player level: " l`
			)
		)
		let IR = await cli.make(PATH_TO_PROJECT, CLI_OPTIONS)
		let IR2 = await cli2.make(PATH_TO_PROJECT, CLI_OPTIONS)
		expect(JSON.stringify(JSON.parse(IR2))).toBe(JSON.stringify(IR))

		//update the value access
		await writeFile(path.join(PATH_TO_PROJECT, 'morphir-ir.json'), JSON.stringify(JSON.parse(IR2)))
		await writeFile(
			path.join(PATH_TO_PROJECT, 'src/Package', 'Rentals.elm'),
			concat(
				'module Package.Rentals exposing (User, logic)',
				'',
				'type User = New | Existing',
				'',
				'logic : String -> String',
				'logic l = ',
				`   String.append "Player level: " l`
			)
		)
		IR = await cli.make(PATH_TO_PROJECT, CLI_OPTIONS)
		IR2 = await cli2.make(PATH_TO_PROJECT, CLI_OPTIONS)
		expect(JSON.stringify(JSON.parse(IR2))).toBe(JSON.stringify(IR))
	})

    test('should add value documentation correctly', async () => {
		// add a type documentation
		await writeFile(
			path.join(PATH_TO_PROJECT, 'src/Package', 'Rentals.elm'),
			concat(
				'module Package.Rentals exposing (..)',
				'',
				'{-| documentation for foo -}',
				'foo = 1'
			)
		)
        let IR = await cli.make(PATH_TO_PROJECT, CLI_OPTIONS)
		let IR2 = await cli2.make(PATH_TO_PROJECT, CLI_OPTIONS)
		expect(JSON.stringify(JSON.parse(IR2))).toBe(JSON.stringify(IR))
	})

    test('should add type documentation correctly', async () => {
		// add a type documentation
		await writeFile(
			path.join(PATH_TO_PROJECT, 'src/Package', 'Rentals.elm'),
			concat(
				'module Package.Rentals exposing (..)',
				'',
				'{-| type to track user stage -}',
				'type User = New | Existing'
			)
		)
        let IR = await cli.make(PATH_TO_PROJECT, CLI_OPTIONS)
		let IR2 = await cli2.make(PATH_TO_PROJECT, CLI_OPTIONS)
		expect(JSON.stringify(JSON.parse(IR2))).toBe(JSON.stringify(IR))

	})

	test('should update type documentation correctly', async () => {
		await writeFile(
			path.join(PATH_TO_PROJECT, 'src/Package', 'Rentals.elm'),
			concat('module Package.Rentals exposing (..)', '', 'type User = New | Existing')
		)
		let IR = await cli.make(PATH_TO_PROJECT, CLI_OPTIONS)
		let IR2 = await cli2.make(PATH_TO_PROJECT, CLI_OPTIONS)
		expect(JSON.stringify(JSON.parse(IR2))).toBe(JSON.stringify(IR))

		// add a type documentation
		await writeFile(path.join(PATH_TO_PROJECT, 'morphir-ir.json'), JSON.stringify(JSON.parse(IR2)))
		await writeFile(
			path.join(PATH_TO_PROJECT, 'src/Package', 'Rentals.elm'),
			concat(
				'module Package.Rentals exposing (..)',
				'',
				'{-| type to track user stage -}',
				'type User = New | Existing'
			)
		)
		IR = await cli.make(PATH_TO_PROJECT, CLI_OPTIONS)
		IR2 = await cli2.make(PATH_TO_PROJECT, CLI_OPTIONS)
		expect(JSON.stringify(JSON.parse(IR2))).toBe(JSON.stringify(IR))

		// update the type documentation
		await writeFile(path.join(PATH_TO_PROJECT, 'morphir-ir.json'), JSON.stringify(JSON.parse(IR2)))
		await writeFile(
			path.join(PATH_TO_PROJECT, 'src/Package', 'Rentals.elm'),
			concat(
				'module Package.Rentals exposing (..)',
				'',
				'{-| a type that tells what type a user is -}',
				'type User = New | Existing'
			)
		)
		IR = await cli.make(PATH_TO_PROJECT, CLI_OPTIONS)
		IR2 = await cli2.make(PATH_TO_PROJECT, CLI_OPTIONS)
		expect(JSON.stringify(JSON.parse(IR2))).toBe(JSON.stringify(IR))
	})
})
