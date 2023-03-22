import React from 'react'

type MediaList = {
	Episode: string | JSX.Element
	Description: JSX.Element

}

const MediaList: MediaList[] = [
	{
		Episode:
			<img width="250" src="https://resources.finos.org/wp-content/uploads/2022/03/introduction-to-the-morphir-show.jpg" />,
		Description: (
			<>
					Introduction to the Morphir Showcase
			</>
		),
	},
	{
		Episode:
			<img width="250" src="https://resources.finos.org/wp-content/uploads/2022/03/what-morphir-is-with-stephen-gol.jpg" />,
		Description: (
			<>
				<a href='https://resources.finos.org/znglist/morphir-showcase/?c=cG9zdDoxNTYz'>
					What Morphir is with Stephen Goldbaum
				</a>
			</>
		),
	},
	{
		Episode:
			<img width="250" src="https://resources.finos.org/wp-content/uploads/2022/03/how-morphir-works-with-attila-mi-1.jpg" />,
		Description: (
			<>
					How Morphir works with Attila Mihaly
			</>
		),
	},
	{
		Episode:
			<img width="250" src="https://resources.finos.org/wp-content/uploads/2022/03/why-morphir-is-important-with-co.jpg" />,
		Description: (
			<>
					Why Morphir is Important – with Colin, James & Stephen
			</>
		),
	},
	{
		Episode:
			<img width="250" src="https://resources.finos.org/wp-content/uploads/2022/03/Screenshot-2022-03-02-at-14.35.18.png" />,
		Description: (
			<>
					The Benefits & Use Case of Morphir with Jane, Chris & Stephen
			</>
		),
	},
	{
		Episode:
			<img width="250" src="https://resources.finos.org/wp-content/uploads/2022/03/how-to-get-involved-closing-pane.jpg" />,
		Description: (
			<>
			
					How to get involved – Closing Panel Q&A
			
			</>
		),
	},
	{
		Episode:
			<img width="250" src="https://resources.finos.org/wp-content/uploads/2022/03/morphir-showcase-full-show.jpg" />,
		Description: (
			<>
				Morphir Showcase – Full Show
			</>
		),
	},
]

export default function MedialPanel(): JSX.Element {
	return (
		<section>
			{MediaList.map((props, idx) => (
				<Media key={idx} {...props} />
			))}
		</section>
	)
}

function Media({ ...props }: MediaList) {
	return (
		
		<div>
			<a href="https://resources.finos.org/znglist/morphir-showcase/?c=cG9zdDoxNTU5">
				<table>
					<tr>
						<th>Episode</th>
						<th>Description</th>

					</tr>
					<tr>
						<td>{props.Episode}</td>
						<td>{props.Description}</td>
					</tr>
				</table>
			</a>
		</div>
	)
}
