import { z } from "zod";

export const FeatureDefinitionSchema = z.object({
  key: z.string(),
  folder: z.string(),
  title: z.string(),
  summary: z.string(),
  route: z.string(),
  dependsOnBridge: z.boolean().default(false),
  tags: z.array(z.string()).default([]),
});

export const FeatureActionResultSchema = z.object({
  success: z.boolean(),
  message: z.string(),
  details: z.string().optional(),
});

export type FeatureDefinition = z.infer<typeof FeatureDefinitionSchema>;
export type FeatureActionResult = z.infer<typeof FeatureActionResultSchema>;
