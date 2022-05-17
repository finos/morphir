This document describes how maintainers can push new releases of `morphir-elm` into NPM and the Elm package repo. 

# Publishing the Elm package

Elm package publishing is automated through a GitHub action so all you need to do is use `elm bump` to let Elm calculate 
the new version number and push it directly if you are a maintainer or get it merged through a PR as a contributor. 
The GitHub action will take care of the rest. Here are the detailed steps:  

1. Run `elm bump` to get the version number in your `elm.json` updated.
    - This will calculate the new version number and ask you to confirm.
2. Commit and push the `elm.json` change.
    ```
    git add elm.json
    git commit -m "Bump Elm package version"
    git push
    ```
3. Create a PR to update the version number on the `main` branch.
4. When the PR is merged a GitHub action will publish the Elm package.

# Publishing the NPM package

1. Clone the `finos/morphir-elm` github repo or pull the latest from the `main` branch if you have a clone already.
    ```
    git clone https://github.com/finos/morphir-elm.git
    ```
    or
    ```
    git pull origin main
    ```
2. Build the CLI.
    ```
    npm run build
    ```
3. Run `np` for publishing.
    - If you don't have `np` installed yet, install it with `npm install -g np`
4. `np` will propmpt you to select the next semantic version number so you'll have to decide if your changes are major, minor or patch.
    - **Note**: `np` might say that there has not been any commits. This is normal if you just published the Elm package since it picks up 
    the tag from that one. It is safe to respond `y` to that question because the rest of the process will use the version number from the
    `package.json` and push a tag with a prefix `v` so it does not collide with Elm which does not use a prefix.
5. `np` will also ask you for credentials.
