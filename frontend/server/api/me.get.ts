// BFF proxy for the backend's /api/me. The browser never sees the access
// token: this handler decrypts it from the encrypted persistent session
// storage that nuxt-oidc-auth maintains, attaches it as a Bearer header,
// and returns whatever the backend produces.
import { decryptToken } from 'nuxt-oidc-auth/runtime/server/utils/security.js'
import { getUserSessionId } from 'nuxt-oidc-auth/runtime/server/utils/session.js'
import { createError, defineEventHandler } from 'h3'

interface MeResponse {
  sub: string
  name: string | null
  email: string | null
  picture: string | null
}

export default defineEventHandler(async (event): Promise<MeResponse> => {
  const sessionId = await getUserSessionId(event)
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const persistent = await useStorage('oidc').getItem<any>(sessionId)
  if (!persistent?.accessToken) {
    throw createError({ statusCode: 401, statusMessage: 'Not authenticated' })
  }

  const tokenKey = process.env.NUXT_OIDC_TOKEN_KEY
  if (!tokenKey) {
    throw createError({
      statusCode: 500,
      statusMessage: 'NUXT_OIDC_TOKEN_KEY is not set',
    })
  }

  const accessToken: string = await decryptToken(persistent.accessToken, tokenKey)

  const config = useRuntimeConfig(event)
  return await $fetch<MeResponse>(`${config.backendInternalUrl}/api/me`, {
    headers: { Authorization: `Bearer ${accessToken}` },
  })
})
