This document describes how maintainers can push new releases of `morphir-elm` into NPM and the Elm package repo. 

# Publishing the Elm package

The latest elm tooling (0.19.1) has some [issues with large docs](https://github.com/elm/compiler/issues?q=is%3Aissue+is%3Aopen+loading+docs) which impacts `finos/morphir-elm`. Because of this we had to turn-off the automation so the publishing can only be done manually by a maintainer.

Here are the steps:

1. Clone the `finos/morphir-elm` repo to a local workspace. Make sure that it's not a clone of your fork but a clone of the main repo.
2. Make sure that the clone is up-to-date and you are on the `main` branch.
3. Run `elm bump`.
4. If this fails with the `PROBLEM LOADING DOCS` error you will have to use an older version of Elm. 
5. You can install the previous version using `npm install -g elm@0.19.0-no-deps`.
6. Run `elm bump` again.
7. This will update the `elm.json` so you need to add an commit it:
    - `git add elm.json`
    - `git commit -m "Bump Elm package version"`
8. Now you need to create a tag that matches the Elm package version:
    - `git tag -a <elm_package_version> -m "new Elm package release"`
    - `git push origin <elm_package_version>`
9. Now you are ready to publish the Elm package:
    - `elm publish`    


# Publishing the NPM package

NPM package publishing is automated through a GitHub action so all you need to do is use `npm version <major | minor | patch>` 
to let NPM calculate the new version number and push it directly if you are a maintainer or get it merged through a PR 
as a contributor. The GitHub action will take care of the rest. Here are the detailed steps:  

1. Run `npm version <major | minor | patch>` to get the version number in your `package.json` updated.
    - This will calculate the new version number, update in `package.json` and commit the change.
2. Create a tag in git. Make sure you are using the `v` prefix for the NPM version tag to differentiate it from Elm package version.
    ```
    git tag -a <npm_package_version>
    ```    
2. Push the `package.json` change and the tags.
    ```
    git push
    git push --tags
    ```
3. Create a PR to update the version number on the `main` branch.
4. When the PR is merged a GitHub action will publish the NPM package.