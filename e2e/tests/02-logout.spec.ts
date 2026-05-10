import { expect, test } from '@playwright/test'

// Story 003: from /profile, clicking "Log Out" terminates the session and
// returns the user to the home page; visiting /profile again must require
// re-authentication.
test('Log Out clears the BFF session and /profile becomes inaccessible', async ({ page }) => {
  // Log in.
  await page.goto('/')
  await page.getByRole('button', { name: /Login with Google/i }).click()
  await page.waitForURL(/\/profile$/, { timeout: 30_000 })

  // Click Log Out.
  await page.getByRole('button', { name: /Log Out/i }).click()

  // After RP-initiated logout the browser hops:
  //   /auth/keycloak/logout → Keycloak end_session_endpoint
  //   → post_logout_redirect_uri = /
  await page.waitForURL((url) => url.pathname === '/', { timeout: 30_000 })
  await expect(page.getByRole('button', { name: /Login with Google/i })).toBeVisible()

  // Direct navigation to /profile must NOT silently render — the global
  // oidcAuth middleware should redirect into the OAuth flow. We don't need
  // to complete it; reaching Keycloak (or the mock) is enough proof that
  // the BFF session was cleared.
  await page.goto('/profile')
  await page.waitForURL(
    (url) =>
      url.host !== 'localhost:3000'
      || url.pathname.startsWith('/auth/'),
    { timeout: 30_000 },
  )
  expect(page.url()).not.toContain('/profile')
})
