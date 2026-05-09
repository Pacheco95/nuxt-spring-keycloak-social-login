package com.example.backend.api

import org.springframework.security.core.annotation.AuthenticationPrincipal
import org.springframework.security.oauth2.jwt.Jwt
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RestController

data class MeResponse(
    val sub: String,
    val name: String?,
    val email: String?,
    val picture: String?,
)

@RestController
@RequestMapping("/api")
class MeController {

    @GetMapping("/me")
    fun me(@AuthenticationPrincipal jwt: Jwt): MeResponse =
        MeResponse(
            sub = jwt.subject,
            name = jwt.getClaimAsString("name")
                ?: listOfNotNull(
                    jwt.getClaimAsString("given_name"),
                    jwt.getClaimAsString("family_name"),
                ).joinToString(" ").ifBlank { null }
                ?: jwt.getClaimAsString("preferred_username"),
            email = jwt.getClaimAsString("email"),
            picture = jwt.getClaimAsString("picture"),
        )
}
