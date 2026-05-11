package com.example.backend.security

import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Configuration
import org.springframework.http.HttpMethod
import org.springframework.security.config.annotation.web.builders.HttpSecurity
import org.springframework.security.config.http.SessionCreationPolicy
import org.springframework.security.web.SecurityFilterChain

@Configuration
class SecurityConfig {

  @Bean
  fun securityFilterChain(http: HttpSecurity): SecurityFilterChain {
    http
      .csrf { it.disable() }
      .cors {}
      .sessionManagement { it.sessionCreationPolicy(SessionCreationPolicy.STATELESS) }
      .authorizeHttpRequests {
        it
          .requestMatchers(HttpMethod.GET, "/actuator/health/**", "/actuator/info")
          .permitAll()
          .requestMatchers("/v3/api-docs/**", "/swagger-ui/**", "/swagger-ui.html")
          .permitAll()
          .anyRequest()
          .authenticated()
      }
      .oauth2ResourceServer { resourceServer -> resourceServer.jwt {} }
    return http.build()
  }
}
