package com.example.backend.user

import org.assertj.core.api.Assertions.assertThat
import org.assertj.core.api.Assertions.assertThatIllegalStateException
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
  fun `prefers preferred_username over name and given_name family_name`() {
    val jwt =
      Jwt.withTokenValue("t")
        .header("alg", "none")
        .subject("sub-4")
        .claim("email", "d@example.com")
        .claim("preferred_username", "dana")
        .claim("name", "Dana Doe")
        .claim("given_name", "Dana")
        .claim("family_name", "Doe")
        .build()

    val user = service.upsertFromJwt(jwt)

    assertThat(user.name).isEqualTo("dana")
  }

  @Test
  fun `falls back to name claim when preferred_username is missing`() {
    val jwt =
      Jwt.withTokenValue("t")
        .header("alg", "none")
        .subject("sub-5")
        .claim("email", "e@example.com")
        .claim("name", "Eve Evans")
        .build()

    val user = service.upsertFromJwt(jwt)

    assertThat(user.name).isEqualTo("Eve Evans")
  }

  @Test
  fun `falls back to given_name and family_name when preferred_username and name are missing`() {
    val jwt =
      Jwt.withTokenValue("t")
        .header("alg", "none")
        .subject("sub-6")
        .claim("email", "f@example.com")
        .claim("given_name", "Frank")
        .claim("family_name", "Foster")
        .build()

    val user = service.upsertFromJwt(jwt)

    assertThat(user.name).isEqualTo("Frank Foster")
  }

  @Test
  fun `throws when the email claim is missing`() {
    val jwt =
      Jwt.withTokenValue("t").header("alg", "none").subject("sub-7").claim("name", "Frank").build()

    assertThatIllegalStateException().isThrownBy { service.upsertFromJwt(jwt) }
  }

  @Test
  fun `throws when no name claim chain can be resolved`() {
    val jwt =
      Jwt.withTokenValue("t")
        .header("alg", "none")
        .subject("sub-8")
        .claim("email", "g@example.com")
        .build()

    assertThatIllegalStateException().isThrownBy { service.upsertFromJwt(jwt) }
  }

  private fun jwt(sub: String, email: String, name: String, picture: String?): Jwt {
    val builder =
      Jwt.withTokenValue("token")
        .header("alg", "none")
        .subject(sub)
        .claim("email", email)
        .claim("name", name)
    if (picture != null) builder.claim("picture", picture)
    return builder.build()
  }
}
