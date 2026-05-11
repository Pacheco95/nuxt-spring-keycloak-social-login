package com.example.backend.security

import com.example.backend.user.UserUpsertService
import org.springframework.core.convert.converter.Converter
import org.springframework.security.authentication.AbstractAuthenticationToken
import org.springframework.security.oauth2.jwt.Jwt
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationConverter
import org.springframework.stereotype.Component

@Component
class JwtUserUpsertConverter(private val userUpsertService: UserUpsertService) :
  Converter<Jwt, AbstractAuthenticationToken> {

  private val delegate = JwtAuthenticationConverter()

  override fun convert(jwt: Jwt): AbstractAuthenticationToken {
    userUpsertService.upsertFromJwt(jwt)
    return delegate.convert(jwt)!!
  }
}
