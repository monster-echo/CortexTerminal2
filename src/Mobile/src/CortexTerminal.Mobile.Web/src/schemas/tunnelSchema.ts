import { z } from "zod";

export const TunnelSchema = z.object({
  tunnelId: z.string(),
  tunnelKey: z.string(),
  port: z.number(),
  sessionId: z.string(),
  workerId: z.string(),
  url: z.string(),
  secret: z.string().nullable().optional(),
  expiresAtUtc: z.string(),
  createdAtUtc: z.string(),
});

export type Tunnel = z.infer<typeof TunnelSchema>;

export const TunnelListResponseSchema = z.object({
  tunnels: z.array(TunnelSchema),
});
