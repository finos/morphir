# Public test trust material

The five `.key` files here are deliberately public, deterministic test seeds.
They exist only so `morphir itest` can sign and publish a fresh release without
network access or hidden credentials. Never reuse them for an actual Library.

`root.json` is a signed TUF bootstrap root. `policy.json` pins its exact bytes
and authorizes the test publisher under `example.com`. The executable scenario
keeps these inputs separate from its consumer directory and writes a new
registry, publisher state, bundle, signed proposal and consumer state each run.
