# history

The record of how this repository's history was extracted from the monorepo,
[The Test Cabinet](https://github.com/TheClockwyrks/TheTestCabinet), where the
crates and packages here lived until the extraction. Nothing builds or tests
against these files; they are kept so the provenance outlives the scratch clone
the extraction ran in.

## The extraction

The history below the scaffold commit is the monorepo's `nightly` at
`249142af1b7dfb26a136439a2e1accd366d1fe05`, filtered to the paths in
[`paths.txt`](paths.txt) by git filter-repo 2.47.0:

```sh
git clone -q --no-local --no-checkout --single-branch --branch nightly --no-tags \
  <the-test-cabinet> x
cd x
uvx --from git-filter-repo==2.47.0 git-filter-repo --force \
  --paths-from-file ../paths.txt --prune-empty always --preserve-commit-hashes
```

Of the 6,763 commits reachable from that commit, 277 touched a path in the list
and were kept (38 of them merges); the rest were pruned. No tag was carried. The
tip tree of every moved directory, and the tip blob of each of the five files
named under the live-path review, hashes the same as the monorepo's at that
commit.

The paths are kept where they were in the monorepo, so the filter needed no
rename and every relative path inside the crates (the manifests
`crates/engines` embeds with `include_str!`, the fixtures) works as it did.

## The files

- [`paths.txt`](paths.txt) is the list handed to `--paths-from-file`
  (sha256 `eb1de31757e81589526b79377753587b6e512950b69a32c923825711f29b6b64`).
  It is generated, not hand-written: the twenty-four moved directories
  (`engines/`, `crates/engines/`, `crates/match-play/`, the eight
  `crates/foray-*/` and six `crates/lattice-*/` crates, and `packages/simple-2d/`,
  `packages/simple-3d/`, `packages/structured-2d/`, `packages/structured-3d/`,
  `packages/case-harness/`, `packages/voxel-runtime/` and
  `packages/particle-runtime/`), the five lattice playback files of the console
  named below, and every path a tracked file among them had before a rename or
  copy, collected by `git log --follow --name-status` over each of the 480
  files, so a file's history reaches back past the commits that moved it into
  place.
- [`commit-map`](commit-map) is filter-repo's map from each monorepo commit (left)
  to the commit it became here (right), all zeros for a pruned one.
  `--preserve-commit-hashes` left the commit ids quoted in the messages as they
  were, so an id in a message below the scaffold commit names a monorepo commit,
  and this map translates it.

## The live-path review

`paths.txt` intersected with the monorepo's tree at the extraction commit names,
outside the twenty-four moved directories, exactly twenty-five live files.

Five are the console's lattice playback, which moves here to become
`@clockwyrks/lattice-runtime`, and which the scaffold commit keeps where it
found them, so the commit after it moves them into `packages/lattice-runtime/`
with `git mv` and `git log --follow` reaches their history across the move:

```text
packages/ui/src/app/pages/runs/lattice/assets/lattice-core.wasm
packages/ui/src/app/pages/runs/lattice/interpolate.test.ts
packages/ui/src/app/pages/runs/lattice/interpolate.ts
packages/ui/src/app/pages/runs/lattice/renderer.integration.test.ts
packages/ui/src/app/pages/runs/lattice/renderer.ts
```

The other twenty are copy sources or copies: a file here began as a copy of
one of them, or was copied out to one, and the monorepo kept its own copy (the
engine pages of the documentation the packages' `docs/` began from, the
reference controllers' committed `.wasm` builds in the test cases and the
backend's test data, and validator files the case harness grew out of). They
were kept in the list so `git log --follow` and blame of the files reach their
history before the copy. Their commits after the copy, which touch the
monorepo's copies only, are in this history too, and the scaffold commit
deletes the twenty files:

```text
apps/docs/src/content/docs/engines/simple-3d/apis/recording.md
apps/docs/src/content/docs/engines/structured-2d/apis/actors.md
apps/docs/src/content/docs/engines/structured-2d/apis/camera.md
apps/docs/src/content/docs/engines/structured-2d/apis/components.md
apps/docs/src/content/docs/engines/structured-2d/apis/rendering.md
apps/docs/src/content/docs/engines/structured-2d/apis/worlds.md
apps/docs/src/content/docs/engines/structured-3d/apis/assets.md
apps/docs/src/content/docs/engines/structured-3d/apis/components.md
apps/docs/src/content/docs/engines/structured-3d/apis/math.md
crates/backend/testdata/definitions/test-cases/adversarial/easy/foray/v1.0.0/references/border-soldier.wasm
crates/backend/testdata/definitions/test-cases/adversarial/easy/foray/v1.0.0/references/fuel-probe.wasm
crates/backend/testdata/definitions/test-cases/adversarial/easy/foray/v1.0.0/references/greedy-raider.wasm
crates/backend/testdata/definitions/test-cases/adversarial/easy/foray/v1.0.0/references/random.wasm
test-cases/adversarial/easy/foray/v1.0.0/references/border-soldier.wasm
test-cases/adversarial/easy/foray/v1.0.0/references/fuel-probe.wasm
test-cases/adversarial/easy/foray/v1.0.0/references/greedy-raider.wasm
test-cases/adversarial/easy/foray/v1.0.0/references/random.wasm
test-cases/end-to-end/easy/carom/v3.0.0/validation/none/chromium.ts
test-cases/end-to-end/easy/carom/v3.0.0/validation/simple-2d/assert.ts
test-cases/end-to-end/easy/fathom/v3.0.0/validation/none/chromium.ts
```

The scaffold commit also deletes `engines/.gitattributes`, the monorepo's rule
for that one directory, which the root `.gitattributes` the kit renders states
for the whole repository.
