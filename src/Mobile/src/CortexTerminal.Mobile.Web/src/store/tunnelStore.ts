import { create } from "zustand";
import type { Tunnel } from "../schemas/tunnelSchema";

interface TunnelState {
  bySession: Record<string, Tunnel[]>;
  setTunnels: (sessionId: string, tunnels: Tunnel[]) => void;
  upsertTunnel: (sessionId: string, tunnel: Tunnel) => void;
  removeTunnel: (sessionId: string, tunnelId: string) => void;
  clearSessionTunnels: (sessionId: string) => void;
}

export const useTunnelStore = create<TunnelState>((set) => ({
  bySession: {},
  setTunnels: (sessionId, tunnels) =>
    set((s) => ({ bySession: { ...s.bySession, [sessionId]: tunnels } })),
  upsertTunnel: (sessionId, tunnel) =>
    set((s) => {
      const current = s.bySession[sessionId] ?? [];
      const idx = current.findIndex((t) => t.tunnelId === tunnel.tunnelId);
      const next = idx >= 0
        ? current.map((t, i) => (i === idx ? tunnel : t))
        : [...current, tunnel];
      return { bySession: { ...s.bySession, [sessionId]: next } };
    }),
  removeTunnel: (sessionId, tunnelId) =>
    set((s) => {
      const current = s.bySession[sessionId] ?? [];
      return { bySession: { ...s.bySession, [sessionId]: current.filter((t) => t.tunnelId !== tunnelId) } };
    }),
  clearSessionTunnels: (sessionId) =>
    set((s) => {
      const next = { ...s.bySession };
      delete next[sessionId];
      return { bySession: next };
    }),
}));

export const selectTunnelsForSession = (sessionId: string) => (s: TunnelState) =>
  s.bySession[sessionId] ?? [];
