import React from 'react'
import clsx from 'clsx'
import Layout from '@theme/Layout'
import useDocusaurusContext from '@docusaurus/useDocusaurusContext'
import styles from './index.module.css'
import { Link } from '@docusaurus/router'
import HomepageFeatures from '../components/HomepageFeatures'
import MediaPanel from '../components/MediaPanel'
import ContributingCompaniesPanel from '../components/ContributingCompaniesPanel'

function HomepageHeader() {
	const { siteConfig } = useDocusaurusContext()

	return (
		<header
			className={clsx('hero hero--primary', styles.heroBanner)}
			style={{
				backgroundImage: `url(img/wide_header.png)`,
				backgroundColor: 'unset',
				backgroundRepeat: 'no-repeat',
				backgroundPosition: 'center',
				height: '400px',
			}}
		>
			<div className='container'>
				<img src='img/logo_white.png' alt='header logo' style={{ width: '500px' }} />
				<p className='hero__subtitle'>{siteConfig.tagline}</p>

				<div className={styles.buttons}>
					<a href='https://resources.finos.org/znglist/morphir/' className='button button--secondary'>
						Get To Know Morphir
					</a>
				</div>
			</div>
		</header>
	)
}

export default function Home(): JSX.Element {
	return (
		<Layout description={'Morphir Home Page'}>
			<HomepageHeader />
			<main>
				<HomepageFeatures />
				<ContributingCompaniesPanel />
				<MediaPanel />
			</main>
		</Layout>
	)
}
