import React from 'react'
import Styles from './ContributingCompaniesPanel.module.css'

type ContributingCompaniesList = {
	BannerName: string
	BannerUrl: string
}

const users: ContributingCompaniesList[] = [
	{
		BannerName: 'Morgan Stanley',
		BannerUrl: 'https://www.morganstanley.com/etc.clientlibs/msdotcomr4/clientlibs/clientlib-site/resources/img/logo-black.png',
	},
	{
		BannerName: 'Capital One',
		BannerUrl: 'https://upload.wikimedia.org/wikipedia/commons/9/98/Capital_One_logo.svg',
	},
	
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
					<div className="">
						<a href={props.BannerUrl}> 
							<img src={props.BannerUrl} alt={props.BannerUrl}></img>
						</a>
						<br/>
						<a href={props.BannerUrl}>{props.BannerName}</a>
					</div>
				</div>
				))}
			</section>
	    </div>
	)
};
