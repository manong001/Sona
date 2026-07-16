package cc.eu.sosee.sona.config;

import cc.eu.sosee.sona.auth.SessionAuthenticationFilter;
import jakarta.servlet.http.HttpServletResponse;
import java.time.Clock;
import org.springframework.http.HttpMethod;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.AnonymousAuthenticationFilter;

@Configuration
class SecurityConfig {

    @Bean
    SecurityFilterChain securityFilterChain(
        HttpSecurity http,
        SessionAuthenticationFilter authenticationFilter
    ) throws Exception {
        return http
            .csrf(csrf -> csrf.disable())
            .sessionManagement(session -> session.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
            .authorizeHttpRequests(requests -> requests
                .requestMatchers("/error", "/api/v1/health", "/api/v1/auth/login").permitAll()
                .requestMatchers(
                    HttpMethod.POST,
                    "/api/v1/app/releases",
                    "/api/v1/app/releases/"
                ).hasRole("ADMIN")
                .requestMatchers(
                    "/api/v1/users/**",
                    "/api/v1/library/**",
                    "/api/v1/downloads/**",
                    "/api/v1/online-playback/sources/**"
                ).hasRole("ADMIN")
                .anyRequest().authenticated()
            )
            .exceptionHandling(errors -> errors
                .authenticationEntryPoint(
                    (request, response, exception) -> response.setStatus(HttpServletResponse.SC_UNAUTHORIZED)
                )
                .accessDeniedHandler(
                    (request, response, exception) -> response.setStatus(HttpServletResponse.SC_FORBIDDEN)
                )
            )
            .addFilterBefore(authenticationFilter, AnonymousAuthenticationFilter.class)
            .build();
    }

    @Bean
    PasswordEncoder passwordEncoder() {
        return new BCryptPasswordEncoder();
    }

    @Bean
    Clock clock() {
        return Clock.systemUTC();
    }
}
