import { atom, read, update } from 'claude-code'
import type { Register } from 'claude-code'

// The engine does not tell plugins the cache's TTL. This session's main thread
// writes 1-hour entries; under usage overage they drop to 5 minutes, which this
// timer cannot see, so it reads optimistic then.
const TTL_MS = 60 * 60 * 1000
const WARN_MS = 10 * 60 * 1000
const TICK_MS = 30 * 1000

const lastReplyAt = atom({ plugin: 'cache-timer', key: 'lastReplyAt' } as const, null)
const now = atom({ plugin: 'cache-timer', key: 'now' } as const, 0)

export function cacheLabel(last: number | null, at: number): { text: string; color: string } | null {
  if (last === null) return null
  const left = last + TTL_MS - at
  if (left <= 0) return { text: '○ cache cold', color: 'inactive' }
  const minutes = Math.max(1, Math.ceil(left / 60000))
  return { text: `● cache warm · ${minutes}m left`, color: left <= WARN_MS ? 'warning' : 'success' }
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    const t = await $.clock.now()
    await update($, now, () => t)
    $.clock.every(TICK_MS, () => void $.clock.now().then(t => update($, now, () => t)))
    return next(e)
  })

  // Only main-thread replies refresh the main prefix; subagents cache their own.
  on('turn.complete', async ($, e, next) => {
    if (e.agentId === undefined) {
      const t = await $.clock.now()
      await update($, lastReplyAt, () => t)
      await update($, now, () => t)
    }
    return next(e)
  })

  on('ui.render', { component: 'SessionMode' }, async ($, e, next) => {
    const label = cacheLabel(await read($, lastReplyAt), await read($, now))
    if (!label) return next(e)
    const { Box, Text } = $.ui.resolve(e)
    return (
      <Box flexDirection="row">
        {e.props.modes.length > 0 && <Text dimColor>{`${e.props.modes.join(' & ')}   `}</Text>}
        <Text color={label.color}>{label.text}</Text>
      </Box>
    )
  })
}
