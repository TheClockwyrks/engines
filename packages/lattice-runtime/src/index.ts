// @clockwyrks/lattice-runtime: the browser playback of a lattice factory.
//
// Three pieces, none holding a rule of the simulation:
//
//   - `Engine` wraps `lattice-core` compiled to wasm, the same authoritative
//     engine the CLI and the validator run, through its playback ABI, and steps
//     it a tick at a time. The reference module ships with the package as
//     `@clockwyrks/lattice-runtime/lattice-core.wasm`; a run's playback hands
//     `Engine.instantiate` the submission's own module instead, which exports
//     the same ABI.
//   - the interpolation places each belt item between the two nearest ticks, so
//     a factory plays smoothly at any frame rate.
//   - `Renderer` draws the board and a tick's state to a 2D canvas from a packed
//     sprite atlas. The atlas is the lattice test case's content, not this
//     package's: a consumer loads its `sheet.png` and `sheet.json` with
//     `loadSheet`.
//
// See https://docs.testcabinet.ai/testing/performance/lattice/architecture/#browser-playback
export * from "./interpolate";
export * from "./renderer";
