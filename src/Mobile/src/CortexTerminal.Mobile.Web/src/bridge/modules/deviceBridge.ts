import { NativeMediaAssetSchema } from "../../schemas/bridgeSchema";
import { invoke } from "../runtime";

export const deviceBridge = {
  pickPhoto: () => invoke("PickPhotoAsync", NativeMediaAssetSchema.nullable()),
  capturePhoto: () =>
    invoke("CapturePhotoAsync", NativeMediaAssetSchema.nullable()),
  pickVideo: () => invoke("PickVideoAsync", NativeMediaAssetSchema.nullable()),
  captureVideo: () =>
    invoke("CaptureVideoAsync", NativeMediaAssetSchema.nullable()),
};
