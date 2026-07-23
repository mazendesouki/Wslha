import { defineConfig } from "astro/config";
import preact from "@astrojs/preact";
import vercel from "@astrojs/vercel/serverless";

export default defineConfig({
  site: 'https://wslha.co',
  output: 'hybrid',
  adapter: vercel(),
  integrations: [
    preact(),
  ],
});
