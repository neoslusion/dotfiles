/** One row of the live delegation-workers band. */
export type WorkerTaskView = {
  id: string;
  role: string;
  model: string;
  effort: string;
  title: string;
  status: string;
  phase: string;
  /** Timestamp of the newest event in the task's events directory. */
  lastEventMs: number;
  startedMs: number;
  finishedMs: number;
  workspace: string;
  checks: { command?: string; exitCode?: number; timedOut?: boolean }[];
  passed: number;
  checkFailed: boolean;
  error: string;
  logFile: string;
};

/** Cached worker rows, elapsed reference and the open detail row. */
export type WorkersViewState = {
  openTaskId: string;
  tasks: WorkerTaskView[];
  nowMs: number;
};

declare module 'claude-code' {
  interface PluginState {
    'delegation-workers': { workersView: WorkersViewState }
  }
}
