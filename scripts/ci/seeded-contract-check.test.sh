#!/usr/bin/env bash
# Table test for seeded-contract-check.sh. Run it directly:
# scripts/ci/seeded-contract-check.test.sh
#
# A copy of the script runs in a throwaway git repository holding the six seeded
# packages' manifests and sources, a package that is not seeded, and a lock
# recording `@clockwyrks/asset-contract` and `@clockwyrks/run-record` as the feed
# would install them. It runs the real `node`, which it needs; without one the
# test is skipped. The subject is each of its two checks: the seeded packages'
# wording, and that no seeded package reaches the run-record contract.
set -uo pipefail

CI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly CI_DIR
readonly SEEDED=(particle-runtime voxel-runtime simple-2d structured-2d simple-3d structured-3d)
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

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

if ! command -v node >/dev/null 2>&1; then
	echo "node is not installed here; skipping the seeded-contract-check test."
	exit 0
fi
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

manifest() { # dir name dependencies-json
	mkdir -p "$1"
	printf '{ "name": "%s", "dependencies": %s }\n' "$2" "$3" >"$1/package.json"
}
lock() { # repo asset-contract-dependencies-json
	cat >"$1/package-lock.json" <<JSON
{
  "lockfileVersion": 3,
  "packages": {
    "node_modules/@clockwyrks/asset-contract": { "version": "0.2.0", "dependencies": $2 },
    "node_modules/@clockwyrks/run-record": { "version": "0.2.0", "dependencies": { "@clockwyrks/asset-contract": "^0.2.0" } },
    "node_modules/@clockwyrks/voxel-runtime": { "resolved": "packages/voxel-runtime", "link": true }
  }
}
JSON
}
fresh_repo() {
	local repo dir
	repo="$(mktemp -d "$tmp/repoXXXXXX")"
	mkdir -p "$repo/scripts/ci"
	cp "$CI_DIR/seeded-contract-check.sh" "$repo/scripts/ci/"
	for dir in "${SEEDED[@]}"; do
		manifest "$repo/packages/$dir" "@clockwyrks/$dir" '{}'
		mkdir -p "$repo/packages/$dir/src"
		echo '/** Steps the game world one tick. */ export function step() {}' >"$repo/packages/$dir/src/index.ts"
	done
	manifest "$repo/packages/voxel-runtime" @clockwyrks/voxel-runtime '{ "@clockwyrks/asset-contract": "0.2.0" }'
	mkdir -p "$repo/packages/simple-2d/src/testing" "$repo/packages/simple-2d/docs"
	echo '// the leaderboard fixture a test reads' >"$repo/packages/simple-2d/src/testing/fixture.ts"
	echo '// asserts the run record is not imported' >"$repo/packages/simple-2d/src/index.test.ts"
	echo '# Input' >"$repo/packages/simple-2d/docs/input.md"
	manifest "$repo/packages/case-harness" @clockwyrks/case-harness '{ "@clockwyrks/run-record": "0.2.0" }'
	mkdir -p "$repo/packages/case-harness/src"
	echo '// reads the run record after the container is gone' >"$repo/packages/case-harness/src/index.ts"
	manifest "$repo/packages/util" @clockwyrks/util '{ "@clockwyrks/run-record": "0.2.0" }'
	lock "$repo" '{}'
	git -C "$repo" init --quiet
	printf '%s' "$repo"
}
run() { (cd "$1" && scripts/ci/seeded-contract-check.sh 2>&1); }

repo="$(fresh_repo)"
out="$(run "$repo")"
check_equal "clean seeded packages pass" "0" "$?"
check_equal "naming the seeded packages" \
	"Seeded packages (${SEEDED[*]}) name nothing about evaluation and none reaches the contract." "$out"

for word in leaderboard "run record" "the review UI" TestCabinet; do
	repo="$(fresh_repo)"
	echo "// shown on the $word" >>"$repo/packages/simple-2d/src/index.ts"
	out="$(run "$repo")"
	check_equal "a seeded package naming '$word' fails" "1" "$?"
	check_contains "naming the line ('$word')" "packages/simple-2d/src/index.ts:2:" "$out"
done

repo="$(fresh_repo)"
echo "The leaderboard is not shown." >>"$repo/packages/simple-2d/docs/input.md"
out="$(run "$repo")"
check_equal "a seeded package's docs naming the leaderboard fail" "1" "$?"
check_contains "naming the doc's line" "packages/simple-2d/docs/input.md:2:" "$out"

repo="$(fresh_repo)"
echo "// the reviewer reads this" >>"$repo/packages/simple-2d/src/index.ts"
out="$(run "$repo")"
check_equal "a seeded package naming a reviewer passes" "0" "$?"

repo="$(fresh_repo)"
echo "// shown on the leaderboard" >>"$repo/packages/case-harness/src/index.ts"
out="$(run "$repo")"
check_equal "a package that is not seeded is not read" "0" "$?"

repo="$(fresh_repo)"
manifest "$repo/packages/simple-3d" @clockwyrks/simple-3d '{ "@clockwyrks/run-record": "0.2.0" }'
out="$(run "$repo")"
check_equal "a seeded package depending on the run record fails" "1" "$?"
check_contains "with the trail" "@clockwyrks/simple-3d -> @clockwyrks/run-record" "$out"

repo="$(fresh_repo)"
manifest "$repo/packages/simple-3d" @clockwyrks/simple-3d '{ "@clockwyrks/util": "*" }'
out="$(run "$repo")"
check_equal "one reaching it through another package of the workspace fails" "1" "$?"
check_contains "with the whole trail" "@clockwyrks/simple-3d -> @clockwyrks/util -> @clockwyrks/run-record" "$out"

repo="$(fresh_repo)"
lock "$repo" '{ "@clockwyrks/run-record": "0.2.0" }'
out="$(run "$repo")"
check_equal "one reaching it through a package the lock records fails" "1" "$?"
check_contains "with the trail through the lock" \
	"@clockwyrks/voxel-runtime -> @clockwyrks/asset-contract -> @clockwyrks/run-record" "$out"

repo="$(fresh_repo)"
manifest "$repo/packages/simple-3d" @clockwyrks/simple-3d '{ "@clockwyrks/unknown": "1.0.0" }'
out="$(run "$repo")"
check_equal "a dependency neither the workspace nor the lock holds fails" "1" "$?"
check_contains "saying how to write the lock" "Write the lock again with \`npm install\`" "$out"

repo="$(fresh_repo)"
rm "$repo/package-lock.json"
out="$(run "$repo")"
check_equal "a workspace without its lock fails" "1" "$?"
check_contains "saying so" "package-lock.json does not exist" "$out"

repo="$(fresh_repo)"
rm -r "$repo/packages/structured-3d"
out="$(run "$repo")"
check_equal "a seeded package that is missing fails" "1" "$?"
check_contains "naming it" "packages/structured-3d/package.json does not exist" "$out"

echo
echo "seeded-contract-check.test.sh: ${pass} passed, ${fail} failed"
[ "$fail" -eq 0 ]
