import { expect, test } from 'claude-code/testing'
import type { Engine } from 'claude-code/testing'

import { diffSource, summarize } from '../hooks/register'

const row = (tool: string, input: unknown, output?: unknown) => ({
  tool_use_id: 't1',
  tool,
  input,
  output,
  isRunning: false,
  isErrored: false,
  isInterrupted: false,
})

const mount = ($: Engine, props: ReturnType<typeof row>) =>
  $.ui.mount({
    plugin: 'pretty-tools',
    surface: 'terminal',
    component: 'ToolUse',
    props,
    viewport: { columns: 100, rows: 30 },
  })

test('Read summaries use an inclusive range for the requested line count', () => {
  expect(summarize('Read', { file_path: 'src/main.ts', offset: 10, limit: 1 }).detail)
    .toBe('src/main.ts (lines 10–10)')
  expect(summarize('Read', { file_path: 'src/main.ts', offset: 10, limit: 5 }).detail)
    .toBe('src/main.ts (lines 10–14)')
})

test('a Bash block shows its description and output, not the raw command as the title', async $ => {
  const ui = await mount($, row(
    'Bash',
    { command: 'git -c core.pager=cat log --oneline -2', description: 'Show recent commits' },
    { stdout: 'abc123 first\ndef456 second\n', stderr: '' },
  ))
  expect(await ui.find({ type: 'Box', text: /Show recent commits/ })).toBeDefined()
  expect(await ui.find({ text: /def456 second/ })).toBeDefined()
})

test('an Edit block draws the result patch as a diff', async $ => {
  const ui = await mount($, row(
    'Edit',
    { file_path: 'C:/repo/src/app.ts', old_string: 'a', new_string: 'b' },
    { structuredPatch: [{ oldStart: 10, newStart: 10, lines: [' keep', '-const a = 1', '+const a = 2'] }] },
  ))
  const code = await ui.find({ type: 'Code' })
  expect(code?.props.format).toBe('diff')
  expect(String(code?.props.source)).toContain('@@ -10,2 +10,2 @@')
  expect(await ui.find({ text: /…\/src\/app\.ts/ })).toBeDefined()
})

test('a new file block shows its first lines', async $ => {
  const ui = await mount($, row('Write', { file_path: 'C:/repo/notes.md', content: '# Title\nbody' }, { type: 'create' }))
  const code = await ui.find({ type: 'Code' })
  expect(String(code?.props.source)).toContain('# Title')
})

test('the engine result row is hidden under an Edit block', async $ => {
  const edit = await $.ui.mount({
    plugin: 'pretty-tools',
    surface: 'terminal',
    component: 'ToolResult',
    props: { tool_use_id: 't1', tool: 'Edit', output: {}, isErrored: false },
  })
  expect(await edit.findAll({ type: 'Text' })).toHaveLength(0)
})

test('a cut diff keeps hunk headers consistent with the lines kept', () => {
  const { source, hidden } = diffSource([{ oldStart: 1, newStart: 1, lines: ['-a', '-b', '+c', '+d'] }], 3)
  expect(source).toBe('@@ -1,2 +1,1 @@\n-a\n-b\n+c')
  expect(hidden).toBe(1)
})
