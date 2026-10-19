#!/usr/bin/env bash
# Table test for build-lattice-wasm.sh. Run it directly: ./build-lattice-wasm.test.sh
#
# Each case copies the script into a scratch repository of the shape it expects
# (`scripts/`, `packages/lattice-runtime/` with a committed module) and runs it
# with a stub `cargo` first on PATH. The stub records the arguments of each call;
# `cargo build` writes a module into the target directory `cargo metadata`
# names, unless the case makes the build fail or leave nothing. The subject is
# that the build asks for the playback ABI build of lattice-core for wasm32,
# that the module it leaves replaces the committed one, and that a failed
# build, a missing module, an unreadable metadata and an argument each fail
# with the committed module left as it was.
set -uo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pass=0
fail=0

ok() { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad() {
	fail=$((fail + 1))
	printf 'FAIL  %s\n' "$1"
	shift
	printf '        %s\n' "$@"
}

check_equal() { # label expected actual
	if [ "$2" = "$3" ]; then
		ok "$1"
	else
		bad "$1" "expected: $2" "got:      ${3:-<empty>}"
	fi
}

check_contains() { # label needle haystack
	if grep -qF -- "$2" <<<"$3"; then
		ok "$1"
	else
		bad "$1" "expected output containing: $2" "got: ${3:-<empty>}"
	fi
}

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

# A scratch repository with the script, a committed module reading "old", and a
# stub cargo whose behaviour the case picks through STUB_MODE.
setup() { # name
	repo="$scratch/$1"
	mkdir -p "$repo/scripts" "$repo/packages/lattice-runtime" "$repo/bin"
	cp "$SCRIPTS_DIR/build-lattice-wasm.sh" "$repo/scripts/"
	printf 'old' >"$repo/packages/lattice-runtime/lattice-core.wasm"
	cat >"$repo/bin/cargo" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$STUB_LOG"
case "$1" in
build)
	[ "$STUB_MODE" = build-fails ] && exit 101
	if [ "$STUB_MODE" != no-module ]; then
		mkdir -p "$STUB_TARGET/wasm32-unknown-unknown/release"
		printf 'new' >"$STUB_TARGET/wasm32-unknown-unknown/release/lattice_core.wasm"
	fi
	;;
metadata)
	[ "$STUB_MODE" = metadata-fails ] && exit 101
	printf '{"packages":[],"target_directory":"%s"}\n' "$STUB_TARGET"
	;;
esac
STUB
	chmod +x "$repo/bin/cargo"
}

run_script() { # mode [args...]
	local mode="$1"
	shift
	: >"$repo/cargo.log"
	output="$(cd "$scratch" && PATH="$repo/bin:$PATH" STUB_MODE="$mode" \
		STUB_LOG="$repo/cargo.log" STUB_TARGET="$repo/target" \
		"$repo/scripts/build-lattice-wasm.sh" "$@" 2>&1)"
	status=$?
	module="$(cat "$repo/packages/lattice-runtime/lattice-core.wasm")"
	calls="$(cat "$repo/cargo.log")"
}

echo "a build replaces the committed module"
setup ok
run_script ok
check_equal "exits 0" 0 "$status"
check_equal "the module is the build's" new "$module"
check_equal "builds the playback ABI for wasm32" \
	"build --release -p lattice-core --target wasm32-unknown-unknown --no-default-features --features playback-abi" \
	"$(head -n1 <<<"$calls")"
check_contains "finds the target directory through cargo metadata" \
	"metadata --no-deps --format-version 1" "$calls"
check_contains "says what it wrote" "wrote packages/lattice-runtime/lattice-core.wasm (3 bytes)" "$output"

echo "a failed build leaves the committed module"
setup build-fails
run_script build-fails
check_equal "exits 1" 1 "$status"
check_equal "the module is unchanged" old "$module"
check_contains "says the build failed" "cargo could not build lattice-core" "$output"

echo "a build that leaves no module fails"
setup no-module
run_script no-module
check_equal "exits 1" 1 "$status"
check_equal "the module is unchanged" old "$module"
check_contains "names the missing module" "the build left no module at $repo/target/" "$output"

echo "an unreadable metadata fails"
setup metadata-fails
run_script metadata-fails
check_equal "exits 1" 1 "$status"
check_equal "the module is unchanged" old "$module"
check_contains "says metadata failed" "cargo metadata could not name the target directory" "$output"

echo "an argument is refused before anything is built"
setup argument
run_script ok --check
check_equal "exits 1" 1 "$status"
check_equal "the module is unchanged" old "$module"
check_equal "runs no cargo" "" "$calls"
check_contains "prints the usage" "takes no arguments" "$output"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
