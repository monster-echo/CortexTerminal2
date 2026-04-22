import { defineConfig } from "vite"
import { resolve } from "node:path"

export default defineConfig({
  build: {
    emptyOutDir: true,
    outDir: resolve(__dirname, "../../Gateway/CortexTerminal.Gateway/wwwroot"),
  },
  test: {
    environment: "jsdom",
    globals: true,
  },
})
