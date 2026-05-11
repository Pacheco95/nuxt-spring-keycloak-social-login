package com.example.backend.user

import org.assertj.core.api.Assertions.assertThat
import org.junit.jupiter.api.Test
import org.springframework.beans.factory.annotation.Autowired
import org.springframework.boot.data.jpa.test.autoconfigure.DataJpaTest
import org.springframework.security.oauth2.jwt.Jwt

@DataJpaTest
class UserUpsertServiceTest @Autowired constructor(private val userRepository: UserRepository) {

  private val service = UserUpsertService(userRepository)

  @Test
  fun `inserts a new user on first sight`() {
    val jwt = jwt(sub = "sub-1", email = "alice@example.com", name = "Alice", picture = "p1")

    val user = service.upsertFromJwt(jwt)

    assertThat(user.keycloakSub).isEqualTo("sub-1")
    assertThat(user.email).isEqualTo("alice@example.com")
    assertThat(user.name).isEqualTo("Alice")
    assertThat(user.picture).isEqualTo("p1")
    assertThat(userRepository.findByKeycloakSub("sub-1")).isNotNull
  }

  @Test
  fun `does not bump updatedAt when claims are unchanged`() {
    val jwt = jwt(sub = "sub-2", email = "bob@example.com", name = "Bob", picture = "p")
    val first = service.upsertFromJwt(jwt)
    val originalUpdatedAt = first.updatedAt

    val second = service.upsertFromJwt(jwt)

    assertThat(second.id).isEqualTo(first.id)
    assertThat(second.updatedAt).isEqualTo(originalUpdatedAt)
    assertThat(userRepository.count()).isEqualTo(1)
  }

  @Test
  fun `refreshes fields when a claim changes`() {
    val initial = jwt(sub = "sub-3", email = "carol@example.com", name = "Carol", picture = "old")
    val first = service.upsertFromJwt(initial)
    val originalUpdatedAt = first.updatedAt

    val changed = jwt(sub = "sub-3", email = "carol@example.com", name = "Carol", picture = "new")
    val second = service.upsertFromJwt(changed)

    assertThat(second.id).isEqualTo(first.id)
    assertThat(second.picture).isEqualTo("new")
    assertThat(second.updatedAt).isAfter(originalUpdatedAt)
    assertThat(userRepository.count()).isEqualTo(1)
  }

  @Test
  fun `derives name from given_name and family_name when name claim is missing`() {
    val jwt =
      Jwt.withTokenValue("t")
        .header("alg", "none")
        .subject("sub-4")
        .claim("email", "d@example.com")
        .claim("given_name", "Dana")
        .claim("family_name", "Doe")
        .build()

    val user = service.upsertFromJwt(jwt)

    assertThat(user.name).isEqualTo("Dana Doe")
  }

  @Test
  fun `falls back to preferred_username when no other name claims are present`() {
    val jwt =
      Jwt.withTokenValue("t")
        .header("alg", "none")
        .subject("sub-5")
        .claim("email", "e@example.com")
        .claim("preferred_username", "eve")
        .build()

    val user = service.upsertFromJwt(jwt)

    assertThat(user.name).isEqualTo("eve")
  }

  private fun jwt(sub: String, email: String?, name: String?, picture: String?): Jwt {
    val builder = Jwt.withTokenValue("token").header("alg", "none").subject(sub)
    if (email != null) builder.claim("email", email)
    if (name != null) builder.claim("name", name)
    if (picture != null) builder.claim("picture", picture)
    return builder.build()
  }
}
