export type MeterRow = { label: string; tokens: number; color: string }
export type Snapshot = { used: number; window: number; percent: number; rows: MeterRow[] }

declare module 'claude-code' {
  interface PluginState {
    'context-meter': { snapshot: Snapshot | null }
  }
}
