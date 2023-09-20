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
		<section className={Styles.features}>
			<div className='container'>
				<div className='row'>
					{
						users.map((props, idx) => (
						<Feature key={idx} {...props} />
					))
					}
				</div>
			</div>
		</section>
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