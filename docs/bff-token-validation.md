# BFF token validation is disabled — known tradeoff

**Status:** intentional, not a security vulnerability today, but a defense-in-depth gap worth closing.

## What's disabled

In `frontend/nuxt.config.ts`, the Keycloak provider for `nuxt-oidc-auth` is configured with:

```ts
validateAccessToken: false,
validateIdToken: false,
```

This means the **BFF does not verify the JWT signature** of the access token or ID token after receiving them from Keycloak's token endpoint. The tokens are stored, sealed in the encrypted session, and forwarded as-is.

## Why this is not a security vulnerability today

- **Tokens are received over a trusted server-to-server channel.** The BFF's token request to `http://keycloak:<port>/.../token` runs entirely inside the docker network, authenticated with the BFF's `client_secret`. There is no MITM vector for an attacker to substitute a forged token.
- **The backend re-validates every JWT on every API call.** `backend/src/main/kotlin/com/example/backend/security/SecurityConfig.kt` configures Spring Security as an OAuth2 resource server with `oauth2ResourceServer { jwt {} }`. Each request to `/api/**` triggers signature verification against Keycloak's JWKS, with `iss` pinned to `BACKEND_OIDC_ISSUER_URI`. A bogus token cannot reach data — it produces a 401 at the backend.
- **The id token is never used as a credential.** It only ever shows up as `id_token_hint` on the RP-initiated logout request, where Keycloak itself validates it.

## What defense-in-depth this costs

- **Slower failure mode on misconfig.** If a future change ever causes the BFF to receive a token that doesn't match the realm's keys (wrong realm, key rotation race, broken proxy), the user sees a generic "could not load profile" error after the request reaches the backend, instead of a clear "invalid token" failure at the BFF layer.
- **Less symmetric trust posture.** Best practice is to have every component that handles a JWT validate it. We have one (the backend) instead of two.

## Why it's currently disabled

`nuxt-oidc-auth`'s Keycloak preset uses a single `baseUrl` to derive every endpoint URL — auth, token, userinfo, logout, AND the `.well-known/openid-configuration` discovery doc that signature validation depends on.

This project deliberately splits those URLs:

| Endpoint        | URL the browser must use     | URL the BFF must use         |
|-----------------|-------------------------------|------------------------------|
| authorization   | `http://localhost:8080/...`  | (browser only)               |
| logout          | `http://localhost:8080/...`  | (browser only)               |
| token exchange  | (server only)                 | `http://keycloak:8080/...`   |
| userinfo        | (server only)                 | `http://keycloak:8080/...`   |
| **discovery**   |                               | **`http://keycloak:8080/...`** |

The split is required because `iss` is pinned to the public hostname (so it matches across browser and server views — see `CLAUDE.md` and `social-login-impl.md`). Setting `baseUrl` to either value forces every endpoint onto one URL and breaks the split.

I worked around it by setting `authorizationUrl`, `tokenUrl`, `userInfoUrl`, `logoutUrl` as absolute URLs (which override the `baseUrl`-derived defaults) and turning validation off so the lib never tries to fetch discovery from a missing/wrong `baseUrl`.

## How to fix it

The `keycloak` provider preset (`node_modules/nuxt-oidc-auth/dist/runtime/providers/keycloak.js`) exposes an `openIdConfiguration` function that the validator calls to load the discovery document. We can override it with one that uses an explicit in-network URL instead of relying on `baseUrl`.

### Step-by-step

1. **In `frontend/nuxt.config.ts`**, inside `oidc.providers.keycloak`, add an `openIdConfiguration` async function that fetches the discovery doc directly from `${internalKc}/realms/${realm}/.well-known/openid-configuration`. Pseudocode:

   ```ts
   keycloak: {
     // ... existing config ...
     validateAccessToken: true,   // turn back on
     validateIdToken: true,       // turn back on
     openIdConfiguration: async () => {
       return await $fetch(
         `${internalKc}/realms/${realm}/.well-known/openid-configuration`
       )
     },
   }
   ```

   The lib's signature for this function takes the merged config as an arg; check the current `keycloak.js` source if the type changed since this doc was written.

2. **Verify Keycloak's discovery doc serves the right `jwks_uri`.** It should already — when `KC_HOSTNAME` is pinned to the public URL, every endpoint in the discovery payload (including `jwks_uri`) reflects the public host. The BFF's signature validator will then either:
   - Fetch JWKS from the public URL (works if the BFF container can reach `http://localhost:<host-port>` — usually no, inside docker), or
   - Need a second override to point JWKS fetching at the internal URL.

   If the second case, also override `jwks_uri` resolution. The simplest path is to fetch the discovery doc, replace `jwks_uri` with the in-network equivalent, and return the modified object from `openIdConfiguration`.

3. **Re-build and re-test.** Bring the BFF up, log in via the full flow, hit `/api/me`, and confirm:
   - `docker logs social-login-frontend-1` shows no JWKS fetch errors at startup or on first authenticated request.
   - A deliberately-tampered token (e.g. flip the last byte of the signature, replay through the cookie-sealed session — easier said than done; consider an integration test that hand-mints a JWT signed by a different key) fails at the BFF, not the backend.

4. **Update `frontend/nuxt.config.ts`'s comment block** to remove the "deliberately disabled" note, and delete this document.

### Acceptance criteria

- `validateAccessToken: true` and `validateIdToken: true` in `nuxt.config.ts`.
- `docker compose up` brings the BFF up cleanly with no discovery-fetch errors.
- A real Google sign-in still works end-to-end and `/profile` renders.
- An integration test demonstrates the BFF rejects a token signed by an unknown key.

## Related

- `CLAUDE.md` → "Design decisions (locked with the user)" → hostname pinning rationale.
- `social-login-impl.md` → "Design decisions (locked)" → same.
- `frontend/nuxt.config.ts` → the config block this document refers to.
- `backend/src/main/kotlin/com/example/backend/security/SecurityConfig.kt` → the validation gate that currently carries the load alone.
