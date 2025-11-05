import React, { useRef, useEffect } from 'react'
import Styles from './MediaPanel.module.css'

type MediaList = {
	EpisodeUrl: string
	Description: string
	thumbnailTime?: number // Time in seconds for thumbnail frame (optional)
}

const MediaList: MediaList[] = [
	{
		EpisodeUrl: 'https://www.finos.org/hubfs/Projects%20%2B%20SIGs/Morphir/Morphir%20Resource%20Page%202025/morphir_case_study_-_introduction_%5Bv1%5D%20(1080p).mp4',
		Description: 'Introduction to the Morphir Showcase',
		thumbnailTime: 5, // Set thumbnail time in seconds (e.g., 5 seconds into the video)
	},
	{
		EpisodeUrl: 'https://www.finos.org/hubfs/2025/Morphir%20Resource%20Page%202025/what_morphir_is_with_stephen_-_morphir_showcase_v2%20(1080p).mp4',
		Description: 'What Morphir is with Stephen Goldbaum',
		thumbnailTime: 21, // Set thumbnail time in seconds
	},
	{
		EpisodeUrl: 'https://www.finos.org/hubfs/2025/Morphir%20Resource%20Page%202025/how_morphir_works_with_attila_-_morphir_showcase_v1%20(1080p).mp4',
		Description: 'How Morphir works with Attila Mihaly',
		thumbnailTime: 19, // Set thumbnail time in seconds
	},
	{
		EpisodeUrl: 'https://www.finos.org/hubfs/2025/Morphir%20Resource%20Page%202025/why_morphir_is_important_-_morphir_showcase%20(1080p).mp4',
		Description: 'Why Morphir is Important – with Colin, James & Stephen',
		thumbnailTime: 22, // Set thumbnail time in seconds
	},
	{
		EpisodeUrl: 'https://www.finos.org/hubfs/2025/Morphir%20Resource%20Page%202025/the_benefits_%26_use_case_-_morphir_showcase%20(1080p).mp4',
		Description: 'The Benefits & Use Case of Morphir with Jane, Chris & Stephen',
		thumbnailTime: 18, // Set thumbnail time in seconds
	},
	{
		EpisodeUrl: 'https://www.finos.org/hubfs/2025/Morphir%20Resource%20Page%202025/how_to_get_involved_-_closing_panel_q%26a_-_morphir_showcase%20(1080p).mp4',
		Description: 'How to get involved – Closing Panel Q&A',
		thumbnailTime: 300, // Set thumbnail time in seconds
	},
	{
		EpisodeUrl: 'https://www.finos.org/hubfs/Projects%20%2B%20SIGs/Morphir/Morphir%20Resource%20Page%202025/morphir_showcase_-_full_show%20(1080p).mp4',
		Description: 'Morphir Showcase – Full Show',
		thumbnailTime: 2, // Set thumbnail time in seconds
	},
]

interface VideoThumbnailProps {
	src: string
	thumbnailTime?: number
	description: string
}

function VideoThumbnail({ src, thumbnailTime, description }: VideoThumbnailProps): JSX.Element {
	const videoRef = useRef<HTMLVideoElement>(null)

	useEffect(() => {
		const video = videoRef.current
		if (!video || thumbnailTime === undefined) return

		const handleLoadedMetadata = () => {
			video.currentTime = thumbnailTime
		}

		video.addEventListener('loadedmetadata', handleLoadedMetadata)

		// If metadata is already loaded, set the time immediately
		if (video.readyState >= 1) {
			video.currentTime = thumbnailTime
		}

		return () => {
			video.removeEventListener('loadedmetadata', handleLoadedMetadata)
		}
	}, [thumbnailTime])

	return (
		<video 
			ref={videoRef}
			src={src} 
			preload="metadata"
			muted
			className={Styles.videoThumbnail}
			style={{ width: '100%', cursor: 'pointer' }}
			aria-label={description}
		/>
	)
}

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
				<div className="col col--4" key={idx}>
					<div className={Styles.videoContainer}>
						<a href={props.EpisodeUrl}> 
							{props.EpisodeUrl.endsWith('.mp4') ? (
								<VideoThumbnail 
									src={props.EpisodeUrl}
									thumbnailTime={props.thumbnailTime}
									description={props.Description}
								/>
							) : (
								<img src={props.EpisodeUrl} alt={props.Description}></img>
							)}
						</a>
						<br/>
						<a href={props.EpisodeUrl}>{props.Description}</a>
					</div>
				</div>
				))}
			</section>
	    </div>
	)}
