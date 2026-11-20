'use strict';
/**
 * Whether the context-size check can read a transcript, and when it can't, which of the shapes it reads is missing.
 * The hook asks from the fifth edit or write of a session on, when it found no context size; check-transcript.js asks
 * on demand.
 *
 * What it looks for is observed, not documented: the transcript is JSONL, and assistant records carry message.usage
 * with input_tokens, cache_read_input_tokens and cache_creation_input_tokens.
 */

const fs = require('fs');
const { readFileTail } = require('./file-tail');
const { DEEP_TRANSCRIPT_TAIL_BYTES, compactBoundaryTokens, extractUsageTokens } = require('./transcript-context');

const TOKEN_FIELDS = ['input_tokens', 'cache_read_input_tokens', 'cache_creation_input_tokens'];

/**
 * { readable: true, tokens, model } when the transcript holds a context size the hook can read, tokens 0 when its
 * usage records all report none yet; otherwise { readable: false, finding }, naming what is missing.
 */
function probeTranscript(transcriptPath, { maxBytes = DEEP_TRANSCRIPT_TAIL_BYTES } = {}) {
  if (typeof transcriptPath !== 'string' || !transcriptPath) {
    return { readable: false, finding: "the hook's input names no transcript_path" };
  }
  let stat;
  try {
    stat = fs.statSync(transcriptPath);
  } catch {
    return { readable: false, finding: `there is no transcript at ${transcriptPath}` };
  }
  if (!stat.isFile()) return { readable: false, finding: `${transcriptPath} isn't a file` };
  const tail = readFileTail(transcriptPath, maxBytes);
  if (!tail) return { readable: false, finding: `the transcript at ${transcriptPath} can't be read` };

  const lines = tail.text.split('\n').slice(tail.truncated ? 1 : 0).map(line => line.trim()).filter(Boolean);
  if (lines.length === 0) return { readable: false, finding: 'the transcript is empty' };
  const reach = maxBytes >= 1024 * 1024 ? `${Math.round(maxBytes / (1024 * 1024))} MiB` : `${Math.round(maxBytes / 1024)} KiB`;
  const where = tail.truncated ? `the records in its last ${reach}` : 'its records';

  let parsed = 0;
  let withUsage = 0;
  let withFields = 0;
  for (let i = lines.length - 1; i >= 0; i--) {
    let record;
    try {
      record = JSON.parse(lines[i]);
    } catch {
      continue;
    }
    parsed++;
    const afterCompaction = compactBoundaryTokens(record);
    if (afterCompaction !== null) return { readable: true, tokens: afterCompaction, model: '' };
    const usage = record && record.message && record.message.usage;
    if (!usage || typeof usage !== 'object') continue;
    withUsage++;
    if (!TOKEN_FIELDS.some(field => Number.isFinite(usage[field]))) continue;
    withFields++;
    const tokens = extractUsageTokens(record);
    if (tokens > 0) {
      return { readable: true, tokens, model: typeof record.message.model === 'string' ? record.message.model : '' };
    }
  }

  if (parsed === 0) return { readable: false, finding: `none of ${where} is JSON` };
  if (withUsage === 0) return { readable: false, finding: `none of ${where} carries message.usage` };
  if (withFields === 0) {
    return { readable: false, finding: `its message.usage records have none of ${TOKEN_FIELDS.join(', ')}` };
  }
  return { readable: true, tokens: 0, model: '' };
}

module.exports = { TOKEN_FIELDS, probeTranscript };
