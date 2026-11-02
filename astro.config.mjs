import { defineConfig } from "astro/config";
import preact from "@astrojs/preact";
import vercel from "@astrojs/vercel";

export default defineConfig({
  site: 'https://wslha.co',
  integrations: [
    preact(),
  ],
  // Astro 5 merged 'hybrid' into 'static' — every page still builds fully
  // static by default (unchanged behavior); only routes that explicitly
  // set `export const prerender = false` (the /api/* session/proxy
  // endpoints, which need to run server-side) are server-rendered. No
  // `output` value means the same thing 'hybrid' used to.
  //
  // @astrojs/vercel also dropped its '/serverless' and '/static' subpath
  // exports in v9+ — a single default export now covers both, picking
  // per-route behavior from each page's own `prerender` export exactly
  // like before.
  adapter: vercel(),
});
