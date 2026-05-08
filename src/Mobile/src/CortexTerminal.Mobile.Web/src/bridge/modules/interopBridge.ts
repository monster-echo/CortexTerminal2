import {
  BinaryTransferResultSchema,
  GreetingResultSchema,
  HelloResultSchema,
  SuccessResponseSchema,
  TextInteropResultSchema,
} from "../../schemas/bridgeSchema";
import { invoke } from "../runtime";

export const interopBridge = {
  hello: () => invoke("HelloAsync", HelloResultSchema),
  greet: (name: string, language = "en") =>
    invoke("GreetAsync", GreetingResultSchema, [{ name, language }]),
  echoText: (message: string) =>
    invoke("EchoTextAsync", TextInteropResultSchema, [message]),
  echoBinary: (base64: string) =>
    invoke("EchoBinaryAsync", BinaryTransferResultSchema, [base64]),
  sendTextMessageToJs: (message: string) =>
    invoke("SendTextMessageToJsAsync", SuccessResponseSchema, [message]),
  sendBinaryMessageToJs: (byteLength = 32) =>
    invoke("SendBinaryMessageToJsAsync", SuccessResponseSchema, [byteLength]),
};
