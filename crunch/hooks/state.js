'use strict';
/**
 * Where the crunch hooks keep a session's state between calls, and how they write it.
 *
 * In the user's own state folder, never the shared temporary one: `crunch` under %LOCALAPPDATA% on
 * Windows, and under $XDG_STATE_HOME or ~/.local/state elsewhere. A folder in the user's home can't be planted in by
 * another user, and listing it costs nothing, where the shared temporary folder can hold tens of thousands of
 * entries. Every write goes to a temporary file that is renamed into place.
 */

const fs = require('fs');
const os = require('os');
const path = require('path');

const FOLDER_NAME = 'crunch';
const MAX_STATE_VALUE = 1000000000;

/** The folder state lives in, created private; null when it can't be, or isn't safely the user's own. */
function stateDir(env = process.env, platform = process.platform) {
  let base;
  if (platform === 'win32') {
    base = env.LOCALAPPDATA || path.join(os.homedir(), 'AppData', 'Local');
  } else {
    base = env.XDG_STATE_HOME && path.isAbsolute(env.XDG_STATE_HOME)
      ? env.XDG_STATE_HOME
      : path.join(os.homedir(), '.local', 'state');
  }
  const dir = path.join(base, FOLDER_NAME);
  try {
    fs.mkdirSync(dir, { recursive: true, mode: 0o700 });
    const stat = fs.lstatSync(dir);
    if (!stat.isDirectory() || stat.isSymbolicLink()) return null;
    if (platform !== 'win32' && typeof process.getuid === 'function' && stat.uid !== process.getuid()) return null;
    return dir;
  } catch {
    return null;
  }
}

/** A session id as a file name: letters, digits, - and _ only; null when nothing is left. */
function sessionKey(sessionId) {
  if (typeof sessionId !== 'string') return null;
  const key = sessionId.replace(/[^a-zA-Z0-9_-]/g, '');
  return key || null;
}

/**
 * The files one session's state is kept in: the hooks' own, and the records a mod reads, which are the count of
 * nudged calls and a count of the compactions that stood for each trigger.
 */
function sessionFiles(dir, key) {
  return {
    count: path.join(dir, `${key}.count`),
    level: path.join(dir, `${key}.level`),
    notice: path.join(dir, `${key}.notice`),
    nudged: path.join(dir, `${key}.nudged`),
    manual: path.join(dir, `${key}.manual`),
    auto: path.join(dir, `${key}.auto`),
    plugin: path.join(dir, `${key}.plugin`)
  };
}

/** Adds one to the number a state file holds, a missing or unreadable one counting as 0. Never throws. */
function addOne(file) {
  const value = readNumber(file);
  return writeState(file, String((value === null ? 0 : value) + 1));
}

/** A whole number from 0 up to a billion stored in a file, or null when it is missing or isn't one. */
function readNumber(file) {
  try {
    const text = fs.readFileSync(file, 'utf8').trim();
    if (!/^\d+$/.test(text)) return null;
    const value = Number(text);
    return value <= MAX_STATE_VALUE ? value : null;
  } catch {
    return null;
  }
}

/** The rename refusals Windows gives while another process, as an antivirus scanner, holds the file a moment. */
const BUSY = new Set(['EPERM', 'EACCES', 'EBUSY']);
const RENAME_TRIES = 5;
const RENAME_WAIT_MS = 20;

/** Renames a file into place, trying again a few times, a moment apart, while Windows refuses it as busy. */
function renameInto(from, to) {
  for (let attempt = 1; ; attempt++) {
    try {
      fs.renameSync(from, to);
      return;
    } catch (err) {
      if (attempt >= RENAME_TRIES || !BUSY.has(err && err.code)) throw err;
      Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, RENAME_WAIT_MS);
    }
  }
}

/** Writes text to a temporary file beside `file`, then renames it into place. Never throws. */
function writeState(file, text) {
  const temporary = `${file}.${process.pid}.${Date.now()}.tmp`;
  try {
    fs.writeFileSync(temporary, text, { encoding: 'utf8', flag: 'wx', mode: 0o600 });
    renameInto(temporary, file);
    return true;
  } catch {
    try {
      fs.rmSync(temporary, { force: true });
    } catch {
      /* nothing more to do */
    }
    return false;
  }
}

/** Removes a state file, if it is there. Never throws. */
function removeState(file) {
  try {
    fs.rmSync(file, { force: true });
  } catch {
    /* nothing more to do */
  }
}

/**
 * Whether a file's name is one the hooks write: a session's file, `<key>.<signal>`, or the temporary file a write
 * leaves when it fails, `<key>.<signal>.<pid>.<ms>.tmp`. A folder called `crunch` may be another program's too.
 */
function isStateFile(name) {
  const signals = Object.keys(sessionFiles('', 'k')).join('|');
  return new RegExp(`^[a-zA-Z0-9_-]+\\.(?:${signals})(?:\\.\\d+\\.\\d+\\.tmp)?$`).test(name);
}

/** Removes the hooks' files older than `days` days from `dir`, except those in `keep`. Never throws. */
function sweep(dir, days, keep = []) {
  const cutoff = Date.now() - days * 24 * 60 * 60 * 1000;
  const kept = new Set(keep.map(file => path.basename(file)));
  let entries;
  try {
    entries = fs.readdirSync(dir, { withFileTypes: true });
  } catch {
    return;
  }
  for (const entry of entries) {
    if (!entry.isFile() || kept.has(entry.name) || !isStateFile(entry.name)) continue;
    const file = path.join(dir, entry.name);
    try {
      if (fs.statSync(file).mtimeMs < cutoff) fs.rmSync(file, { force: true });
    } catch {
      /* gone already, or not ours to remove */
    }
  }
}

module.exports = { FOLDER_NAME, stateDir, sessionKey, sessionFiles, readNumber, writeState, addOne, removeState, sweep };
