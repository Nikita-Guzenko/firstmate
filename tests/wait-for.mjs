// tests/wait-for.mjs - polling waits for the node-driven watcher/plugin tests.
//
// NEVER wait for an asynchronous side effect with a fixed number of short
// sleeps (`for (let i = 0; i < 50; i += 1) await sleep(20)` == a 1s ceiling).
// That pattern made tests/fm-pi-watch-extension.test.sh flaky: the Pi extension
// arms its watcher child asynchronously, and on a loaded box (inside the
// no-mistakes daemon, say) spawning bash + reading its output takes longer than
// the 1s window, so the case failed as a bare `expected exit 0, got 1` with no
// hint of what it was still waiting for.
//
// Use waitFor() instead: it polls to a generous ceiling and, on timeout, throws
// naming exactly the condition that never became true. Consumers get the path
// to this file from the FM_TEST_WAIT_FOR env var exported by tests/lib.sh:
//
//   const { waitFor } = await import(pathToFileURL(process.env.FM_TEST_WAIT_FOR).href);
//   await waitFor("the watcher arm log to exist", () => existsSync(log));
//
// Override the ceiling for a whole run with FM_TEST_WAIT_TIMEOUT_MS.

const DEFAULT_TIMEOUT_MS = Number(process.env.FM_TEST_WAIT_TIMEOUT_MS || 30000);

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

// waitFor(description, predicate, options) - poll predicate() until it returns
// a truthy value, then return that value. On timeout throw an Error naming the
// description, the elapsed ceiling, and options.diagnose() output when given.
//
// description reads as the thing being awaited ("the arm child to send a
// follow-up prompt"), because it is interpolated into "timed out ... waiting
// for <description>".
export async function waitFor(description, predicate, options = {}) {
  const timeoutMs = options.timeoutMs ?? DEFAULT_TIMEOUT_MS;
  const intervalMs = options.intervalMs ?? 20;
  const started = Date.now();
  for (;;) {
    const value = await predicate();
    if (value) return value;
    if (Date.now() - started >= timeoutMs) {
      const detail = options.diagnose ? `\nstate: ${await options.diagnose()}` : "";
      throw new Error(
        `timed out after ${timeoutMs}ms waiting for ${description}${detail}`,
      );
    }
    await sleep(intervalMs);
  }
}

// waitForFileContaining(path, needle) - wait until <path> exists AND already
// holds <needle>, then return its full text.
//
// Waiting on existsSync() alone is a trap whenever the assertion afterwards
// reads the file: a child that writes with `>>` creates the file before its
// first line lands, so the read can return "" and the case fails with an empty
// diagnostic. Wait for the content the assertion needs, not for the inode.
export async function waitForFileContaining(path, needle, options = {}) {
  const { readFileSync } = await import("node:fs");
  const read = () => {
    try {
      return readFileSync(path, "utf8");
    } catch {
      return null;
    }
  };
  return waitFor(`${path} to contain ${JSON.stringify(needle)}`, () => {
    const text = read();
    return text !== null && text.includes(needle) ? text : null;
  }, {
    ...options,
    diagnose: () => {
      const text = read();
      return text === null ? "file does not exist" : `file holds ${JSON.stringify(text)}`;
    },
  });
}

// settle(ms, why) - a deliberate fixed pause used ONLY to give a side effect a
// chance to happen before asserting that it did NOT. There is no condition to
// poll for in that direction, so the pause is the assertion window; `why` keeps
// it from being mistaken for a waitFor() that someone shortened.
export async function settle(ms, why) {
  if (!why) throw new Error("settle() requires a reason");
  await sleep(ms);
}
