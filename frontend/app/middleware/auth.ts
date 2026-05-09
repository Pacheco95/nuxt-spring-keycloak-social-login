// Sends unauthenticated visitors of protected pages back home with an error
// flag the index page can render (story 005).
export default defineNuxtRouteMiddleware((to) => {
  const { loggedIn } = useOidcAuth()
  if (!loggedIn.value) {
    return navigateTo({
      path: '/',
      query: { ...(to.query.error ? { error: to.query.error } : { error: 'login_required' }) },
    })
  }
})
