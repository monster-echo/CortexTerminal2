import { invoke } from "../runtime";
import {
  SupportInfoSchema,
  FeedbackSubmitResponseSchema,
  FeedbackImageUploadResponseSchema,
  type SupportInfo,
} from "../../schemas/bridgeSchema";

export const supportBridge = {
  getSupportInfo: (): Promise<SupportInfo | null> =>
    invoke("GetSupportInfoAsync", SupportInfoSchema.nullable(), [], { timeoutMs: 12000 }),

  uploadImage: (
    localPath: string,
    filename: string,
    contentType: string,
  ): Promise<{ imageUrl: string }> =>
    invoke(
      "UploadFeedbackImageAsync",
      FeedbackImageUploadResponseSchema,
      [localPath, filename, contentType],
      { timeoutMs: 30000 },
    ),

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
