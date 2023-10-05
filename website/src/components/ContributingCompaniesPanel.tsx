import React from 'react'
import Styles from './ContributingCompaniesPanel.module.css'

type ContributingCompaniesList = {
	BannerName: string
	BannerUrl: string
}

const users: ContributingCompaniesList[] = [
	{
		BannerName: 'Morgan Stanley',
		BannerUrl: 'https://www.finos.org/hubfs/morgan-stanley-platinum-12-21.png',
	},
	{
		BannerName: 'Capital One',
		BannerUrl: 'https://www.finos.org/hubfs/capital-one-gold-09-20.png',
	},
	{
		BannerName: 'databricks',
		BannerUrl: 'https://www.finos.org/hubfs/databricks-apr-21.png',
	}
	
]
export default function UserShowcase(){
	return (
		<div className='container padding--lg'>
			<section className='row text--center padding-horiz--md'>
				<div className="col col--12">
					<h2>Our contributing Partners</h2>
				</div>
			</section>
			<section className='row text--center padding-horiz--md'>
				{users.map(({...props}, idx) => (
				<div className="col col--4">
					<div className={Styles.companyLogos}>
						<a href={props.BannerUrl}> 
							<img src={props.BannerUrl} alt={props.BannerName}></img>
						</a>
						<br/>
					</div>
				</div>
				))}
			</section>
	    </div>
	)
};
