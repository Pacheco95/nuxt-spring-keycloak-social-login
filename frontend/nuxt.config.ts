// https://nuxt.com/docs/api/configuration/nuxt-config
//
// Hostname split (locked decision — see CLAUDE.md): the BFF needs DIFFERENT
// URLs for Keycloak depending on who's making the request:
//   * Browser-facing (auth, logout): public URL like http://localhost:8080
//   * Server-to-server (token, userinfo): in-network compose service name
//
// All these values are baked as placeholders here and overridden at RUNTIME
// from the docker-compose `environment:` block via Nuxt's NUXT_<PATH>
// runtimeConfig env-mapping. Computing them here at build time would freeze
// in the wrong values because the build container has no .env loaded.
//
// Cookie.Secure: see comment on `cookieSecure` below.

const cookieSecure = (process.env.FRONTEND_PUBLIC_URL ?? '').startsWith('https://')

export default defineNuxtConfig({
  compatibilityDate: '2025-07-15',
  devtools: { enabled: true },
  ssr: true,
  modules: ['nuxt-oidc-auth'],

  runtimeConfig: {
    // Overridden at runtime by NUXT_BACKEND_INTERNAL_URL (set in compose).
    backendInternalUrl: '',
    public: {
      siteName: 'Social Login Demo',
    },
  },

  oidc: {
    defaultProvider: 'keycloak',
    middleware: {
      // Fail-closed: every route requires auth by default. Public routes opt
      // out via `definePageMeta({ oidcAuth: { enabled: false } })`.
      globalMiddlewareEnabled: true,
    },
    session: {
      automaticRefresh: true,
      expirationCheck: true,
      cookie: {
        sameSite: 'lax',
        // Cookie.Secure requires HTTPS. On http://localhost browsers technically
        // allow Secure cookies, but other dev hosts may not — derive from the
        // public URL scheme so production behind HTTPS flips this on.
        secure: cookieSecure,
      },
    },
    providers: {
      // Every URL/secret here is a placeholder. The real values come from
      // docker-compose's NUXT_OIDC_PROVIDERS_KEYCLOAK_* env vars at runtime.
      keycloak: {
        clientId: '',
        clientSecret: '',
        redirectUri: '',
        logoutRedirectUri: '',
        // Pinned post-callback landing page. See docker-compose.yml comment
        // explaining why the per-login query-param mechanism doesn't work
        // (the lib clears the auth session before reading the URL out of
        // it). Overridden at runtime via NUXT_OIDC_PROVIDERS_KEYCLOAK_CALLBACK_REDIRECT_URL.
        callbackRedirectUrl: '/profile',
        authorizationUrl: '',
        tokenUrl: '',
        userInfoUrl: '',
        logoutUrl: '',
        scope: ['openid', 'profile', 'email'],
        // The backend re-validates every JWT against the realm's JWKS, so
        // skipping validation here is not a security gap — but it does
        // remove one layer of defense-in-depth. Tracked in
        // docs/bff-token-validation.md.
        validateAccessToken: false,
        validateIdToken: false,
        // Strict BFF: the access token never appears in the session payload
        // returned to the browser. /api/me proxies via a server route that
        // decrypts the persistent oidc storage.
        exposeAccessToken: false,
      },
    },
  },
})
