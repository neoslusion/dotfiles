export type ReplyStamp = number | null

declare module 'claude-code' {
  interface PluginState {
    'cache-timer': { lastReplyAt: ReplyStamp; now: number }
  }
}
