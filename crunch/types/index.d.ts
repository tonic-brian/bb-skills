// crunch's values in `$.state`.

/**
 * The band above the prompt: the latest nudge and the focus offered for `/compact`; null before any nudge and once
 * taken down, by Dismiss, Compact now, Enter, or a `/compact` of the developer's that stood.
 */
export type CrunchBand = {
  /** The latest nudge, as the toast and the log line read it. */
  line: string
  /** The context's three largest `used` rows, once read. */
  breakdown?: string
  /** What the field holds until a draft comes: `state in PROGRESS.md` where the root holds the file, else empty. */
  fallback: string
  /** The fork's reply on one line, when it gave one that isn't a WAIT. */
  draft?: string
  /** The rest of a WAIT reply: what the session is in the middle of. */
  wait?: string
  /** What the developer typed in the field, kept until the band goes down. */
  typed?: string
  /** Why the band's last compaction didn't happen. */
  message?: string
} | null

/** Whether a `/compact` the mod didn't run is under way, the developer's or another plugin's. */
export type CrunchCompacting = boolean

declare module 'claude-code' {
  interface PluginState {
    crunch: { band: CrunchBand; compacting: CrunchCompacting }
  }
}
