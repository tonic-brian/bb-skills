import { atom, read, update } from 'claude-code'
import type { ContextCategory, EngineInterface, ModelForkResult, PluginOptions, Register } from 'claude-code'

import type { CrunchBand } from '../types'

// crunch shows the skill's nudges where the developer looks. Its settings hooks keep records in
// their state folder, one file per session and record: suggest-compact.js counts the calls it nudged Claude on, and
// on-compact.js the compactions that stood, one count per trigger. This mod reads them on events that reach a
// person's plugins under any account, and shows the developer the context's size from `$.session.usage()`, with the
// hint to compact. At the end of a main turn that nudged, it asks a fork of the session for the focus of a `/compact`,
// which the band's field holds and its button, Enter or the automatic mode compacts on, by running `/compact` as the
// developer would type it.

const LABEL = '/compact '
const PROGRESS = 'PROGRESS.md'
const FALLBACK = 'state in PROGRESS.md'
const SUFFIX = '; state in PROGRESS.md'
const MAX_WORDS = 40
const MILLION = 1_000_000
const FOLDER = 'crunch'
const REJECTED = 'Not compacted: the turn was stopped before it ran. Compact again.'

const PROMPT_HEAD = 'crunch is about to offer a /compact. Answer in one line and nothing else. If you are in ' +
  'the middle of implementing something, with names, paths or half-made edits a summary would lose, answer WAIT: and ' +
  'what you are in the middle of.'
const PROMPT_ON_PROGRESS = 'If PROGRESS.md doesn\'t yet record where the work stands, answer WAIT: and what it\'s missing.'
const PROMPT_LAST = 'Otherwise answer the focus for /compact: what the next phase is and what it needs kept, in at most 25 words.'

/** Each switch the manifest declares, at the default it declares there. */
const DEFAULTS = {
  showStatusLine: true,
  showToast: true,
  showLog: true,
  showBand: false,
  showNotification: false,
  autoCompact: false,
  addNote: true
}

type Switch = keyof typeof DEFAULTS
type Switches = Record<Switch, boolean>

/** The records the hooks keep: the count of nudged calls, and of the compactions that stood, by trigger. */
const RECORDS = ['nudged', 'manual', 'auto', 'plugin'] as const
type RecordName = (typeof RECORDS)[number]
type Counts = Record<RecordName, number>

/** What a read found risen since the read before it. */
type Rises = Record<RecordName, boolean>
const NONE: Rises = { nudged: false, manual: false, auto: false, plugin: false }

/** Where a read happens: the mod's own `/compact` and the one its hook awaits own the `manual` rise they ran. */
type At = 'turn' | 'call' | 'own' | 'command'

/** Where the session stands, as the mod has seen it since it loaded; a switch of session id starts it again. */
type Session = {
  /** The status line's hint is on. */
  isHinting: boolean
  /** A nudge came with no size to show yet. */
  isWaiting: boolean
  /** The main turn under way saw a nudge. */
  isNudged: boolean
  /** The automatic mode's compaction failed once: the fork is asked once more at the next main turn's end. */
  isRetrying: boolean
  /** On a window under 1M, after a WAIT or no reply, the fork is asked at each main turn's end. */
  isAsking: boolean
  /** The reason of the last WAIT the automatic mode held back on. */
  lastWait: string | undefined
  /** Compactions that stood, and switches of session: a reply to a fork asked before the latest is dropped. */
  generation: number
  /** Compactions seen inside a turn, whose notes wait for its end. */
  heldNotes: number
}

/** What the mod keeps whatever the session: the reads, and the `/compact` runs under way. */
type Mod = {
  /** The session the counts were last read for, and where they stood. */
  key: string | undefined
  last: Counts | undefined
  /** The reads, one at a time, so none takes a count from before another. */
  reading: Promise<unknown>
  /** The hooks' state folder, found once. */
  dir: Promise<string | undefined> | undefined
  /** A main turn is under way. */
  isTurnRunning: boolean
  /** The mod's own `/compact` runs under way, claimed before anything else so two can't start. */
  ownCalls: number
  /** `/compact` runs the mod didn't start, under way: the developer's or another plugin's. */
  compactions: number
  /** Runs whose rise in `manual` is left to the call awaiting them, until that call has read it. */
  awaiting: number
}

/** How the mod comes to compact: by the developer's hand or by itself, and whether that is its second try. */
type Attempt = { isAuto: boolean; isRetry: boolean }

const band = atom({ plugin: 'crunch', key: 'band' } as const, null as CrunchBand)
const compacting = atom({ plugin: 'crunch', key: 'compacting' } as const, false)

type Band = NonNullable<CrunchBand>

function freshSession(generation: number): Session {
  return {
    isHinting: false, isWaiting: false, isNudged: false, isRetrying: false, isAsking: false, lastWait: undefined,
    generation, heldNotes: 0
  }
}

/** The band as the state keeps it, plain data: a part with nothing to show is left out. */
function bandOf(fields: Band): Band {
  return Object.fromEntries(Object.entries(fields).filter(([, value]) => value !== undefined)) as Band
}

/** A switch as stored: true or false, or the text of either; anything else, "" included, is its default. */
function isOn(options: PluginOptions, name: Switch): boolean {
  const value = options[name]
  if (value === true || value === 'true') return true
  if (value === false || value === 'false') return false
  return DEFAULTS[name]
}

/** The hint to compact, naming the skill by the folder it is installed in, each command in backticks. */
function codeHintOf($: EngineInterface): string {
  const skill = $.plugin.root.split(/[\\/]/).filter(Boolean).pop() ?? FOLDER
  return ` - consider \`/${skill}\` | \`/compact\``
}

/** The window as the hook labels it: 1M, or thousands. */
function windowLabel(window: number): string {
  return window >= MILLION ? '1M' : `${Math.round(window / 1000)}k`
}

function messageOf(err: unknown): string {
  return err instanceof Error ? err.message : String(err)
}

/** Awaits display work so that a failure reaches the debug log, never the call or the turn it rides on. */
async function quietly($: EngineInterface, work: Promise<unknown>): Promise<void> {
  try {
    await work
  } catch (err) {
    $.ui.log(`a display failed: ${messageOf(err)}`, { to: 'debug' })
  }
}

/** Joins names onto a path with the separator the path itself uses. */
function joinOf(base: string, ...names: string[]): string {
  const separator = base.includes('\\') && !base.includes('/') ? '\\' : '/'
  return [base.replace(/[\\/]+$/, ''), ...names].join(separator)
}

/**
 * The folder the hooks keep their state in, decided as their state.js decides it: on Windows `LOCALAPPDATA`, else
 * `USERPROFILE`'s `AppData\Local`; elsewhere `XDG_STATE_HOME` when absolute, else `HOME`'s `.local/state`.
 */
async function stateDirOf($: EngineInterface): Promise<string | undefined> {
  if ((await $.env.get('OS')) === 'Windows_NT') {
    const local = await $.env.get('LOCALAPPDATA')
    if (local) return joinOf(local, FOLDER)
    const profile = await $.env.get('USERPROFILE')
    return profile ? joinOf(profile, 'AppData', 'Local', FOLDER) : undefined
  }
  const xdg = await $.env.get('XDG_STATE_HOME')
  if (xdg !== undefined && xdg.startsWith('/')) return joinOf(xdg, FOLDER)
  const home = await $.env.get('HOME')
  return home ? joinOf(home, '.local', 'state', FOLDER) : undefined
}

/** A number a record holds: a missing record reads 0, and one there but unreadable throws. */
async function readCount($: EngineInterface, file: string): Promise<number> {
  let text: string
  try {
    text = String(await $.fs.read(file)).trim()
  } catch (err) {
    if (!(await $.fs.exists(file))) return 0
    throw err
  }
  return /^\d+$/.test(text) ? Number(text) : 0
}

/** The session's id, cut as state.js's sessionKey cuts it to name its files. */
async function keyOf($: EngineInterface): Promise<string> {
  return (await $.session.id()).replace(/[^a-zA-Z0-9_-]/g, '')
}

/** The session's records; undefined where no folder is named. */
async function readCounts($: EngineInterface, m: Mod, key: string): Promise<Counts | undefined> {
  m.dir ??= stateDirOf($)
  const dir = await m.dir
  if (dir === undefined) return undefined
  const counts = { nudged: 0, manual: 0, auto: 0, plugin: 0 }
  for (const name of RECORDS) counts[name] = await readCount($, joinOf(dir, `${key}.${name}`))
  return counts
}

/** Runs reads one at a time. */
function oneAtATime<T>(m: Mod, work: () => Promise<T>): Promise<T> {
  const run = m.reading.then(work)
  m.reading = run.catch(() => undefined)
  return run
}


/** What the hooks module keeps between events: the switches, the reads and runs, and the session as seen. */
type Ctx = { show: Switches; m: Mod; s: Session }

/** A switch of session: what the mod kept for the old one goes, a draft on its way and the band with it. */
async function startAgain($: EngineInterface, c: Ctx): Promise<void> {
  Object.assign(c.s, freshSession(c.s.generation + 1))
  if (c.show.showBand) await update($, band, () => null)
}

/**
 * Reads the records and says which rose since the last read. Under a session id it last read for, a count above the
 * last is a rise and one below it starts again from there, as after the sweep. Under any other, the session starts
 * again: where the counts stand is its start, so a load or a switch shows nothing old. While a `/compact` is awaited,
 * a read that isn't its own leaves `manual` to it. A read that fails changes nothing. With `isStartOnly`, it reads
 * only to start a session not read yet.
 */
function readRises($: EngineInterface, c: Ctx, at: At, isStartOnly = false): Promise<Rises> {
  const { m } = c
  return oneAtATime(m, async () => {
    let key: string
    let counts: Counts | undefined
    try {
      key = await keyOf($)
      if (key === '' || (isStartOnly && key === m.key && m.last !== undefined)) return NONE
      counts = await readCounts($, m, key)
    } catch (err) {
      $.ui.log(`the records couldn't be read: ${messageOf(err)}`, { to: 'debug' })
      return NONE
    }
    if (counts === undefined) return NONE
    if (key !== m.key || m.last === undefined) {
      const isSwitch = m.key !== undefined
      m.key = key
      m.last = counts
      if (isSwitch) await startAgain($, c)
      return NONE
    }
    const last = m.last
    const isOwner = at === 'own' || at === 'command'
    const kept = !isOwner && m.awaiting > 0 ? { ...counts, manual: last.manual } : counts
    m.last = kept
    return {
      nudged: kept.nudged > last.nudged, manual: kept.manual > last.manual, auto: kept.auto > last.auto,
      plugin: kept.plugin > last.plugin
    }
  })
}

/** The project's PROGRESS.md where the session's root holds one, joined with the root's own separator. */
async function progressPath($: EngineInterface): Promise<string | undefined> {
  const path = joinOf(await $.session.root(), PROGRESS)
  return (await $.fs.exists(path)) ? path : undefined
}

/** The fork's prompt: with the sentence on PROGRESS.md, before the last, where the root holds the file. */
function promptFor(hasProgress: boolean): string {
  return [PROMPT_HEAD, ...(hasProgress ? [PROMPT_ON_PROGRESS] : []), PROMPT_LAST].join(' ')
}

/** A reply on one line: each line break, with the spaces around it, one space. */
function oneLine(text: string): string {
  return text.trim().split(/\s*\r?\n\s*/).join(' ')
}

/** The rest of a reply's line where, stripped of spaces, emphasis and quote marks, it begins WAIT in any case. */
function waitReasonOf(text: string): string | undefined {
  const line = (text.trim().split(/\r?\n/)[0] ?? '').replace(/^[\s*_`"'“”‘’>]+|[\s*_`"'“”‘’]+$/g, '')
  if (!/^wait/i.test(line)) return undefined
  return line.slice(4).replace(/^[\s*_`"'“”‘’:;,.—–-]+/, '')
}

/** Whether the automatic mode takes a reply as the one line asked for: no line break, and at most 40 words. */
function isOneLine(text: string): boolean {
  const trimmed = text.trim()
  return !/\n/.test(trimmed) && trimmed.split(/\s+/).length <= MAX_WORDS
}

/** The three largest `used` rows of the breakdown, as `Messages 180k · Tool results 62k · System tools 21k`. */
function breakdownOf(categories: readonly ContextCategory[]): string | undefined {
  const rows = categories.filter(row => row.kind === 'used').sort((a, b) => b.tokens - a.tokens).slice(0, 3)
  if (rows.length === 0) return undefined
  return rows.map(row => `${row.name} ${Math.round(row.tokens / 1000)}k`).join(' · ')
}

/** The window of the session's model, or 1M where it can't be read. */
async function windowOf($: EngineInterface): Promise<number> {
  try {
    return (await $.session.usage()).context.window
  } catch {
    return MILLION
  }
}

/** Whether an app, not a terminal, draws the session. */
async function isInApp($: EngineInterface): Promise<boolean> {
  return (await $.session.surfaces()).some(surface => surface !== 'terminal')
}

/** Shows one nudge on each display switched on: the toast and the log line only where an app draws the session. */
async function display($: EngineInterface, show: Switches, text: string): Promise<void> {
  const isApp = await isInApp($)
  if (isApp && show.showToast) $.ui.toast(text)
  if (isApp && show.showLog) $.ui.log(text)
  // Not awaited: the person's Notification hooks run first, and the tool call does not wait on them.
  if (show.showNotification) {
    $.ui.notify(text).catch(err => $.ui.log(`the notification failed: ${String(err)}`, { to: 'debug' }))
  }
  if (!show.showBand) return
  const fallback = (await progressPath($)) === undefined ? '' : FALLBACK
  await update($, band, shown => bandOf({ ...(shown ?? {}), line: text, fallback, message: undefined }))
  // The breakdown is read once the tool call has gone on, so the call never waits on it.
  $.clock.after(0, () => {
    void quietly($, showBreakdown($))
  })
}

/** Puts the context's largest rows on the band. */
async function showBreakdown($: EngineInterface): Promise<void> {
  const { context } = await $.session.usage({ breakdown: 'summary' })
  const breakdown = breakdownOf(context.breakdown?.categories ?? [])
  if (breakdown !== undefined) await update($, band, shown => (shown === null ? shown : { ...shown, breakdown }))
}

/** Reads the context's size into the status line, and shows a waiting nudge once there is a size to show. */
async function refresh($: EngineInterface, c: Ctx): Promise<void> {
  const { show, s } = c
  const { context } = await $.session.usage()
  if (context.tokens === undefined) {
    if (show.showStatusLine) $.ui.status(undefined)
    return
  }
  const percent = context.percent ?? Math.round((context.tokens / context.window) * 100)
  if (show.showStatusLine) $.ui.status(`Context @ ${percent}%${s.isHinting ? ' · /compact' : ''}`)
  if (!s.isWaiting) return
  s.isWaiting = false
  const tokens = `${Math.round(context.tokens / 1000)}k`
  const label = windowLabel(context.window)
  await display($, show, `Context ~${tokens} tokens @ ${percent}%${codeHintOf($)} (${label} window)`)
}

/** Tells Claude, in a row it reads and the developer doesn't see, to read the project's PROGRESS.md first. */
async function addNote($: EngineInterface): Promise<void> {
  const path = await progressPath($)
  if (path === undefined) return
  const text = `This conversation was just compacted. Before carrying on, read \`${path}\` for where the work stands.`
  await $.session.append({ message: { type: 'user', content: [{ type: 'text', text }] } })
}

/** Adds the note: once the turn under way ends, so it never lands between a tool call and its result. */
function noteLater($: EngineInterface, c: Ctx): void {
  if (!c.show.addNote) return
  if (c.m.isTurnRunning) {
    c.s.heldNotes += 1
    return
  }
  $.clock.after(0, () => void quietly($, addNote($)))
}

/** Shows one line on every surface by the log switch, and as a toast where an app draws the session. */
async function announce($: EngineInterface, show: Switches, text: string): Promise<void> {
  if ((await isInApp($)) && show.showToast) $.ui.toast(text)
  if (show.showLog) $.ui.log(text)
}

/** Claims the mod's own `/compact` before anything else, so two can't start: none while another runs. */
function claim(m: Mod): boolean {
  if (m.ownCalls > 0 || m.compactions > 0) return false
  m.ownCalls += 1
  return true
}

/**
 * Acts on what a read found risen: first a nudge, which came before any compaction found with it, turning the hint
 * on and marking the turn nudged; then a compaction that stood, dropping what was judged before it and adding the
 * note. `manual`, the developer's /compact or the mod's own, takes the hint off and the band down, unless another
 * plugin ran it; `auto`, Claude Code's own, turns the hint on; `plugin` leaves both. Seen as a /compact resolves, the
 * size still reads from before it, so the status line waits for the next response; seen later, it is read afresh.
 */
async function act($: EngineInterface, c: Ctx, found: Rises, at: At, isOther = false): Promise<void> {
  const { show, s } = c
  if (found.nudged) {
    s.isHinting = true
    s.isWaiting = true
    s.isNudged = true
  }
  if (!found.manual && !found.auto && !found.plugin) return
  s.generation += 1
  s.isNudged = false
  s.isRetrying = false
  s.isAsking = false
  const isYours = found.manual && !isOther
  if (found.auto) s.isHinting = true
  if (isYours) {
    s.isHinting = false
    s.isWaiting = false
    if (show.showBand) await quietly($, update($, band, () => null))
  }
  if ((at === 'own' || at === 'command') && show.showStatusLine) $.ui.status(undefined)
  noteLater($, c)
}

/** Reads the records and acts on what rose. */
async function observe($: EngineInterface, c: Ctx, at: At, isOther = false): Promise<Rises> {
  const found = await readRises($, c, at)
  await act($, c, found, at, isOther)
  return found
}

/** A refusal or a rejection: the band comes back saying so, and the automatic mode tries once more. */
async function failed($: EngineInterface, c: Ctx, message: string, attempt: Attempt, held: Band | null): Promise<void> {
  const { show, s } = c
  if (show.showBand) {
    await update($, band, shown => {
      const base = shown ?? held
      return base === null ? base : bandOf({ ...base, message })
    })
  }
  if (!attempt.isAuto) return
  if (!attempt.isRetry) {
    s.isRetrying = true
    return
  }
  s.isAsking = (await windowOf($)) < MILLION
}

/**
 * Runs `/compact` on the focus, as the developer would type it, the run claimed by the caller. A run that stood shows
 * as its record rising. One that didn't is refused where the command says why, and rejected where it never ran; one
 * with no rise and no word either way shows nothing, and is read again at the next turn's start. A refusal or a
 * rejection brings the band back, as `held`, saying so.
 */
async function compactOwn($: EngineInterface, c: Ctx, focus: string, attempt: Attempt, held: Band | null = null): Promise<void> {
  const { m } = c
  let failure: string | undefined
  m.awaiting += 1
  try {
    // A session not read yet starts where its counts stand, so the run's own rise is the one seen after it.
    await readRises($, c, 'own', true)
    if (attempt.isAuto) await quietly($, announce($, c.show, `auto-compact: ${focus}`))
    let output: string
    try {
      output = ((await $.command.run({ command: 'compact', args: focus })).text ?? '').trim()
    } catch (err) {
      $.ui.log(`/compact was rejected: ${messageOf(err)}`, { to: 'debug' })
      failure = REJECTED
      return
    }
    const found = await observe($, c, 'own')
    if (found.manual) return
    if (output !== '') failure = `Not compacted: ${output}`
    else $.ui.log('/compact left no record and no output: read again at the next turn\'s start', { to: 'debug' })
  } finally {
    m.awaiting -= 1
    m.ownCalls -= 1
    if (failure !== undefined) await quietly($, failed($, c, failure, attempt, held))
  }
}

/** Compact now or Enter: the band goes down at once, and `/compact` runs on the focus, queued while a turn runs. */
async function compactByHand($: EngineInterface, c: Ctx, focus?: string): Promise<void> {
  if (!claim(c.m)) return
  let held: Band | null
  try {
    held = await read($, band)
    if (held !== null) await update($, band, () => null)
  } catch (err) {
    c.m.ownCalls -= 1
    throw err
  }
  if (held === null) {
    c.m.ownCalls -= 1
    return
  }
  const text = focus ?? held.typed ?? held.draft ?? held.fallback
  await compactOwn($, c, text, { isAuto: false, isRetry: false }, held)
}

/**
 * Asks a fork of the session for the focus of a `/compact`, at the end of a main turn, and acts on its reply: the
 * band's field holds a draft and shows a WAIT, and the automatic mode compacts on a draft of one line.
 */
async function askFork($: EngineInterface, c: Ctx, isNudged: boolean): Promise<void> {
  const { show, m, s } = c
  const generation = s.generation
  const isRetry = s.isRetrying
  s.isRetrying = false
  const path = await progressPath($)
  const started = await $.clock.now()
  let reply: ModelForkResult | undefined
  try {
    reply = await $.model.fork({ prompt: promptFor(path !== undefined) })
  } catch (err) {
    $.ui.log(`the fork failed: ${messageOf(err)}`, { to: 'debug' })
  }
  const ms = (await $.clock.now()) - started
  const usage = reply !== undefined && 'usage' in reply ? ` ${JSON.stringify(reply.usage)}` : ''
  $.ui.log(`fork: ${reply === undefined ? 'threw' : reply.isAnswered ? 'answered' : reply.reason} in ${ms} ms${usage}`,
    { to: 'debug' })
  // A compaction that stood, or a switch of session, leaves the fork's judgment behind.
  if (generation !== s.generation) return
  const text = reply?.isAnswered ? reply.text.trim() : ''
  const wait = text === '' ? undefined : waitReasonOf(text)
  const draft = text === '' || wait !== undefined
    ? undefined
    : `${oneLine(text)}${path !== undefined && !text.includes(PROGRESS) ? SUFFIX : ''}`
  if (show.showBand) {
    await update($, band, shown => (shown === null ? shown : bandOf({ ...shown, draft, wait, typed: shown.typed })))
  }
  if (!show.autoCompact) return
  if (draft !== undefined && isOneLine(text)) {
    // A turn that started meanwhile may change what the draft judged: wait for its end, as after a rejection.
    if (m.isTurnRunning) {
      s.isRetrying = true
      return
    }
    if (!claim(m)) return
    await compactOwn($, c, draft, { isAuto: true, isRetry })
    return
  }
  s.isAsking = (await windowOf($)) < MILLION
  if (wait === undefined) return
  if (!show.showBand && show.showLog && (isNudged || wait !== s.lastWait)) $.ui.log(`auto-compact waiting: ${wait}`)
  s.lastWait = wait
}

/** One line to the debug log: how each switch is set, and where the session draws. */
async function logStart($: EngineInterface, show: Switches): Promise<void> {
  const surfaces = await $.session.surfaces()
  const switches = (Object.keys(show) as Switch[]).map(name => `${name} ${show[name] ? 'on' : 'off'}`)
  $.ui.log(`${switches.join(', ')}; surfaces: ${surfaces.join(', ') || 'none'}`, { to: 'debug' })
}

/** At a main call's `tool.check`: the records read, and the status line with them. */
async function atCheck($: EngineInterface, c: Ctx): Promise<void> {
  await observe($, c, 'call')
  await refresh($, c)
}

/** After a main call: the records read again, and the status line only where something rose. */
async function afterCall($: EngineInterface, c: Ctx): Promise<void> {
  const found = await observe($, c, 'call')
  if (Object.values(found).some(Boolean)) await refresh($, c)
}

/** At a main turn's end: the records read, the status line, and the notes held for it. */
async function atTurnEnd($: EngineInterface, c: Ctx): Promise<void> {
  await observe($, c, 'turn')
  await refresh($, c)
  const held = c.s.heldNotes
  c.s.heldNotes = 0
  for (let i = 0; i < held; i++) $.clock.after(0, () => void quietly($, addNote($)))
}

/** A /compact the mod didn't run: `compacting…` while it runs, then its rise read as its own. */
async function aroundCommand($: EngineInterface, c: Ctx, isOther: boolean, run: () => Promise<unknown>): Promise<void> {
  const { m } = c
  m.compactions += 1
  m.awaiting += 1
  try {
    // A session not read yet starts where its counts stand, so the run's own rise is the one seen after it.
    await quietly($, readRises($, c, 'command', true))
    await quietly($, update($, compacting, () => true))
    await run()
    await quietly($, observe($, c, 'command', isOther))
  } finally {
    m.compactions -= 1
    m.awaiting -= 1
    await quietly($, update($, compacting, () => m.compactions > 0))
  }
}

export const register: Register = (on, options) => {
  const show = Object.fromEntries(
    (Object.keys(DEFAULTS) as Switch[]).map(name => [name, name !== 'autoCompact' && isOn(options, name)])
  ) as Switches
  const m: Mod = {
    key: undefined, last: undefined, reading: Promise.resolve(), dir: undefined, isTurnRunning: false, ownCalls: 0,
    compactions: 0, awaiting: 0
  }
  // The hint goes on at a nudge or at Claude Code's own compaction, and off at a /compact of the developer's.
  const c: Ctx = { show, m, s: freshSession(0) }

  // It fires again whenever the mod loads: where the counts stand is the start, so nothing old is shown again.
  on('session.start', async ($, e, next) => {
    const started = await next(e)
    await quietly($, readRises($, c, 'turn'))
    await quietly($, logStart($, show))
    return started
  })

  // A main call: its `tool.check` fires after the settings hooks have run and before the tool does, so a nudge shows
  // as its call starts. The verdict is passed on as it came.
  on('tool.check', async ($, e, next) => {
    const verdict = await next(e)
    if (e.tool_use_id !== undefined && e.agentId === undefined) await quietly($, atCheck($, c))
    return verdict
  })

  // And after the call, for one that `tool.check` didn't reach, and for Claude Code's own compaction inside a turn.
  on('tool.call', async ($, e, next) => {
    const result = await next(e)
    if (e.agentId === undefined) await quietly($, afterCall($, c))
    return result
  })

  // The first under a session id not read yet, as after /clear, starts the session again.
  on('turn.start', async ($, e, next) => {
    if (e.agentId === undefined) {
      m.isTurnRunning = true
      await quietly($, observe($, c, 'turn'))
    }
    return next(e)
  })

  on('turn.complete', async ($, e, next) => {
    const completed = await next(e)
    // A subagent's turn leaves the session's context where it was.
    const isMain = e.agentId === undefined
    if (isMain) {
      m.isTurnRunning = false
      await quietly($, atTurnEnd($, c))
    }
    const isNudged = isMain && c.s.isNudged
    if (isMain) c.s.isNudged = false
    // The session judges its moment between phases: at a turn it answered, not one interrupted or broken; and only
    // where the band or the automatic mode reads the reply.
    const isAsked = isMain && e.reason === 'answer' && (show.showBand || show.autoCompact) &&
      (isNudged || (show.autoCompact && (c.s.isRetrying || c.s.isAsking)))
    if (isAsked) {
      // Once the hook has returned, so the turn's end never waits on the fork.
      $.clock.after(0, () => {
        void quietly($, askFork($, c, isNudged))
      })
    }
    return completed
  })

  // A /compact the mod didn't run: the developer's, typed, or another plugin's. The mod's own is left to its call.
  on('command.run', { command: 'compact' }, async ($, e, next) => {
    const origin = e.origin as { kind: string; name?: string } | undefined
    if (origin?.kind === 'plugin' && origin.name === $.plugin.name) return next(e)
    let result: Awaited<ReturnType<typeof next>> | undefined
    await aroundCommand($, c, origin?.kind === 'plugin', async () => {
      result = await next(e)
    })
    return result as Awaited<ReturnType<typeof next>>
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const shown = show.showBand && !e.props.hasSurvey && e.surface !== 'mobile' ? await read($, band) : null
    if (shown === null) return next(e)
    const table = $.ui.resolve(e)
    if (!('Input' in table)) return next(e)
    const { Box, Button, Input, Markdown, Text } = table
    const isCompacting = await read($, compacting)
    const value = shown.typed ?? shown.draft ?? shown.fallback

    // The line's backticks draw each command as code; a terminal prints the hook's line already. A Text takes no key,
    // so each part a press or a test finds is a keyed Box.
    return (
      <Box flexDirection="column">
        {e.surface !== 'terminal' ? <Markdown key="line" text={shown.line} /> : null}
        {shown.breakdown !== undefined ? <Box key="breakdown"><Text dimColor>{shown.breakdown}</Text></Box> : null}
        {shown.wait !== undefined
          ? <Box key="wait"><Text>{`Claude is mid-implementation: ${shown.wait}`}</Text></Box>
          : null}
        <Box>
          <Input
            key="focus"
            label={LABEL}
            value={value}
            onInput={(typed: string) => {
              void update($, band, current => (current === null ? current : { ...current, typed }))
            }}
            onSubmit={(focus: string) => {
              if (!isCompacting) void compactByHand($, c, focus)
            }}
          />
          {isCompacting ? <Box key="compacting"><Text dimColor>compacting…</Text></Box> : null}
          {!isCompacting ? <Button key="compact" label="Compact now" onPress={() => compactByHand($, c)} /> : null}
          <Button key="dismiss" label="Dismiss" onPress={() => update($, band, () => null)} />
        </Box>
        {shown.message !== undefined ? <Box key="message"><Text>{shown.message}</Text></Box> : null}
        {await next(e)}
      </Box>
    )
  })
}
