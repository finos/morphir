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

// export default function MedialPanel(): JSX.Element {
// 	return (
// 		<section>
// 			{MediaList.map((props, idx) => (
// 				<Media key={idx} {...props} />
// 			))}
// 		</section>
// 	)
// }

// function Media({ ...props }: MediaList) {
// 	return (
// 		<div className='mediaPanel'>
// 			<table>
// 				<thead>
// 				<tr>
// 					<th>Episode</th>
// 					<th>Description</th>
// 				</tr>
// 				</thead>
// 				<tr>
// 					<td>
// 						<a href={props.EpisodeUrl}>
// 							<img width='250' src={props.EpisodeImg}></img>
// 						</a>
// 					</td>
// 					<td style={{ width: 478.2 }}>
// 						<a href={props.EpisodeUrl}>{props.Description} </a>
// 					</td>
// 				</tr>
// 			</table>
// 		</div>
// 	)
// export default function MediaPanel (): JSX.Element{
// 	return(
// 		<div>
// 			{MediaList.map(({...props}, idx) => (
// 		<div className={Styles.mediaPanel}>
// 			<table>
// 				<thead>
// 					<tr>
// 					<th>Episode</th>
// 					<th>Description</th>
// 					</tr>
// 				</thead>
// 				<tbody>
// 						<tr key={idx}>
// 							<td>
// 								<a href = {props.EpisodeUrl}> 
// 								<img width='250' src={props.EpisodeImg}></img>
// 								</a>
// 							</td>
// 							<td style={{ width: 478.2}}>
// 								<a href={props.EpisodeUrl}>{props.Description}</a>
// 							</td>	
// 						</tr>
// 				</tbody>
// 			</table>
// 		</div>
// 					))}
// 	</div>
// 	)
// }
export default function MediaPanel (): JSX.Element{
	return(
		<div className='container'>
			{MediaList.map(({...props}, idx) => (
			<div className={Styles.mediaPanel}>
				<div>
					<a href = {props.EpisodeUrl}> 
					<img src={props.EpisodeImg}></img>
					</a>
				</div>
				<div>
					<a href={props.EpisodeUrl}>{props.Description}</a>
				</div>	
			</div>
			))}
	</div>
	)}