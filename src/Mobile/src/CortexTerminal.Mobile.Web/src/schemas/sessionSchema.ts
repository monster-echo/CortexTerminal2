import { z } from "zod";

export const SessionStatusSchema = z.enum([
  "idle",
  "running",
  "waiting",
  "failed",
]);

export const TerminalSessionSchema = z.object({
  id: z.string(),
  title: z.string(),
  subtitle: z.string().nullable().optional(),
  cwd: z.string().nullable().optional(),
  status: SessionStatusSchema,
  updatedAt: z.string(),
  pinned: z.boolean().default(false),
  workerId: z.string().nullable().optional(),
  gatewayStatus: z.string().nullable().optional(),
});

export const TerminalSessionsSchema = z.array(TerminalSessionSchema);

export const WorkerStatusSchema = z.enum([
  "idle",
  "running",
  "offline",
]);

export const WorkerSummarySchema = z.object({
  id: z.string(),
  name: z.string(),
  status: WorkerStatusSchema,
  activeTask: z.string().optional(),
  workerId: z.string().optional(),
  hostname: z.string().nullable().optional(),
  operatingSystem: z.string().nullable().optional(),
  architecture: z.string().nullable().optional(),
  version: z.string().nullable().optional(),
  sessionCount: z.number().optional(),
  address: z.string().nullable().optional(),
  lastSeenAtUtc: z.string().nullable().optional(),
});

export const WorkerSummariesSchema = z.array(WorkerSummarySchema);

export type SessionStatus = z.infer<typeof SessionStatusSchema>;
export type TerminalSession = z.infer<typeof TerminalSessionSchema>;
export type WorkerStatus = z.infer<typeof WorkerStatusSchema>;
export type WorkerSummary = z.infer<typeof WorkerSummarySchema>;
