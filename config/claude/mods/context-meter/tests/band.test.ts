import { expect, test } from 'claude-code/testing'

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

// The exact figure (26k of a 1M window) is double the categories' estimate, so
// the headline must take the exact one and each category scale by two.
test('the band headlines the exact usage and scales the split to it', async ($, on) => {
  on('session.usage', () => ({ value: { startedAt: 0, rateLimits: [], context: { window: 1000000, tokens: 26000, percent: 3, breakdown } } }) as never)
  on('session.messages', () => ({ value: messages }) as never)
  on('session.measure', (_$, e) => ({ changed: e.changed }))

  await $.session.measure({ context: { window: 200000 }, rateLimits: [], startedAt: 0, changed: [] } as never)

  const ui = await $.ui.mount({
    plugin: 'context-meter',
    surface: 'terminal',
    component: 'AbovePrompt',
    props: { hasSurvey: false, isWorking: false, maxRows: 10, bodyColumns: 80 } as never,
  })
  expect(await ui.find({ text: /Context 26\.0k\/1\.0M \(3%\)/ })).toBeDefined()
  expect(await ui.find({ text: /Tool calls 6\.7k/ })).toBeDefined()
  expect(await ui.find({ text: /Tool results 6\.7k/ })).toBeDefined()
  expect(await ui.find({ text: /Your prompts 6\.7k/ })).toBeDefined()
})
