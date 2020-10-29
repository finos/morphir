This document describes how maintainers can push new releases of `morphir-elm` into NPM and the Elm package repo. 

# Publishing the Elm package

1. Clone the `finos/morphir-elm` github repo or pull the latest from the master branch if you have a clone already.
    ```
    git clone https://github.com/finos/morphir-elm.git
    ```
    or
    ```
    git pull origin master
    ```
2. Run `elm bump` to get the version number in your `elm.json` updated.
    - This will calculate the new version number and ask you to confirm.
3. Commit the `elm.json` change.
```
git add elm.json
git commit -m "Bump Elm package version"
```
4. Create and push a new tag with the release number.
```
git tag <version>
git push --tags origin master
```
5. Run `elm publish` to get the new release registered in [the Elm package repo](https://package.elm-lang.org/)
```
elm publish
```

# Publishing the NPM package

1. Clone the `finos/morphir-elm` github repo or pull the latest from the master branch if you have a clone already.
```
git clone https://github.com/finos/morphir-elm.git
```
or
```
git pull origin master
```
2. Build the CLI.
```
npm run make-cli
```
3. Run `np` for publishing.
    - If you don't have `np` installed yet, install it with `npm install -g np`
4. `np` will propmpt you to select the next semantic version number so you'll have to decide if your changes are major, minor or patch.
    - **Note**: `np` might say that there has not been any commits. This is normal if you just published the Elm package since it picks up 
    the tag from that one. It is safe to respond `y` to that question because the rest of the process will use the version number from the
    `package.json` and push a tag with a prefix `v` so it does not collide with Elm which does not use a prefix.
5. `np` will also ask you for credentials.
  
