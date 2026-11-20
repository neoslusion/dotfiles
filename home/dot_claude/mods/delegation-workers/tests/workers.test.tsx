import type { On } from 'claude-code';
import type { Engine } from 'claude-code/testing';
import { expect, mock, test } from 'claude-code/testing';
import { register } from '../hooks/register';
import * as workerParts from '../hooks/workers';

const BAND = 'delegation-workers-above-prompt';
const HOME = 'C:/home';
const DATA_BASE = `${HOME}/.claude/plugins/data`;
const DATA_DIR = 'agent-delegation-test';
const ROOT = `${DATA_BASE}/${DATA_DIR}`;
const SESSION = 'session-this';
const OTHER = 'session-other';
const BASE = Date.UTC(2026, 10, 18, 12, 0, 0);

const BAND_PROPS = {
  hasSurvey: false,
  isCollapsed: false,
  isWorking: false,
  maxRows: 30,
  bodyColumns: 120,
  scroll: { offset: 0, bodyRows: 29 },
  view: {},
} as const;

type JobFile = { path: string; text: string; mtimeMs: number };
type JobRec = Record<string, unknown>;
type Clock = ReturnType<typeof mock.clock>;

const iso = (offsetMs: number) => new Date(BASE + offsetMs).toISOString();

const job = (overrides: JobRec = {}): JobRec => ({
  version: 1,
  id: 'task-default',
  executor: 'opencode',
  role: 'writer',
  model: 'opencode/hy4-flash-free',
  sessionId: SESSION,
  status: 'running',
  phase: 'running',
  title: 'default task',
  startedAt: iso(-60000),
  updatedAt: iso(0),
  workspaceRoot: 'C:/repos/gemini-plugin-cc',
  checks: [],
  checkResults: [],
  ...overrides,
});

const file = (ws: string, rec: JobRec, mtimeMs = BASE): JobFile => {
  const name = `${String(rec.id)}.json`;
  return {
    path: `${ROOT}/state/${ws}/jobs/${name}`,
    text: `${JSON.stringify(rec)}\n`,
    mtimeMs,
  };
};

const dir = (name: string) => ({ name, kind: 'dir' as const, size: 0, mtimeMs: 0, isLink: false });

function setup(on: On, files: JobFile[], bottom?: On, events: Record<string, string> = {}): { clock: Clock } {
  const clock = mock.clock(on, { now: BASE });

  on('session.start', (_, e) => ({ cwd: e.cwd }));
  // The mod resolves the agent-delegation data dir under HOME; it never reads
  // CLAUDE_PLUGIN_DATA (that would point at this mod's own directory).
  on('env.get', (_, e) => ({ value: e.name === 'HOME' ? HOME : '' }));
  on('session.id', () => ({ value: SESSION }));
  on('fs.list', (_, e) => {
    // The engine normalises separators for this platform; compare on '/'.
    const path = e.path.replace(/\\/g, '/');
    if (path === DATA_BASE) {
      return { value: [dir(DATA_DIR)] };
    }
    if (path === `${ROOT}/state`) {
      const names = [...new Set(files.map(entry =>
        entry.path.slice(`${ROOT}/state/`.length).split('/')[0]))];
      return { value: names.map(dir) };
    }
    if (path.endsWith('/jobs')) {
      return {
        value: files
          .filter(entry => entry.path.startsWith(`${path}/`))
          .map(entry => ({
            name: entry.path.split('/').pop() ?? '',
            kind: 'file' as const,
            size: entry.text.length,
            mtimeMs: entry.mtimeMs,
            isLink: false,
          })),
      };
    }
    if (path.startsWith(`${ROOT}/events/`)) {
      const id = path.slice(`${ROOT}/events/`.length);
      return {
        value: id in events
          ? [{ name: '1.json', kind: 'file' as const, size: 80, mtimeMs: BASE, isLink: false }]
          : [],
      };
    }
    return { value: [] };
  });
  on('fs.read', (_, e) => {
    const path = e.path.replace(/\\/g, '/');
    if (path.startsWith(`${ROOT}/events/`)) {
      const id = path.slice(`${ROOT}/events/`.length).replace(/\/1\.json$/, '');
      return { value: JSON.stringify({ version: 1, taskId: id, sequence: 1, type: 'task.update', createdAt: events[id] }) };
    }
    return { value: files.find(entry => entry.path === path)?.text ?? '' };
  });

  if (bottom) {
    on('ui.render', { component: 'AbovePrompt' }, ($, e) => {
      const { Text } = $.ui.resolve(e);
      return <Text>below-marker</Text>;
    });
  }
  return { clock };
}

async function start($: Engine) {
  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true });
}

async function mountBand($: Engine, props: Partial<typeof BAND_PROPS> = {}) {
  return $.ui.mount({
    plugin: 'delegation-workers',
    surface: 'terminal',
    component: 'AbovePrompt',
    requestId: BAND,
    props: { ...BAND_PROPS, ...props },
  });
}

// The band draws from state the poll timer writes; the first tick fills it.
const firstTick = async (clock: Clock) => clock.advance(2000);

const buttons = async (ui: { findAll: (q: { type: string }) => Promise<{ key?: string; text: string }[]> }) =>
  ui.findAll({ type: 'Button' });

const header = async (ui: { find: (q: { type: string; text: RegExp }) => Promise<{ text: string } | undefined> }) =>
  ui.find({ type: 'Text', text: /[Dd]elegation workers/ });

type Node = { type?: string; props?: Record<string, unknown>; children?: unknown[] };
type Laid = { lines: string[]; width: number };

const nodeWhere = (node: unknown, match: (tree: Node) => boolean): Node | undefined => {
  if (node == null || typeof node !== 'object') return undefined;
  if (Array.isArray(node)) {
    for (const child of node) {
      const found = nodeWhere(child, match);
      if (found) return found;
    }
    return undefined;
  }
  const tree = node as Node;
  if (match(tree)) return tree;
  for (const child of tree.children ?? []) {
    const found = nodeWhere(child, match);
    if (found) return found;
  }
  return undefined;
};

const nodeText = (node: unknown): string => {
  if (node == null) return '';
  if (typeof node === 'string') return node;
  if (Array.isArray(node)) return node.map(nodeText).join('');
  const tree = node as Node;
  if (!tree.type || tree.type === 'engine' || tree.type === 'Client') return '';
  const nested = (tree.children ?? []).map(nodeText).join('');
  if (nested) return nested;
  if (typeof tree.props?.label === 'string') return tree.props.label as string;
  if (typeof tree.props?.value === 'string') return tree.props.value as string;
  return '';
};

/** Mirrors the terminal layout: widths, padding, gaps and round borders. */
function layout(node: unknown, available: number): Laid {
  if (node == null || typeof node !== 'object') return { lines: [' '], width: 1 };
  if (Array.isArray(node)) {
    const parts = node.map(child => layout(child, available));
    return { lines: parts.flatMap(part => part.lines), width: Math.max(1, ...parts.map(part => part.width)) };
  }
  const tree = node as Node;
  if (!tree.type || tree.type === 'engine' || tree.type === 'Client') return { lines: [], width: 0 };
  if (tree.type !== 'Box') {
    const text = tree.type === 'Text' ? nodeText(tree)
      : tree.type === 'Input' ? `${tree.props?.label ?? ''}: ${tree.props?.value || tree.props?.placeholder || ''}`
        : tree.props?.plain ? nodeText(tree) : `[ ${nodeText(tree)} ]`;
    return { lines: [text], width: text.length };
  }
  const ownW = typeof tree.props?.width === 'number'
    ? Math.min(Math.max(1, available), Math.max(1, Number(tree.props.width)))
    : Math.max(1, available);
  const padL = Number(tree.props?.paddingLeft ?? 0);
  const padR = Number(tree.props?.paddingRight ?? 0);
  const border = tree.props?.borderStyle === 'round'
    ? { top: '╭', bottom: '╰', corner: '╮', end: '╯' }
    : tree.props?.borderStyle
      ? { top: '┌', bottom: '└', corner: '┐', end: '┘' }
      : null;
  const innerW = Math.max(0, ownW - padL - padR - (border ? 2 : 0));
  const gapX = Number(tree.props?.columnGap ?? 0);
  const gapY = Number(tree.props?.rowGap ?? 0);
  const kids = (tree.children ?? []).filter(child =>
    child != null && typeof child === 'object' && (child as Node).type !== 'engine');
  let lines: string[];
  if (tree.props?.flexDirection === 'row') {
    lines = [];
    let x = 0;
    for (const child of kids) {
      const kid = child as Node;
      const room = Math.max(1, innerW - x);
      const cw = typeof kid.props?.width === 'number'
        ? Math.min(room, Math.max(1, Number(kid.props.width))) : room;
      const part = layout(child, cw);
      part.lines.forEach((line, i) => {
        const base = lines[i] ?? ' '.repeat(innerW);
        lines[i] = `${base.slice(0, x)}${line.slice(0, part.width)}`.padEnd(innerW).slice(0, innerW);
      });
      x += part.width + gapX;
    }
  } else {
    lines = [];
    for (const child of kids) {
      if (lines.length && gapY) lines.push(' '.repeat(innerW));
      lines.push(...layout(child, innerW).lines.map(line => line.slice(0, innerW).padEnd(innerW)));
    }
  }
  if (!lines.length) lines = [' '.repeat(innerW)];
  lines = lines.map(line => line.slice(0, innerW).padEnd(innerW));
  if (border) {
    lines = [
      `${border.top}${'─'.repeat(innerW)}${border.corner}`,
      ...lines.map(line => `│${line}│`),
      `${border.bottom}${'─'.repeat(innerW)}${border.end}`,
    ];
  }
  if (padL || padR) lines = lines.map(line => `${' '.repeat(padL)}${line}${' '.repeat(padR)}`);
  return { lines, width: ownW };
}

const sketch = (tree: unknown, width: number): string[] => layout(tree, width).lines;

// ---- nothing to show -------------------------------------------------------

test('no tasks draws nothing and passes the band on', async ($, on) => {
  const { clock } = setup(on, [], true);
  await start($);
  const ui = await mountBand($);
  await firstTick(clock);

  expect(await header(ui)).toBeUndefined();
  expect((await buttons(ui)).length).toBe(0);
  expect((await ui.find({ type: 'Text', text: /below-marker/ }))).toBeDefined();
  await ui.unmount();
});

// ---- session scoping and counts -------------------------------------------

test('two workspaces show only this session with correct header counts', async ($, on) => {
  const { clock } = setup(on, [
    file('gemini-plugin-cc', job({ id: 'task-a', title: 'band-form fix' })),
    file('context-meter', job({
      id: 'task-b', title: 'context-meter band', workspaceRoot: 'C:/repos/context-meter',
    })),
    file('foreign', job({ id: 'task-c', sessionId: OTHER, title: 'foreign task' })),
  ]);
  await start($);
  const ui = await mountBand($);
  await firstTick(clock);

  const rows = await buttons(ui);
  expect(rows.length).toBe(2);
  expect(rows.some(row => row.text.includes('band-form fix'))).toBe(true);
  expect(rows.some(row => row.text.includes('context-meter band'))).toBe(true);
  expect(rows.some(row => row.text.includes('foreign task'))).toBe(false);
  expect((await header(ui))?.text).toContain('Delegation workers · 2 running · 0 queued');
  await ui.unmount();
});

// ---- columns, truncation and elapsed --------------------------------------

test('role, model and effort render; title truncates; elapsed advances on a tick', async ($, on) => {
  const { clock } = setup(on, [
    file('gemini-plugin-cc', job({
      id: 'task-long',
      role: 'writer',
      model: 'opencode/hy4-flash-free',
      execution: { effort: 'high' },
      title: 'X'.repeat(200),
      startedAt: iso(-134000),
    })),
  ]);
  await start($);
  const ui = await mountBand($, { bodyColumns: 90 });
  await firstTick(clock);

  let rows = await buttons(ui);
  expect(rows.length).toBe(1);
  const label = rows[0]?.text ?? '';
  expect(label).toContain('writer');
  expect(label).toContain('opencode/hy4-flash-free');
  expect(label).toContain('effort high');
  expect(label).toContain('2m16s');
  expect(label).toContain('…');
  expect(label.includes('X'.repeat(30))).toBe(false);

  await clock.advance(2000);
  rows = await buttons(ui);
  expect(rows[0]?.text).toContain('2m18s');
  await ui.unmount();
});

// ---- finished rows and check results --------------------------------------

test('a finished task shows checks 2/2 and leaves after 60 seconds', async ($, on) => {
  const { clock } = setup(on, [
    file('gemini-plugin-cc', job({
      id: 'task-done',
      status: 'completed',
      phase: 'completed',
      title: 'brief-view',
      startedAt: iso(-241000),
      completedAt: iso(-1000),
      checkResults: [
        { command: 'npm test', exitCode: 0 },
        { command: 'claude plugin test', exitCode: 0 },
      ],
    })),
  ]);
  await start($);
  const ui = await mountBand($);
  await firstTick(clock);

  const rows = await buttons(ui);
  expect(rows.length).toBe(1);
  expect(rows[0]?.text).toContain('✔');
  expect(rows[0]?.text).toContain('done 4m00s');
  expect(rows[0]?.text).toContain('checks 2/2');

  await clock.advance(70000);
  expect(await header(ui)).toBeUndefined();
  expect((await buttons(ui)).length).toBe(0);
  await ui.unmount();
});

test('a running task rewritten as completed with the same updatedAt shows done, then leaves after 60s', async ($, on) => {
  const staleUpdatedAt = iso(-5000);
  const files: JobFile[] = [
    file('gemini-plugin-cc', job({
      id: 'task-finish',
      status: 'running',
      phase: 'running',
      title: 'finish task',
      startedAt: iso(-10000),
      updatedAt: staleUpdatedAt,
    })),
  ];
  const { clock } = setup(on, files);
  await start($);
  const ui = await mountBand($);
  await firstTick(clock);

  let row = (await buttons(ui)).find(button => button.key === 'task:task-finish');
  expect(row?.text).toContain('●');
  expect(row?.text).not.toContain('done');

  // Same job, now completed, with a fresh mtime but the SAME stale updatedAt
  // (old records on disk never had their updatedAt stamped on write).
  files[0] = file('gemini-plugin-cc', job({
    id: 'task-finish',
    status: 'completed',
    phase: 'done',
    title: 'finish task',
    startedAt: iso(-10000),
    updatedAt: staleUpdatedAt,
    completedAt: iso(-4000),
  }), BASE + 3000);
  await clock.advance(2000);

  row = (await buttons(ui)).find(button => button.key === 'task:task-finish');
  expect(row).toBeDefined();
  expect(row?.text).toContain('✔');
  expect(row?.text).toContain('done');

  // More than 60s past completedAt: the finished row ages out of the band.
  await clock.advance(65000);
  expect(await header(ui)).toBeUndefined();
  expect((await buttons(ui)).length).toBe(0);
  await ui.unmount();
});

test('a check failure shows the failed marker and check failed', async ($, on) => {
  const { clock } = setup(on, [
    file('gemini-plugin-cc', job({
      id: 'task-fail',
      status: 'failed',
      phase: 'failed',
      title: 'pane review',
      errorMessage: 'check failed: npm test (exit 1)',
      checkResults: [{ command: 'npm test', exitCode: 1 }],
    })),
  ]);
  await start($);
  const ui = await mountBand($);
  await firstTick(clock);

  const rows = await buttons(ui);
  expect(rows.length).toBe(1);
  expect(rows[0]?.text).toContain('✖');
  expect(rows[0]?.text).toContain('check failed');
  await ui.unmount();
});

// ---- the band chain --------------------------------------------------------

test('a hook beneath the band still draws below-marker', async ($, on) => {
  const { clock } = setup(on, [file('gemini-plugin-cc', job({ id: 'task-chain' }))], true);
  await start($);
  const ui = await mountBand($);
  await firstTick(clock);

  expect((await buttons(ui)).length).toBe(1);
  expect((await ui.find({ type: 'Text', text: /below-marker/ }))).toBeDefined();
  await ui.unmount();
});

// ---- detail toggle ---------------------------------------------------------

test('pressing a row toggles its detail block', async ($, on) => {
  const { clock } = setup(on, [
    file('gemini-plugin-cc', job({
      id: 'task-detail',
      title: 'detail task',
      execution: { effort: 'high' },
      checkResults: [{ command: 'npm test', exitCode: 0 }],
      logFile: 'C:/data/state/gemini-plugin-cc/jobs/task-detail.log',
      errorMessage: null,
    })),
  ]);
  await start($);
  const ui = await mountBand($);
  await firstTick(clock);

  expect((await ui.find({ type: 'Text', text: /task-detail/ }))).toBeUndefined();
  await ui.press({ key: 'task:task-detail' });

  expect((await ui.find({ type: 'Text', text: /id\s+task-detail/ }))).toBeDefined();
  expect((await ui.find({ type: 'Text', text: /workspace/ }))).toBeDefined();
  expect((await ui.find({ type: 'Text', text: /PASS npm test/ }))).toBeDefined();
  expect((await ui.find({ type: 'Text', text: /effort\s+high/ }))).toBeDefined();
  expect((await ui.find({ type: 'Text', text: /task-detail\.log/ }))).toBeDefined();

  await ui.press({ key: 'task:task-detail' });
  expect((await ui.find({ type: 'Text', text: /id\s+task-detail/ }))).toBeUndefined();
  await ui.unmount();
});

// ---- poll interval ---------------------------------------------------------

test('polling slows to 15 seconds when nothing is running', async ($, on) => {
  const files: JobFile[] = [];
  const { clock } = setup(on, files);
  await start($);
  const ui = await mountBand($);

  await firstTick(clock);
  files.push(file('gemini-plugin-cc', job({ id: 'task-new', title: 'new dispatch' })));

  await clock.advance(12000);
  expect((await buttons(ui)).length).toBe(0);

  await clock.advance(4000);
  const rows = await buttons(ui);
  expect(rows.length).toBe(1);
  expect(rows[0]?.text).toContain('new dispatch');
  await ui.unmount();
});

// ---- the band hooks --------------------------------------------------------

test('the mod registers one session.start and one AbovePrompt hook, with no catch-all matchers', async () => {
  const seen: { event: string; matcher?: unknown }[] = [];
  const fakeOn = (event: string, matcher?: unknown) => {
    seen.push({ event, matcher });
    return { catch() {} };
  };
  register(fakeOn as never);

  expect(seen.map(entry => entry.event)).toEqual(['session.start', 'ui.render']);
  expect(seen.filter(entry => entry.event === 'session.start')).toHaveLength(1);
  expect(seen.filter(entry => entry.event === 'ui.render')).toHaveLength(1);
  for (const entry of seen) {
    const matcher = entry.matcher;
    const isCatchAll = matcher instanceof RegExp
      || (!!matcher && typeof matcher === 'object'
        && Object.values(matcher as Record<string, unknown>).some(value => value instanceof RegExp));
    expect(isCatchAll).toBe(false);
  }
  // workers.tsx exports plain functions, not a hooks module.
  expect((workerParts as Record<string, unknown>).register).toBeUndefined();
});

// ---- colour, border and stall ----------------------------------------------

const borderOf = (tree: unknown) =>
  nodeWhere(tree, node => node.props?.borderStyle === 'round')?.props?.borderColor;

test('the workers band is round with a cyan border while running', async ($, on) => {
  const { clock } = setup(on, [file('gemini-plugin-cc', job({ id: 'task-run', status: 'running', phase: 'running' }))]);
  await start($);
  const ui = await mountBand($);
  await firstTick(clock);
  expect(borderOf(await ui.drawn())).toBe('cyan');
  await ui.unmount();
});

test('the workers band border turns red after a failure', async ($, on) => {
  const { clock } = setup(on, [file('gemini-plugin-cc', job({
    id: 'task-fail', status: 'failed', phase: 'failed',
    checkResults: [{ command: 'npm test', exitCode: 1 }],
  }))]);
  await start($);
  const ui = await mountBand($);
  await firstTick(clock);
  expect(borderOf(await ui.drawn())).toBe('red');
  await ui.unmount();
});

test('the band border turns green when every worker finished cleanly', async ($, on) => {
  const { clock } = setup(on, [file('gemini-plugin-cc', job({
    id: 'task-done', status: 'completed', phase: 'done',
  }))]);
  await start($);
  const ui = await mountBand($);
  await firstTick(clock);
  expect(borderOf(await ui.drawn())).toBe('green');
  await ui.unmount();
});

test('a role always maps to the same colour', async ($, on) => {
  const { clock } = setup(on, [
    file('gemini-plugin-cc', job({ id: 'task-a', role: 'writer' })),
    file('gemini-plugin-cc', job({ id: 'task-b', role: 'planner' })),
    file('gemini-plugin-cc', job({ id: 'task-c', role: 'writer' })),
  ]);
  await start($);
  const ui = await mountBand($);
  await firstTick(clock);
  const roleTexts = (await ui.findAll({ type: 'Text' }))
    .filter(text => ['writer', 'planner'].includes(text.text.trim()));
  const writerColours = roleTexts.filter(text => text.text.trim() === 'writer').map(text => text.props.color);
  expect(writerColours.length).toBeGreaterThan(1);
  expect(new Set(writerColours).size).toBe(1);
  expect(roleTexts.some(text => text.text.trim() === 'planner' && text.props.color)).toBe(true);
  await ui.unmount();
});

test('a running task shows a yellow quiet marker four minutes after its last event', async ($, on) => {
  const { clock } = setup(on, [file('gemini-plugin-cc', job({
    id: 'task-quiet', status: 'running', phase: 'running', startedAt: iso(-300000),
  }))], undefined, { 'task-quiet': iso(-240000) });
  await start($);
  const ui = await mountBand($);
  await firstTick(clock);
  expect((await buttons(ui)).find(button => button.key === 'task:task-quiet')?.text).toContain('⚠ quiet 4m');
  const yellow = (await ui.findAll({ type: 'Text' }))
    .filter(text => text.props.color === 'yellow');
  expect(yellow.some(text => text.text.includes('quiet 4m'))).toBe(true);
  await ui.unmount();
});

test('a task in checking shows running checks instead of a quiet marker', async ($, on) => {
  const { clock } = setup(on, [file('gemini-plugin-cc', job({
    id: 'task-checks', status: 'running', phase: 'checking', startedAt: iso(-80000),
  }))], undefined, { 'task-checks': iso(-200000) });
  await start($);
  const ui = await mountBand($);
  await firstTick(clock);
  const row = (await buttons(ui)).find(button => button.key === 'task:task-checks');
  expect(row?.text).toContain('running checks');
  expect(row?.text).not.toContain('quiet');
  await ui.unmount();
});

test('no workers line exceeds bodyColumns minus the border, and the band sketch is drawn', async ($, on) => {
  const { clock } = setup(on, [
    file('gemini-plugin-cc', job({ id: 'task-sketch', status: 'running', phase: 'running', title: 'a long task title that should be clipped to the column width' })),
  ], true);
  await start($);
  const ui = await mountBand($);
  await firstTick(clock);

  const lines = sketch(await ui.drawn(), 120);
  for (const line of lines) expect(line.length).toBeLessThanOrEqual(120);
  for (const button of await buttons(ui)) expect(button.text.length).toBeLessThanOrEqual(118);
  console.log('\n=== BAND SKETCH 120 ===');
  for (const line of lines) console.log(line);
  console.log('=== END BAND SKETCH ===');
  await ui.unmount();
});
