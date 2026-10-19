# engines

The authored engines, the playback runtimes, the case harness, and the
adversarial and performance runtimes with the match runner.

This repository is one component of
[The Test Cabinet](https://github.com/TheClockwyrks/TheTestCabinet). What it is
and how it fits with the others is stated by the documentation site, which
lives in the superrepo at `apps/docs/src/content/docs/`. Its Repositories page,
`apps/docs/src/content/docs/development/repositories.md`, draws the edges
between the repositories.

## What lives here

- `engines/<slug>/engine.toml`: the manifests of the five built-in engines
  (`none`, `simple-2d`, `structured-2d`, `simple-3d`, `structured-3d`).
- `crates/engines` (`test-cabinet-engines`): the manifests embedded, and
  `built_in_catalog`, the suite runtime's engine catalog bound to them.
- `packages/simple-2d`, `packages/simple-3d`, `packages/structured-2d` and
  `packages/structured-3d` (`@clockwyrks/<slug>`): the engines a produced game
  is built on, each with its documentation under `docs/`. An engine's version
  is its package's version, which a run records.
- `packages/voxel-runtime` and `packages/particle-runtime`: the playback
  runtimes of a produced voxel rig and particle system, over the contracts
  repository's `@clockwyrks/asset-contract`.
- `packages/case-harness` (`@clockwyrks/case-harness`): the validation harness
  and canvas recorder a test case's validator project is built on.
- `crates/foray-*` and `crates/match-play`: the adversarial runtime, Foray's
  rules (`foray-core`), its wasm host, CLI, controller SDK and reference
  controllers, and the match runner.
- `crates/lattice-*`: the performance runtime, Lattice's oracle
  (`lattice-core`), its wasm host, CLI, SDK and reference engines.
- `packages/lattice-runtime` (`@clockwyrks/lattice-runtime`): the browser
  playback of a lattice factory, the canvas renderer, the interpolation between
  ticks and `lattice-core` compiled to the playback ABI, committed as
  `lattice-core.wasm` and exported as the package's `./lattice-core.wasm`
  subpath. `scripts/build-lattice-wasm.sh` rebuilds the module from the crate
  whenever the simulation changes. It takes nothing of the project.
- `history/`: how this repository's history was extracted from the monorepo.

The engines and the voxel and particle runtimes are vendored into a model's
workspace, so the `seeded-contract` gate holds their prose to the seeded
vocabulary and their closure clear of the run-record contract.

## Getting started

Open the superrepo in its devcontainer, which carries every toolchain the
repositories need, and work from this repository's root.
A build here inherits the superrepo's Cargo configuration, which redirects
every dependency on another repository to the sibling checkout, so nothing is
fetched from a mirror.

One command runs every gate:

```sh
make gate
```

Each gate is a file under `ci/gates/` whose stem is the gate's id.
`uv run --quiet --project ci gate list` names them all, and
`azure-pipelines.yml` runs each one as a step of its own on every push, inside
the CI images the superrepo builds.
