import React from 'react'
import styles from './ContributingCompaniesPanel.module.css'

type ContributingCompany = {
	name: string
	logoUrl: string
}

const companies: ContributingCompany[] = [
	{
		name: 'Morgan Stanley',
		logoUrl: 'https://www.finos.org/hubfs/morgan-stanley-platinum-12-21.png',
	},
	{
		name: 'Capital One',
		logoUrl: 'https://www.finos.org/hubfs/capital-one-gold-09-20.png',
	},
	{
		name: 'Databricks',
		logoUrl: 'https://www.finos.org/hubfs/databricks-apr-21.png',
	},
]

export default function ContributingCompaniesPanel(): JSX.Element {
	return (
		<section className={styles.panel}>
			<div className='container'>
				<div className={styles.header}>
					<h2>Our Contributing Partners</h2>
					<p>Organizations supporting Morphir with collaboration and resources.</p>
				</div>
				<div className={styles.logoGrid}>
					{companies.map((company) => (
						<div key={company.name} className={styles.logoCard}>
							<img
								className={styles.logo}
								alt={`${company.name} logo`}
								src={company.logoUrl}
								loading='lazy'
							/>
						</div>
					))}
				</div>
			</div>
		</section>
	)
}
