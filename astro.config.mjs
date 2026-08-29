import { defineConfig } from "astro/config";
import preact from "@astrojs/preact";
import vercel from "@astrojs/vercel/serverless";

export default defineConfig({
  site: 'https://wslha.co',
  integrations: [
    preact(),
  ],
  // 'hybrid': every existing page keeps building fully static (unchanged
  // behavior) — only routes that explicitly set `export const prerender =
  // false` (the new /api/auth/* session endpoints, which need to run
  // server-side to set an HttpOnly cookie) are server-rendered.
  output: 'hybrid',
  adapter: vercel(),
});
