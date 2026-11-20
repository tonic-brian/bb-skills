#!/usr/bin/env node
'use strict';
/**
 * crunch's PreToolUse hook, before every tool call: suggests /compact at a natural point, from two signals.
 *
 * - The context's size, the primary one: the latest usage in the session transcript, against a threshold scaled to
 *   the context window (160k of 200k, 250k of 1M), then again at each further threshold, or COMPACT_CONTEXT_INTERVAL:
 *   250k, 500k and 750k of 1M.
 * - The count of the session's edits and writes, the secondary one: at COMPACT_THRESHOLD (50), then at each further
 *   COMPACT_THRESHOLD, or COMPACT_INTERVAL: 50, 100, 150. Any other tool call counts nothing.
 *
 * A suggestion goes to Claude, beside the tool result, and to the developer, who is the one who can run /compact:
 * Claude gets the tagged lines below; the developer gets one line of their own, the context's size when it was read,
 * else the count, naming this skill by the folder it is installed in.
 * A subagent's call is left alone: it can't compact the session it works for. The hook always exits 0.
 *
 * When it finds no context size from the fifth edit or write of a session on, it asks transcript-probe.js why, and
 * tells the developer once per session what is missing, since the transcript's shape is observed, not documented.
 * Calls of other tools don't bring that on: a session's first response can make several before the transcript holds
 * any size at all.
 *
 * Rebuilt from affaan-m/ECC's scripts/hooks/suggest-compact.js (MIT, see ../LICENSE), keeping its signals,
 * thresholds, variables and wording where they were right. README.md here lists what changed and why.
 */

const path = require('path');
const { readHookInput, log, output } = require('./hook-io');
const state = require('./state');
const context = require('./transcript-context');
const { probeTranscript } = require('./transcript-probe');

const EDIT_TOOLS = new Set(['Edit', 'Write']);
const NOTICE_FROM_EDIT = 5;
const DEFAULT_COUNT_THRESHOLD = 50;
const DEFAULT_RETENTION_DAYS = 14;
const SKILL = path.basename(path.dirname(__dirname));

/** A whole number from 1 to max parsed from text, or the fallback. */
function wholeNumber(raw, fallback, max) {
  if (typeof raw !== 'string' || !/^\s*\d+\s*$/.test(raw)) return fallback;
  const parsed = Number.parseInt(raw, 10);
  return parsed > 0 && parsed <= max ? parsed : fallback;
}

/**
 * The context-size suggestion for this reading, or null. The reading it last fired at is kept per session: it fires
 * on first reaching the threshold and again on passing each further interval beyond it, the interval being the
 * threshold itself unless COMPACT_CONTEXT_INTERVAL sets it. The levels are counted against the threshold and interval
 * of this reading, so a window taken for 1M once the context passes 200k still nudges at its own threshold. Falling
 * below the threshold, as after a compaction, clears it, and falling below it while still above the threshold starts
 * it again from there.
 */
function contextSuggestion(usage, levelFile, env) {
  const { windowTokens, inferred } = context.resolveContextWindow(usage.tokens, usage.model);
  const threshold = context.resolveContextThreshold(env, windowTokens);
  if (threshold <= 0) return null;
  const interval = context.resolveContextInterval(env, threshold);
  const last = state.readNumber(levelFile);

  if (usage.tokens < threshold) {
    if (last !== null) state.removeState(levelFile);
    return null;
  }
  if (last !== null && usage.tokens < last) {
    state.writeState(levelFile, String(usage.tokens));
    return null;
  }
  const level = tokens => context.computeContextBucket(tokens, threshold, interval);
  if (last !== null && level(usage.tokens) <= level(last)) return null;

  state.writeState(levelFile, String(usage.tokens));
  const approx = `${Math.round(usage.tokens / 1000)}k`;
  // A percentage only when the window was detected: against an assumed one it would mislead.
  const scale = inferred
    ? ''
    : ` (${Math.round((usage.tokens / windowTokens) * 100)}% of ${context.formatWindowLabel(windowTokens)} window)`;
  return `[Crunch] Context ~${approx} tokens${scale} - consider /compact at the next logical boundary`;
}

/** The edit-count suggestion for the session's count so far, or null: at the threshold, then at each step past it. */
function countSuggestion(count, threshold, step = threshold) {
  if (count === threshold) {
    return `[Crunch] ${threshold} edits and writes so far - consider /compact if moving to a new phase`;
  }
  if (count > threshold && (count - threshold) % step === 0) {
    return `[Crunch] ${count} edits and writes - a good checkpoint for /compact if the context is stale`;
  }
  return null;
}

/**
 * The developer's line for a nudge: the context's size when it was read, its share and the window too when the
 * window was detected, else the session's count of edits and writes.
 */
function developerLine(usage, count) {
  const ask = ` - consider /${SKILL} | /compact`;
  if (!usage) return `${count} edits and writes${ask}`;
  const { windowTokens, inferred } = context.resolveContextWindow(usage.tokens, usage.model);
  const approx = `${Math.round(usage.tokens / 1000)}k`;
  if (inferred) return `Context ~${approx} tokens${ask}`;
  const percent = Math.round((usage.tokens / windowTokens) * 100);
  return `Context ~${approx} tokens @ ${percent}%${ask} (${context.formatWindowLabel(windowTokens)} window)`;
}

async function main(env = process.env) {
  const { input, problem } = await readHookInput();
  if (problem) {
    log(`[Crunch] Input not used (${problem}); nothing counted`);
    return;
  }
  if (input.agent_id) return;
  const key = state.sessionKey(input.session_id);
  if (!key) return;
  const dir = state.stateDir(env);
  if (!dir) {
    log('[Crunch] No private state folder; nothing counted');
    return;
  }
  const files = state.sessionFiles(dir, key);
  const isEdit = EDIT_TOOLS.has(input.tool_name);

  // The count file is written on a session's first call of any tool, so the sweep runs once a session.
  const previous = state.readNumber(files.count);
  const count = (previous === null ? 0 : previous) + (isEdit ? 1 : 0);
  if (previous === null || isEdit) state.writeState(files.count, String(count));
  if (previous === null) {
    state.sweep(dir, wholeNumber(env.COMPACT_STATE_TTL_DAYS, DEFAULT_RETENTION_DAYS, 3650), Object.values(files));
  }

  const messages = [];
  const notices = [];
  const transcriptPath = typeof input.transcript_path === 'string' ? input.transcript_path : '';
  let usage = null;
  try {
    usage = context.readLatestContextTokens(transcriptPath);
  } catch (err) {
    log(`[Crunch] Context signal skipped: ${err.message}`);
  }
  if (usage) {
    const suggestion = contextSuggestion(usage, files.level, env);
    if (suggestion) messages.push(suggestion);
  } else if (count >= NOTICE_FROM_EDIT && state.readNumber(files.notice) === null) {
    const notice = transcriptNotice(transcriptPath);
    if (notice) {
      notices.push(notice);
      state.writeState(files.notice, '1');
    }
  }

  if (isEdit) {
    const countThreshold = wholeNumber(env.COMPACT_THRESHOLD, DEFAULT_COUNT_THRESHOLD, 10000);
    const counted = countSuggestion(count, countThreshold, wholeNumber(env.COMPACT_INTERVAL, countThreshold, 10000));
    if (counted) messages.push(counted);
  }

  // The record a mod reads: one more nudged call, written before the answer goes out. The notice is no nudge.
  if (messages.length > 0 && !state.addOne(files.nudged)) {
    log('[Crunch] The nudge record could not be written; a mod reading it misses this nudge');
  }

  if (messages.length > 0 || notices.length > 0) {
    // One line for the developer however many nudges fired: it is built from the size, not from each nudge.
    const told = messages.length > 0 ? [developerLine(usage, count)] : [];
    const payload = { systemMessage: [...told, ...notices].join('\n') };
    if (messages.length > 0) {
      payload.hookSpecificOutput = { hookEventName: 'PreToolUse', additionalContext: messages.join('\n') };
    }
    output(payload);
  }
}

/** What to tell the developer when the transcript can't be read, or null when the probe finds it can. */
function transcriptNotice(transcriptPath) {
  let result;
  try {
    result = probeTranscript(transcriptPath);
  } catch (err) {
    result = { readable: false, finding: `probing it failed: ${err.message}` };
  }
  if (result.readable) return null;
  const check = path.join(__dirname, 'check-transcript.js').replace(/\\/g, '/');
  const target = transcriptPath ? ` "${transcriptPath.replace(/\\/g, '/')}"` : '';
  return `[Crunch] The context-size check can't read this Claude Code's transcript: ${result.finding}. ` +
    `Only the count of edits and writes is working. To look further: node "${check}"${target}`;
}

if (require.main === module) {
  main()
    .catch(err => log(`[Crunch] Error: ${err && err.message}`))
    .finally(() => {
      process.exitCode = 0;
    });
}

module.exports = { contextSuggestion, countSuggestion, developerLine, transcriptNotice, wholeNumber };
