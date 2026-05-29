import { create } from "zustand";
import type { TerminalSession, WorkerSummary } from "../schemas/sessionSchema";

export interface SessionState {
  recentSessions: TerminalSession[];
  workers: WorkerSummary[];
  isGatewayLoaded: boolean;
  setSessions: (sessions: TerminalSession[]) => void;
  setWorkers: (workers: WorkerSummary[]) => void;
  setGatewayLoaded: (value: boolean) => void;
  removeSession: (sessionId: string) => void;
}

export const useSessionStore = create<SessionState>((set) => ({
  recentSessions: [],
  workers: [],
  isGatewayLoaded: false,
  setSessions: (recentSessions) =>
    set((state) => {
      return {
        recentSessions: recentSessions,
      };
    }),
  setWorkers: (workers) => set({ workers }),
  setGatewayLoaded: (isGatewayLoaded) => set({ isGatewayLoaded }),

  removeSession: (sessionId) =>
    set((state) => {
      const filtered = state.recentSessions.filter((s) => s.id !== sessionId);
      return {
        recentSessions: filtered,
      };
    }),
}));
