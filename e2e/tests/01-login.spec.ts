import { expect, test } from '@playwright/test'

// Stories 001 + 002:
//  - "As a new user I want to access the home page and click Login with Google"
//  - "As a logged-in user I want to land on /profile and see name/email/picture"
test('clicking Login with Google walks the full chain to /profile with user details', async ({ page }) => {
  await page.goto('/')

  // Story 001: home page is accessible to a logged-out user and shows the
  // Login button.
  await expect(page.getByRole('heading', { name: 'Welcome' })).toBeVisible()
  const loginButton = page.getByRole('button', { name: /Login with Google/i })
  await expect(loginButton).toBeVisible()

  // Click the button. The browser is going to take several redirect hops:
  //   localhost:3000/auth/keycloak/login
  //   → localhost:8080/realms/.../protocol/openid-connect/auth?kc_idp_hint=google
  //   → mock-google /authorize (auto-redirects with a code)
  //   → localhost:8080/.../broker/google/endpoint
  //   → localhost:3000/auth/keycloak/callback
  //   → localhost:3000/profile
  await loginButton.click()

  // Story 002: end up on /profile with the fixture user's data.
  await page.waitForURL(/\/profile$/, { timeout: 30_000 })

  await expect(page.getByRole('heading', { name: 'Profile' })).toBeVisible()
  await expect(page.getByText('Test User')).toBeVisible()
  await expect(page.getByText('test.user@example.com')).toBeVisible()

  // Picture: the <img> must have the mock's avatar URL and must actually
  // load (not a broken-image placeholder).
  const avatar = page.locator('img.avatar')
  await expect(avatar).toBeVisible()
  await expect(avatar).toHaveAttribute('src', /\/avatar\.png$/)

  // Sanity: the image actually loads (naturalWidth > 0 means decoded).
  const naturalWidth = await avatar.evaluate(
    (img) => (img as HTMLImageElement).naturalWidth,
  )
  expect(naturalWidth).toBeGreaterThan(0)
})
