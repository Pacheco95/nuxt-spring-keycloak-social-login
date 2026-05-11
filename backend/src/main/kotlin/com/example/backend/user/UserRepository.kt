package com.example.backend.user

import java.util.UUID
import org.springframework.data.jpa.repository.JpaRepository

interface UserRepository : JpaRepository<User, UUID> {
  fun findByKeycloakSub(keycloakSub: String): User?
}
