# Security Testing Reference

Security testing patterns for MVC (MockMvc) and WebFlux (WebTestClient).

---

## Security Testing (MockMvc)

For MVC-based applications using `MockMvc`.

```java
@WebMvcTest(OrderController.class)
@Import(SecurityConfig.class)
class OrderControllerSecurityTest {

    @Autowired
    private MockMvc mockMvc;

    @MockBean
    private OrderService orderService;

    @Test
    void shouldReturn401WhenNoToken() throws Exception {
        mockMvc.perform(get("/api/v1/orders"))
            .andExpect(status().isUnauthorized());
    }

    @Test
    @WithMockUser(roles = "USER")
    void shouldReturn403WhenInsufficientRole() throws Exception {
        mockMvc.perform(get("/api/v1/admin/users"))
            .andExpect(status().isForbidden());
    }

    @Test
    @WithMockUser(roles = "ADMIN")
    void shouldReturn200WithAdminRole() throws Exception {
        mockMvc.perform(get("/api/v1/admin/users"))
            .andExpect(status().isOk());
    }

    @Test
    void shouldRejectSqlInjectionAttempt() throws Exception {
        mockMvc.perform(get("/api/v1/users")
                .param("name", "'; DROP TABLE users; --")
                .with(user("testuser").roles("USER")))
            .andExpect(status().isBadRequest());
    }
}
```

---

## Security Testing (WebTestClient)

For WebFlux-based applications.

```java
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class SecurityIntegrationTest {

    @Autowired
    private WebTestClient webTestClient;

    @Test
    void shouldReturn401WhenNoToken() {
        webTestClient.get().uri("/api/v1/orders")
            .exchange()
            .expectStatus().isUnauthorized();
    }

    @Test
    void shouldReturn403WhenInsufficientRole() {
        webTestClient.get().uri("/api/v1/admin/users")
            .headers(h -> h.setBearerAuth(tokenForRole("USER")))
            .exchange()
            .expectStatus().isForbidden();
    }

    @Test
    void shouldReturn200WithValidAdminToken() {
        webTestClient.get().uri("/api/v1/admin/users")
            .headers(h -> h.setBearerAuth(tokenForRole("ADMIN")))
            .exchange()
            .expectStatus().isOk();
    }

    @Test
    void shouldRejectSqlInjectionAttempt() {
        webTestClient.get()
            .uri(u -> u.path("/api/v1/users").queryParam("name", "'; DROP TABLE users; --").build())
            .headers(h -> h.setBearerAuth(userToken()))
            .exchange()
            .expectStatus().isBadRequest();
    }

    @Test
    void shouldIncludeSecurityHeaders() {
        webTestClient.get().uri("/api/v1/public/health")
            .exchange()
            .expectHeader().valueEquals("X-Content-Type-Options", "nosniff")
            .expectHeader().valueEquals("X-Frame-Options", "DENY");
    }

    @Test
    void shouldNotExposeInternalErrorDetails() {
        webTestClient.get().uri("/api/v1/orders/trigger-error")
            .headers(h -> h.setBearerAuth(userToken()))
            .exchange()
            .expectStatus().is5xxServerError()
            .expectBody()
            .jsonPath("$.detail").isEqualTo("An unexpected error occurred")
            .jsonPath("$.stackTrace").doesNotExist();
    }

    private String tokenForRole(String role) {
        return jwtProvider.generate("test-user", List.of(role));
    }
}
```

---

## OWASP Dependency Scanning

### Gradle Configuration

```groovy
// build.gradle
plugins {
    id 'org.owasp.dependencycheck' version '9.0.0'
}

dependencyCheck {
    failBuildOnCVSS = 7      // Block on HIGH/CRITICAL
    formats = ['HTML', 'JSON']
    suppressionFile = 'owasp-suppressions.xml'
}
```

Run: `./gradlew dependencyCheckAnalyze`

### CI/CD Integration

- Enable Dependabot or Renovate for automated dependency updates
- Run OWASP scan in CI pipeline, fail build on CVSS >= 7
- Review and update `owasp-suppressions.xml` for false positives
