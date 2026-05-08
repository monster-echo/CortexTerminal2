import {
  FeatureDefinitionSchema,
  type FeatureDefinition,
} from "../../schemas/featureSchema";

export function createFeatureDefinitions(): FeatureDefinition[] {
  return FeatureDefinitionSchema.array().parse([
    {
      key: "home",
      folder: "features/home",
      title: "Home feature",
      summary: "Starter 首页入口，负责展示平台状态、功能边界和基础导航。",
      route: "/home",
      dependsOnBridge: false,
      tags: ["shell", "starter", "entry"],
    },
    {
      key: "theme",
      folder: "features/theme",
      title: "Theme feature",
      summary: "主题同步单独成页，只负责浅色/深色/跟随系统。",
      route: "/theme",
      dependsOnBridge: true,
      tags: ["theme", "appearance", "shell"],
    },
    {
      key: "settings",
      folder: "features/settings",
      title: "Settings feature",
      summary: "设置页只保留支持、分享、条款和应用信息。",
      route: "/settings",
      dependsOnBridge: true,
      tags: ["settings", "about", "support"],
    },
  ]);
}

export const createFeatureCatalog = createFeatureDefinitions;
