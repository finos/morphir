import React from 'react'
import Styles from './ContributingCompaniesPanel.module.css'

type ContributingCompaniesList = {
	BannerName: string
	bannerUrl: string
}

const users: ContributingCompaniesList[] = [
	{
		BannerName: 'Morgan Stanley',
		bannerUrl: 'https://www.morganstanley.com/etc.clientlibs/msdotcomr4/clientlibs/clientlib-site/resources/img/logo-black.png',
	},
	{
		BannerName: 'Capital One',
		BannerUrl: 'https://www.capitalone.co.uk/images/c1/brand/logo.svg',
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
					<div className={Styles.videoContainer}>
						<a href={props.EpisodeUrl}> 
							<img src={props.EpisodeImg} alt={props.Description}></img>
						</a>
						<br/>
						<a href={props.EpisodeUrl}>{props.Description}</a>
					</div>
				</div>
				))}
			</section>
	    </div>
	)
};
// const pinnedUsers = users.filter(user => user.pinned);
//   pinnedUsers.sort((a, b) => a.name.localeCompare(b.name))

//   return (
//     <div className="userShowcase productShowcaseSection padding-top--lg padding-bottom--lg" style={{textAlign: 'center'}}>
//       <h2>Our contributing partners</h2>
//       <Showcase users={pinnedUsers} />
//     </div>
//   );