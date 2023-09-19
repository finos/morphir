import React from 'react'
import Styles from './ContributingCompaniesPanel.module.css'

type ContributingCompaniesList = {
	EpisodeImg: string
	EpisodeUrl: string
	Description: string
}

const users: ContributingCompaniesList[] = [
	{
		EpisodeImg: 'https://resources.finos.org/wp-content/uploads/2022/03/introduction-to-the-morphir-show.jpg',
		EpisodeUrl: 'https://resources.finos.org/znglist/morphir-showcase/?c=cG9zdDoxNTYx',
		Description: 'Introduction to the Morphir Showcase',
	},
	{
		EpisodeImg: 'https://resources.finos.org/wp-content/uploads/2022/03/what-morphir-is-with-stephen-gol.jpg',
		EpisodeUrl: 'https://resources.finos.org/znglist/morphir-showcase/?c=cG9zdDoxNTYz',
		Description: 'What Morphir is with Stephen Goldbaum',
	},
	{
		EpisodeImg: 'https://resources.finos.org/wp-content/uploads/2022/03/how-morphir-works-with-attila-mi-1.jpg',
		EpisodeUrl: 'https://resources.finos.org/znglist/morphir-showcase/?c=cG9zdDoxNTY2',
		Description: 'How Morphir works with Attila Mihaly',
	},
	{
		EpisodeImg: 'https://resources.finos.org/wp-content/uploads/2022/03/why-morphir-is-important-with-co.jpg',
		EpisodeUrl: 'https://resources.finos.org/znglist/morphir-showcase/?c=cG9zdDoxNTY4',
		Description: 'Why Morphir is Important – with Colin, James & Stephen',
	},
	{
		EpisodeImg: 'https://resources.finos.org/wp-content/uploads/2022/03/Screenshot-2022-03-02-at-14.35.18.png',
		EpisodeUrl: 'https://resources.finos.org/znglist/morphir-showcase/?c=cG9zdDoxNTcw',
		Description: 'The Benefits & Use Case of Morphir with Jane, Chris & Stephen',
	},
	{
		EpisodeImg: 'https://resources.finos.org/wp-content/uploads/2022/03/how-to-get-involved-closing-pane.jpg',
		EpisodeUrl: 'https://resources.finos.org/znglist/morphir-showcase/?c=cG9zdDoxNTcy',
		Description: 'How to get involved – Closing Panel Q&A',
	},
	{
		EpisodeImg: 'https://resources.finos.org/wp-content/uploads/2022/03/morphir-showcase-full-show.jpg',
		EpisodeUrl: 'https://resources.finos.org/znglist/morphir-showcase/?c=cG9zdDoxNTU5',
		Description: 'Morphir Showcase – Full Show',
	},
]
export default function UserShowcase (){
        const pinnedUsers = users.filter(user => user.pinned);
          pinnedUsers.sort((a, b) => a.name.localeCompare(b.name))
        
          return (
            <div className="userShowcase productShowcaseSection padding-top--lg padding-bottom--lg" style={{textAlign: 'center'}}>
              <h2>Our contributing partners</h2>
              <p style={{margin: 'auto'}}>The Financial Desktop Connectivity and Collaboration Consortium (FDC3) standards are created and used by <a href="/users">leading organizations across the financial industry</a>. For more detail on who's using FDC3, developer tools, training and examples see the <a href="/community">community page</a>.</p>
              <Showcase users={pinnedUsers} />
            </div>
          );
        };