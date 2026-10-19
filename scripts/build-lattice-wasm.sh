#!/usr/bin/env bash
# Rebuild the lattice playback engine that @clockwyrks/lattice-runtime ships.
#
#   scripts/build-lattice-wasm.sh
#
# `packages/lattice-runtime/lattice-core.wasm` is `crates/lattice-core`
# compiled for the browser: the same rules the CLI, the hosts and the validator
# run, exporting the tick-at-a-time playback ABI the renderer calls (`alloc`,
# `playback_load`, `playback_board`, `playback_step`, `playback_reset`). It is
# committed beside the renderer, so a consumer of the package needs no Rust
# toolchain, and it is rebuilt with this script whenever the simulation changes:
# a module that lags the crate draws a factory the graded engine never computed.
#
# The flags are the build's whole meaning. `--features playback-abi` turns on
# the playback driver and the C ABI the browser calls; `playback` alone builds
# the driver with no exports, which is what a model's engine links, and a module
# built so has nothing for the renderer to call. `--no-default-features` drops
# the `schema` feature, which only the native artifact generator needs.
#
# The module is not byte-reproducible across machines: it carries the source
# paths of its dependencies for their panic messages, and this repository
# commits no Cargo.lock, so a rebuild resolves the newest compatible serde. A
# rebuild that changes no rule changes bytes but not behaviour, which the
# package's tests (the playback ABI and the integration test) hold.
#
# The build output is found where `cargo metadata` says the target directory
# is, read with `jq`, and copied over the committed module.
set -euo pipefail

say() { printf 'build-lattice-wasm: %s\n' "$*"; }
die() {
	printf 'build-lattice-wasm: %s\n' "$1" >&2
	exit 1
}

[ "$#" -eq 0 ] || die "usage: $0 (it takes no arguments)"

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
module="$root/packages/lattice-runtime/lattice-core.wasm"
cd "$root"

say "building lattice-core for wasm32-unknown-unknown with the playback ABI"
cargo build --release -p lattice-core --target wasm32-unknown-unknown \
	--no-default-features --features playback-abi ||
	die "cargo could not build lattice-core for wasm32-unknown-unknown"

metadata="$(cargo metadata --no-deps --format-version 1)" ||
	die "cargo metadata could not name the target directory"
target="$(jq -er '.target_directory' <<<"$metadata")" ||
	die "cargo metadata named no target directory"
built="$target/wasm32-unknown-unknown/release/lattice_core.wasm"
[ -f "$built" ] || die "the build left no module at $built"

cp "$built" "$module"
say "wrote packages/lattice-runtime/lattice-core.wasm ($(wc -c <"$module") bytes)"
