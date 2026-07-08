import { invoke } from "../runtime";
import {
  SupportInfoSchema,
  FeedbackSubmitResponseSchema,
  FeedbackFilePickResponseSchema,
  type SupportInfo,
} from "../../schemas/bridgeSchema";

export const supportBridge = {
  getSupportInfo: (): Promise<SupportInfo | null> =>
    invoke("GetSupportInfoAsync", SupportInfoSchema.nullable(), [], { timeoutMs: 12000 }),

  pickFile: (): Promise<{ imageUrl: string; filename: string } | null> =>
    invoke("PickFeedbackFileAsync", FeedbackFilePickResponseSchema.nullable(), [], { timeoutMs: 60000 }),

  submitFeedback: (
    type: string,
    subtype: string,
    content: string,
    contact: string,
    username: string,
    lang: string,
    appVersion: string,
    attachmentsJson: string,
  ): Promise<{ success: boolean; ticketId: string }> =>
    invoke(
      "SubmitFeedbackAsync",
      FeedbackSubmitResponseSchema,
      [type, subtype, content, contact, username, lang, appVersion, attachmentsJson],
      { timeoutMs: 20000 },
    ),
};
