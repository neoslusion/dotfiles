import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { MeterRow, Snapshot } from '../types'

const snapshot = atom({ plugin: 'context-meter', key: 'snapshot' } as const, null)

type Block = { type: string; [field: string]: unknown }

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
  on('session.measure', async ($, e, next) => {
    const fresh = await measure($)
    if (fresh) await update($, snapshot, () => fresh)
    return next(e)
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const snap = await read($, snapshot)
    if (e.props.hasSurvey || !snap) return next(e)

    const { Box, Text } = $.ui.resolve(e)
    const header = `Context ${k(snap.used)}/${k(snap.window)} (${snap.percent}%) `
    const barWidth = Math.max(10, e.props.bodyColumns - header.length)
    const cells = snap.rows.map(row => Math.round((row.tokens / snap.window) * barWidth))
    const free = Math.max(0, barWidth - cells.reduce((a, b) => a + b, 0))

    return (
      <Box flexDirection="column" marginBottom={1}>
        <Text wrap="truncate-end">
          <Text bold>{header}</Text>
          {snap.rows.map((row, i) => (
            <Text color={row.color}>{'█'.repeat(cells[i] ?? 0)}</Text>
          ))}
          <Text dimColor>{'░'.repeat(free)}</Text>
        </Text>
        <Text wrap="wrap">
          {snap.rows.map(row => (
            <Text>
              <Text color={row.color}>■ </Text>
              <Text dimColor>{`${row.label} ${k(row.tokens)}   `}</Text>
            </Text>
          ))}
        </Text>
      </Box>
    )
  })
}
