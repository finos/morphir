# Independent notebook validation

The CLI notebook qualification validates every exported Jupyter fixture against
the Jupyter nbformat 4.5 schema with Ajv's independent draft-04 validator. The
application uses Moon-Lander's notebook models; the validator does not use that
codec. It also rejects a malformed exported-shape fixture to prove the check runs.

The schema is copied without changes from jupyter/nbformat v5.10.4, commit
`60b6151fedcbdc9f137fb2d223eeb10c935a8378`, at
`nbformat/v4/nbformat.v4.5.schema.json`. Its SHA-256 is
`523e3578ddbfcad52933d2423dc5951114ef73f48df180b6a601498ba5ca071a`.
The upstream BSD license is in LICENSE. Root development dependencies pin
`ajv` 8.20.0 and `ajv-draft-04` 1.0.0 exactly; normal frozen setup installs them.
No validator is added to the installed CLI runtime or its protocol payloads.

Run the existing CLI qualification (`mise run test:cli`) or its selected-target
entry point, for example `node apps/morphir/scripts/test.ts js`. Notebook checks
also run in the existing headless-only path and against the installed npm CLI.
