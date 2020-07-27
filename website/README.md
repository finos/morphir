This website was created with [Docusaurus](https://docusaurus.io/).

# What's In This Document

- [Get Started in 5 Minutes](#get-started-in-5-minutes)
- [Directory Structure](#directory-structure)
- [Editing Content](#editing-content)
- [Adding Content](#adding-content)
- [Full Documentation](#full-documentation)

# Get Started in 5 Minutes

1. Ensure NodeJS is installed
```sh
$ node -v
$ npm -v
```

2. Install and run Docusaurus locally

```sh
$ git clone git@github.com:<your fork>/{project name}.git
$ cd {project name}

# Download dependencies
$ yarn --cwd website install

# Generate contributing.md page
./scripts/build-contribute-page.sh

$ yarn --cwd website start
```
This will open a browser on http://localhost:3300

## Directory Structure

Your project file structure should look something like this

```
/
  docs/
    home.md
    roadmap.md
    team.md
  website/
    pages/en
      index.js
    static/
      css/
      img/
    package.json
    sidebars.json
    siteConfig.js
```

# Editing pages
This website only includes one page, the `index.js`, which serves the `/` root path of the website.

You can edit contents there, feel free to check other index pages to take inspiration:
- [FDC3](http://fdc3.org/) - https://github.com/finos/FDC3/blob/master/website/pages/en/index.js
- [Financial Objects](https://fo.finos.org/) - https://github.com/finos/finos-fo/blob/master/website/pages/en/index.js

# Editing docs contents

## Editing an existing docs page

Edit docs by navigating to `docs/` and editing the corresponding document:

`docs/doc-to-be-edited.md`

```markdown
---
id: page-needs-edit
title: This Doc Needs To Be Edited
---

Edit me...
```

For more information about docs, click [here](https://docusaurus.io/docs/en/navigation)

# Adding Content

## Adding a new docs page to an existing sidebar

1. Create the doc as a new markdown file in `/docs`, example `docs/newly-created-doc.md`:

```md
---
id: newly-created-doc
title: This Doc Needs To Be Edited
---

My new content here..
```

1. Refer to that doc's ID in an existing sidebar in `website/sidebars.json`:

```javascript
// Add newly-created-doc to the Getting Started category of docs
{
  "docs": {
    "Getting Started": [
      "quick-start",
      "newly-created-doc" // new doc here
    ],
    ...
  },
  ...
}
```

For more information about adding new docs, click [here](https://docusaurus.io/docs/en/navigation)

## Adding items to your site's top navigation bar

1. Add links to docs, custom pages or external links by editing the headerLinks field of `website/siteConfig.js`:

`website/siteConfig.js`

```javascript
{
  headerLinks: [
    ...
    /* you can add docs */
    { doc: 'my-examples', label: 'Examples' },
    /* you can add custom pages */
    { page: 'help', label: 'Help' },
    /* you can add external links */
    { href: 'https://github.com/facebook/docusaurus', label: 'GitHub' },
    ...
  ],
  ...
}
```

For more information about the navigation bar, click [here](https://docusaurus.io/docs/en/navigation)

## Adding custom pages

1. Docusaurus uses React components to build pages. The components are saved as .js files in `website/pages/en`:
1. If you want your page to show up in your navigation header, you will need to update `website/siteConfig.js` to add to the `headerLinks` element:

`website/siteConfig.js`

```javascript
{
  headerLinks: [
    ...
    { page: 'my-new-custom-page', label: 'My New Custom Page' },
    ...
  ],
  ...
}
```

For more information about custom pages, click [here](https://docusaurus.io/docs/en/custom-pages).

# Full Documentation

Full documentation can be found on the [website](https://docusaurus.io/).
