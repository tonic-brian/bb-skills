#!/usr/bin/env node
'use strict';
/**
 * How long each agent of a Claude Code session has run, and how long since it last wrote.
 *
 * Claude Code keeps a session's transcript at <projects>/<project>/<session>.jsonl, and the transcript of each agent
 * the session starts at <projects>/<project>/<session>/subagents/agent-<id>.jsonl, beside a small agent-<id>.meta.json
 * that names it; a workflow's agents are in subagents/workflows/wf_<id>/, beside the workflow's journal.jsonl, and the
 * session's workflows/wf_<id>.json holds the labels the workflow gave them. None of these files is documented: what
 * this reads is observed. It reads the metadata files, journals and run states, and of an agent's transcript only
 * its first line, whose timestamp is when the agent started, and its last 256 KiB, whose last record's timestamp is
 * when the agent last wrote. The file's own times stand in when those have none: its write time can be touched long
 * after its last record, so it serves otherwise only as a first filter for --hours.
 *
 * An agent's state is the first of these that settles it: a result for it in its workflow's journal (journal); an
 * agent-<id>.prefix.json, which some agents get when they stop, written no earlier than 5 s before their last write
 * (prefix); the agent's own last record, an assistant's end_turn that asks for no tool (turn); and, for the agents
 * still undecided, what the session transcript recorded since they last wrote: a completion notice, which names an
 * agent completed, failed or killed (notice), and for a foreground agent the tool result its report came back as, no
 * earlier than 5 s before its last write (report), finished or, when the request was interrupted, interrupted.
 * Otherwise it is running, or quiet once it has written nothing for --quiet-minutes: still on one long step, or
 * stopped unseen. Each row names what decided its state, and nothing for running and quiet: when Claude Code changes
 * these undocumented files, agents that should read finished turn quiet with nothing to say why, rather than hiding
 * it.
 *
 * Exits 0 with the table, even an empty one, and 2 on a usage error or when it finds no session.
 */

const fs = require('fs');
const os = require('os');
const path = require('path');

const USAGE = `Usage: node agent-times.js [options] [<agent id>...]

How long each agent of a Claude Code session has run, and how long since it last wrote. A bare word is an agent id,
or its start, as --agent takes one.

  --session-folder <dir>   the session's folder, <projects>/<project>/<session>; overrides the options below
  --session <id>           a session's id, or its start, in the project named, else in any project; default: the
                           session $CLAUDE_CODE_SESSION_ID names unless a project is, else the project's newest
  --project-dir <dir>      the directory the session was started in; default: the current directory
  --project-folder <dir>   a project's folder under <Claude home>/projects; overrides --project-dir
  --claude-home <dir>      Claude Code's own folder; default: $CLAUDE_CONFIG_DIR, else ~/.claude
  --agent <id>[,<id>...]   only the agents whose ids start with one of these; repeatable
  --hours <n>              only the agents that wrote within this many hours, 1 to 8760; default 24
  --quiet-minutes <n>      how long without a write makes a running agent quiet, 1 to 1440; default 15
  --json                   the session and its agents as JSON, times in ISO 8601 and durations in seconds
  --help                   this text
`;

const MINUTE_MS = 60 * 1000;
const HOUR_MS = 60 * MINUTE_MS;
const PREFIX_GRACE_MS = 5 * 1000;
const REPORT_GRACE_MS = 5 * 1000;
const INTERRUPTED = '[Request interrupted';
const NOTICE_GRACE_MS = MINUTE_MS;
const NOTICE_LOOKBACK_MS = 10 * MINUTE_MS;
const SEARCH_WINDOW_BYTES = 4 * 1024 * 1024;
const LINES_FOR_A_TIME = 50;
const READ_CHUNK_BYTES = 1024 * 1024;
const TAIL_BYTES = 256 * 1024;
const HEAD_BYTES = 64 * 1024;
const TIMESTAMP_PATTERN = /"timestamp":"([^"]+)"/g;
// [^\n] and not ., which stops at the line and paragraph separators JSON may carry unescaped.
const NOTICE_PATTERN = /<task-id>([0-9A-Za-z]+)<\/task-id>[^\n]*?<status>([a-z_]+)<\/status>/g;

const VALUE_OPTIONS = new Map([
  ['--session-folder', 'sessionFolder'],
  ['--session', 'session'],
  ['--project-dir', 'projectDir'],
  ['--project-folder', 'projectFolder'],
  ['--claude-home', 'claudeHome'],
  ['--agent', 'agents'],
  ['--hours', 'hours'],
  ['--quiet-minutes', 'quietMinutes']
]);
const RANGES = { hours: [1, 8760], quietMinutes: [1, 1440] };

/** A failure the command reports and exits 2 on: a usage error, or no session to read. */
class AgentTimesError extends Error {
  constructor(message, { usage = false } = {}) {
    super(message);
    this.usage = usage;
  }
}

function wholeNumber(name, text, [low, high]) {
  const value = /^\d+$/.test(text) ? Number(text) : NaN;
  if (!(value >= low && value <= high)) {
    throw new AgentTimesError(`${name} takes a whole number from ${low} to ${high}, not ${text}`, { usage: true });
  }
  return value;
}

/** The command line's options; anything it doesn't take is an AgentTimesError marked as a usage error. */
function parseArgs(args) {
  const options = { agents: [], hours: 24, quietMinutes: 15, json: false, help: false };
  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === '--json') {
      options.json = true;
      continue;
    }
    if (arg === '--help' || arg === '-h') {
      options.help = true;
      continue;
    }
    // A bare word is an agent id's start, so that `agent-times a2d0ff a6331f` asks for those two.
    if (!arg.startsWith('-')) {
      options.agents.push(arg);
      continue;
    }
    const equals = arg.startsWith('--') ? arg.indexOf('=') : -1;
    const name = equals === -1 ? arg : arg.slice(0, equals);
    const key = VALUE_OPTIONS.get(name);
    if (!key) throw new AgentTimesError(`unknown option ${arg}`, { usage: true });
    let value;
    if (equals !== -1) value = arg.slice(equals + 1);
    else if (i + 1 < args.length && !args[i + 1].startsWith('--')) value = args[++i];
    else throw new AgentTimesError(`${name} needs a value`, { usage: true });

    if (key === 'agents') options.agents.push(value);
    else if (key in RANGES) options[key] = wholeNumber(name, value, RANGES[key]);
    else options[key] = value;
  }
  return options;
}

function statOrNull(file) {
  try {
    return fs.statSync(file);
  } catch {
    return null;
  }
}

function isFolder(file) {
  const stat = statOrNull(file);
  return Boolean(stat && stat.isDirectory());
}

function isFile(file) {
  const stat = statOrNull(file);
  return Boolean(stat && stat.isFile());
}

function claudeHomeFrom(env) {
  return env.CLAUDE_CONFIG_DIR || path.join(os.homedir(), '.claude');
}

/** Claude Code names a project's folder after its directory, every character but a letter or digit a hyphen. */
function projectFolderFor(claudeHome, projectDir) {
  return path.join(claudeHome, 'projects', projectDir.replace(/[^A-Za-z0-9]/g, '-'));
}

/** Every project's folder under Claude Code's own folder. */
function projectFolders(claudeHome) {
  const projects = path.join(claudeHome, 'projects');
  if (!isFolder(projects)) return [];
  return fs
    .readdirSync(projects, { withFileTypes: true })
    .filter(entry => entry.isDirectory())
    .map(entry => path.join(projects, entry.name));
}

/** A project folder's session transcripts whose ids start with `start`, in any case: newest file first. */
function transcriptsIn(project, start = '') {
  const wanted = start.toLowerCase();
  const transcripts = [];
  for (const entry of fs.readdirSync(project, { withFileTypes: true })) {
    if (!entry.isFile() || !entry.name.toLowerCase().endsWith('.jsonl')) continue;
    const id = entry.name.slice(0, -'.jsonl'.length);
    if (!id.toLowerCase().startsWith(wanted)) continue;
    const transcript = path.join(project, entry.name);
    const stat = statOrNull(transcript);
    if (stat) transcripts.push({ id, project, transcript, written: stat.mtimeMs });
  }
  return transcripts.sort((a, b) => b.written - a.written);
}

function sessionOf({ id, project, transcript }, chosenBy) {
  return { id, folder: path.join(project, id), transcript, chosenBy };
}

/**
 * The session's id, folder and transcript, and which rule chose it: session-folder, session, CLAUDE_CODE_SESSION_ID
 * or newest. --session-folder names it outright. --session is an id's start, looked
 * for in the project folder a project option names, and with none in every project's. Without either, a session of
 * Claude Code's names itself in $CLAUDE_CODE_SESSION_ID, found in whichever project's folder holds it, unless a project
 * option names another project. Otherwise it is the session, of the project the options or the current directory
 * name, whose last record is newest.
 */
function resolveSession({ sessionFolder, session, projectDir, projectFolder, claudeHome, cwd = process.cwd(), sessionId }) {
  if (sessionFolder) {
    const folder = path.resolve(sessionFolder);
    if (!fs.existsSync(folder)) throw new AgentTimesError(`No session folder at ${folder}.`);
    const id = path.basename(folder);
    return { id, folder, transcript: path.join(path.dirname(folder), `${id}.jsonl`), chosenBy: 'session-folder' };
  }

  const projectNamed = Boolean(projectFolder || projectDir);
  if (session && !projectNamed) {
    const matches = projectFolders(claudeHome)
      .flatMap(project => transcriptsIn(project, session))
      .sort((a, b) => b.written - a.written);
    if (matches.length === 0) {
      throw new AgentTimesError(`No session starting ${session} under ${path.join(claudeHome, 'projects')}.`);
    }
    if (matches.length > 1) {
      const named = matches.map(match => `${path.basename(match.project)}/${match.id}`);
      throw new AgentTimesError(`More than one session starts ${session}: ${named.join(', ')}.`);
    }
    return sessionOf(matches[0], 'session');
  }
  if (!session && !projectNamed && sessionId) {
    const own = projectFolders(claudeHome)
      .flatMap(project => transcriptsIn(project, sessionId))
      .find(match => match.id.toLowerCase() === sessionId.toLowerCase());
    if (own) return sessionOf(own, 'CLAUDE_CODE_SESSION_ID');
  }

  const project = path.resolve(projectFolder || projectFolderFor(claudeHome, projectDir || cwd));
  if (!isFolder(project)) {
    throw new AgentTimesError(`No project folder at ${project}. Pass --project-folder, or --session-folder.`);
  }
  const transcripts = transcriptsIn(project, session || '');
  if (transcripts.length === 0) {
    throw new AgentTimesError(`${session ? `No session starting ${session}` : 'No session'} in ${project}.`);
  }
  if (session && transcripts.length > 1) {
    throw new AgentTimesError(`More than one session starts ${session}: ${transcripts.map(t => t.id).join(', ')}.`);
  }
  return session ? sessionOf(transcripts[0], 'session') : sessionOf(newestByRecord(transcripts), 'newest');
}

/**
 * Of transcripts newest file first, the one whose last record is newest. A file's time can be touched after its last
 * record but is never earlier, so the tails are read until a file's time falls before the newest record found.
 */
function newestByRecord(transcripts) {
  let newest = null;
  for (const transcript of transcripts) {
    if (newest && transcript.written < newest.time) break;
    const time = lastLineTime(tailLines(transcript.transcript)) ?? transcript.written;
    if (!newest || time > newest.time) newest = { transcript, time };
  }
  return newest.transcript;
}

/** A timestamp in ms, or null. A time with no offset is read as UTC. */
function parseTime(text) {
  const utc = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d+)?)?$/.test(text) ? `${text}Z` : text;
  const ms = Date.parse(utc);
  return Number.isNaN(ms) ? null : ms;
}

/** A transcript line's own time in ms, or null: its last timestamp field, since its content can quote others first. */
function lineTime(line) {
  let last = null;
  for (const match of line.matchAll(TIMESTAMP_PATTERN)) last = match[1];
  return last === null ? null : parseTime(last);
}

/**
 * An open file's lines from a byte offset: next() gives one a call, without its line break, and null at the end;
 * bytesRead() how many bytes it has read from the file so far.
 */
function lineReader(fd, offset) {
  const chunk = Buffer.alloc(READ_CHUNK_BYTES);
  let position = offset;
  let start = 0;
  let end = 0;
  let atEnd = false;

  function text(parts) {
    const line = (parts.length === 1 ? parts[0] : Buffer.concat(parts)).toString('utf8');
    return line.endsWith('\r') ? line.slice(0, -1) : line;
  }

  function next() {
    const parts = [];
    for (;;) {
      if (start < end) {
        const newline = chunk.subarray(0, end).indexOf(0x0a, start);
        if (newline !== -1) {
          parts.push(chunk.subarray(start, newline));
          start = newline + 1;
          return text(parts);
        }
        // The chunk is read into again, so the line's start is copied out of it.
        parts.push(Buffer.from(chunk.subarray(start, end)));
        start = end;
      }
      if (atEnd) return parts.length > 0 ? text(parts) : null;
      end = fs.readSync(fd, chunk, 0, chunk.length, position);
      position += end;
      start = 0;
      atEnd = end === 0;
    }
  }

  return { next, bytesRead: () => position - offset };
}

/** The time of the first line that starts after a byte offset of an open transcript, or null at its end. */
function readLineTimeAt(fd, offset) {
  const reader = lineReader(fd, offset);
  if (offset > 0) reader.next();
  for (let count = 0; count < LINES_FOR_A_TIME; count++) {
    const line = reader.next();
    if (line === null) return null;
    const time = lineTime(line);
    if (time !== null) return time;
  }
  return null;
}

/** A tool result's text: its content when that is a string, else its text parts. */
function resultText(content) {
  if (typeof content === 'string') return content;
  if (!Array.isArray(content)) return '';
  return content
    .filter(part => part && part.type === 'text' && typeof part.text === 'string')
    .map(part => part.text)
    .join('\n');
}

/** The tool results of one session transcript line for the tool uses asked about, as [toolUseId, text] pairs. */
function toolResults(line, toolUseIds) {
  if (!line.includes('"tool_result"') || ![...toolUseIds].some(id => line.includes(id))) return [];
  let record;
  try {
    record = JSON.parse(line);
  } catch {
    return [];
  }
  const content = record && record.message && Array.isArray(record.message.content) ? record.message.content : [];
  return content
    .filter(item => item && item.type === 'tool_result' && toolUseIds.has(item.tool_use_id))
    .map(item => [item.tool_use_id, resultText(item.content)]);
}

/**
 * What a session's transcript recorded since a time: the latest completion notice per agent id, lower-cased, as
 * { at, status }; the latest tool result for each of `toolUseIds`, as { at, interrupted }; and the byte it started
 * reading at and how many bytes it read from there. A transcript only grows, its lines in time order, so a binary
 * search over its lines' times finds where to start, to within 4 MiB, and it reads from there to the end.
 */
function readSession(transcript, since, toolUseIds = []) {
  const notices = new Map();
  const reports = new Map();
  if (!isFile(transcript)) return { notices, reports, start: 0, bytesRead: 0 };
  const wanted = new Set(toolUseIds);

  const fd = fs.openSync(transcript, 'r');
  let low = 0;
  let reader;
  try {
    let high = fs.fstatSync(fd).size;
    while (high - low > SEARCH_WINDOW_BYTES) {
      const middle = low + Math.floor((high - low) / 2);
      const time = readLineTimeAt(fd, middle);
      if (time !== null && time < since) low = middle;
      else high = middle;
    }

    reader = lineReader(fd, low);
    if (low > 0) reader.next();
    for (let line = reader.next(); line !== null; line = reader.next()) {
      const isNotice = line.includes('<task-notification>');
      const results = wanted.size > 0 ? toolResults(line, wanted) : [];
      if (!isNotice && results.length === 0) continue;
      const at = lineTime(line);
      if (at === null) continue;
      if (isNotice) {
        for (const [, id, status] of line.matchAll(NOTICE_PATTERN)) {
          const key = id.toLowerCase();
          const known = notices.get(key);
          if (!known || known.at < at) notices.set(key, { at, status });
        }
      }
      for (const [toolUseId, text] of results) {
        const known = reports.get(toolUseId);
        if (!known || known.at < at) reports.set(toolUseId, { at, interrupted: text.startsWith(INTERRUPTED) });
      }
    }
  } finally {
    fs.closeSync(fd);
  }
  return { notices, reports, start: low, bytesRead: reader.bytesRead() };
}

/** The last `bytes` of a file as UTF-8 text, and whether bytes before them were left out; null when unreadable. */
function readTail(file, bytes) {
  let fd;
  try {
    fd = fs.openSync(file, 'r');
  } catch {
    return null;
  }
  try {
    const size = fs.fstatSync(fd).size;
    const start = Math.max(0, size - bytes);
    const buffer = Buffer.alloc(size - start);
    const read = fs.readSync(fd, buffer, 0, buffer.length, start);
    return { text: buffer.toString('utf8', 0, read), truncated: start > 0 };
  } finally {
    fs.closeSync(fd);
  }
}

function parses(line) {
  try {
    JSON.parse(line);
    return true;
  } catch {
    return false;
  }
}

/**
 * The complete records in the last 256 KiB of an agent's transcript, oldest first: a first line the tail cuts is left
 * out, and so is a last one still being written.
 */
function tailLines(file) {
  const tail = readTail(file, TAIL_BYTES);
  if (!tail) return [];
  const lines = tail.text.split('\n');
  if (tail.truncated) lines.shift();
  const last = lines.pop();
  if (last.trim() && parses(last)) lines.push(last);
  return lines.map(line => line.replace(/\r$/, '')).filter(line => line.trim());
}

/** A file's first line when it ends within the file's first 64 KiB, or when it is the whole file; else null. */
function firstLine(file) {
  let fd;
  try {
    fd = fs.openSync(file, 'r');
  } catch {
    return null;
  }
  try {
    const buffer = Buffer.alloc(HEAD_BYTES);
    const read = fs.readSync(fd, buffer, 0, HEAD_BYTES, 0);
    const newline = buffer.subarray(0, read).indexOf(0x0a);
    if (newline !== -1) return buffer.toString('utf8', 0, newline).replace(/\r$/, '');
    const whole = buffer.toString('utf8', 0, read);
    return read < HEAD_BYTES && parses(whole) ? whole : null;
  } finally {
    fs.closeSync(fd);
  }
}

/** When an agent started: its transcript's first record's time, else the file's creation time; null when neither. */
function agentStart(file, stat) {
  const line = firstLine(file);
  const time = line === null ? null : lineTime(line);
  if (time !== null) return time;
  // A file system that keeps no creation time gives 0.
  return stat.birthtimeMs > 0 ? stat.birthtimeMs : null;
}

/** The time of the latest of these lines that has one, or null. */
function lastLineTime(lines) {
  for (let i = lines.length - 1; i >= 0; i--) {
    const time = lineTime(lines[i]);
    if (time !== null) return time;
  }
  return null;
}

/** Whether an agent's turn ended: its last complete record is an assistant's end_turn that asks for no tool. */
function turnEnded(lines) {
  for (let i = lines.length - 1; i >= 0; i--) {
    let record;
    try {
      record = JSON.parse(lines[i]);
    } catch {
      continue;
    }
    if (!record || typeof record !== 'object') continue;
    const message = record.message || {};
    const content = Array.isArray(message.content) ? message.content : [];
    return (
      record.type === 'assistant' &&
      message.stop_reason === 'end_turn' &&
      !content.some(item => item && item.type === 'tool_use')
    );
  }
  return false;
}

function readMeta(file) {
  try {
    const info = JSON.parse(fs.readFileSync(file, 'utf8').replace(/^﻿/, ''));
    return info && typeof info === 'object' ? info : {};
  } catch {
    return {};
  }
}

/** The ids, lower-cased, of the agents a workflow's journal records a result for. */
function readJournal(file) {
  const resulted = new Set();
  let text;
  try {
    text = fs.readFileSync(file, 'utf8');
  } catch {
    return resulted;
  }
  for (const line of text.split('\n')) {
    if (!line.trim()) continue;
    let record;
    try {
      record = JSON.parse(line);
    } catch {
      continue;
    }
    if (record && record.type === 'result' && typeof record.agentId === 'string') {
      resulted.add(record.agentId.toLowerCase());
    }
  }
  return resulted;
}

/**
 * The labels a workflow gave its agents, per agent id lower-cased, from the run state the session keeps in
 * workflows/wf_<id>.json. The journal's keys are cache keys, a hash, so they label nothing.
 */
function readRunLabels(file) {
  const labels = new Map();
  let state;
  try {
    state = JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch {
    return labels;
  }
  const progress = state && Array.isArray(state.workflowProgress) ? state.workflowProgress : [];
  for (const entry of progress) {
    if (entry && typeof entry.agentId === 'string' && typeof entry.label === 'string' && entry.label) {
      labels.set(entry.agentId.toLowerCase(), entry.label);
    }
  }
  return labels;
}

/**
 * The folders a session keeps agents in: subagents/ itself, and each workflow's subagents/workflows/wf_<id>/ with
 * the workflow's name, the agents its journal has a result for, and the labels its run state gives them.
 */
function agentFolders(agentsFolder) {
  const folders = [{ folder: agentsFolder, workflow: null, resulted: new Set(), labels: new Map() }];
  const workflows = path.join(agentsFolder, 'workflows');
  if (!isFolder(workflows)) return folders;
  const runStates = path.join(path.dirname(agentsFolder), 'workflows');
  for (const entry of fs.readdirSync(workflows, { withFileTypes: true })) {
    if (!entry.isDirectory() || !entry.name.startsWith('wf_')) continue;
    const folder = path.join(workflows, entry.name);
    folders.push({
      folder,
      workflow: entry.name,
      resulted: readJournal(path.join(folder, 'journal.jsonl')),
      labels: readRunLabels(path.join(runStates, `${entry.name}.json`))
    });
  }
  return folders;
}

function asText(value) {
  return value === undefined || value === null ? '' : String(value);
}

function isLive(state) {
  return state === 'running' || state === 'quiet';
}

/**
 * One row per agent of the session that wrote within `hours`, in the order they started: its times in ms, and its
 * duration and idle time as ms spans. `stats`, when given, gets where the session transcript was read from and how
 * many bytes of it were read, 0 and 0 when its agents' own files decided them all.
 */
function agentTimes(session, { agents = [], hours = 24, quietMinutes = 15, now = Date.now(), stats = {} } = {}) {
  Object.assign(stats, { transcriptStart: 0, transcriptBytes: 0 });
  const agentsFolder = path.join(session.folder, 'subagents');
  if (!isFolder(agentsFolder)) return [];

  const prefixes = agents
    .flatMap(value => value.split(','))
    .map(value => value.trim().toLowerCase())
    .filter(Boolean);
  const found = new Map();
  for (const { folder, workflow, resulted, labels } of agentFolders(agentsFolder)) {
    for (const entry of fs.readdirSync(folder, { withFileTypes: true })) {
      const match = /^agent-(.*)\.meta\.json$/i.exec(entry.name);
      if (!match || !entry.isFile()) continue;
      const id = match[1];
      const logPath = path.join(folder, `agent-${id}.jsonl`);
      const log = statOrNull(logPath);
      if (!log || !log.isFile()) continue;
      // No record is later than its file's time, so the file time rules an agent out cheaply; its last record then
      // rules out one whose file was touched since.
      const since = now - hours * HOUR_MS;
      if (log.mtimeMs < since) continue;
      const lines = tailLines(logPath);
      const last = lastLineTime(lines) ?? log.mtimeMs;
      if (last < since) continue;

      const info = readMeta(path.join(folder, entry.name));
      const prefix = statOrNull(path.join(folder, `agent-${id}.prefix.json`));
      const stoppedAt = prefix && prefix.isFile() ? prefix.mtimeMs : null;
      found.set(id.toLowerCase(), {
        id,
        // A workflow's agent has no description in its meta; the label its workflow gave it says what it is.
        description: info.description ? String(info.description) : labels.get(id.toLowerCase()) || id,
        type: asText(info.agentType),
        parent: asText(info.parentAgentId),
        workflow,
        started: agentStart(logPath, log),
        last,
        resulted: resulted.has(id.toLowerCase()),
        stopped: stoppedAt !== null && stoppedAt >= last - PREFIX_GRACE_MS,
        turnEnded: turnEnded(lines),
        // A foreground agent's report comes back to the session as the tool result of the tool use that started it.
        reportsTo: info.requestShape === 'foreground' && info.toolUseId ? String(info.toolUseId) : null
      });
    }
  }

  const wanted = [...found.values()].filter(
    agent => prefixes.length === 0 || prefixes.some(prefix => agent.id.toLowerCase().startsWith(prefix))
  );
  // The session transcript is read only for the agents their own files leave undecided, which in a live session are
  // the ones still at work, and only from shortly before the earliest of those last wrote.
  const undecided = wanted.filter(agent => !agent.resulted && !agent.stopped && !agent.turnEnded);
  let notices = new Map();
  let reports = new Map();
  if (undecided.length > 0) {
    const since = Math.min(...undecided.map(agent => agent.last)) - NOTICE_LOOKBACK_MS;
    const read = readSession(session.transcript, since, undecided.map(agent => agent.reportsTo).filter(Boolean));
    ({ notices, reports } = read);
    Object.assign(stats, { transcriptStart: read.start, transcriptBytes: read.bytesRead });
  }

  return wanted
    .sort((a, b) => (a.started ?? Infinity) - (b.started ?? Infinity) || 0)
    .map(agent => {
      const idle = now - agent.last;
      const notice = notices.get(agent.id.toLowerCase());
      // Held to a result from 5 s before the last write on, so that the acknowledgement of a launch, reworded, can't
      // pass for a report.
      const reported = agent.reportsTo ? reports.get(agent.reportsTo) : null;
      let state;
      let decidedBy = null;
      if (agent.resulted) [state, decidedBy] = ['finished', 'journal'];
      else if (agent.stopped) [state, decidedBy] = ['finished', 'prefix'];
      else if (agent.turnEnded) [state, decidedBy] = ['finished', 'turn'];
      else if (notice && notice.at >= agent.last - NOTICE_GRACE_MS) {
        [state, decidedBy] = [notice.status === 'completed' ? 'finished' : notice.status, 'notice'];
      } else if (reported && reported.at >= agent.last - REPORT_GRACE_MS) {
        [state, decidedBy] = [reported.interrupted ? 'interrupted' : 'finished', 'report'];
      } else if (idle >= quietMinutes * MINUTE_MS) state = 'quiet';
      else state = 'running';

      const parent = agent.parent ? found.get(agent.parent.toLowerCase()) : null;
      let startedBy = 'the session';
      if (agent.workflow) startedBy = `workflow ${agent.workflow}`;
      else if (agent.parent) startedBy = parent ? parent.description : agent.parent;
      return {
        id: agent.id,
        agent: agent.description,
        type: agent.type,
        startedBy,
        started: agent.started,
        state,
        decidedBy,
        duration: agent.started === null ? null : (isLive(state) ? now : agent.last) - agent.started,
        lastWrite: agent.last,
        idle
      };
    });
}

const WHOLE = new Intl.NumberFormat(undefined, { maximumFractionDigits: 0 });

function pad(value) {
  return String(value).padStart(2, '0');
}

function hourMinute(ms) {
  const time = new Date(ms);
  return `${pad(time.getHours())}:${pad(time.getMinutes())}`;
}

/** A local time as HH:mm on `now`'s day, else as MM-dd HH:mm; an unknown one as unknown. */
function clock(ms, now) {
  if (ms === null) return 'unknown';
  const time = new Date(ms);
  const today = new Date(now);
  const sameDay =
    time.getFullYear() === today.getFullYear() &&
    time.getMonth() === today.getMonth() &&
    time.getDate() === today.getDate();
  return sameDay ? hourMinute(ms) : `${pad(time.getMonth() + 1)}-${pad(time.getDate())} ${hourMinute(ms)}`;
}

/** A span as its whole hours and the minutes past them, Nh MMm; a negative one's minutes carry the sign too. */
function span(ms) {
  if (ms === null) return 'unknown';
  const minutes = Math.trunc(ms / MINUTE_MS) % 60;
  return `${Math.floor(ms / HOUR_MS)}h ${minutes < 0 ? '-' : ''}${pad(Math.abs(minutes))}m`;
}

/** An idle span as whole minutes, rounded and grouped as the locale writes numbers. */
function minutesAgo(ms) {
  return `${WHOLE.format(ms / MINUTE_MS)} min ago`;
}

const COLUMNS = [
  ['Agent', row => row.agent],
  ['Type', row => row.type],
  ['Started by', row => row.startedBy],
  ['Started', (row, now) => clock(row.started, now)],
  ['State', row => row.state],
  ['For', row => span(row.duration)],
  ['Last write', (row, now) => (isLive(row.state) ? minutesAgo(row.idle) : clock(row.lastWrite, now))],
  ['From', row => row.decidedBy || ''],
  ['Id', row => row.id]
];

/** The rows as a table, each column as wide as its widest cell, times local. */
function formatTable(rows, now) {
  const cells = rows.map(row => COLUMNS.map(([, cell]) => cell(row, now)));
  const widths = COLUMNS.map(([label], i) => Math.max(label.length, ...cells.map(values => values[i].length)));
  const line = values => values.map((value, i) => value.padEnd(widths[i])).join(' ').trimEnd();
  const labels = COLUMNS.map(([label]) => label);
  return [line(labels), line(labels.map(label => '-'.repeat(label.length))), ...cells.map(line)].join('\n') + '\n';
}

const CHOSEN = {
  'session-folder': 'by --session-folder',
  session: 'by --session',
  CLAUDE_CODE_SESSION_ID: 'by $CLAUDE_CODE_SESSION_ID',
  newest: "as its project's newest"
};

/** The run's output as the table: a header naming the session and what chose it, then its agents or that none wrote. */
function report(session, rows, hours, now) {
  const header = `Session ${session.id}, as of ${hourMinute(now)} local, chosen ${CHOSEN[session.chosenBy]}.`;
  if (rows.length === 0) return `${header}\nNo agent wrote within ${hours} hours.\n`;
  return `${header}\n\n${formatTable(rows, now)}`;
}

/** The run's output as JSON: times in ISO 8601, durations in whole seconds, null where unknown. */
function toJson(session, rows, now) {
  const iso = ms => (ms === null ? null : new Date(ms).toISOString());
  const seconds = ms => (ms === null ? null : Math.round(ms / 1000));
  return {
    session: { id: session.id, folder: session.folder, transcript: session.transcript, chosenBy: session.chosenBy },
    asOf: iso(now),
    agents: rows.map(row => ({
      id: row.id,
      agent: row.agent,
      type: row.type,
      startedBy: row.startedBy,
      started: iso(row.started),
      state: row.state,
      decidedBy: row.decidedBy,
      duration: seconds(row.duration),
      lastWrite: iso(row.lastWrite),
      idle: seconds(row.idle)
    }))
  };
}

function main(args, env = process.env, cwd = process.cwd()) {
  try {
    const options = parseArgs(args);
    if (options.help) {
      process.stdout.write(USAGE);
      return 0;
    }
    const session = resolveSession({
      sessionFolder: options.sessionFolder,
      session: options.session,
      projectDir: options.projectDir,
      projectFolder: options.projectFolder,
      claudeHome: options.claudeHome || claudeHomeFrom(env),
      cwd,
      sessionId: env.CLAUDE_CODE_SESSION_ID
    });
    const now = Date.now();
    const { agents, hours, quietMinutes } = options;
    const rows = agentTimes(session, { agents, hours, quietMinutes, now });
    const json = () => `${JSON.stringify(toJson(session, rows, now), null, 2)}\n`;
    process.stdout.write(options.json ? json() : report(session, rows, hours, now));
    return 0;
  } catch (err) {
    if (!(err instanceof AgentTimesError)) throw err;
    process.stderr.write(`agent-times: ${err.message}\n`);
    if (err.usage) process.stderr.write('Run it with --help for its options.\n');
    return 2;
  }
}

if (require.main === module) {
  process.exitCode = main(process.argv.slice(2));
}

module.exports = {
  AgentTimesError,
  agentStart,
  agentTimes,
  clock,
  formatTable,
  lineTime,
  main,
  parseArgs,
  readLineTimeAt,
  readSession,
  report,
  resolveSession,
  span,
  toJson,
  turnEnded
};
