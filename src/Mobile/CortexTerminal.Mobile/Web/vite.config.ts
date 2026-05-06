import { defineConfig } from "vite"
import { resolve } from "node:path"

export default defineConfig({
  base: "./",
  resolve: {
    alias: {
      "@": resolve(__dirname, "./src"),
    },
  },
  build: {
    emptyOutDir: true,
    outDir: resolve(__dirname, "../Resources/Raw/wwwroot"),
  },
  test: {
    environment: "jsdom",
    globals: true,
    setupFiles: ["./src/test-setup.ts"],
  },
})
