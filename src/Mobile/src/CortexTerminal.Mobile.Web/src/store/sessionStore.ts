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
  touchSession: (session: TerminalSession) => void;
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
      const sorted = [...recentSessions].sort((a, b) =>
        new Date(b.updatedAt).getTime() - new Date(a.updatedAt).getTime(),
      );
      return {
        recentSessions: sorted,
        currentSessionId:
          state.currentSessionId &&
          sorted.some((session) => session.id === state.currentSessionId)
            ? state.currentSessionId
            : sorted[0]?.id ?? null,
      };
    }),
  setWorkers: (workers) => set({ workers }),
  setGatewayLoaded: (isGatewayLoaded) => set({ isGatewayLoaded }),
  touchSession: (session) =>
    set((state) => ({
      currentSessionId: session.id,
      recentSessions: [
        session,
        ...state.recentSessions.filter((item) => item.id !== session.id),
      ],
    })),
  removeSession: (sessionId) =>
    set((state) => {
      const filtered = state.recentSessions.filter((s) => s.id !== sessionId);
      return {
        recentSessions: filtered,
        currentSessionId:
          state.currentSessionId === sessionId
            ? filtered[0]?.id ?? null
            : state.currentSessionId,
      };
    }),
}));
