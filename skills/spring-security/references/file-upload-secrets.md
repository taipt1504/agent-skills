# File Upload Security and Secrets Management Reference

File upload validation, path traversal prevention, and secrets management.

---

## File Upload Validation

```java
@Component
public class FileValidator {
    private static final Set<String> ALLOWED_EXTENSIONS = Set.of("jpg","jpeg","png","pdf","docx");
    private static final long MAX_SIZE = 5 * 1024 * 1024L;  // 5MB

    // Validate by magic bytes -- extensions can be spoofed
    private static final Map<byte[], String> MAGIC_BYTES = Map.of(
        new byte[]{(byte)0xFF, (byte)0xD8, (byte)0xFF}, "image/jpeg",
        new byte[]{(byte)0x89, 0x50, 0x4E, 0x47}, "image/png",
        new byte[]{0x25, 0x50, 0x44, 0x46}, "application/pdf"
    );

    public Mono<Void> validate(FilePart file) {
        String filename = StringUtils.cleanPath(file.filename());
        if (filename.contains("..") || filename.contains("/")) {
            return Mono.error(new BadRequestException("Invalid filename"));
        }
        String ext = getExtension(filename).toLowerCase();
        if (!ALLOWED_EXTENSIONS.contains(ext)) {
            return Mono.error(new BadRequestException("File type not allowed: " + ext));
        }
        long size = file.headers().getContentLength();
        if (size > MAX_SIZE) {
            return Mono.error(new BadRequestException("File too large"));
        }
        return Mono.empty();
    }
}
```

---

## Path Traversal Prevention

```java
@Service
public class SecureFileService {
    private final Path uploadRoot;

    public Mono<Path> resolveSecurely(String filename) {
        Path resolved = uploadRoot.resolve(StringUtils.cleanPath(filename)).normalize();
        if (!resolved.startsWith(uploadRoot)) {
            return Mono.error(new SecurityException("Path traversal detected"));
        }
        return Mono.just(resolved);
    }
}
```

---

## Secrets Management

Use a record for `@ConfigurationProperties` (idiomatic Java 17+). Never use a class with setters.

```java
// CORRECT: record form (immutable, Java 17+)
@ConfigurationProperties(prefix = "app.jwt")
@Validated
public record JwtProperties(
    @NotBlank String secret,
    @Positive long expirationMs,
    @NotBlank String issuer
) {}
```

```yaml
# application.yml -- reference env vars, never hardcode values
app:
  jwt:
    secret: ${JWT_SECRET}
    expiration-ms: ${JWT_EXPIRATION:3600000}
    issuer: ${JWT_ISSUER:my-app}
```

For broader security properties:

```java
@ConfigurationProperties(prefix = "app.security")
@Validated
public record SecurityProperties(
    @NotBlank String jwtSecret,
    @NotNull Duration jwtExpiration,
    @NotBlank String encryptionKey
) {}
```

```yaml
# application.yml
app:
  security:
    jwt-secret: ${JWT_SECRET}
    jwt-expiration: ${JWT_EXPIRATION:1h}
    encryption-key: ${ENCRYPTION_KEY}

# For Vault (Spring Cloud Vault)
spring:
  cloud:
    vault:
      host: vault.example.com
      authentication: KUBERNETES
      kv:
        enabled: true
        default-context: order-service
```

### .gitignore Rules

```
# Secrets
.env
*.pem
*.key
application-local.yml
application-secret.yml
```
