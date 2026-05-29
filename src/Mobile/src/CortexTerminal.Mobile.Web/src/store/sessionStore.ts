import { create } from "zustand";
import type { TerminalSession, WorkerSummary } from "../schemas/sessionSchema";

export interface SessionState {
  currentSessionId: string | null;
  recentSessions: TerminalSession[];
  workers: WorkerSummary[];
  isGatewayLoaded: boolean;
  setCurrentSession: (sessionId: string | null) => void;
  setSessions: (sessions: TerminalSession[]) => void;
  setWorkers: (workers: WorkerSummary[]) => void;
  setGatewayLoaded: (value: boolean) => void;
  removeSession: (sessionId: string) => void;
}

export const useSessionStore = create<SessionState>((set) => ({
  currentSessionId: null,
  recentSessions: [],
  workers: [],
  isGatewayLoaded: false,
  setCurrentSession: (currentSessionId) => set({ currentSessionId }),
  setSessions: (recentSessions) =>
    set((state) => {
      const sorted = recentSessions;
      return {
        recentSessions: recentSessions,
        currentSessionId:
          state.currentSessionId &&
          sorted.some((session) => session.id === state.currentSessionId)
            ? state.currentSessionId
            : (sorted[0]?.id ?? null),
      };
    }),
  setWorkers: (workers) => set({ workers }),
  setGatewayLoaded: (isGatewayLoaded) => set({ isGatewayLoaded }),

  removeSession: (sessionId) =>
    set((state) => {
      const filtered = state.recentSessions.filter((s) => s.id !== sessionId);
      return {
        recentSessions: filtered,
        currentSessionId:
          state.currentSessionId === sessionId
            ? (filtered[0]?.id ?? null)
            : state.currentSessionId,
      };
    }),
}));
