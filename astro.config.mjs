import { defineConfig } from "astro/config";
import preact from "@astrojs/preact";
import sitemap from '@astrojs/sitemap';

export default defineConfig({
  site: 'https://wslha.co',
  integrations: [
    preact(),
    sitemap({
      canonicalURL: 'https://wslha.co'
    })
  ],
});
