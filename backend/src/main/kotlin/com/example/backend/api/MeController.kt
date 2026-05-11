package com.example.backend.api

import com.example.backend.user.UserRepository
import java.util.UUID
import org.springframework.security.core.annotation.AuthenticationPrincipal
import org.springframework.security.oauth2.jwt.Jwt
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RestController

data class MeResponse(
  val id: UUID,
  val sub: String,
  val name: String,
  val email: String,
  val picture: String?,
)

@RestController
@RequestMapping("/api")
class MeController(private val userRepository: UserRepository) {

  @GetMapping("/me")
  fun me(@AuthenticationPrincipal jwt: Jwt): MeResponse {
    val user =
      userRepository.findByKeycloakSub(jwt.subject)
        ?: error("Authenticated user not persisted: ${jwt.subject}")
    return MeResponse(
      id = user.id,
      sub = user.keycloakSub,
      name = user.name,
      email = user.email,
      picture = user.picture,
    )
  }
}
