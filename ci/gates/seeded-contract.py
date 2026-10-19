"""Keep evaluation vocabulary out of the packages seeded into a model's workspace.

The engines and the voxel and particle runtimes are vendored into a run's
workspace with their whole dependency closure, where the model building the
case reads every byte. scripts/ci/seeded-contract-check.sh greps them for the
project's name and for words about how a run is judged, and fails when the
closure, read from the workspace's lock, reaches the run-record contract. The
closure's `@clockwyrks/asset-contract` is the contracts repository's, whose own
tests hold it to the same vocabulary.

The gate is this repository's own, not the kit's: the pipeline renders a step
for it from the kit's table of extra gates, and an update of the kit never
touches this file.
"""

from the_test_cabinet_ci import GIT_LOCATION_VARIABLES, enter_repo_root, fail, require_tool, run

enter_repo_root()
require_tool("node", "The devcontainer and the web CI image install it.")

# The script finds the checkout with `git rev-parse`, so it must not inherit a
# commit hook's GIT_DIR (see GIT_LOCATION_VARIABLES).
if run(["scripts/ci/seeded-contract-check.sh"], unset=GIT_LOCATION_VARIABLES).returncode != 0:
    fail(
        "",
        "A seeded package names this project or how a run is judged, or reaches the",
        "run-record contract. Reword the source, or drop the dependency.",
    )
