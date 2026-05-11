package com.example.backend.user

import jakarta.persistence.Column
import jakarta.persistence.Entity
import jakarta.persistence.Id
import jakarta.persistence.Table
import java.time.Instant
import java.util.UUID

@Entity
@Table(name = "users")
class User(
  @Id val id: UUID = UUID.randomUUID(),
  @Column(name = "keycloak_sub", nullable = false, unique = true) val keycloakSub: String,
  @Column(unique = true) var email: String?,
  @Column var name: String?,
  @Column(columnDefinition = "text") var picture: String?,
  @Column(name = "created_at", nullable = false, updatable = false)
  val createdAt: Instant = Instant.now(),
  @Column(name = "updated_at", nullable = false) var updatedAt: Instant = Instant.now(),
)
