import { expect, mock, test } from 'claude-code/testing'
import type { TestBody } from 'claude-code/testing'

const breakdown = {
  categories: [
    { name: 'System prompt', tokens: 3000, color: 'promptBorder', isDeferred: false, kind: 'used' },
    { name: 'Messages', tokens: 10000, color: 'purple', isDeferred: false, kind: 'used' },
    { name: 'Free space', tokens: 187000, color: 'inactive', isDeferred: false, kind: 'free' },
  ],
  totalTokens: 13000,
  maxTokens: 200000,
  rawMaxTokens: 200000,
  autocompactSource: 'auto',
  percentage: 7,
  gridRows: [],
  model: 'claude-opus-5-5',
  memoryFiles: [],
  mcpTools: [],
  agents: [],
  isAutoCompactEnabled: true,
  apiUsage: null,
}

// Equal-sized prompt, tool call and tool result: each should get a third of Messages.
const filler = 'x'.repeat(300)
const messages = [
  { role: 'user', content: [{ type: 'text', text: filler }] },
  { role: 'assistant', content: [{ type: 'tool_use', id: 'a', name: '', input: filler }] },
  { role: 'user', content: [{ type: 'tool_result', tool_use_id: 'a', content: filler }] },
]

const NOW = Date.parse('2026-01-01T00:00:00Z')
const resetIn = (hours: number) => new Date(NOW + hours * 3600000).toISOString()

type On = Parameters<TestBody>[1]
type Limit = { kind: string; percentUsed: number; resetsAt?: string }

function setup(on: On) {
  const clock = mock.clock(on, { now: NOW })
  on('session.usage', () => ({ value: { startedAt: 0, rateLimits: [], context: { window: 1000000, tokens: 26000, percent: 3, breakdown } } }) as never)
  on('session.messages', () => ({ value: messages }) as never)
  on('session.measure', (_$, e) => ({ changed: e.changed }))
  on('session.start', (_$, e) => ({ cwd: e.cwd }))
  return { clock }
}

const measure = ($: Parameters<TestBody>[0], rateLimits: Limit[]) =>
  $.session.measure({ context: { window: 200000 }, rateLimits, startedAt: 0, changed: ['rateLimits'] } as never)

const mountBand = ($: Parameters<TestBody>[0], columns = 100, maxRows = 10) =>
  $.ui.mount({
    plugin: 'context-meter',
    surface: 'terminal',
    component: 'AbovePrompt',
    props: { hasSurvey: false, isWorking: false, maxRows, bodyColumns: columns } as never,
  })

const LIMITS: Limit[] = [
  { kind: 'five_hour', percentUsed: 23.4, resetsAt: resetIn(2 + 10 / 60) },
  { kind: 'seven_day', percentUsed: 41, resetsAt: resetIn(76) },
]

test('the band headlines the exact usage and scales the split to it', async ($, on) => {
  setup(on)
  await measure($, [])
  const ui = await mountBand($)
  expect(await ui.find({ text: /Context 26\.0k\/1\.0M {2}3%/ })).toBeDefined()
  expect(await ui.find({ text: /Tool calls 6\.7k/ })).toBeDefined()
  expect(await ui.find({ text: /Tool results 6\.7k/ })).toBeDefined()
  expect(await ui.find({ text: /Your prompts 6\.7k/ })).toBeDefined()
})

// The band is one chain: a plugin below context-meter must still get to draw
// through next(e). A fake lower hook leaves a marker the mount must show too.
test('a snapshot band passes the rest of the chain through next(e)', async ($, on) => {
  setup(on)
  on('ui.render', { component: 'AbovePrompt' }, (hook$, e) => {
    const { Text } = hook$.ui.resolve(e)
    return Text({ children: 'below-marker' })
  })
  await measure($, [])
  const ui = await mountBand($)
  expect(await ui.find({ text: /Context / })).toBeDefined()
  expect(await ui.find({ text: /below-marker/ })).toBeDefined()
})

// --- limits ---------------------------------------------------------------

type Tree = { type?: string; props?: Record<string, unknown>; children?: unknown[] }

const kids = (n: Tree): Tree[] =>
  (n.children ?? []).filter((c): c is Tree => typeof c === 'object' && c !== null)

const textOf = (n: Tree | string): string =>
  typeof n === 'string' ? n : (n.children ?? []).map(c => textOf(c as Tree | string)).join('')

const sectionsOf = async (ui: Awaited<ReturnType<typeof $.ui.mount>>): Promise<Tree[]> =>
  kids(kids(await ui.drawn())[0]!)

const limitRows = async (ui: Awaited<ReturnType<typeof $.ui.mount>>, index = 2): Promise<string[]> =>
  kids((await sectionsOf(ui))[index]!).map(textOf)

test('the band shows one gauge row per window, 5-hour first, below the context', async ($, on) => {
  setup(on)
  await measure($, [
    { kind: 'seven_day', percentUsed: 41, resetsAt: resetIn(76) },
    { kind: 'five_hour', percentUsed: 23.4, resetsAt: resetIn(2 + 10 / 60) },
    { kind: 'seven_day_fable', percentUsed: 12, resetsAt: resetIn(76) },
  ])
  const ui = await mountBand($)
  const [bar, legend] = await sectionsOf(ui)
  expect(bar!.type).toBe('Text')
  expect(textOf(legend!)).toContain('■ Tool results')

  // Labels padded to the longest ("Fable weekly"), so the gauges line up.
  expect(await limitRows(ui)).toEqual([
    '5-hour        ██░░░░░░░░   23%  resets in 2h 10m',
    'Weekly        ████░░░░░░   41%  resets in 3d 4h',
    'Fable weekly  █░░░░░░░░░   12%  resets in 3d 4h',
  ])
})

test('windows at 85% and 96% show warning and critical glyphs', async ($, on) => {
  setup(on)
  await measure($, [
    { kind: 'five_hour', percentUsed: 85, resetsAt: resetIn(2) },
    { kind: 'seven_day', percentUsed: 96, resetsAt: resetIn(76) },
  ])
  const [five, week] = await limitRows(await mountBand($))
  expect(five).toMatch(/ 85%.* ⚠$/)
  expect(week).toMatch(/ 96%.* ‼$/)
})

test('limits show before the first context measurement', async ($, on) => {
  // No breakdown yet: the engine has nothing to split, so there is no snapshot.
  mock.clock(on, { now: NOW })
  on('session.usage', () => ({ value: { startedAt: 0, rateLimits: [], context: { window: 1000000 } } }) as never)
  on('session.measure', (_$, e) => ({ changed: e.changed }))
  await measure($, LIMITS)
  const ui = await mountBand($)
  const sections = await sectionsOf(ui)
  // Only the limits section: no bar, no legend.
  expect(sections).toHaveLength(1)
  expect(textOf(sections[0]!)).toMatch(/^5-hour .* 23%/)
})

test('an empty rateLimits reading hides the limits line', async ($, on) => {
  setup(on)
  await measure($, LIMITS)
  await measure($, [])
  const sections = await sectionsOf(await mountBand($))
  expect(sections).toHaveLength(2)
  expect(textOf(sections[1]!)).toContain('■ ')
})

test('the countdown advances on the 60s clock tick', async ($, on) => {
  const { clock } = setup(on)
  await $.session.start({ cwd: '/', surface: null, isInteractive: true } as never)
  await measure($, [{ kind: 'five_hour', percentUsed: 23, resetsAt: resetIn(2 + 10 / 60) }])
  await clock.advance(60000)
  const ui = await mountBand($)
  expect(await ui.find({ text: /resets in 2h 9m/ })).toBeDefined()
})

// --- band spacing ----------------------------------------------------------

// The band relies on flexWrap, so no single line (an item plus its gaps) may
// be wider than the body. Greedy packing mirrors a terminal's wrap.
function wrappedLines(items: string[], gap: number, columns: number): string[] {
  const lines: string[] = []
  let line = ''
  for (const item of items) {
    const next = line ? `${line}${' '.repeat(gap)}${item}` : item
    if (line && next.length > columns) {
      lines.push(line)
      line = item
    } else {
      line = next
    }
  }
  if (line) lines.push(line)
  return lines
}

test('the band separates bar, legend and limits with a blank row when maxRows is large', async ($, on) => {
  setup(on)
  on('ui.render', { component: 'AbovePrompt' }, (hook$, e) => {
    const { Text } = hook$.ui.resolve(e)
    return Text({ children: 'below-marker' })
  })
  await measure($, LIMITS)
  const ui = await mountBand($)
  const meter = kids(await ui.drawn())[0]!

  expect(meter.props!.rowGap).toBeGreaterThanOrEqual(1)
  expect(meter.props!.marginBottom).toBe(1)

  const [bar, legend, limits] = kids(meter)
  expect(bar!.type).toBe('Text')
  expect(legend!.props!.flexDirection).toBe('row')
  expect(limits!.props!.flexDirection).toBe('column')
  expect(textOf(legend!)).toContain('■ Tool results')
  expect(textOf(limits!)).toMatch(/^5-hour/)
  expect(await ui.find({ text: /below-marker/ })).toBeDefined()
})

test('the legend row gaps its items by at least 4 columns and wraps them', async ($, on) => {
  setup(on)
  await measure($, LIMITS)
  const [, legend] = await sectionsOf(await mountBand($))
  expect(legend!.props!.flexWrap).toBe('wrap')
  expect(legend!.props!.columnGap as number).toBeGreaterThanOrEqual(4)

  const items = kids(legend!)
  expect(items.length).toBeGreaterThan(0)
  for (const item of items) {
    const line = textOf(item)
    expect(line.startsWith('■ ')).toBe(true)
    expect(line).not.toMatch(/\s$/) // trailing-spaces hack is gone
  }
})

test('no band line exceeds bodyColumns at 80 columns', async ($, on) => {
  setup(on)
  await measure($, LIMITS)
  const columns = 80
  const [bar, legend, limits] = await sectionsOf(await mountBand($, columns))

  // The bar is capped by truncate-end and fills exactly the body width.
  expect(textOf(bar!).length).toBeLessThanOrEqual(columns)

  for (const line of wrappedLines(kids(legend!).map(textOf), legend!.props!.columnGap as number, columns)) {
    expect(line.length).toBeLessThanOrEqual(columns)
  }
  for (const line of kids(limits!).map(textOf)) {
    expect(line.length).toBeLessThanOrEqual(columns)
  }
})

test('a tight maxRows drops the blank row but keeps all three sections', async ($, on) => {
  setup(on)
  await measure($, LIMITS)
  const ui = await mountBand($, 80, 4)
  const meter = kids(await ui.drawn())[0]!
  expect(meter.props!.rowGap).toBe(0)
  expect(meter.props!.marginBottom).toBe(1)

  const sections = kids(meter)
  expect(sections).toHaveLength(3)
  expect(textOf(sections[1]!)).toContain('■ ')
  expect(textOf(sections[2]!)).toMatch(/^5-hour/)
})
