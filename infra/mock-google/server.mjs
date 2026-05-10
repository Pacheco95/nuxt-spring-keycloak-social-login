// Tiny mock OIDC provider used in place of accounts.google.com during
// `make test-e2e`. Speaks the OIDC subset Keycloak needs to broker (discovery,
// authorize, token, userinfo, JWKS) and issues ID tokens with the same shape
// Google would: email, email_verified, name, given_name, family_name, picture.
//
// Hostname pinning: the issuer is set to MOCK_GOOGLE_PUBLIC_URL (the host-
// mapped URL the browser sees) so the iss claim matches even though Keycloak
// reaches /token and /jwks via the in-network compose service name. Same trap
// as the real Keycloak setup — see CLAUDE.md.
import { OAuth2Server } from 'oauth2-mock-server'

const port = Number.parseInt(process.env.MOCK_GOOGLE_PORT ?? '9000', 10)
const publicUrl = process.env.MOCK_GOOGLE_PUBLIC_URL ?? `http://localhost:${port}`

const server = new OAuth2Server()
await server.issuer.keys.generate('RS256')
server.issuer.url = publicUrl

const fixture = {
  sub: 'mock-google-test-user',
  email: 'test.user@example.com',
  email_verified: true,
  name: 'Test User',
  given_name: 'Test',
  family_name: 'User',
  picture: `${publicUrl}/avatar.png`,
}

server.service.on('beforeTokenSigning', (token) => {
  Object.assign(token.payload, fixture)
})

server.service.on('beforeUserinfo', (userInfoResponse) => {
  userInfoResponse.body = { ...userInfoResponse.body, ...fixture }
})

// 1x1 transparent PNG so the BFF's <img> on /profile resolves rather than
// showing a broken-image icon during e2e tests.
const tinyPng = Buffer.from(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg==',
  'base64',
)
server.service.requestHandler.get('/avatar.png', (_req, res) => {
  res.set('Content-Type', 'image/png')
  res.send(tinyPng)
})

await server.start(port, '0.0.0.0')
console.log(`[mock-google] listening on :${port}, issuer=${publicUrl}`)
