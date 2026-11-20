import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register, SessionRateLimit } from 'claude-code'

import type { MeterRow, Snapshot } from '../types'

const snapshot = atom({ plugin: 'context-meter', key: 'snapshot' } as const, null)
const limits = atom({ plugin: 'context-meter', key: 'rateLimits' } as const, [])
const now = atom({ plugin: 'context-meter', key: 'now' } as const, 0)

type Block = { type: string; [field: string]: unknown }

// Labels for the windows the engine names directly. Anything else has a window
// prefix plus a suffix (a model name, say), which labelFor folds in.
const WINDOWS: [prefix: string, label: string][] = [
  ['five_hour', '5-hour'],
  ['seven_day', 'Weekly'],
  ['spend_limit', 'Spend'],
]

const title = (word: string): string => (word ? word[0]!.toUpperCase() + word.slice(1).toLowerCase() : word)

function labelFor(kind: string): string {
  for (const [prefix, short] of WINDOWS) {
    if (kind === prefix) return short
    if (kind.startsWith(`${prefix}_`)) {
      const rest = kind
        .slice(prefix.length + 1)
        .split('_')
        .filter(Boolean)
        .map(title)
        .join(' ')
      return rest ? `${rest} ${short.toLowerCase()}` : short
    }
  }
  return (
    kind
      .split('_')
      .filter(Boolean)
      .map(title)
      .join(' ') || kind
  )
}

// A stable draw order: 5h, then weekly, then every other kind alphabetically.
function ordered(rates: SessionRateLimit[]): SessionRateLimit[] {
  const rank = (kind: string) => (kind === 'five_hour' ? 0 : kind === 'seven_day' ? 1 : 2)
  return [...rates].sort((a, b) => {
    const ra = rank(a.kind)
    const rb = rank(b.kind)
    if (ra !== rb) return ra - rb
    return ra === 2 ? a.kind.localeCompare(b.kind) : 0
  })
}

const glyphFor = (percent: number): string => (percent >= 95 ? '‼' : percent >= 80 ? '⚠' : '')
const colorFor = (percent: number): string => (percent < 50 ? 'success' : percent < 80 ? 'warning' : 'error')

function countdown(resetsAt: string | undefined, at: number): string {
  if (!resetsAt) return ''
  const ms = new Date(resetsAt).getTime() - at
  if (!Number.isFinite(ms)) return ''
  const minutes = Math.max(0, Math.floor(ms / 60000))
  const days = Math.floor(minutes / 1440)
  const hours = Math.floor((minutes % 1440) / 60)
  const mins = minutes % 60
  if (days > 0) return `${days}d ${hours}h`
  if (hours > 0) return `${hours}h ${mins}m`
  return `${mins}m`
}

// Each window gets a short gauge of its own; the labels are padded to one
// width so the gauges line up in a column.
const GAUGE_CELLS = 10

// The countdowns tick on their own; a redraw is only needed when they change.
const TICK_MS = 60 * 1000
let ticker: { cancel: () => void } | undefined

const size = (value: unknown): number =>
  typeof value === 'string' ? value.length : JSON.stringify(value ?? '').length

// Character counts per kind of block; only their proportions matter, since they
// are scaled onto the engine's own Messages figure.
function splitMessages(messages: { role: string; content: Block[] }[]) {
  const chars = { toolCalls: 0, toolResults: 0, thinking: 0, prompts: 0, replies: 0 }
  for (const message of messages) {
    for (const block of message.content) {
      if (block.type === 'tool_use') chars.toolCalls += size(block.input) + size(block.name)
      else if (block.type === 'tool_result') chars.toolResults += size(block.content)
      else if (block.type === 'thinking') chars.thinking += size(block.thinking)
      else if (block.type === 'redacted_thinking') chars.thinking += size(block.data)
      else if (message.role === 'user') chars.prompts += size(block.text ?? block)
      else chars.replies += size(block.text ?? block)
    }
  }
  return chars
}

async function measure($: EngineInterface): Promise<Snapshot | null> {
  const { context } = await $.session.usage({ breakdown: 'summary' })
  const breakdown = context.breakdown
  if (!breakdown) return null

  const rows: MeterRow[] = []
  for (const category of breakdown.categories) {
    if (category.kind !== 'used' || category.tokens <= 0) continue
    // The engine has no kind for the transcript row, so its /context label is
    // the only handle for splitting it further.
    if (category.name !== 'Messages') {
      rows.push({ label: category.name, tokens: category.tokens, color: category.color })
      continue
    }
    const chars = splitMessages(await $.session.messages({ as: 'api' }))
    const totalChars = Object.values(chars).reduce((a, b) => a + b, 0) || 1
    const share = (n: number) => Math.round((category.tokens * n) / totalChars)
    rows.push(
      { label: 'Tool results', tokens: share(chars.toolResults), color: 'warning' },
      { label: 'Tool calls', tokens: share(chars.toolCalls), color: 'autoAccept' },
      { label: 'Thinking', tokens: share(chars.thinking), color: 'planMode' },
      { label: 'Your prompts', tokens: share(chars.prompts), color: 'suggestion' },
      { label: 'Claude replies', tokens: share(chars.replies), color: 'claude' },
    )
  }
  rows.sort((a, b) => b.tokens - a.tokens)

  // The breakdown is per-category estimates; the last response's input tokens
  // are exact, so headline that figure and scale the categories to sum to it.
  const used = context.tokens ?? breakdown.totalTokens
  const scale = breakdown.totalTokens > 0 ? used / breakdown.totalTokens : 1

  return {
    used,
    window: context.window,
    percent: context.percent ?? Math.round((used / context.window) * 100),
    rows: rows
      .map(row => ({ ...row, tokens: Math.round(row.tokens * scale) }))
      .filter(row => row.tokens > 0),
  }
}

const k = (n: number) =>
  n >= 1e6 ? `${(n / 1e6).toFixed(1)}M` : n >= 1000 ? `${(n / 1000).toFixed(1)}k` : `${n}`

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    const started = await $.clock.now()
    await update($, now, () => started)
    ticker?.cancel()
    ticker = $.clock.every(TICK_MS, () => {
      void $.clock.now().then(at => update($, now, () => at))
    })
    return next(e)
  })

  on('session.measure', async ($, e, next) => {
    const fresh = await measure($)
    if (fresh) await update($, snapshot, () => fresh)
    if (Array.isArray(e.rateLimits)) await update($, limits, () => e.rateLimits)
    return next(e)
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const snap = await read($, snapshot)
    const rates = (await read($, limits)) ?? []
    // The limits are the account's, not the context's: they still show before
    // the first measurement and right after /compact, when there is no snapshot.
    if (e.props.hasSurvey || (!snap && rates.length === 0)) return next(e)

    const at = (await read($, now)) || (await $.clock.now())
    const { Box, Text } = $.ui.resolve(e)
    // A tight band keeps its content: only the breathing room between the
    // bar, legend and limits is given up when there are few rows to draw in.
    const rowGap = e.props.maxRows < 6 ? 0 : 1

    const sections = []
    if (snap) {
      const header = `Context ${k(snap.used)}/${k(snap.window)}  ${snap.percent}%  `
      const barWidth = Math.max(10, e.props.bodyColumns - header.length)
      const cells = snap.rows.map(row => Math.round((row.tokens / snap.window) * barWidth))
      const free = Math.max(0, barWidth - cells.reduce((a, b) => a + b, 0))
      sections.push(
        <Text wrap="truncate-end">
          <Text bold>{header}</Text>
          {snap.rows.map((row, i) => (
            <Text color={row.color}>{'█'.repeat(cells[i] ?? 0)}</Text>
          ))}
          <Text dimColor>{'░'.repeat(free)}</Text>
        </Text>,
        <Box flexDirection="row" columnGap={4} flexWrap="wrap">
          {snap.rows.map(row => (
            <Box key={row.label}>
              <Text color={row.color}>■</Text>
              <Text dimColor>{` ${row.label} ${k(row.tokens)}`}</Text>
            </Box>
          ))}
        </Box>,
      )
    }

    if (rates.length > 0) {
      const rows = ordered(rates)
      const labelWidth = Math.max(...rows.map(rate => labelFor(rate.kind).length))
      sections.push(
        <Box flexDirection="column">
          {rows.map(rate => {
            const percent = Math.max(0, Math.min(100, rate.percentUsed))
            const filled = Math.round((percent / 100) * GAUGE_CELLS)
            const glyph = glyphFor(rate.percentUsed)
            const color = colorFor(rate.percentUsed)
            const left = countdown(rate.resetsAt, at)
            return (
              <Text key={rate.kind} wrap="truncate-end">
                <Text dimColor>{`${labelFor(rate.kind).padEnd(labelWidth)}  `}</Text>
                <Text color={color}>{'█'.repeat(filled)}</Text>
                <Text dimColor>{'░'.repeat(GAUGE_CELLS - filled)}</Text>
                <Text color={color} bold={rate.percentUsed >= 80}>
                  {`  ${String(Math.round(rate.percentUsed)).padStart(3)}%`}
                </Text>
                {left && <Text dimColor>{`  resets in ${left}`}</Text>}
                {glyph && <Text color={color}>{`  ${glyph}`}</Text>}
              </Text>
            )
          })}
        </Box>,
      )
    }

    const meter = (
      <Box flexDirection="column" rowGap={rowGap} marginBottom={1}>
        {sections}
      </Box>
    )

    return (
      <Box flexDirection="column">
        {meter}
        {await next(e)}
      </Box>
    )
  })
}
