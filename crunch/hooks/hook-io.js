'use strict';
/**
 * How the crunch hooks read their input and give their answer. In place of the helpers upstream's hook
 * took from affaan-m/ECC's 742-line scripts/lib/utils.js; where state is kept is state.js's business.
 */

const MAX_INPUT_BYTES = 16 * 1024 * 1024;
const INPUT_TIMEOUT_MS = 2000;

/**
 * The hook's input, JSON on stdin. Resolves to { input } when it arrives whole and is a JSON object, and otherwise to
 * { problem }: 'empty', 'too large', 'late', 'not JSON', 'not an object' or 'unreadable'. It never rejects. Up to
 * 16 MiB is read, because a Write's input carries the whole file; upstream's 1 MiB turned a large Write into {} and
 * its session into a 'default' that every such session shared.
 */
function readHookInput({ timeoutMs = INPUT_TIMEOUT_MS, maxBytes = MAX_INPUT_BYTES, stream = process.stdin } = {}) {
  return new Promise(resolve => {
    const chunks = [];
    let size = 0;
    let tooLarge = false;
    let done = false;

    const finish = problem => {
      if (done) return;
      done = true;
      clearTimeout(timer);
      stream.removeAllListeners('data');
      stream.removeAllListeners('end');
      stream.removeAllListeners('error');
      if (typeof stream.unref === 'function') stream.unref();
      if (problem) return resolve({ problem });
      if (tooLarge) return resolve({ problem: 'too large' });
      const text = Buffer.concat(chunks).toString('utf8');
      if (!text.trim()) return resolve({ problem: 'empty' });
      let input;
      try {
        input = JSON.parse(text);
      } catch {
        return resolve({ problem: 'not JSON' });
      }
      if (!input || typeof input !== 'object' || Array.isArray(input)) return resolve({ problem: 'not an object' });
      resolve({ input });
    };
    const timer = setTimeout(() => finish('late'), timeoutMs);

    stream.on('data', chunk => {
      if (done || tooLarge) return;
      size += chunk.length;
      if (size > maxBytes) {
        // Keep reading to the end without keeping anything, so the writer isn't cut off mid-write.
        tooLarge = true;
        chunks.length = 0;
        return;
      }
      chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
    });
    stream.on('end', () => finish(null));
    stream.on('error', () => finish('unreadable'));
  });
}

/** A line for the debug log: Claude Code shows a hook's stderr to no one when it exits 0. */
function log(message) {
  console.error(message);
}

/** The hook's answer on stdout, as JSON when it is an object. */
function output(data) {
  console.log(typeof data === 'object' ? JSON.stringify(data) : data);
}

module.exports = { MAX_INPUT_BYTES, INPUT_TIMEOUT_MS, readHookInput, log, output };
