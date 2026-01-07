# Get Started

## Prerequisites

This project requires **Node.js 24** or later. 

### Using NVM (Recommended)

If you use [nvm](https://github.com/nvm-sh/nvm) (Node Version Manager), the correct Node version will be automatically selected when you enter the website directory:

```sh
$ nvm use
Found '/path/to/morphir/website/.nvmrc' with version <24>
```

### Manual Installation

Ensure NodeJS 24 or later is installed:

```sh
$ node -v  # Should show v24.x.x or later
$ npm -v
```

## Local Development

```sh
$ git clone git@github.com:finos/morphir.git
$ cd morphir/website

# Download dependencies
$ npm install

# Start development server
$ npm start
```

This will open a browser on http://localhost:3000/morphir/

## Build

To create a production build:

```sh
$ npm run build
```

The static files will be generated in the `build/` directory.

## Netlify Configuration

This website is configured to deploy on Netlify with Node.js 24. The configuration is in the root `netlify.toml` file, which specifies:
- Build base directory: `website`
- Publish directory: `build` (relative to base, resolves to `website/build`)
- Node version: 24
- Build command: `npm run build`
