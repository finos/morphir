/**
 * Copyright (c) 2017-present, Facebook, Inc.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

const React = require('react');

class Footer extends React.Component {
  docUrl(doc, language = '') {
    const baseUrl = this.props.config.baseUrl;
    const docsUrl = this.props.config.docsUrl;
    const defaultVersionShown = this.props.config.defaultVersionShown;
    const docsPart = `${docsUrl ? `${docsUrl}/` : ''}`;
    const versionPart = `${defaultVersionShown ? `${defaultVersionShown}/` : ''}`;
    const langPart = `${language ? `${language}/` : ''}`;
    return `${baseUrl}${docsPart}${versionPart}${langPart}${doc}`;
  }

  pageUrl(doc, language) {
    const baseUrl = this.props.config.baseUrl;
    const defaultVersionShown = this.props.config.defaultVersionShown;
    const versionPart = `${defaultVersionShown ? `${defaultVersionShown}/` : ''}`;
    const langPart = `${language ? `${language}/` : ''}`;
    return `${baseUrl}${versionPart}${langPart}${doc}`;
  }

  render() {
    return (
      <footer className="nav-footer" id="footer">
        <section className="sitemap">     
          <a href={this.props.config.baseUrl} className="nav-home">
            {this.props.config.footerIcon && (
              <img
                src={this.props.config.baseUrl + this.props.config.footerIcon}
                alt={this.props.config.title}
              />
            )}
          </a>
          <div>
            <h5>Docs</h5>
            <a href={this.docUrl('home')}>
              Getting Started
            </a>
            <a href={this.docUrl('team')}>
              Team
            </a>
            <a href={this.docUrl('roadmap')}>
              Roadmap
            </a>
          </div>
          <div>
            <h5>FINOS</h5>
            <a
              href="https://www.finos.org/"
              target="_blank"
              rel="noreferrer noopener">
              FINOS Website
            </a>
            <a
              href="https://finosfoundation.atlassian.net/wiki/spaces/FINOS/pages/80642059/Community+Handbook"
              target="_blank"
              rel="noreferrer noopener">
              Community Handbook
            </a>
            <a
              href="https://finosfoundation.atlassian.net/wiki/spaces/FINOS/pages/75530783/Community+Governance"
              target="_blank"
              rel="noreferrer noopener">
              Community Governance
            </a>            
          </div>
          <div>
            <h5>More</h5>
            <div className="social">
              <a
                className="github-button" // part of the https://buttons.github.io/buttons.js script in siteConfig.js
                href={this.props.config.repoUrl}
                data-count-href={`${this.props.config.repoUrl}/stargazers`}
                data-show-count="true"
                data-count-aria-label="# stargazers on GitHub"
                aria-label="Star this project on GitHub">
                {this.props.config.projectName}
              </a>
            </div>
            {this.props.config.twitterUsername && (
              <div className="social">
                <a
                  href={`https://twitter.com/${this.props.config.twitterUsername}`}
                  className="twitter-follow-button">
                  Follow @{this.props.config.twitterUsername}
                </a>
              </div>
            )}
            <div className="social">
              <a
                href={`https://www.linkedin.com/company/finosfoundation`}
                className="linkedin-follow-button">
                FINOS on LinkedIn
              </a>
            </div>
          </div>
        </section>
        <section className="finos finosBanner">
          <a href="https://www.finos.org">
            <img id="finosicon" src={`img/finos_wordmark.svg`} height='75px' alt="FINOS" title="FINOS"/>
            <h2 id="proud">Proud member of the Fintech Open Source Foundation</h2>
          </a>

        </section>
        
        <section className="copyright">{this.props.config.copyright}</section>

      </footer>
    );
  }
}



module.exports = Footer;
