// The workspace's tests: every package's own suite, each run as a vitest
// project under the package's own configuration (jsdom for the engines, the
// fixture site and Chromium for case-harness, node for the runtimes), so one
// run from the root covers them all and writes one report.
//
// The projects are named rather than globbed, so a directory under packages/
// that is not a package is no project. A package with a configuration of its
// own is named by that file, which keeps the root it sets (case-harness serves
// its fixture site from `test/`); one without is named by its directory.
//
// Given CI_GATE_ARTIFACTS (the typescript gate sets it), the run writes the JUnit
// report and the coverage summary into that directory, as ci/README.md names
// them; without it, it writes neither.
import { defineConfig } from "vitest/config";

const artifacts = process.env.CI_GATE_ARTIFACTS;

export default defineConfig({
  test: {
    projects: [
      // A project named by its configuration file is rooted at the file's
      // directory, whatever root the file sets, and case-harness serves its
      // fixture site from the root its suite runs in, `test/`: so it is
      // declared inline, extending its own configuration at that root. Its
      // configuration caps the workers that share its one browser, and a
      // project with a cap of its own runs in a group of its own, after the
      // others.
      {
        extends: "./packages/case-harness/vitest.config.ts",
        root: "./packages/case-harness/test",
        test: {
          name: "@clockwyrks/case-harness",
          sequence: { groupOrder: 1 },
        },
      },
      "packages/particle-runtime",
      "packages/simple-2d/vitest.config.ts",
      "packages/simple-3d/vitest.config.ts",
      "packages/structured-2d/vitest.config.ts",
      "packages/structured-3d/vitest.config.ts",
      "packages/voxel-runtime",
    ],
    ...(artifacts
      ? {
          reporters: ["default", "junit"],
          outputFile: { junit: `${artifacts}/junit.xml` },
          coverage: {
            enabled: true,
            provider: "v8",
            reporter: ["json-summary"],
            reportsDirectory: artifacts,
            include: ["packages/*/src/**/*.{ts,js}"],
          },
        }
      : {}),
  },
});
