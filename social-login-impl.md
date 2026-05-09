# Project Context

This is a greenfield full stack monorepo project that will be used as a foundation to implement social login using Keycloak as an identity broker.


## Backend

The backend is a REST API made with `Kotlin` and `Sprint Boot 4`.


## Frontend

The frontend is a SSR `Nuxt 4` application.


## Implementation requirements

- Today is May 9th, 2026. Be sure to check the date of online search results to be close to this date and avoid using outdated content.
- The frontend has SSR enabled and will be used as a BFF
- The authentication will be implemented with keycloak 26
- The project should be configured using docker compose
- **VERY IMPORTANT!**: All the relevant project configuration should be defined in environment variables in a `.env` file in the project root directory.
It will be used as the source of truth configuration for **ALL** docker compose services.
- A file `.env.example` should be added to the root directory, but remove any sensitive values from it. This file should be commited.
- Use Postgres 16 to store Keycloak data
- Use Postgres 16 to store backend data
- Do not use the same database for keycloak and the backend
- The keycloak realm should be auto-configured when the docker compose starts for the first time. One possible sollution is to use [Keycloak Admin CLI](https://www.keycloak.org/docs/latest/server_admin/index.html)
- Addd a PgAdmin service and auto configure servers for both keycloak and backend database.
- All the infrastructure directory tree configuration, including docker compose, should be inside a directory called `infra` in the project root directory.
- Add relevant commands that will be used often to a `Makefile` in the project root directory.
- The backend project already have useful installed dependencies but you can install others if necessary.
- The frontend does not have any extra libraries installed, it is a very minimalistic Nuxt project. You can install extra packages if necessary. `nuxt-oidc-auth` is prpably one of them that you will have to install to make the authentication work.
- 



## Authentication flow (summary)

1. User clicks "Login with Google" in Nuxt
2. Nuxt (BFF) initiates the OAuth Authorization Code Flow + PKCE with Keycloak
3. Keycloak redirects the browser to Google (Identity Brokering)
4. User authenticates with Google
5. Google redirects back to Keycloak with an authorization code
6. Keycloak exchanges the code for tokens with Google (server-to-server)
7. Keycloak creates/updates the internal user based on the Google ID Token
8. Keycloak redirects the browser back to the Nuxt BFF with its own authorization code
9. **Nuxt BFF** (not the browser) exchanges the code for tokens with Keycloak (server-to-server, using the PKCE verifier)
10. BFF stores tokens in a server-side session and sends a session cookie (HttpOnly, Secure, SameSite=Lax) to the browser
11. On subsequent requests, the browser sends the session cookie; the BFF attaches the Bearer token and calls Spring Boot
12. Spring Boot validates the JWT using Keycloak’s public key (cached via JWKS)


## Why this architecture

- **BFF Pattern:** tokens never reach the browser. XSS cannot exfiltrate reusable credentials. Only the session cookie circulates in the browser.
- **Keycloak as an Identity Broker:** Spring Boot and Nuxt never interact directly with Google. Adding GitHub, Microsoft, or email/password login in the future is just a Keycloak configuration change — zero code changes.
- **JWT locally validated in Spring Boot:** Spring fetches Keycloak’s public key once (via the JWKS endpoint), caches it, and validates signatures locally. Stateless and scalable.
- **Authorization Code Flow + PKCE:** current industry standard. Tokens never pass through the browser; only the authorization code (short-lived, single-use, disposable) travels via redirect.


# Before implementation begins

- Read all the rquirements and tech stack and propose a directory structure for the `infra` related files.
- Suggest a naming convention to environment variables.


# User stories

## User story 001

**As a** new unregistered user
**I want to** access the home page and click a button "Login with Google"
**So that** I can login into the application using my google account.


## User story 002

**As a** user that just logged in with my google accout
**I want to** be redirected to `/profile` page
**So that** I can confirm my registration/login was sucessfull and see my name, email and profile picture.


## User story 003

**As a** logged in user in the `/profile` page
**I want to** be able to click a button labeled `Log Out`
**So that** I can log out from the application and be redirected to the home page.


## User story 004

**As a** logged in user
**I want to** stay logged in until I explicitly log out or my token expires
**So that** I can navigate the application smootlhy without being force to login every time


## User story 005

**As a** user attempting to login with my google account
**I want to** be visually informed with meaningfull error messages that happened during my login attempt
**So that** I'm well instructed to understand what went wrong and instructed to login sucessfully in the next attempt.


## User story 006

**As a** new team member developer
**I want to** have a project level README.md file containing all the necessary instrution on how to spin up the project for the first time such as enviroment variables and google account configuration.
**So that** I can quickly start contributing to the project without spending much time trying to understand and configure the project on my local machine.
