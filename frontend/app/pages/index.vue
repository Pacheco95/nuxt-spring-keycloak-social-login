<script setup lang="ts">
// Public route — explicit opt-out of the global oidcAuth middleware so an
// unauthenticated visitor can see and click the Login button (story 001).
// All other routes stay fail-closed by default.
definePageMeta({ oidcAuth: { enabled: false } })

const { loggedIn, login } = useOidcAuth()
const route = useRoute()

// User story 005 — surface OIDC errors that arrived as ?error=... query params.
const errorMessage = computed<string | null>(() => {
  const code = route.query.error
  if (typeof code !== 'string') return null
  switch (code) {
    case 'access_denied':
      return 'Access was denied. You may have cancelled the Google sign-in, or your account is not permitted to use this app.'
    case 'login_required':
      return 'You need to sign in again to continue.'
    case 'temporarily_unavailable':
      return "The login service is temporarily unavailable. Please try again in a moment."
    case 'session_error':
      return 'Your session could not be restored. Please sign in again.'
    case 'token_refresh_failed':
      return 'We could not keep you signed in. Please sign in again.'
    default:
      return `Sign-in failed (${code}). Please try again.`
  }
})

// Story 002: after the OAuth flow, the user must land on /profile. The
// post-callback target is set server-side via the provider's
// `callbackRedirectUrl` config (NUXT_OIDC_PROVIDERS_KEYCLOAK_CALLBACK_REDIRECT_URL
// in docker-compose.yml). We do NOT pass it as a per-login query param
// because the lib clears the auth-session before reading it back from the
// callback handler — the query-param mechanism is effectively dead.
//
// Skipping Keycloak's IdP-chooser screen (going straight to Google) is
// handled by adding `?kc_idp_hint=google` to the authorize URL in
// docker-compose.yml — the lib's `withQuery` preserves it.
async function handleLogin() {
  await login('keycloak')
}
</script>

<template>
  <main class="page">
    <h1>Welcome</h1>
    <p>Sign in with your Google account to access your profile.</p>

    <button
      v-if="!loggedIn"
      class="btn-google"
      type="button"
      @click="handleLogin"
    >
      <svg
        aria-hidden="true"
        viewBox="0 0 18 18"
        width="18"
        height="18"
      >
        <path fill="#4285F4" d="M17.64 9.2c0-.637-.057-1.251-.164-1.84H9v3.481h4.844a4.14 4.14 0 0 1-1.796 2.717v2.258h2.908c1.702-1.567 2.684-3.875 2.684-6.615z"/>
        <path fill="#34A853" d="M9 18c2.43 0 4.467-.806 5.956-2.184l-2.908-2.258c-.806.54-1.837.86-3.048.86-2.344 0-4.328-1.583-5.036-3.711H.957v2.332A8.997 8.997 0 0 0 9 18z"/>
        <path fill="#FBBC05" d="M3.964 10.707A5.41 5.41 0 0 1 3.682 9c0-.593.102-1.17.282-1.707V4.96H.957A8.997 8.997 0 0 0 0 9c0 1.452.348 2.827.957 4.04l3.007-2.333z"/>
        <path fill="#EA4335" d="M9 3.58c1.321 0 2.508.454 3.44 1.345l2.582-2.58C13.463.891 11.426 0 9 0A8.997 8.997 0 0 0 .957 4.96L3.964 7.293C4.672 5.165 6.656 3.58 9 3.58z"/>
      </svg>
      Login with Google
    </button>
    <NuxtLink v-else to="/profile" class="btn-profile">
      Go to your profile →
    </NuxtLink>

    <p v-if="errorMessage" class="error" role="alert">
      {{ errorMessage }}
    </p>
  </main>
</template>

<style scoped>
.page {
  max-width: 32rem;
  margin: 6rem auto;
  padding: 0 1.5rem;
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
  color: #1f2937;
}
h1 { font-size: 2rem; margin: 0 0 0.5rem; }
p { margin: 0 0 1.5rem; color: #4b5563; }
.btn-google {
  display: inline-flex;
  align-items: center;
  gap: 0.75rem;
  padding: 0.75rem 1.25rem;
  background: white;
  border: 1px solid #d1d5db;
  border-radius: 0.5rem;
  font-size: 1rem;
  font-weight: 500;
  color: #1f2937;
  cursor: pointer;
  transition: background-color 0.15s, box-shadow 0.15s;
}
.btn-google:hover { background: #f9fafb; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }
.btn-profile {
  display: inline-block;
  padding: 0.75rem 1.25rem;
  background: #1f2937;
  color: white;
  border-radius: 0.5rem;
  text-decoration: none;
  font-weight: 500;
}
.btn-profile:hover { background: #111827; }
.error {
  margin-top: 1.5rem;
  padding: 0.75rem 1rem;
  background: #fef2f2;
  border: 1px solid #fecaca;
  border-radius: 0.375rem;
  color: #991b1b;
}
</style>
