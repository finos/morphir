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
