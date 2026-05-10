import { expect, test } from '@playwright/test'

// Story 005: meaningful error messages when login fails. The home page
// renders human-readable strings for OIDC error codes arriving as ?error=...
// query parameters.
test.describe('error message rendering', () => {
  test('access_denied surfaces a helpful message', async ({ page }) => {
    await page.goto('/?error=access_denied')
    await expect(
      page.getByText(
        /Access was denied\. You may have cancelled the Google sign-in/,
      ),
    ).toBeVisible()
  })

  test('login_required surfaces its message', async ({ page }) => {
    await page.goto('/?error=login_required')
    await expect(
      page.getByText(/You need to sign in again to continue/),
    ).toBeVisible()
  })

  test('unknown error code falls back to a generic message with the code', async ({ page }) => {
    await page.goto('/?error=mysterious_failure_42')
    await expect(
      page.getByText(/Sign-in failed \(mysterious_failure_42\)/),
    ).toBeVisible()
  })
})
