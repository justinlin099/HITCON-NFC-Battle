import { describe, expect, it } from "vitest";
import { authHeaders, createTestServer, jsonRequest, readJson } from "./helpers";

describe("user profile behavior", () => {
  it("returns missing, limited, then full target profiles through the scan flow", async () => {
    const server = await createTestServer();
    const aliceAuth = await authHeaders("alice");
    const bobAuth = await authHeaders("bob");

    const aliceInit = await server.request("/users/me", { headers: aliceAuth });
    expect(aliceInit.status).toBe(200);
    const aliceInitBody = await readJson(aliceInit) as {
      data: {
        nfc_tag_key: string;
      };
    };
    expect(aliceInitBody.data.nfc_tag_key).toMatch(/^[0-9a-f]{12}$/);

    const missingBob = await server.request("/users/bob", { headers: aliceAuth });
    expect(missingBob.status).toBe(404);

    const bobInit = await server.request("/users/me", { headers: bobAuth });
    expect(bobInit.status).toBe(200);

    const limitedBob = await server.request("/users/bob", { headers: aliceAuth });
    expect(limitedBob.status).toBe(200);
    await expect(readJson(limitedBob)).resolves.toEqual({
      status: "success",
      data: {
        user_id: "bob",
        display_name: "Player_bob",
        emoji_icon: "🙂",
      },
    });

    const limitedBobWithMatchingVersions = await server.request(
      "/users/bob?profile_version=1&collection_version=0",
      { headers: aliceAuth },
    );
    expect(limitedBobWithMatchingVersions.status).toBe(200);
    await expect(readJson(limitedBobWithMatchingVersions)).resolves.toEqual({
      status: "success",
      data: {
        user_id: "bob",
        display_name: "Player_bob",
        emoji_icon: "🙂",
      },
    });

    const limitedBatchWithMatchingVersions = await server.request(
      "/users/batch",
      await jsonRequest(
        "POST",
        {
          users: [{ user_id: "bob", profile_version: 1, collection_version: 0 }],
        },
        aliceAuth,
      ),
    );
    expect(limitedBatchWithMatchingVersions.status).toBe(200);
    await expect(readJson(limitedBatchWithMatchingVersions)).resolves.toEqual({
      status: "success",
      data: {
        results: [
          {
            user_id: "bob",
            unchanged: false,
            data: {
              user_id: "bob",
              display_name: "Player_bob",
              emoji_icon: "🙂",
            },
          },
        ],
      },
    });

    const bobPair = await server.request(
      "/tags/pair",
      await jsonRequest("POST", { physical_id: "tag-bob" }, bobAuth),
    );
    expect(bobPair.status).toBe(200);

    const aliceScanBob = await server.request(
      "/collection/scan",
      await jsonRequest("POST", { user_id: "bob", physical_id: "tag-bob" }, aliceAuth),
    );
    expect(aliceScanBob.status).toBe(200);

    const fullBob = await server.request("/users/bob", {
      headers: aliceAuth,
    });
    expect(fullBob.status).toBe(200);
    const fullBobBody = await readJson(fullBob) as {
      data: Record<string, unknown>;
    };
    expect(fullBobBody).toMatchObject({
      status: "success",
      data: {
        user_id: "bob",
        role: "ATTENDEE",
        display_name: "Player_bob",
        emoji_icon: "🙂",
        bio: "",
        pixel_avatar_base64: "",
        profile_version: 1,
        collection_version: 0,
      },
    });
    expect(fullBobBody.data).not.toHaveProperty("nfc_tag_key");

    const bobUpdate = await server.request(
      "/users/me",
      await jsonRequest(
        "PATCH",
        {
          display_name: "Bob",
          emoji_icon: "🚀",
          bio: "Updated Bob detail.",
          pixel_avatar_base64: "iVBORw0KGgo...",
        },
        bobAuth,
      ),
    );
    expect(bobUpdate.status).toBe(200);

    const updatedBob = await server.request("/users/bob", {
      headers: aliceAuth,
    });
    expect(updatedBob.status).toBe(200);
    await expect(readJson(updatedBob)).resolves.toMatchObject({
      data: {
        user_id: "bob",
        display_name: "Bob",
        emoji_icon: "🚀",
        bio: "Updated Bob detail.",
        pixel_avatar_base64: "iVBORw0KGgo...",
        profile_version: 2,
      },
    });

    const unchangedBob = await server.request("/users/bob?profile_version=2&collection_version=0", {
      headers: aliceAuth,
    });
    expect(unchangedBob.status).toBe(200);
    await expect(readJson(unchangedBob)).resolves.toEqual({
      status: "success",
      data: {
        user_id: "bob",
        unchanged: true,
      },
    });

    const trimmedPathBob = await server.request("/users/%20bob%20", {
      headers: aliceAuth,
    });
    expect(trimmedPathBob.status).toBe(200);
    await expect(readJson(trimmedPathBob)).resolves.toMatchObject({
      status: "success",
      data: {
        user_id: "bob",
        display_name: "Bob",
      },
    });
  });

  it("rejects invalid profile updates and prize lookup before freeze", async () => {
    const server = await createTestServer();
    const aliceAuth = await authHeaders("alice");

    const aliceInit = await server.request("/users/me", { headers: aliceAuth });
    expect(aliceInit.status).toBe(200);

    const aliceProfile = await server.request("/users/me", { headers: aliceAuth });
    expect(aliceProfile.status).toBe(200);
    await expect(readJson(aliceProfile)).resolves.toMatchObject({
      data: {
        user_id: "alice",
        role: "ATTENDEE",
        nfc_tag_key: expect.stringMatching(/^[0-9a-f]{12}$/),
      },
    });

    const noOpUpdate = await server.request(
      "/users/me",
      await jsonRequest(
        "PATCH",
        {
          display_name: "Player_alice",
          emoji_icon: "🙂",
          bio: "",
          pixel_avatar_base64: "",
        },
        aliceAuth,
      ),
    );
    expect(noOpUpdate.status).toBe(200);
    await expect(readJson(noOpUpdate)).resolves.toMatchObject({
      data: {
        profile_version: 1,
      },
    });

    const invalidUpdate = await server.request(
      "/users/me",
      await jsonRequest("PATCH", { display_name: "Alice", unknown_field: "nope" }, aliceAuth),
    );
    expect(invalidUpdate.status).toBe(400);

    const prizeResult = await server.request("/users/me/prize", { headers: aliceAuth });
    expect(prizeResult.status).toBe(409);
  });

  it("supports cacheable batch, profile, and collection reads", async () => {
    const server = await createTestServer();
    const aliceAuth = await authHeaders("alice");
    const bobAuth = await authHeaders("bob");
    const carolAuth = await authHeaders("carol");

    await server.request("/users/me", { headers: aliceAuth });
    await server.request("/users/me", { headers: bobAuth });
    await server.request("/users/me", { headers: carolAuth });

    await server.request(
      "/tags/pair",
      await jsonRequest("POST", { physical_id: "tag-bob" }, bobAuth),
    );
    await server.request(
      "/tags/pair",
      await jsonRequest("POST", { physical_id: "tag-carol" }, carolAuth),
    );

    await server.request(
      "/collection/scan",
      await jsonRequest("POST", { user_id: "bob", physical_id: "tag-bob" }, aliceAuth),
    );
    await server.request(
      "/collection/scan",
      await jsonRequest("POST", { user_id: "carol", physical_id: "tag-carol" }, bobAuth),
    );

    const batch = await server.request(
      "/users/batch",
      await jsonRequest(
        "POST",
        {
          users: [
            { user_id: "bob", profile_version: 1, collection_version: 1 },
            { user_id: "carol", profile_version: 1 },
          ],
        },
        aliceAuth,
      ),
    );
    expect(batch.status).toBe(200);
    await expect(readJson(batch)).resolves.toEqual({
      status: "success",
      data: {
        results: [
          {
            user_id: "bob",
            unchanged: true,
          },
          {
            user_id: "carol",
            unchanged: false,
            data: {
              user_id: "carol",
              display_name: "Player_carol",
              emoji_icon: "🙂",
            },
          },
        ],
      },
    });

    const trimmedBatch = await server.request(
      "/users/batch",
      await jsonRequest(
        "POST",
        {
          users: [{ user_id: " bob ", profile_version: 1, collection_version: 1 }],
        },
        aliceAuth,
      ),
    );
    expect(trimmedBatch.status).toBe(200);
    await expect(readJson(trimmedBatch)).resolves.toEqual({
      status: "success",
      data: {
        results: [
          {
            user_id: "bob",
            unchanged: true,
          },
        ],
      },
    });

    const bobCollection = await server.request("/users/bob/collection", { headers: aliceAuth });
    expect(bobCollection.status).toBe(200);
    await expect(readJson(bobCollection)).resolves.toEqual({
      status: "success",
      data: {
        user_id: "bob",
        collection_version: 1,
        users: [
          {
            user_id: "carol",
            display_name: "Player_carol",
            emoji_icon: "🙂",
          },
        ],
      },
    });

    const unchangedCollection = await server.request("/users/bob/collection?collection_version=1", {
      headers: aliceAuth,
    });
    expect(unchangedCollection.status).toBe(200);
    await expect(readJson(unchangedCollection)).resolves.toEqual({
      status: "success",
      data: {
        user_id: "bob",
        unchanged: true,
      },
    });

    const trimmedPathCollection = await server.request("/users/%20bob%20/collection", {
      headers: aliceAuth,
    });
    expect(trimmedPathCollection.status).toBe(200);
    await expect(readJson(trimmedPathCollection)).resolves.toMatchObject({
      status: "success",
      data: {
        user_id: "bob",
        collection_version: 1,
      },
    });

    const forbiddenCollection = await server.request("/users/carol/collection", {
      headers: aliceAuth,
    });
    expect(forbiddenCollection.status).toBe(403);
  });

  it("covers cached version combinations for batch, profile, and collection reads", async () => {
    const server = await createTestServer();
    const aliceAuth = await authHeaders("alice");
    const bobAuth = await authHeaders("bob");
    const carolAuth = await authHeaders("carol");

    await server.request("/users/me", { headers: aliceAuth });
    await server.request("/users/me", { headers: bobAuth });
    await server.request("/users/me", { headers: carolAuth });

    await server.request(
      "/tags/pair",
      await jsonRequest("POST", { physical_id: "tag-bob" }, bobAuth),
    );
    await server.request(
      "/tags/pair",
      await jsonRequest("POST", { physical_id: "tag-carol" }, carolAuth),
    );
    await server.request(
      "/collection/scan",
      await jsonRequest("POST", { user_id: "bob", physical_id: "tag-bob" }, aliceAuth),
    );
    await server.request(
      "/collection/scan",
      await jsonRequest("POST", { user_id: "carol", physical_id: "tag-carol" }, bobAuth),
    );

    const versionCases = [
      {
        name: "both omitted",
        requestVersions: {},
        query: "",
        unchanged: false,
      },
      {
        name: "only profile current",
        requestVersions: { profile_version: 1 },
        query: "profile_version=1",
        unchanged: false,
      },
      {
        name: "only profile stale",
        requestVersions: { profile_version: 0 },
        query: "profile_version=0",
        unchanged: false,
      },
      {
        name: "only collection current",
        requestVersions: { collection_version: 1 },
        query: "collection_version=1",
        unchanged: false,
      },
      {
        name: "only collection stale",
        requestVersions: { collection_version: 0 },
        query: "collection_version=0",
        unchanged: false,
      },
      {
        name: "both current",
        requestVersions: { profile_version: 1, collection_version: 1 },
        query: "profile_version=1&collection_version=1",
        unchanged: true,
      },
      {
        name: "profile stale collection current",
        requestVersions: { profile_version: 0, collection_version: 1 },
        query: "profile_version=0&collection_version=1",
        unchanged: false,
      },
      {
        name: "profile current collection stale",
        requestVersions: { profile_version: 1, collection_version: 0 },
        query: "profile_version=1&collection_version=0",
        unchanged: false,
      },
      {
        name: "both stale",
        requestVersions: { profile_version: 0, collection_version: 0 },
        query: "profile_version=0&collection_version=0",
        unchanged: false,
      },
    ];

    for (const versionCase of versionCases) {
      const batch = await server.request(
        "/users/batch",
        await jsonRequest(
          "POST",
          {
            users: [
              {
                user_id: "bob",
                ...versionCase.requestVersions,
              },
            ],
          },
          aliceAuth,
        ),
      );
      expect(batch.status, `batch ${versionCase.name}`).toBe(200);
      const batchBody = (await readJson(batch)) as {
        data: {
          results: Array<{
            user_id: string;
            unchanged: boolean;
            data?: unknown;
          }>;
        };
      };

      if (versionCase.unchanged) {
        expect(batchBody.data.results[0], `batch ${versionCase.name}`).toEqual({
          user_id: "bob",
          unchanged: true,
        });
      } else {
        expect(batchBody.data.results[0], `batch ${versionCase.name}`).toMatchObject({
          user_id: "bob",
          unchanged: false,
          data: {
            user_id: "bob",
            role: "ATTENDEE",
            profile_version: 1,
            collection_version: 1,
          },
        });
      }

      const profilePath = versionCase.query ? `/users/bob?${versionCase.query}` : "/users/bob";
      const profile = await server.request(profilePath, { headers: aliceAuth });
      expect(profile.status, `profile ${versionCase.name}`).toBe(200);
      const profileBody = (await readJson(profile)) as {
        data: {
          user_id: string;
          unchanged?: boolean;
          role?: string;
          profile_version?: number;
          collection_version?: number;
        };
      };

      if (versionCase.unchanged) {
        expect(profileBody.data, `profile ${versionCase.name}`).toEqual({
          user_id: "bob",
          unchanged: true,
        });
      } else {
        expect(profileBody.data, `profile ${versionCase.name}`).toMatchObject({
          user_id: "bob",
          role: "ATTENDEE",
          profile_version: 1,
          collection_version: 1,
        });
      }
    }

    const collectionCases = [
      {
        name: "omitted",
        path: "/users/bob/collection",
        unchanged: false,
      },
      {
        name: "current",
        path: "/users/bob/collection?collection_version=1",
        unchanged: true,
      },
      {
        name: "stale",
        path: "/users/bob/collection?collection_version=0",
        unchanged: false,
      },
    ];

    for (const collectionCase of collectionCases) {
      const collection = await server.request(collectionCase.path, { headers: aliceAuth });
      expect(collection.status, `collection ${collectionCase.name}`).toBe(200);
      const collectionBody = (await readJson(collection)) as {
        data: {
          user_id: string;
          unchanged?: boolean;
          collection_version?: number;
          users?: unknown[];
        };
      };

      if (collectionCase.unchanged) {
        expect(collectionBody.data, `collection ${collectionCase.name}`).toEqual({
          user_id: "bob",
          unchanged: true,
        });
      } else {
        expect(collectionBody.data, `collection ${collectionCase.name}`).toEqual({
          user_id: "bob",
          collection_version: 1,
          users: [
            {
              user_id: "carol",
              display_name: "Player_carol",
              emoji_icon: "🙂",
            },
          ],
        });
      }
    }
  });
});
