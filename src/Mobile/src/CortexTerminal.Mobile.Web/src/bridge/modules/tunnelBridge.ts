import { SuccessResponseSchema } from "../../schemas/bridgeSchema";
import { TunnelListResponseSchema, TunnelSchema } from "../../schemas/tunnelSchema";
import { invoke } from "../runtime";

export const tunnelBridge = {
  createTunnel: (sessionId: string, port: number) =>
    invoke("CreateTunnelAsync", TunnelSchema, [sessionId, port], { timeoutMs: 30000 }),

  listTunnels: (sessionId: string) =>
    invoke("ListTunnelsAsync", TunnelListResponseSchema, [sessionId]),

  revokeTunnel: (tunnelId: string) =>
    invoke("RevokeTunnelAsync", SuccessResponseSchema, [tunnelId]),
};
