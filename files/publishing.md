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

NPM package publishing is automated through a GitHub action so all you need to do is use `npm version <major | minor | patch>` 
to let NPM calculate the new version number and push it directly if you are a maintainer or get it merged through a PR 
as a contributor. The GitHub action will take care of the rest. Here are the detailed steps:  

1. Run `npm version <major | minor | patch>` to get the version number in your `package.json` updated.
    - This will calculate the new version number, update in `package.json` and commit the change.
2. Push the `package.json` change.
    ```
    git push
    ```
3. Create a PR to update the version number on the `main` branch.
4. When the PR is merged a GitHub action will publish the NPM package.