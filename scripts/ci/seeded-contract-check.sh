#!/usr/bin/env bash
# Gate: the packages that get SEEDED into a model's workspace must not name this
# project or say anything about how a run is judged.
#
# The engines and the voxel and particle runtimes are vendored into a model's own
# workspace at seed time, with the whole closure they depend on, so every byte of
# them is readable by the model building the case. That binds them by the
# documentation's guide to writing case specifications: a model must not learn
# that it is being evaluated, that its output is scored, or that the project
# exists.
#
# The runtimes' one dependency of the project's, `@clockwyrks/asset-contract`,
# is the contracts repository's. It is generated from Rust doc comments, and that
# repository's own tests (`tests/asset-contract.test.ts`) hold it to the STRICT
# list below. This script checks the hand-written packages that live here and
# the closure that reaches it.
#
# The rest of the contract (`@clockwyrks/run-record`, records and reviews, and
# the backend's `@clockwyrks/backend-api`, ladders and snapshots) is deliberately
# NOT checked: it is never seeded, and it is supposed to talk about evaluation.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

# Two tiers, because the two bodies of code can afford different vocabulary.
#
# STRICT applies to what is nothing but wire shapes: the generated asset contract
# (checked in the contracts repository, by the same list) and every manifest the
# superrepo's staging script writes (its stage-tcab-packages.test.mjs reads the
# list from here). No word here has an innocent reading in a file that describes
# a rig, so the list can be broad, and being broad is the point, since the
# contract's prose comes from Rust doc comments written by someone thinking about
# the harness. Nothing in this script reads it; the staging test does, by this
# line's text.
# shellcheck disable=SC2034
readonly STRICT='test.cabinet|testcabinet|\btcab\b|\bbenchmark(s|ed|ing)?\b|\bevaluat(e|ed|es|ing|ion)\b|\bscor(e|ed|es|ing)\b|\bgrad(e|ed|es|ing)\b|\breview(s|ed|er|ers|ing)?\b|\brun.record\b|\bleaderboard\b|\bladder\b|\bharness\b|https?://'

# HANDWRITTEN applies to the engines and runtimes, which are ordinary game code and
# legitimately full of words STRICT bans: `player.score` is a game's own score, an
# F-curve is `evaluated`, and the spec guide explicitly permits naming reviewers
# ("Mentioning reviewers is acceptable"). So this tier bans only what has no reading
# except this project: our identity, our nouns for the machinery around a run, and
# the surfaces a model has no business knowing exist.
readonly HANDWRITTEN='test.cabinet|testcabinet|\btcab\b|\brun.record\b|\bleaderboard\b|\bbenchmark(s|ed|ing)?\b|review (tab|page|queue|ui)|\bthe review UI\b|\bthis (test.)?case.s manifest\b'

# The packages of this repository a run's workspace is seeded with, by their
# directory under packages/: the four engines, seeded under `.vendor/engine/`,
# and the two runtimes a case may name, seeded under `.vendor/packages/`. They
# are what the superrepo's staging script stages, less `case-harness`, which is
# read after the container is gone and never seeded, and `lattice-runtime`,
# which the console plays a factory with and no run is seeded with.
readonly SEEDED=(particle-runtime voxel-runtime simple-2d structured-2d simple-3d structured-3d)

for dir in "${SEEDED[@]}"; do
	[ -f "packages/$dir/package.json" ] || {
		echo >&2 "packages/$dir/package.json does not exist, yet SEEDED in $0 names it."
		exit 1
	}
	for sub in src docs; do
		[ -d "packages/$dir/$sub" ] || continue
		# Only what the package actually publishes. Every engine's tsconfig excludes
		# `src/**/*.test.ts` and `src/testing` from the build, so neither reaches a
		# `dist/` and neither reaches a run; `src/testing/gl.ts`'s WebGL stub reports
		# a VENDOR string naming this project and is genuinely fine where it is.
		hits=$(grep -rniE "$HANDWRITTEN" "packages/$dir/$sub" 2>/dev/null |
			grep -vE "^packages/$dir/$sub/testing/|\.test\.tsx?:" || true)
		if [ -n "$hits" ]; then
			echo >&2 "A seeded package names what a model must not learn:"
			echo >&2
			echo "$hits" >&2
			echo >&2
			echo >&2 "This package is vendored into a model's workspace, doc comments and all."
			echo >&2 "Reword so it describes the game or the engine rather than the machinery"
			echo >&2 "around a run. Naming a *reviewer* is fine; naming our surfaces is not."
			exit 1
		fi
	done
done

# The other half of the same guarantee, and the one that actually regressed once:
# scrubbing this package's words is pointless if a seedable package reaches the
# evaluation contract by an edge instead. Seeding copies a package's whole
# closure out of the host store, so one `dependencies` entry is all it takes for
# `run-record` (records, reviews) to land in a run workspace again, and with it
# anything that depends on it, `backend-api`'s ladders and snapshots included.
#
# A package of this workspace is read from its manifest, and one from elsewhere,
# `@clockwyrks/asset-contract` from the feed, from the workspace's lock, which
# records the dependencies of the very version an install puts in place. So the
# check needs no install, and it judges the closure the lock commits to.
#
# The script below is node, not shell: nothing in it is meant to expand here, and
# the word splitting on the last line is how the list becomes argv.
# shellcheck disable=SC2016,SC2086
node --input-type=module -e '
import { existsSync, readFileSync } from "node:fs";

const SEEDED = process.argv.slice(2);
const BANNED = "@clockwyrks/run-record";

if (!existsSync("package-lock.json")) {
  console.error("package-lock.json does not exist, so the closure of a package from the feed cannot be read.");
  process.exit(1);
}
const locked = JSON.parse(readFileSync("package-lock.json", "utf8")).packages ?? {};

// The dependencies of a package of the project: a member of this workspace by
// its manifest, any other by its entry in the lock.
const dependencies = (name) => {
  const own = `packages/${name.replace(/^@clockwyrks\//, "")}/package.json`;
  if (existsSync(own)) {
    const manifest = JSON.parse(readFileSync(own, "utf8"));
    if (manifest.name === name) return manifest.dependencies ?? {};
  }
  const entry = locked[`node_modules/${name}`];
  if (!entry) {
    console.error(`${name} is neither a package of this workspace nor in package-lock.json.`);
    console.error("Write the lock again with `npm install` and commit it.");
    process.exit(1);
  }
  return entry.dependencies ?? {};
};

const failures = [];
for (const dir of SEEDED) {
  const root = JSON.parse(readFileSync(`packages/${dir}/package.json`, "utf8")).name;
  const seen = new Set();
  const walk = (name, path) => {
    if (seen.has(name)) return;
    seen.add(name);
    for (const dep of Object.keys(dependencies(name))) {
      if (!dep.startsWith("@clockwyrks/")) continue;
      const trail = [...path, dep];
      if (dep === BANNED) { failures.push(trail.join(" -> ")); continue; }
      walk(dep, trail);
    }
  };
  walk(root, [root]);
}

if (failures.length) {
  console.error("A seeded package depends on the evaluation contract:\n");
  for (const f of failures) console.error("  " + f);
  console.error(`\nSeeding copies the whole closure into the run repository, so
${BANNED} would be readable by the model: leaderboards, reviews and
all. Depend on @clockwyrks/asset-contract instead, or move the type you need
into it (the contracts repository'"'"'s crates/contract-codegen, ASSET_SPEC_TYPES).`);
  process.exit(1);
}
' -- "${SEEDED[@]}"

echo "Seeded packages (${SEEDED[*]}) name nothing about evaluation and none reaches the contract."
