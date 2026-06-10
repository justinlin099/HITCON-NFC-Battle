# HITCON 2026 NFC Tag Game Backend API

The product flow is maintained in [`game-flow.md`](./game-flow.md). Treat that
file as the source of truth for backend behavior.

The machine-readable API contract is maintained in [`openapi.yaml`](./openapi.yaml)
and should be updated to match [`game-flow.md`](./game-flow.md) whenever the flow
changes.

Use Swagger UI to view and explore the API contract:

1. Open <https://editor.swagger.io/>.
2. Import or paste the contents of [`openapi.yaml`](./openapi.yaml).
3. Use the rendered Swagger UI panels to inspect endpoints, schemas, examples,
   authentication, and error responses.
