// https://nuxt.com/docs/api/configuration/nuxt-config
//
// Hostname split (locked decision — see CLAUDE.md):
//   * Browser-facing endpoints (auth, logout) use FRONTEND_OIDC_KEYCLOAK_PUBLIC_URL.
//   * Server-side endpoints (token, userinfo) use KEYCLOAK_INTERNAL_URL set
//     by docker-compose (the in-network compose service name).
// Setting these absolute URLs avoids nuxt-oidc-auth's baseUrl auto-derivation
// (which would force every endpoint onto a single base).

const realm = process.env.KEYCLOAK_REALM_NAME ?? 'social-login'
const publicKc = process.env.FRONTEND_OIDC_KEYCLOAK_PUBLIC_URL
  ?? process.env.KEYCLOAK_PUBLIC_URL
  ?? 'http://localhost:8080'
const internalKc = process.env.KEYCLOAK_INTERNAL_URL ?? publicKc

export default defineNuxtConfig({
  compatibilityDate: '2025-07-15',
  devtools: { enabled: true },
  ssr: true,
  modules: ['nuxt-oidc-auth'],

  runtimeConfig: {
    backendInternalUrl:
      process.env.FRONTEND_BACKEND_INTERNAL_URL ?? 'http://localhost:8081',
    public: {
      siteName: 'Social Login Demo',
    },
  },

  oidc: {
    defaultProvider: 'keycloak',
    middleware: {
      // Fail-closed: every route requires auth by default. Routes that need
      // to be public (e.g. the home page with the Login button) opt out via
      // `definePageMeta({ oidcAuth: { enabled: false } })`.
      globalMiddlewareEnabled: true,
    },
    session: {
      automaticRefresh: true,
      expirationCheck: true,
    },
    providers: {
      keycloak: {
        clientId: process.env.NUXT_OIDC_PROVIDERS_KEYCLOAK_CLIENT_ID ?? '',
        clientSecret:
          process.env.NUXT_OIDC_PROVIDERS_KEYCLOAK_CLIENT_SECRET ?? '',
        redirectUri:
          process.env.FRONTEND_OIDC_REDIRECT_URI
          ?? 'http://localhost:3000/auth/keycloak/callback',
        logoutRedirectUri:
          process.env.FRONTEND_OIDC_POST_LOGOUT_REDIRECT_URI
          ?? 'http://localhost:3000/',
        // Browser-facing.
        authorizationUrl: `${publicKc}/realms/${realm}/protocol/openid-connect/auth`,
        logoutUrl: `${publicKc}/realms/${realm}/protocol/openid-connect/logout`,
        // Server-to-server (BFF → Keycloak).
        tokenUrl: `${internalKc}/realms/${realm}/protocol/openid-connect/token`,
        userInfoUrl: `${internalKc}/realms/${realm}/protocol/openid-connect/userinfo`,
        scope: ['openid', 'profile', 'email'],
        // The backend re-validates every JWT against the realm's JWKS, so
        // skipping validation here is not a security gap — but it does
        // remove one layer of defense-in-depth and slows failure on any
        // future misconfig. Re-enabling requires overriding the lib's
        // `openIdConfiguration` to use the internal URL instead of the
        // (split) baseUrl. Tracked in docs/bff-token-validation.md.
        validateAccessToken: false,
        validateIdToken: false,
        // Strict BFF: the access token never appears in the session payload
        // returned to the browser. /api/me proxies via a server route that
        // decrypts the persistent session storage.
        exposeAccessToken: false,
        // exposeIdToken stays at the keycloak preset default (true) so the
        // logout handler can attach it as `id_token_hint`. The id token only
        // carries identity claims, not API authorization.
      },
    },
  },
})
