import { cp, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { parse } from "yaml";

const projectDir = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const sourceSpecPath = resolve(projectDir, "../openapi.yaml");
const swaggerDistDir = resolve(projectDir, "node_modules/swagger-ui-dist");
const outputDir = resolve(projectDir, "public/docs");

const sourceSpec = parse(await readFile(sourceSpecPath, "utf8"));
sourceSpec.servers = [
  {
    url: "/",
    description: "API serving this documentation",
  },
];

await rm(outputDir, { recursive: true, force: true });
await mkdir(outputDir, { recursive: true });

for (const file of [
  "swagger-ui.css",
  "swagger-ui-bundle.js",
  "swagger-ui-bundle.js.LICENSE.txt",
  "favicon-16x16.png",
  "favicon-32x32.png",
  "LICENSE",
  "NOTICE",
]) {
  await cp(join(swaggerDistDir, file), join(outputDir, file));
}

await writeFile(join(outputDir, "openapi.json"), `${JSON.stringify(sourceSpec, null, 2)}\n`);
await writeFile(
  join(outputDir, "index.html"),
  `<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="referrer" content="no-referrer">
    <title>HITCON NFC Battle API Documentation</title>
    <link rel="icon" type="image/png" href="./favicon-32x32.png" sizes="32x32">
    <link rel="icon" type="image/png" href="./favicon-16x16.png" sizes="16x16">
    <link rel="stylesheet" href="./swagger-ui.css">
    <style>
      html { box-sizing: border-box; overflow-y: scroll; }
      *, *::before, *::after { box-sizing: inherit; }
      body { margin: 0; background: #fafafa; }
      .api-environment { padding: 10px 20px; background: #171717; color: #fff; font: 600 14px system-ui, sans-serif; }
      .api-environment code { color: #7dd3fc; }
    </style>
  </head>
  <body>
    <header class="api-environment">HITCON NFC Battle API: <code id="api-origin"></code></header>
    <div id="swagger-ui"></div>
    <script src="./swagger-ui-bundle.js"></script>
    <script>
      document.getElementById("api-origin").textContent = window.location.origin;
      window.ui = SwaggerUIBundle({
        url: "./openapi.json",
        dom_id: "#swagger-ui",
        deepLinking: true,
        displayRequestDuration: true,
        persistAuthorization: false,
        presets: [SwaggerUIBundle.presets.apis],
        validatorUrl: null
      });
    </script>
  </body>
</html>
`,
);
