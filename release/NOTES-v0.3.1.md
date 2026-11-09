weft 0.3.1 provides the MoonBit deployment planner API, native/Node planning CLI, versioned plan format and local browser demo.

- Module/CLI version: 0.3.1; plan JSON: 0.2.0. Manifest readers accept exact 0.1.0/0.2.0.
- Mooncakes: https://mooncakes.io/docs/soehi/weft — 0.3.0 registry source candidate `d6ebb0b`; 0.3.1 source is recorded in release/CANDIDATE.md.
- The tag commit identifies this release's CLI source; each archive's BUILD.json records its full SHA and fixed inputs.
- Windows x86_64 and Linux x86_64 archives include native CLI, Node CLI, examples, license/notices and SHA256SUMS. Companion .zip.sha256 files check archive transport integrity.
- Node CLI needs Node 24 series. Linux native is verified on Ubuntu 24.04; system ABI/shared-library requirements apply.
- The browser demo runs locally from source; user components stay in browser memory. See demo/README.md.
- The optional Linux execution command is experimental and source-only. It is not part of these planning CLI bundles; generic weft run remains unsupported.
- Requested execution resource limits are rejected. plan_hash is a plan-body FNV identifier, not a binary digest or security checksum.
- Windows native execution and macOS execution are not verified. The project does not claim sandbox/security isolation.

See README.md, release/DEMO.md and docs/ROADMAP.md for installation, independent registry consumer verification and review steps.

0.3.1 corrects source error-example paths and the release asset collector. 0.3.0 registry content remains immutable; its GitHub release attempt did not publish assets. No plan/API compatibility changes.
