import * as irUtils from '../ts-test-utils/ir-utils'

const path = require('path')
const util = require('util')
const fs = require('fs')
const mkdir = fs.mkdirSync
const rmdir = util.promisify(fs.rm)
const cli = require('../../cli2/lib/cli')
const writeFile = util.promisify(fs.writeFile)

// utility function for joining strings with newlines
const concat = (...rest: string[]): string => rest.join('\n')

describe('Testing Morphir make command', () => {
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
		expect(irUtils.getModules(JSON.parse(IR))).toMatchObject([])
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
		const typesInRental = irUtils.getModuleTypesFromIR('Rentals', JSON.parse(IR))
		expect(typesInRental).toMatchObject([])
	})

	test('should create an IR with no values when no values are found in elm file', async () => {
		await writeFile(
			path.join(PATH_TO_PROJECT, 'src/Package', 'Rentals.elm'),
			concat('module Package.Rentals exposing (Action)', '', 'type Action', `   = Rent`, `   | Return`)
		)

		const IR = await cli.make(PATH_TO_PROJECT, CLI_OPTIONS)
		const valuesInRental = irUtils.getModuleValuesFromIR('Rentals', JSON.parse(IR))
		expect(valuesInRental).toMatchObject([])
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
		const rentalsModule = irUtils.findModuleByName('Rentals', JSON.parse(IR))
		expect(irUtils.getValuesFromModule(rentalsModule)).not.toMatchObject([])
		expect(irUtils.getTypesFromModule(rentalsModule)).not.toMatchObject([])
		expect(irUtils.moduleHasType(rentalsModule, 'Action')).toBe(true)
		expect(irUtils.moduleHasValue(rentalsModule, 'logic')).toBe(true)
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
		const rentalsModule = irUtils.findModuleByName('Rentals', JSON.parse(IR))
		expect(irUtils.getTypesFromModule(rentalsModule)).not.toMatchObject([])
		expect(irUtils.getValuesFromModule(rentalsModule)).toMatchObject([])
		expect(irUtils.moduleHasType(rentalsModule, 'Action')).toBe(true)
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
		const modules = irUtils.getModules(JSON.parse(IR))
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
		const IR = await cli.make(PATH_TO_PROJECT, CLI_OPTIONS)
		const modules = irUtils.getModules(JSON.parse(IR))
		expect(modules).toHaveLength(1)
	})

	test('should have private scope if module not exposed', async () => {
		await writeFile(
			path.join(PATH_TO_PROJECT, 'src/Package', 'Rentals.elm'),
			concat(
				'module Package.Rentals exposing (logic)',
                'import Package.RentalTypes exposing (..)',
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
		const rentalTypeModule = irUtils.findModuleByName('RentalTypes', JSON.parse(IR))
		expect(irUtils.getModuleAccess(rentalTypeModule)).toMatch(/[Pp]rivate/)
	})

	test('should have public scope if module is implicitly exposed', async () => {
		await writeFile(
			path.join(PATH_TO_PROJECT, 'src/Package', 'Rentals.elm'),
			concat(
				'module Package.Rentals exposing (..)',
				'import Package.RentalTypes exposing (..)',
				'',
				'type alias New = Action', // implicitly exposing RentalTypes where Action is defined
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
		const rentalTypeModule = irUtils.findModuleByName('RentalTypes', JSON.parse(IR))
		expect(irUtils.getModuleAccess(rentalTypeModule)).toMatch(/[Pp]ublic/)
	})

	test('should update rentals with new type', async () => {
		await writeFile(
			path.join(PATH_TO_PROJECT, 'src/Package', 'Rentals.elm'),
			concat('module Package.Rentals exposing (..)', '', 'type Type = Type String')
		)
		let IR = await cli.make(PATH_TO_PROJECT, CLI_OPTIONS)
		let rentalsModule = irUtils.findModuleByName('Rentals', JSON.parse(IR))
		expect(irUtils.moduleHasType(rentalsModule, 'Type')).toBe(true)

		//update the module with a new type
		await writeFile(path.join(PATH_TO_PROJECT, 'morphir-ir.json'), JSON.stringify(JSON.parse(IR)))
		await writeFile(
			path.join(PATH_TO_PROJECT, 'src/Package', 'Rentals.elm'),
			concat('module Package.Rentals exposing (..)', '', 'type Type = Type String', 'type Foo = Foo')
		)
		IR = await cli.make(PATH_TO_PROJECT, CLI_OPTIONS)
		rentalsModule = irUtils.findModuleByName('Rentals', JSON.parse(IR))
		expect(irUtils.moduleHasType(rentalsModule, 'Type')).toBe(true)
		expect(irUtils.moduleHasType(rentalsModule, 'Foo')).toBe(true)

		//update the module with a new type and delete an existing type
		await writeFile(path.join(PATH_TO_PROJECT, 'morphir-ir.json'), JSON.stringify(JSON.parse(IR)))
		await writeFile(
			path.join(PATH_TO_PROJECT, 'src/Package', 'Rentals.elm'),
			concat('module Package.Rentals exposing (..)', '', 'type Bar = Bar String', 'type Foo = Foo')
		)
		IR = await cli.make(PATH_TO_PROJECT, CLI_OPTIONS)
		rentalsModule = irUtils.findModuleByName('Rentals', JSON.parse(IR))
		expect(irUtils.moduleHasType(rentalsModule, 'Bar')).toBe(true)
		expect(irUtils.moduleHasType(rentalsModule, 'Foo')).toBe(true)
		expect(irUtils.moduleHasType(rentalsModule, 'Type')).toBe(false)
	})

	test('should update rentals with new value', async () => {
		await writeFile(
			path.join(PATH_TO_PROJECT, 'src/Package', 'Rentals.elm'),
			concat('module Package.Rentals exposing (..)', '', 'level = 1')
		)
		let IR = await cli.make(PATH_TO_PROJECT, CLI_OPTIONS)
		let rentalsModule = irUtils.findModuleByName('Rentals', JSON.parse(IR))
		expect(irUtils.moduleHasValue(rentalsModule, 'level')).toBe(true)

		//update the module with a new value
		await writeFile(path.join(PATH_TO_PROJECT, 'morphir-ir.json'), JSON.stringify(JSON.parse(IR)))
		await writeFile(
			path.join(PATH_TO_PROJECT, 'src/Package', 'Rentals.elm'),
			concat(
				'module Package.Rentals exposing (..)',
				'',
				'level = 1',
				'',
				'logic l = ',
				`   String.append "Player level: " l`
			)
		)
		IR = await cli.make(PATH_TO_PROJECT, CLI_OPTIONS)
		rentalsModule = irUtils.findModuleByName('Rentals', JSON.parse(IR))
		expect(irUtils.moduleHasValue(rentalsModule, 'level')).toBe(true)
		expect(irUtils.moduleHasValue(rentalsModule, 'logic')).toBe(true)

		//update the module with a new value and delete an existing value
		await writeFile(path.join(PATH_TO_PROJECT, 'morphir-ir.json'), JSON.stringify(JSON.parse(IR)))
		await writeFile(
			path.join(PATH_TO_PROJECT, 'src/Package', 'Rentals.elm'),
			concat(
				'module Package.Rentals exposing (..)',
				'',
				'playerName = "Frank"',
				'',
				'logic l =',
				'   String.append "Player level: " l'
			)
		)
		IR = await cli.make(PATH_TO_PROJECT, CLI_OPTIONS)
		rentalsModule = irUtils.findModuleByName('Rentals', JSON.parse(IR))
		expect(irUtils.moduleHasValue(rentalsModule, 'playerName')).toBe(true)
		expect(irUtils.moduleHasValue(rentalsModule, 'logic')).toBe(true)
		expect(irUtils.moduleHasValue(rentalsModule, 'level')).toBe(false)
	})

	test('should add type documentation', async () => {
		// add a type documentation
		await writeFile(
			path.join(PATH_TO_PROJECT, 'src/Package', 'Rentals.elm'),
			concat(
				'module Package.Rentals exposing (..)',
				'',
				'{-| documentation for Type -}',
				'type alias Type = String'
			)
		)
		let IR = await cli.make(PATH_TO_PROJECT, CLI_OPTIONS)
		const rentalModule = irUtils.findModuleByName('Rentals', JSON.parse(IR))
		const typ = irUtils.findTypeByName(rentalModule, 'Type')
		const doc: string = irUtils.getTypeDoc(typ)
		expect(doc).toMatch(/.*documentation for Type.*/)
	})

	test('should update type documentation', async () => {
		// add a type documentation
		await writeFile(
			path.join(PATH_TO_PROJECT, 'src/Package', 'Rentals.elm'),
			concat(
				'module Package.Rentals exposing (..)',
				'',
				'{-| documentation for Type -}',
				'type alias Type = String'
			)
		)
		let IR = await cli.make(PATH_TO_PROJECT, CLI_OPTIONS)

		// write the IR to disk
		await writeFile(path.join(PATH_TO_PROJECT, 'morphir-ir.json'), JSON.stringify(JSON.parse(IR)))

		// update a value documentation
		await writeFile(
			path.join(PATH_TO_PROJECT, 'src/Package', 'Rentals.elm'),
			concat(
				'module Package.Rentals exposing (..)',
				'',
				'{-| documentation for Type updated -}',
				'type alias Type = String'
			)
		)
		IR = await cli.make(PATH_TO_PROJECT, CLI_OPTIONS)
		const rentalModule = irUtils.findModuleByName('Rentals', JSON.parse(IR))
		const typ = irUtils.findTypeByName(rentalModule, 'Type')
		const doc: string = irUtils.getTypeDoc(typ)
		expect(doc).toMatch(/.*documentation for Type updated.*/)
	})

	test.skip('should fail to update type', async () => {
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

		await writeFile(path.join(PATH_TO_PROJECT, 'morphir-ir.json'), JSON.stringify(JSON.parse(IR)))

		// make type private
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

	test('should make value private', async () => {
		await writeFile(
			path.join(PATH_TO_PROJECT, 'src/Package', 'Rentals.elm'),
			concat(
				'module Package.Rentals exposing (logic)',
				'',
				'privateValue = 1',
				'',
				'logic l = ',
				'   String.append "Player level: " l'
			)
		)
		const IR = await cli.make(PATH_TO_PROJECT, CLI_OPTIONS)
		const rentalModule = irUtils.findModuleByName('Rentals', JSON.parse(IR))
		expect(irUtils.getValueAccess(rentalModule, 'privateValue')).toMatch(/[Pp]rivate/)
	})

	test('should add value documentation correctly', async () => {
		// add a value documentation
		await writeFile(
			path.join(PATH_TO_PROJECT, 'src/Package', 'Rentals.elm'),
			concat('module Package.Rentals exposing (..)', '', '{-| documentation for foo -}', 'foo = 1')
		)
		let IR = await cli.make(PATH_TO_PROJECT, CLI_OPTIONS)
		const rentalModule = irUtils.findModuleByName('Rentals', JSON.parse(IR))
		const foo = irUtils.findValueByName(rentalModule, 'foo')
		const doc: string = irUtils.getValueDoc(foo)
		expect(doc).toMatch(/.*documentation for foo.*/)
	})

	test('should update value documentation correctly', async () => {
		// add a value documentation
		await writeFile(
			path.join(PATH_TO_PROJECT, 'src/Package', 'Rentals.elm'),
			concat('module Package.Rentals exposing (..)', '', '{-| documentation for foo -}', 'foo = 1')
		)
		let IR = await cli.make(PATH_TO_PROJECT, CLI_OPTIONS)

		// write the IR to disk
		await writeFile(path.join(PATH_TO_PROJECT, 'morphir-ir.json'), JSON.stringify(JSON.parse(IR)))

		// update a value documentation
		await writeFile(
			path.join(PATH_TO_PROJECT, 'src/Package', 'Rentals.elm'),
			concat('module Package.Rentals exposing (..)', '', '{-| foo documentation -}', 'foo = 1')
		)
		IR = await cli.make(PATH_TO_PROJECT, CLI_OPTIONS)
		const rentalModule = irUtils.findModuleByName('Rentals', JSON.parse(IR))
		const foo = irUtils.findValueByName(rentalModule, 'foo')
		const doc: string = irUtils.getValueDoc(foo)
		expect(doc).toMatch(/.*foo documentation.*/)
	})
})
