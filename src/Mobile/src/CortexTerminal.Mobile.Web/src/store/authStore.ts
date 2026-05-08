import { create } from "zustand";

export interface AuthUser {
  username: string;
}

export interface AuthState {
  user: AuthUser | null;
  token: string | null;
  isLoggedIn: boolean;
  isLoading: boolean;
  setSession: (user: AuthUser, token: string) => void;
  clearSession: () => void;
  setLoading: (loading: boolean) => void;
}

export const useAuthStore = create<AuthState>((set) => ({
  user: null,
  token: null,
  isLoggedIn: false,
  isLoading: true,
  setSession: (user, token) => set({ user, token, isLoggedIn: true, isLoading: false }),
  clearSession: () => set({ user: null, token: null, isLoggedIn: false, isLoading: false }),
  setLoading: (isLoading) => set({ isLoading }),
}));
