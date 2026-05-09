<script setup lang="ts">
interface MeResponse {
  sub: string
  name: string | null
  email: string | null
  picture: string | null
}

// Authentication is enforced by the global oidcAuth middleware (fail-closed
// default in nuxt.config.ts). Unauthenticated visitors are kicked into the
// OAuth flow with a callbackRedirectUrl that brings them back here.
const { logout } = useOidcAuth()

// SSR-friendly fetch through the BFF proxy. The bearer token is attached
// server-side; the browser never sees it.
const { data: me, error, status } = await useFetch<MeResponse>('/api/me')

async function handleLogout() {
  await logout('keycloak')
}
</script>

<template>
  <main class="page">
    <h1>Profile</h1>

    <div v-if="status === 'pending'" class="loading">Loading…</div>

    <div v-else-if="error" class="error" role="alert">
      We could not load your profile right now.
      <span v-if="error?.statusCode">(HTTP {{ error.statusCode }})</span>
    </div>

    <div v-else-if="me" class="profile">
      <img
        v-if="me.picture"
        :src="me.picture"
        :alt="me.name ? `${me.name}'s profile picture` : 'Profile picture'"
        class="avatar"
        referrerpolicy="no-referrer"
      >
      <div v-else class="avatar avatar-placeholder" aria-hidden="true">
        {{ (me.name ?? me.email ?? '?').charAt(0).toUpperCase() }}
      </div>
      <dl>
        <dt>Name</dt>
        <dd>{{ me.name ?? '—' }}</dd>
        <dt>Email</dt>
        <dd>{{ me.email ?? '—' }}</dd>
      </dl>
    </div>

    <button class="btn-logout" type="button" @click="handleLogout">
      Log Out
    </button>
  </main>
</template>

<style scoped>
.page {
  max-width: 32rem;
  margin: 4rem auto;
  padding: 0 1.5rem;
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
  color: #1f2937;
}
h1 { font-size: 1.875rem; margin: 0 0 1.5rem; }
.loading { color: #6b7280; }
.error {
  padding: 0.75rem 1rem;
  background: #fef2f2;
  border: 1px solid #fecaca;
  border-radius: 0.375rem;
  color: #991b1b;
  margin-bottom: 1.5rem;
}
.profile {
  display: grid;
  grid-template-columns: auto 1fr;
  gap: 1.5rem;
  align-items: start;
  margin-bottom: 2rem;
}
.avatar {
  width: 96px;
  height: 96px;
  border-radius: 50%;
  object-fit: cover;
  background: #e5e7eb;
}
.avatar-placeholder {
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 2.5rem;
  font-weight: 600;
  color: #6b7280;
}
dl { margin: 0; display: grid; grid-template-columns: max-content 1fr; gap: 0.25rem 1rem; }
dt { color: #6b7280; font-size: 0.875rem; }
dd { margin: 0; }
.btn-logout {
  padding: 0.5rem 1rem;
  background: white;
  border: 1px solid #d1d5db;
  border-radius: 0.375rem;
  font-size: 0.875rem;
  font-weight: 500;
  cursor: pointer;
  color: #1f2937;
}
.btn-logout:hover { background: #f9fafb; }
</style>
