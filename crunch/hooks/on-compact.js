#!/usr/bin/env node
'use strict';
/**
 * crunch's PostCompact hook, for manual and automatic compaction alike: a compaction starts the session's
 * edit count and context level again, so the next suggestions measure from the compacted context. State is found by
 * session id, which this machine's transcripts show a compaction keeps; the docs don't say. A subagent compacting its
 * own context says nothing about the session's, so its call is left alone. It always exits 0.
 */

const { readHookInput, log } = require('./hook-io');
const state = require('./state');

const RECORDED = new Set(['manual', 'auto', 'plugin']);

async function main(env = process.env) {
  const { input, problem } = await readHookInput();
  if (problem) {
    log(`[Crunch] PostCompact input not used (${problem})`);
    return;
  }
  if (input.agent_id) return;
  const key = state.sessionKey(input.session_id);
  if (!key) return;
  const dir = state.stateDir(env);
  if (!dir) return;
  const files = state.sessionFiles(dir, key);
  // The record a mod reads: one more compaction that stood, under its trigger. Another trigger names no file.
  if (RECORDED.has(input.trigger) && !state.addOne(files[input.trigger])) {
    log(`[Crunch] The ${input.trigger} compaction's record could not be written; a mod reading it misses it`);
  }
  state.removeState(files.count);
  state.removeState(files.level);
}

if (require.main === module) {
  main()
    .catch(err => log(`[Crunch] PostCompact error: ${err && err.message}`))
    .finally(() => {
      process.exitCode = 0;
    });
}
