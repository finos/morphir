import useBaseUrl from '@docusaurus/useBaseUrl'
import React from 'react'
import styles from './HomepageFeatures.module.css'
import Link from '@docusaurus/Link'

type FeatureItem = {
	title: string | JSX.Element
	description: JSX.Element
	column?: 3 | 4 | 6 | 12
	image?: string
	brTop?: boolean
	brBottom?: boolean
}

const FeatureList: FeatureItem[] = [
	{
		title: 'What is it?',
		description: (
			<>
				A set of tools for integrating technologies. Morphir is composed of a library of tools that facilitate the
				digitisation of business logic into multiple different languages & platforms. The Morphir framework is unique
				too in that facilities elements of automation and conversion that were previously unavailable in the field of
				finance-tech.
			</>
		),
	},
	{
		title: 'Why is it important?',
		column: 6,
		description: (
			<>
				Makes business logic portable. Business logic digitised provides distinct advantages: capacity for movement
				across departments and fields & the ability to be converted to new languages and applications.
			</>
		),
	},
	{
		title: 'How does it work?',
		column: 6,
		description: (
			<>
				Defines a standard format for storing and sharing business logic. A clear set of standards and format is
				in-place from the input/output, allowing for coherent structure.
			</>
		),
	},
	{
		title: 'What are the benefits?',
		brTop: true,
		brBottom: true,
		description: (
			<div className='container'>
				<section className='row text--center'>
					{[
						{
							title: '✔️ Eliminates technical debt risk',
							description: (
								<>
									Refactoring code libraries is often a harmful and time-sensitive issue for businesses, Morphir ensure
									the standards introduced from input eliminate delays at deployment.
								</>
							),
						},
						{
							title: '✔️ Increases agility',
							description: (
								<>
									Adaptability and usability are key concepts of the Morphir framework, business logic can now move with
									the code, be easily understood and adopted, in an ever-developing eco-system.
								</>
							),
						},
						{
							title: '✔️ Ensures correctness',
							description: (
								<>
									Certifying that specified functions behave as intended from input to output is assured through the
									Morphir library / tool chain.
								</>
							),
						},
						{
							title: '✔️ Disseminates information through automation',
							description: (
								<>
									Morphir's automated processing helps disseminate information which otherwise may not be understood or
									shared at all, a useful tool when brining elements of business logic to conversation outside of its
									immediate audience (i.e developers).
								</>
							),
						},
					].map(({ title, description }, idx) => (
						<div key={idx} className='text--left col col--6'>
							<h3>{title}</h3>
							<div>{description}</div>
						</div>
					))}
				</section>
			</div>
		),
	},
	{
		title: 'An ecosystem of innovative features.',
		column: 6,
		description: (
			<>
				<p>
					Supporting the development of your business' needs in an ever-developing ecosystem based on firm standards and
					the integration of new languages.
				</p>
				<p>
					Check out{' '}
					<a href='https://github.com/stephengoldbaum/morphir-examples/tree/master/tutorial'>
						Stephen Goldbaum's Morphir Examples on GitHub
					</a>
				</p>
			</>
		),
	},
	{
		title: (
			<a href='https://resources.finos.org/znglist/morphir/' target='_blank'>
				Morphir Resource Centre
			</a>
		),
		column: 6,
		description: <>Library of content where you can watch, browse, and read all things morphir related</>,
	},
	{
		title: 'Further Reading',
		description: (
			<div className='container'>
				<section className='row text--center'>
					<div className='col col--4'>
						<h4>Introduction & Background</h4>
						<div className={styles.furtherReading}>
							<Link to={'https://morphir.finos.org/docs/functional-programming'}>Why Functional Programming?</Link>
							<Link to={'https://morphir.finos.org/docs/application-article'}>What's it all about?</Link>
							<Link to={'https://morphir.finos.org/docs/background-story'}>Background</Link>
							<Link to={'https://morphir.finos.org/docs/morphir-community'}>Community</Link>
							<Link to={'https://resources.finos.org/znglist/morphir/'}>Resource Centre</Link>
						</div>
					</div>
					<div className='col col--4'>
						<h4>Using Morphir</h4>
						<div className={styles.furtherReading}>
							<Link to={'https://morphir.finos.org/docs/domain-model'}>What Makes a Good Model</Link>
							<Link to={'https://morphir.finos.org/docs/dev-bots'}>Development Automation (Dev Bots)</Link>
							<Link to={'https://morphir.finos.org/docs/modeling-applications'}>Modeling an Application</Link>
							<Link to={'https://github.com/finos/morphir-examples/tree/main/src/Morphir/Sample/Rules'}>
								Modeling Decision Tables
							</Link>
							<Link to={'https://morphir.finos.org/docs/modeling/modeling-database-developers'}>
								Modeling for database developers
							</Link>
						</div>
					</div>
					<div className='col col--4'>
						<h4>Applicability</h4>
						<div className={styles.furtherReading}>
							<Link
								to={
									'https://github.com/finos/morphir/blob/dcf8dc59b1430170790da3fd6df9d74a0cef7282/docs/presentations/Morphir%20-%20Sharing%20Business%20Logic.pdf'
								}
							>
								Sharing Business Logic Across Application Boundaries
							</Link>
							<Link to={'http://morphir.finos.org/docs/automating-regtech'}>Regulatory Technology</Link>
						</div>
					</div>
				</section>
			</div>
		),
	},
]

function Feature({ title, description, ...props }: FeatureItem) {
	let border = {}
	if (props?.brTop) border = { borderTop: '1px solid var(--ifm-color-primary-darkest)', paddingTop: '1em' }
	if (props?.brBottom)
		border = { ...border, borderBottom: '1px solid var(--ifm-color-primary-darkest)', marginBottom: '1em' }
	return (
		<div className={`col col--${props?.column ? props.column : 12}`}>
			<div className='text--center padding--lg' style={{ ...border }}>
				{props?.image && (
					<img
						className={styles.featureSvg}
						alt={typeof title === 'string' ? title : title.props.children}
						src={useBaseUrl(props.image)}
					/>
				)}
				<div className='padding-horiz--md'>
					<h2>{title}</h2>
					<div>{description}</div>
				</div>
			</div>
		</div>
	)
}

export default function HomepageFeatures(): JSX.Element {
	return (
		<section className={styles.features}>
			<div className='container'>
				<div className='row'>
					{FeatureList.map((props, idx) => (
						<Feature key={idx} {...props} />
					))}
				</div>
			</div>
		</section>
	)
}
