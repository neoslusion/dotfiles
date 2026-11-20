// Copied from gemini-plugin-cc/plugins/agent-delegation/hooks/workers.tsx; keep in sync until the band is synced back into the plugin.
import { atom, read, update } from 'claude-code';
import type { EngineInterface, RenderInput, Timer } from 'claude-code';
import type { WorkerTaskView, WorkersViewState } from '../types';

const ACTIVE_MS = 2000;
const IDLE_MS = 15000;
const FINISHED_MS = 60000;
const DAY_MS = 24 * 60 * 60 * 1000;
const MAX_ROWS = 6;
const MAX_FILES = 50;

const workersView = atom(
  { plugin: 'delegation-workers', key: 'workersView' } as const,
  { openTaskId: '', tasks: [], nowMs: 0 } as WorkersViewState,
);

type CheckResult = WorkerTaskView['checks'][number];

type Job = {
  id?: string;
  sessionId?: string;
  role?: string;
  executor?: string;
  model?: string;
  execution?: { effort?: string; role?: string; executor?: string; model?: string };
  status?: string;
  phase?: string;
  title?: string;
  request?: string;
  startedAt?: string;
  completedAt?: string;
  cancelledAt?: string;
  updatedAt?: string;
  workspaceRoot?: string;
  checks?: unknown[];
  checkResults?: CheckResult[];
  errorMessage?: string | null;
  logFile?: string;
};

type Task = WorkerTaskView & { sessionId: string };

type Scan = { tasks: Task[]; nowMs: number; active: number };
type CacheEntry = { mtimeMs: number; updatedAt: string; task: Task | null };
type Ctx = {
  timer?: Timer;
  interval: number;
  cache: Map<string, CacheEntry>;
  active: number;
};

// A session owns one context. A fresh session (and a hot reload) resets it,
// so an old timer or parse cache never leaks into the new one.
let ctx: Ctx = { interval: ACTIVE_MS, cache: new Map(), active: 0 };
const resetCtx = (): void => {
  ctx = { interval: ACTIVE_MS, cache: new Map(), active: 0 };
};

const joinPath = (base: string, name: string): string =>
  `${base.replace(/[\\/]+$/, '')}/${name}`;

const short = (text: string, max: number): string =>
  text.length > max ? `${text.slice(0, Math.max(0, max - 1))}…` : text;

const pad = (text: string, width: number): string => text + ' '.repeat(Math.max(0, width - text.length));

const basename = (path: string): string => path.split(/[\\/]/).filter(Boolean).pop() ?? '';

const fmtElapsed = (ms: number): string => {
  const total = Math.max(0, Math.floor(ms / 1000));
  if (total < 60) return `${total}s`;
  if (total < 3600) return `${Math.floor(total / 60)}m${String(total % 60).padStart(2, '0')}s`;
  return `${Math.floor(total / 3600)}h${String(Math.floor(total / 60) % 60).padStart(2, '0')}m`;
};

const MARKER: Record<string, string> = {
  running: '●',
  queued: '◌',
  completed: '✔',
  failed: '✖',
  cancelled: '■',
};

const MARKER_COLOR: Record<string, string> = {
  running: 'cyan',
  queued: 'yellow',
  completed: 'green',
  failed: 'red',
};

const PROVIDER_COLOR: Record<string, string> = {
  opencode: 'blue',
  codex: 'green',
  claude: 'magenta',
  agy: 'yellow',
};

const PHASE_COLOR: Record<string, string> = {
  running: 'cyan',
  checking: 'yellow',
  done: 'green',
  failed: 'red',
};

const ROLE_PALETTE = ['magenta', 'blue', 'cyan', 'yellow', 'green'] as const;

/** A small stable hash: the same role always draws in the same colour. */
export function roleColor(role: string): string {
  let hash = 0;
  for (const char of role) hash = (hash * 31 + char.charCodeAt(0)) >>> 0;
  return ROLE_PALETTE[hash % ROLE_PALETTE.length] ?? 'blue';
}

/** Read only the newest event file beside the job, never the whole log. */
async function lastEventAt(
  $: EngineInterface,
  root: string,
  id: string,
  nowMs: number,
): Promise<number> {
  if (!id) return nowMs;
  const dir = joinPath(joinPath(root, 'events'), id);
  let files: readonly { name: string; kind: string; mtimeMs: number }[];
  try {
    files = await $.fs.list(dir);
  } catch {
    return nowMs;
  }
  const names = files
    .filter(file => file.kind === 'file' && /^\d+\.json$/.test(file.name))
    .sort((a, b) => Number(a.name.slice(0, -5)) - Number(b.name.slice(0, -5)));
  const last = names[names.length - 1];
  if (!last) return nowMs;
  try {
    const event = JSON.parse(await $.fs.read(joinPath(dir, last.name))) as { createdAt?: string };
    return Date.parse(String(event.createdAt ?? '')) || nowMs;
  } catch {
    return nowMs;
  }
}

// Resolve the agent-delegation plugin's data dir, not this mod's: the task
// files are written by that plugin, so CLAUDE_PLUGIN_DATA is deliberately not
// consulted here (it would point at this mod's own directory).
async function resolveDataRoot($: EngineInterface): Promise<{ root: string; error: string }> {
  const configured = await $.env.get('CLAUDE_CONFIG_DIR');
  const profile = await $.env.get('USERPROFILE');
  const home = profile || await $.env.get('HOME');
  if (!configured && !home) {
    return { root: '', error: 'CLAUDE_CONFIG_DIR, USERPROFILE and HOME are all unset; cannot locate the plugin data directory' };
  }
  const base = joinPath(configured || joinPath(home ?? '', '.claude'), 'plugins/data');
  // This mod reads the agent-delegation plugin's data dir, never its own.
  const prefix = 'agent-delegation-';
  let names: readonly string[] = [];
  try {
    names = (await $.fs.list(base)).map(entry => entry.name);
  } catch {
    names = [];
  }
  const matches = names.filter(name => name.startsWith(prefix));
  if (matches.length === 1) return { root: joinPath(base, matches[0] ?? ''), error: '' };
  const found = matches.length ? matches.join(', ') : 'none';
  return {
    root: '',
    error: `Cannot pick a delegation data directory in ${base}: found ${found}. Keep exactly one ${prefix}* directory.`,
  };
}

// Returns the task only when it belongs to this session and is either active
// or finished within the last minute.
function toTask(job: Job, sessionId: string, nowMs: number, lastEventMs: number): Task | null {
  if (!job || job.sessionId !== sessionId) return null;
  const status = String(job.status ?? 'queued');
  const active = status === 'queued' || status === 'running';
  const startedMs = Date.parse(String(job.startedAt ?? job.updatedAt ?? '')) || nowMs;
  const finishedMs = active
    ? 0
    : (Date.parse(String(job.completedAt ?? job.cancelledAt ?? job.updatedAt ?? '')) || nowMs);
  if (!active && nowMs - finishedMs > FINISHED_MS) return null;

  const executor = String(job.executor ?? job.execution?.executor ?? '');
  const rawModel = String(job.model ?? job.execution?.model ?? '');
  const model = rawModel && executor && !rawModel.startsWith(`${executor}/`)
    ? `${executor}/${rawModel}`
    : (rawModel || executor);

  const checks = Array.isArray(job.checkResults) ? job.checkResults : [];
  const done = checks.filter(check => typeof check.exitCode === 'number');
  const passed = done.filter(check => check.exitCode === 0 && !check.timedOut).length;
  const error = String(job.errorMessage ?? '');
  const checkFailed = done.length > passed || /check failed/i.test(error);

  return {
    id: String(job.id ?? ''),
    sessionId,
    role: String(job.role ?? job.execution?.role ?? 'worker'),
    model,
    effort: String(job.execution?.effort ?? ''),
    title: String(job.title ?? job.request ?? job.id ?? '').replace(/\s*\n\s*/g, ' ').trim(),
    status,
    phase: String(job.phase ?? (status === 'queued' ? 'queued' : 'running')),
    lastEventMs,
    startedMs,
    finishedMs,
    workspace: String(job.workspaceRoot ?? ''),
    checks,
    passed,
    checkFailed,
    error,
    logFile: String(job.logFile ?? ''),
  };
}

// A cached file still has to leave the view once its finished row ages out.
const stillVisible = (task: Task, sessionId: string, nowMs: number): boolean =>
  task.sessionId === sessionId
  && (task.status === 'queued' || task.status === 'running' || nowMs - task.finishedMs <= FINISHED_MS);

async function scan($: EngineInterface): Promise<Scan> {
  const { root } = await resolveDataRoot($);
  ctx.active = 0;
  if (!root) return { tasks: [], nowMs: 0, active: 0 };

  let workspaces: readonly { name: string; kind: string }[];
  try {
    workspaces = await $.fs.list(joinPath(root, 'state'));
  } catch {
    return { tasks: [], nowMs: 0, active: 0 };
  }

  // Collect candidate paths first. With no jobs there is no need to read the
  // clock (other plugins may draw the same band without a mocked clock).
  const candidates: { path: string; file: { name: string; kind: string; mtimeMs: number } }[] = [];
  for (const ws of workspaces) {
    if (ws.kind !== 'dir') continue;
    const jobsDir = joinPath(joinPath(joinPath(root, 'state'), ws.name), 'jobs');
    let files: readonly { name: string; kind: string; mtimeMs: number }[];
    try {
      files = await $.fs.list(jobsDir);
    } catch {
      continue;
    }
    for (const file of files) {
      if (file.kind === 'file' && file.name.endsWith('.json')) {
        candidates.push({ path: joinPath(jobsDir, file.name), file });
      }
    }
  }
  if (!candidates.length) return { tasks: [], nowMs: 0, active: 0 };

  const sessionId = await $.session.id();
  const nowMs = await $.clock.now();
  const cutoff = nowMs - DAY_MS;
  const tasks: Task[] = [];
  const live = new Set<string>();
  let parsed = 0;

  for (const { path, file } of candidates) {
    const cached = ctx.cache.get(path);

    // A stat mtime from fs.list is enough to skip the file entirely.
    if (cached && file.mtimeMs > 0 && cached.mtimeMs === file.mtimeMs) {
      live.add(path);
      if (cached.task && stillVisible(cached.task, sessionId, nowMs)) tasks.push(cached.task);
      continue;
    }
    if (file.mtimeMs > 0 && file.mtimeMs < cutoff) continue;
    if (parsed >= MAX_FILES) continue;
    parsed += 1;

    let job: Job;
    try {
      job = JSON.parse(await $.fs.read(path)) as Job;
    } catch {
      ctx.cache.delete(path);
      continue;
    }
    const updatedAt = String(job.updatedAt ?? '');
    // Old records carry a stale updatedAt, so it is not a safe change marker.
    // Once the file has been re-read (its mtime changed), always rebuild the
    // task with toTask rather than reusing the cached, possibly running one.
    const finishedAt = String(job.completedAt ?? job.cancelledAt ?? '');
    const markAt = finishedAt || updatedAt;
    if (markAt && Date.parse(markAt) < cutoff) continue;

    live.add(path);
    const lastEventMs = await lastEventAt($, root, String(job.id ?? ''), nowMs);
    const task = toTask(job, sessionId, nowMs, lastEventMs);
    ctx.cache.set(path, { mtimeMs: file.mtimeMs, updatedAt, task });
    if (task) tasks.push(task);
  }
  for (const key of [...ctx.cache.keys()]) if (!live.has(key)) ctx.cache.delete(key);

  const active = tasks.filter(task => task.status === 'queued' || task.status === 'running').length;
  ctx.active = active;
  return { tasks, nowMs, active };
}

// Keep polling, switching between a fast tick while work is active and a slow
// tick that still notices new dispatches once the session is quiet.
function schedule($: EngineInterface): void {
  ctx.timer = $.clock.after(ctx.interval, () => {
    void (async () => {
      try {
        const result = await scan($);
        ctx.interval = result.active > 0 ? ACTIVE_MS : IDLE_MS;
        await update($, workersView, current => ({
          ...current,
          nowMs: result.nowMs,
          tasks: result.tasks.map(({ sessionId: _sessionId, ...view }) => view),
        }));
      } catch {
        // A failed poll must not stop the timer chain.
      }
      schedule($);
    })();
  });
}

function ensureTimer($: EngineInterface): void {
  if (!ctx.timer) schedule($);
}

/** Called once from this mod's single session.start hook. */
export function startWorkersPolling($: EngineInterface): void {
  resetCtx();
  try {
    ensureTimer($);
  } catch {
    // Timers are optional for a surface that cannot host them.
  }
}

/**
 * Draw the live workers band, or null when there is nothing to show. This is
 * wrapped by the single AbovePrompt hook in register.tsx.
 */
export async function renderWorkers(
  $: EngineInterface,
  e: RenderInput<'AbovePrompt'>,
): Promise<JSX.Element | null> {
  if (e.props.hasSurvey) return null;

  // The timer owns all I/O; the render only draws cached rows. Keeping this
  // read-only also lets other plugins share the same band in tests.
  const state = await read($, workersView);
  const tasks = state.tasks;
  if (!tasks.length) return null;

  const { Box, Button, Text } = $.ui.resolve(e);
  const columns = Math.max(40, e.props.bodyColumns > 0 ? e.props.bodyColumns : 120);
  const maxLine = columns - 2; // two cells are taken by the round border
  const nowMs = state.nowMs;
  const active = tasks.filter(task => task.status === 'queued' || task.status === 'running').length;
  const running = tasks.filter(task => task.status === 'running').length;
  const queued = tasks.filter(task => task.status === 'queued').length;
  const header = active
    ? `Delegation workers · ${running} running · ${queued} queued`
    : `Delegation workers · ${tasks.length} recently finished`;
  const failed = tasks.some(task => task.status === 'failed' || task.checkFailed);
  const borderColor = failed ? 'red' : active ? 'cyan' : 'green';

  const priority = (task: WorkerTaskView): number =>
    task.status === 'running' ? 0 : task.status === 'queued' ? 1 : 2;
  const ordered = [...tasks].sort((a, b) =>
    priority(a) - priority(b) || b.startedMs - a.startedMs);
  const shown = ordered.slice(0, MAX_ROWS);
  const more = ordered.length - shown.length;

  const quietText = (ms: number): string => {
    const total = Math.max(0, Math.floor(ms / 1000));
    if (total < 60) return `${total}s`;
    if (total < 3600) return `${Math.floor(total / 60)}m`;
    return `${Math.floor(total / 3600)}h${String(Math.floor(total / 60) % 60).padStart(2, '0')}m`;
  };

  type Cell = { text: string; color?: string; dim?: boolean; bold?: boolean };
  type Row = {
    task: WorkerTaskView;
    icon: Cell;
    role: Cell;
    model: string;
    effort: Cell;
    title: string;
    elapsed: Cell;
    time: Cell;
    phase: Cell;
  };

  const rowsData: Row[] = shown.map(task => {
    const quiet = Math.max(0, nowMs - task.lastEventMs);
    let time: Cell;
    if (task.status === 'running') {
      if (task.phase === 'checking') {
        time = { text: `running checks ${fmtElapsed(nowMs - task.startedMs)}`, color: 'yellow' };
      } else if (quiet >= 10 * 60 * 1000) {
        time = { text: `⚠ quiet ${quietText(quiet)}`, color: 'red' };
      } else if (quiet >= 3 * 60 * 1000) {
        time = { text: `⚠ quiet ${quietText(quiet)}`, color: 'yellow' };
      } else {
        time = { text: `active ${quietText(quiet)} ago`, dim: true };
      }
    } else if (task.status === 'queued') {
      time = { text: 'queued', color: 'yellow' };
    } else if (task.status === 'completed') {
      time = {
        text: `done ${fmtElapsed(task.finishedMs - task.startedMs)}`
          + (task.checks.length ? ` · checks ${task.passed}/${task.checks.length}` : ''),
        color: 'green',
      };
    } else if (task.status === 'failed') {
      time = {
        text: task.checkFailed
          ? 'check failed'
          : `failed ${fmtElapsed(task.finishedMs - task.startedMs)}`,
        color: 'red',
      };
    } else {
      time = { text: 'cancelled', dim: true };
    }

    return {
      task,
      icon: {
        text: MARKER[task.status] ?? ' ',
        color: MARKER_COLOR[task.status],
        dim: task.status === 'cancelled',
      },
      role: { text: task.role, color: roleColor(task.role), bold: true },
      model: task.model,
      effort: { text: `effort ${task.effort || '—'}`, dim: true },
      title: task.title + (task.workspace ? ` (${basename(task.workspace)})` : ''),
      elapsed: task.status === 'running'
        ? { text: fmtElapsed(nowMs - task.startedMs), dim: true }
        : { text: '' },
      time,
      phase: task.status === 'running'
        ? { text: task.phase, color: PHASE_COLOR[task.phase] }
        : { text: '' },
    };
  });

  // Pad before colouring, so a coloured cell keeps its column width.
  const iconW = 2;
  const roleW = Math.min(16, Math.max(5, ...rowsData.map(row => row.role.text.length)));
  let modelW = Math.min(28, Math.max(5, ...rowsData.map(row => row.model.length)));
  const effortW = Math.min(12, Math.max(8, ...rowsData.map(row => row.effort.text.length)));
  const elapsedW = Math.min(9, Math.max(5, ...rowsData.map(row => row.elapsed.text.length || 5)));
  const timeW = Math.min(26, Math.max(12, ...rowsData.map(row => row.time.text.length)));
  const phaseW = Math.min(10, Math.max(2, ...rowsData.map(row => row.phase.text.length)));
  const gap = 2;
  const fixed = () => iconW + roleW + modelW + effortW + elapsedW + timeW + phaseW + gap * 7;
  if (fixed() > maxLine) modelW = Math.max(5, modelW - (fixed() - maxLine));
  const titleW = Math.max(0, maxLine - fixed());

  const rows: JSX.Element[] = [];
  for (const row of rowsData) {
    const modelCell = pad(short(row.model, modelW), modelW);
    const slash = modelCell.indexOf('/');
    const provider = slash > 0 && PROVIDER_COLOR[modelCell.slice(0, slash)]
      ? modelCell.slice(0, slash + 1) : '';
    const pieces: { text: string; cell?: Cell }[] = [
      { text: pad(row.icon.text, iconW), cell: row.icon },
      { text: '  ' },
      { text: pad(short(row.role.text, roleW), roleW), cell: row.role },
      { text: '  ' },
      ...(provider
        ? [
          { text: provider, cell: { text: provider, color: PROVIDER_COLOR[modelCell.slice(0, slash)] } },
          { text: modelCell.slice(provider.length) },
        ]
        : [{ text: modelCell }]),
      { text: '  ' },
      { text: pad(short(row.effort.text, effortW), effortW), cell: row.effort },
      { text: '  ' },
      { text: pad(short(row.title, titleW), titleW) },
      { text: '  ' },
      { text: pad(short(row.elapsed.text, elapsedW), elapsedW), cell: row.elapsed },
      { text: '  ' },
      { text: pad(short(row.time.text, timeW), timeW), cell: row.time },
      { text: '  ' },
      { text: pad(short(row.phase.text, phaseW), phaseW), cell: row.phase },
    ];
    const label = pieces.map(piece => piece.text).join('');
    const children: JSX.Element[] = pieces.map((piece, index) => {
      const cell = piece.cell;
      return cell
        ? <Text key={`c${index}`} bold={cell.bold} dimColor={cell.dim} color={cell.color}>{piece.text}</Text>
        : <Text key={`s${index}`}>{piece.text}</Text>;
    });

    rows.push(
      <Button
        key={`task:${row.task.id}`}
        plain
        label={label}
        onPress={() => {
          void update($, workersView, current => ({
            ...current,
            openTaskId: current.openTaskId === row.task.id ? '' : row.task.id,
          }));
        }}
      >
        {...children}
      </Button>,
    );

    if (state.openTaskId === row.task.id) {
      const task = row.task;
      const detail = [
        `  id        ${task.id}`,
        `  workspace ${task.workspace}`,
        `  model     ${task.model}`,
        `  effort    ${task.effort || '—'}`,
        ...task.checks.map(check =>
          `  ${check.exitCode === 0 && !check.timedOut ? 'PASS' : 'FAIL'} ${check.command ?? 'check'}`),
        ...(task.error ? [`  error     ${task.error}`] : []),
        ...(task.logFile ? [`  log       ${task.logFile}`] : []),
      ];
      detail.forEach((text, index) => {
        rows.push(<Text key={`detail:${task.id}:${index}`} dimColor>{short(text, maxLine)}</Text>);
      });
    }
  }

  if (more > 0) rows.push(<Text key="more" dimColor>{`… ${more} more`}</Text>);

  return (
    <Box flexDirection="column" borderStyle="round" borderColor={borderColor}>
      <Text key="header" bold color={borderColor}>{short(header, maxLine)}</Text>
      <Box key="rows" flexDirection="column" columnGap={2}>{...rows}</Box>
    </Box>
  );
}
