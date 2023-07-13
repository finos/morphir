import React from 'react'
import Styles from './MediaPanel.module.css'

type MediaList = {
	EpisodeImg: string
	EpisodeUrl: string
	Description: string
}

const MediaList: MediaList[] = [
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

export default function MediaPanel (): JSX.Element{
	return(
		<div className='container padding--lg'>
			<section className='row text--center padding-horiz--md'>
				<div className="col col--12">
					<h2>Morphir in the Media</h2>
				</div>
			</section>
			<section className='row text--center padding-horiz--md'>
				{MediaList.map(({...props}, idx) => (
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
	)}
