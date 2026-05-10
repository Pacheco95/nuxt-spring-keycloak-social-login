import { expect, test } from '@playwright/test'

// Story 004: stay logged in across navigations and full reloads until
// explicit logout or token expiry.
test('session survives reloads and home-and-back navigation', async ({ page }) => {
  // Log in.
  await page.goto('/')
  await page.getByRole('button', { name: /Login with Google/i }).click()
  await page.waitForURL(/\/profile$/, { timeout: 30_000 })
  await expect(page.getByText('Test User')).toBeVisible()

  // Full reload — session cookie must round-trip and the page must render
  // again without re-running the OAuth flow.
  await page.reload()
  await expect(page).toHaveURL(/\/profile$/)
  await expect(page.getByText('Test User')).toBeVisible()

  // Navigate home, then back to /profile. Going home while logged in should
  // keep us on / (the previous bug auto-redirected back to /profile and
  // trapped the user). The home page should now show a "Go to your profile"
  // link instead of the Login button.
  await page.goto('/')
  await expect(page).toHaveURL(/\/$/)
  await expect(page.getByRole('link', { name: /Go to your profile/i })).toBeVisible()
  await expect(page.getByRole('button', { name: /Login with Google/i })).toHaveCount(0)

  // Click the link → straight to /profile, no OAuth roundtrip.
  await page.getByRole('link', { name: /Go to your profile/i }).click()
  await page.waitForURL(/\/profile$/, { timeout: 5_000 })
  await expect(page.getByText('Test User')).toBeVisible()
})
