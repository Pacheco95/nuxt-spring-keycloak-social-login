package com.example.backend.user

import java.time.Instant
import org.springframework.security.oauth2.jwt.Jwt
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional

@Service
class UserUpsertService(private val userRepository: UserRepository) {

  @Transactional
  fun upsertFromJwt(jwt: Jwt): User {
    val sub = jwt.subject
    val email = jwt.getClaimAsString("email")
    val name = deriveName(jwt)
    val picture = jwt.getClaimAsString("picture")

    val existing = userRepository.findByKeycloakSub(sub)
    if (existing == null) {
      return userRepository.save(
        User(keycloakSub = sub, email = email, name = name, picture = picture)
      )
    }

    if (existing.email != email || existing.name != name || existing.picture != picture) {
      existing.email = email
      existing.name = name
      existing.picture = picture
      existing.updatedAt = Instant.now()
    }
    return existing
  }

  private fun deriveName(jwt: Jwt): String? {
    jwt.getClaimAsString("name")?.let {
      return it
    }
    val composed =
      listOfNotNull(jwt.getClaimAsString("given_name"), jwt.getClaimAsString("family_name"))
        .joinToString(" ")
        .ifBlank { null }
    if (composed != null) return composed
    return jwt.getClaimAsString("preferred_username")
  }
}
