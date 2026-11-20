#!/usr/bin/env node
'use strict';
/**
 * Says whether crunch's context-size check can read a transcript: the one named, or by default the newest
 * Claude Code keeps under its config folder's projects, which is $CLAUDE_CONFIG_DIR or ~/.claude. Exits 0 when it
 * can, 1 when it can't, and 2 when there is nothing to check.
 *
 *   node check-transcript.js [transcript.jsonl]
 */

const fs = require('fs');
const os = require('os');
const path = require('path');
const { probeTranscript } = require('./transcript-probe');

function configDir(env) {
  return env.CLAUDE_CONFIG_DIR || path.join(os.homedir(), '.claude');
}

/** The most recently written session transcript one folder down under `projects`, or null. */
function newestTranscript(projects) {
  let newest = null;
  let folders;
  try {
    folders = fs.readdirSync(projects, { withFileTypes: true });
  } catch {
    return null;
  }
  for (const folder of folders) {
    if (!folder.isDirectory()) continue;
    const dir = path.join(projects, folder.name);
    let files;
    try {
      files = fs.readdirSync(dir, { withFileTypes: true });
    } catch {
      continue;
    }
    for (const file of files) {
      if (!file.isFile() || !file.name.endsWith('.jsonl')) continue;
      const full = path.join(dir, file.name);
      try {
        const written = fs.statSync(full).mtimeMs;
        if (!newest || written > newest.written) newest = { full, written };
      } catch {
        /* gone since it was listed */
      }
    }
  }
  return newest && newest.full;
}

function main(args, env) {
  const projects = path.join(configDir(env), 'projects');
  const transcript = args[0] || newestTranscript(projects);
  if (!transcript) {
    console.log(`There is no transcript to check under ${projects}.`);
    return 2;
  }
  const result = probeTranscript(transcript);
  if (!result.readable) {
    console.log(`${transcript}: the context-size check can't read it: ${result.finding}.`);
    return 1;
  }
  const size = result.tokens > 0
    ? `its latest context is ~${Math.round(result.tokens / 1000)}k tokens${result.model ? ` (${result.model})` : ''}`
    : 'it holds no context size yet';
  console.log(`${transcript}: the context-size check can read it; ${size}.`);
  return 0;
}

if (require.main === module) {
  process.exitCode = main(process.argv.slice(2), process.env);
}

module.exports = { main, newestTranscript };
