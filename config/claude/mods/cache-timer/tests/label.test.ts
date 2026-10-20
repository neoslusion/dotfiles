import { expect, test } from 'claude-code/testing'

import { cacheLabel } from '../hooks/register'

const MIN = 60 * 1000

test('the label counts down the hour and turns cold after it', () => {
  expect(cacheLabel(null, 0)).toBeNull()
  expect(cacheLabel(0, 13 * MIN)).toEqual({ text: '● cache warm · 47m left', color: 'success' })
  expect(cacheLabel(0, 55 * MIN)).toEqual({ text: '● cache warm · 5m left', color: 'warning' })
  expect(cacheLabel(0, 61 * MIN)).toEqual({ text: '○ cache cold', color: 'inactive' })
})

test('a main-thread reply starts the timer and the footer shows it beside the engine modes', async ($, on) => {
  on('clock.now', () => ({ value: 0 }) as never)
  on('turn.complete', (_$, e) => ({ text: (e as { answer: string }).answer }) as never)
  await $.turn.complete({ answer: 'done', durationMs: 1, isAborted: false, turnId: 't1' } as never)

  const ui = await $.ui.mount({
    plugin: 'cache-timer',
    surface: 'terminal',
    component: 'SessionMode',
    props: { modes: ['focus'] },
  })
  expect(await ui.find({ text: /focus/ })).toBeDefined()
  expect(await ui.find({ text: /cache warm · 60m left/ })).toBeDefined()
})
