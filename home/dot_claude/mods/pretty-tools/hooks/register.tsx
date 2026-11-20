import type { Register, RenderElement } from 'claude-code'

type Input = Record<string, unknown>
type Hunk = { oldStart: number; newStart: number; lines: string[] }

// Rows the body of one block may take before it says how much is left out.
const BODY_ROWS = 16
const OUTPUT_ROWS = 8

// Tools whose block already shows what the result would; the engine's own
// result row under them is hidden so the content is not drawn twice.
const SELF_CONTAINED = new Set(['Edit', 'Write', 'Bash', 'Read'])

const str = (value: unknown) => (typeof value === 'string' ? value : undefined)
const obj = (value: unknown) =>
  value !== null && typeof value === 'object' ? (value as Record<string, unknown>) : undefined

// Last two path segments: enough to tell files apart without the drive prefix.
const shortPath = (path: unknown) => {
  const parts = (str(path) ?? '').split(/[\\/]/).filter(Boolean)
  return parts.length > 2 ? `…/${parts.slice(-2).join('/')}` : parts.join('/')
}

const firstLine = (text: string) => {
  const [head, ...rest] = text.trim().split('\n')
  return rest.length ? `${head} …` : (head ?? '')
}

export function summarize(tool: string, input: Input): { name: string; detail: string } {
  if (tool.startsWith('mcp__')) {
    const [, server, name] = tool.split('__')
    return { name: `${server} › ${name ?? tool}`, detail: '' }
  }
  switch (tool) {
    case 'Bash':
      return { name: 'Shell', detail: str(input.description) ?? firstLine(str(input.command) ?? '') }
    case 'Read': {
      const offset = typeof input.offset === 'number' ? input.offset : undefined
      const limit = typeof input.limit === 'number' ? input.limit : undefined
      const range = offset !== undefined && limit !== undefined ? ` (lines ${offset}–${offset + limit - 1})` : ''
      return { name: 'Read', detail: shortPath(input.file_path) + range }
    }
    case 'Edit':
    case 'Write':
    case 'NotebookEdit':
      return { name: tool, detail: shortPath(input.file_path ?? input.notebook_path) }
    case 'Grep': {
      const where = str(input.glob) ?? (input.path ? shortPath(input.path) : '')
      return { name: 'Search', detail: `"${str(input.pattern) ?? ''}"${where ? ` in ${where}` : ''}` }
    }
    case 'Glob':
      return { name: 'Find files', detail: str(input.pattern) ?? '' }
    case 'Agent':
      return { name: 'Agent', detail: str(input.description) ?? '' }
    case 'Skill':
      return { name: 'Skill', detail: str(input.skill) ?? '' }
    case 'WebFetch':
      return { name: 'Fetch', detail: (str(input.url) ?? '').replace(/^https?:\/\//, '') }
    case 'WebSearch':
      return { name: 'Web search', detail: str(input.query) ?? '' }
    default: {
      const first = Object.values(input).find(v => typeof v === 'string') as string | undefined
      return { name: tool, detail: first ? firstLine(first) : '' }
    }
  }
}

const KIND_COLOR: Record<string, string> = {
  Read: 'suggestion',
  Edit: 'warning',
  Write: 'success',
  NotebookEdit: 'warning',
  Bash: 'bashBorder',
  Grep: 'permission',
  Glob: 'permission',
  Agent: 'planMode',
}

// The engine's result records are untyped here, so each field is probed and the
// block falls back to the call's own input when the result lacks it.
function hunksOf(tool: string, input: Input, output: unknown): Hunk[] {
  const patch = obj(output)?.structuredPatch
  if (Array.isArray(patch) && patch.length > 0) {
    return patch.flatMap(raw => {
      const h = obj(raw)
      const lines = Array.isArray(h?.lines) ? h.lines.filter((l): l is string => typeof l === 'string') : []
      return lines.length ? [{ oldStart: Number(h?.oldStart) || 1, newStart: Number(h?.newStart) || 1, lines }] : []
    })
  }
  if (tool !== 'Edit') return []
  const before = str(input.old_string)
  const after = str(input.new_string)
  if (before === undefined || after === undefined) return []
  const lines = [...before.split('\n').map(l => `-${l}`), ...after.split('\n').map(l => `+${l}`)]
  return [{ oldStart: 1, newStart: 1, lines }]
}

// Keeps whole hunks within the row budget, cutting the last one short when it
// overflows; each kept hunk's header is recounted so the diff still parses.
export function diffSource(hunks: Hunk[], budget = BODY_ROWS): { source: string; hidden: number } {
  const out: string[] = []
  let used = 0
  let hidden = 0
  for (const hunk of hunks) {
    const room = budget - used
    const kept = room > 0 ? hunk.lines.slice(0, room) : []
    hidden += hunk.lines.length - kept.length
    if (!kept.length) continue
    const oldCount = kept.filter(l => !l.startsWith('+')).length
    const newCount = kept.filter(l => !l.startsWith('-')).length
    out.push(`@@ -${hunk.oldStart},${oldCount} +${hunk.newStart},${newCount} @@`, ...kept)
    used += kept.length
  }
  return { source: out.join('\n'), hidden }
}

const tail = (text: string, rows: number) => {
  const lines = text.replace(/\s+$/, '').split('\n')
  return { lines: lines.slice(-rows), hidden: Math.max(0, lines.length - rows) }
}

export const register: Register = on => {
  on('ui.render', { component: 'ToolUse' }, async ($, e, next) => {
    if (e.surface !== 'terminal') return next(e)
    const { Box, Text, Code } = $.ui.resolve(e)
    const { tool, isRunning, isErrored, isInterrupted, output } = e.props
    const input = (obj(e.props.input) ?? {}) as Input
    const { name, detail } = summarize(tool, input)
    const result = obj(output)

    const status = isInterrupted ? 'inactive' : isErrored ? 'error' : isRunning ? 'warning' : 'success'
    const border = isErrored ? 'error' : (KIND_COLOR[tool] ?? 'inactive')
    const width = Math.max(30, (e.viewport?.columns ?? 100) - 2)

    let body: RenderElement | null = null
    let note = ''
    if (!isRunning && !isErrored && !isInterrupted) {
      if (tool === 'Edit' || tool === 'Write') {
        const { source, hidden } = diffSource(hunksOf(tool, input, output))
        if (source) {
          body = <Code source={source} format="diff" wrap="truncate-end" />
          if (hidden) note = `… ${hidden} more lines`
        } else if (tool === 'Write') {
          const lines = (str(input.content) ?? '').split('\n')
          const shown = lines.slice(0, BODY_ROWS)
          body = <Code source={shown.join('\n')} path={str(input.file_path)} startLine={1} wrap="truncate-end" />
          if (lines.length > shown.length) note = `… ${lines.length - shown.length} more lines (new file)`
        }
      } else if (tool === 'Bash') {
        const out = tail(`${str(result?.stdout) ?? ''}${str(result?.stderr) ? `\n${str(result?.stderr)}` : ''}`, OUTPUT_ROWS)
        body = (
          <Box flexDirection="column">
            <Text dimColor wrap="truncate-end">{`$ ${firstLine(str(input.command) ?? '')}`}</Text>
            {out.lines.join('').trim() !== '' && <Text wrap="truncate-end">{out.lines.join('\n')}</Text>}
          </Box>
        )
        if (out.hidden) note = `… ${out.hidden} earlier lines`
      } else if (tool === 'Read') {
        const lines = Number(obj(result?.file)?.numLines)
        if (lines) note = `${lines} lines`
      }
    }

    return (
      <Box flexDirection="column" borderStyle="round" borderColor={border} paddingX={1} width={width}>
        <Box flexDirection="row">
          <Text color={status}>{isRunning ? '◌ ' : '● '}</Text>
          <Text bold color={border}>{name}</Text>
          {detail !== '' && <Text dimColor wrap="truncate-end">{`  ${detail}`}</Text>}
          {isInterrupted && <Text color="inactive"> · interrupted</Text>}
        </Box>
        {body}
        {note !== '' && <Text dimColor>{note}</Text>}
      </Box>
    )
  })

  on('ui.render', { component: 'ToolResult' }, async ($, e, next) => {
    if (e.surface !== 'terminal' || e.props.isErrored || !SELF_CONTAINED.has(e.props.tool)) return next(e)
    const { Box } = $.ui.resolve(e)
    return <Box />
  })
}
