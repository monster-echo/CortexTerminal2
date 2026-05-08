import { SuccessResponseSchema } from "../../schemas/bridgeSchema";
import { invoke } from "../runtime";

export const integrationBridge = {
  openExternalLink: (url: string) =>
    invoke("OpenExternalLinkAsync", SuccessResponseSchema, [url]),
  shareText: (title: string, text: string) =>
    invoke("ShareTextAsync", SuccessResponseSchema, [title, text]),
  composeSupportEmail: (subject: string, body: string, recipient?: string) =>
    invoke("ComposeSupportEmailAsync", SuccessResponseSchema, [
      subject,
      body,
      recipient ?? null,
    ]),
};
