import { describe, expect, it } from "vitest";
import { authHeaders, createTestServer, jsonRequest, readJson } from "./helpers";

describe("user profile behavior", () => {
  it("returns missing, limited, then full target profiles through the scan flow", async () => {
    const server = await createTestServer();
    const aliceAuth = await authHeaders("alice");
    const bobAuth = await authHeaders("bob");

    const aliceInit = await server.request("/users/me", { headers: aliceAuth });
    expect(aliceInit.status).toBe(200);

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

    const fullBob = await server.request("/users/bob?physical_id=tag-bob", {
      headers: aliceAuth,
    });
    expect(fullBob.status).toBe(200);
    await expect(readJson(fullBob)).resolves.toMatchObject({
      status: "success",
      data: {
        user_id: "bob",
        role: "ATTENDEE",
        display_name: "Player_bob",
        emoji_icon: "🙂",
        bio: "",
        pixel_avatar_base64: "",
        physical_id: "tag-bob",
        collection: [],
      },
    });

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

    const updatedBob = await server.request("/users/bob?physical_id=tag-bob", {
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
        physical_id: "tag-bob",
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
});
