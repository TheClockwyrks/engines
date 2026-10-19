import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

// The committed `lattice-core.wasm` is what `Engine` instantiates, and the only
// thing tying it to the renderer is the playback ABI: the exports `Engine` calls
// by name. A module built with the wrong features (`playback` without `-abi`
// builds the driver with no exports at all) or from a crate whose ABI moved would
// still be a valid module, and the renderer would fail at its first call. So read
// the module's export table and hold it to the ABI, with the signatures the
// wrapper's unpacking assumes (a packed i64 of pointer and length), and take no
// import, since `Engine` instantiates it with none.

const here = dirname(fileURLToPath(import.meta.url));
const MODULE = join(here, "..", "lattice-core.wasm");

const PLAYBACK_ABI = [
  "alloc",
  "playback_load",
  "playback_board",
  "playback_step",
  "playback_reset",
];

describe("the committed lattice-core.wasm", () => {
  const module = new WebAssembly.Module(readFileSync(MODULE));

  it("exports the playback ABI and its memory", () => {
    const exports = new Map(
      WebAssembly.Module.exports(module).map((e) => [e.name, e.kind]),
    );
    for (const name of PLAYBACK_ABI) {
      expect(exports.get(name), name).toBe("function");
    }
    expect(exports.get("memory")).toBe("memory");
  });

  it("imports nothing", () => {
    expect(WebAssembly.Module.imports(module)).toEqual([]);
  });

  it("answers the calls with the shapes the wrapper unpacks", async () => {
    const instance = await WebAssembly.instantiate(module, {});
    const x = instance.exports as unknown as {
      memory: WebAssembly.Memory;
      alloc(len: number): number;
      playback_load(ptr: number, len: number): number;
      playback_board(): bigint;
      playback_step(): bigint;
      playback_reset(): void;
    };
    const scenario = new TextEncoder().encode("not a scenario");
    const ptr = x.alloc(scenario.length);
    expect(typeof ptr).toBe("number");
    new Uint8Array(x.memory.buffer, ptr, scenario.length).set(scenario);
    // A scenario that does not parse is refused with 0, not a trap.
    expect(x.playback_load(ptr, scenario.length)).toBe(0);
    // The board and the step return a packed i64; with nothing loaded, a step
    // has no state to give.
    expect(typeof x.playback_board()).toBe("bigint");
    expect(BigInt.asUintN(32, x.playback_step())).toBe(0n);
    expect(x.playback_reset()).toBeUndefined();
  });
});
