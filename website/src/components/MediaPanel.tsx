import React from 'react'

type MediaList = {
	Episode: string | JSX.Element
	Description: JSX.Element
}

const MediaList: MediaList[] = [
	{
		Episode:
			'<a href="https://resources.finos.org/znglist/morphir-showcase/?c=cG9zdDoxNTYx"><img width="250" src="https://resources.finos.org/wp-content/uploads/2022/03/introduction-to-the-morphir-show.jpg" /></a> ',
		Description: (
			<>
				<a href='https://resources.finos.org/znglist/morphir-showcase/?c=cG9zdDoxNTYx'>
					Introduction to the Morphir Showcase
				</a>
			</>
		),
	},
	{
		Episode:
			'<a href="https://resources.finos.org/znglist/morphir-showcase/?c=cG9zdDoxNTYz"><img width="250" src="https://resources.finos.org/wp-content/uploads/2022/03/what-morphir-is-with-stephen-gol.jpg" /></a> ',
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
			'<a href="https://resources.finos.org/znglist/morphir-showcase/?c=cG9zdDoxNTY2"><img width="250" src="https://resources.finos.org/wp-content/uploads/2022/03/how-morphir-works-with-attila-mi-1.jpg" /></a>',
		Description: (
			<>
				<a href='https://resources.finos.org/znglist/morphir-showcase/?c=cG9zdDoxNTY2'>
					How Morphir works with Attila Mihaly
				</a>
			</>
		),
	},
	{
		Episode:
			'<a href="https://resources.finos.org/znglist/morphir-showcase/?c=cG9zdDoxNTY4"><img width="250" src="https://resources.finos.org/wp-content/uploads/2022/03/why-morphir-is-important-with-co.jpg" /></a>',
		Description: (
			<>
				<a href='https://resources.finos.org/znglist/morphir-showcase/?c=cG9zdDoxNTY4'>
					Why Morphir is Important – with Colin, James & Stephen
				</a>
			</>
		),
	},
	{
		Episode:
			'<a href="https://resources.finos.org/znglist/morphir-showcase/?c=cG9zdDoxNTcw"><img width="250" src="https://resources.finos.org/wp-content/uploads/2022/03/Screenshot-2022-03-02-at-14.35.18.png" /></a>',
		Description: (
			<>
				<a href='https://resources.finos.org/znglist/morphir-showcase/?c=cG9zdDoxNTcw'>
					The Benefits & Use Case of Morphir with Jane, Chris & Stephen
				</a>
			</>
		),
	},
	{
		Episode:
			'<a href="https://resources.finos.org/znglist/morphir-showcase/?c=cG9zdDoxNTcy"><img width="250" src="https://resources.finos.org/wp-content/uploads/2022/03/how-to-get-involved-closing-pane.jpg" /></a>',
		Description: (
			<>
				<a href='https://resources.finos.org/znglist/morphir-showcase/?c=cG9zdDoxNTcy'>
					How to get involved – Closing Panel Q&A
				</a>
			</>
		),
	},
	{
		Episode:
			'<a href="https://resources.finos.org/znglist/morphir-showcase/?c=cG9zdDoxNTU5"><img width="250" src="https://resources.finos.org/wp-content/uploads/2022/03/morphir-showcase-full-show.jpg" /></a>',
		Description: (
			<>
				<a href='https://resources.finos.org/znglist/morphir-showcase/?c=cG9zdDoxNTU5'>Morphir Showcase – Full Show</a>
			</>
		),
	},
]

export default function MedialPanel(): JSX.Element {
	return (
		<>
			{MediaList.map((props, idx) => {
				;<Media key={idx} {...props} />
			})}
		</>
	)
}
function Media({ ...props }: MediaList) {
	return (
		<div>
			<div>{props.Episode}</div>
			<div>{props.Description}</div>
		</div>
	)
}
