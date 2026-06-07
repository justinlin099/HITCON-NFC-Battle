```txt
npm install
npm run dev
```

```txt
npm run deploy
```

## Database

Initial D1 schema lives in [`migrations/0001_initial_schema.sql`](./migrations/0001_initial_schema.sql).
It defines only the stable backbone tables; add new migrations incrementally as
API implementation clarifies more details.

[For generating/synchronizing types based on your Worker configuration run](https://developers.cloudflare.com/workers/wrangler/commands/#types):

```txt
npm run cf-typegen
```

Pass the `CloudflareBindings` as generics when instantiating `Hono`:

```ts
// src/index.ts
const app = new Hono<{ Bindings: CloudflareBindings }>()
```
