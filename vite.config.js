// Vite dev server config for hot-reloading the static viewer.
// In production this app is served by static-web-server — Vite is dev-only.

import { defineConfig } from 'vite';

const port = Number(process.env.PORT ?? 8080);
const host = process.env.HOST ?? '0.0.0.0';
const base = process.env.SIMCORE_NODE_BASEPATH
  ? `${process.env.SIMCORE_NODE_BASEPATH.replace(/\/$/, '')}/`
  : '/';

export default defineConfig({
  root: 'src',
  base,
  publicDir: false,
  server: {
    host,
    port,
    strictPort: true,
    watch: {
      // Required for bind-mounted volumes on Linux to detect changes reliably.
      usePolling: true,
      interval: 300,
    },
  },
});
