# API Documentation

Generate or update OpenAPI/Swagger documentation for REST endpoints.

## Instructions

1. Check existing OpenAPI configuration:

```bash
# Find SpringDoc / Swagger config
grep -rn "springdoc\|openapi\|swagger" --include="*.yml" --include="*.java" src/ | head -20

# Find controllers to document
find src/main/java -name "*Controller.java" | head -20

# Check existing API docs annotations
grep -rn "@Operation\|@Tag\|@ApiResponse\|@Schema" --include="*.java" src/main/ | wc -l
```

2. Check `build.gradle` or `pom.xml` for springdoc dependency:

```bash
grep -n "springdoc\|springfox" build.gradle pom.xml 2>/dev/null
```

3. If springdoc is missing, provide the dependency to add:

```xml
<!-- Maven: pom.xml -->
<dependency>
    <groupId>org.springdoc</groupId>
    <artifactId>springdoc-openapi-starter-webmvc-ui</artifactId>
    <version>2.3.0</version>
</dependency>
<!-- For WebFlux: use springdoc-openapi-starter-webflux-ui -->
```

```groovy
// Gradle: build.gradle
implementation 'org.springdoc:springdoc-openapi-starter-webmvc-ui:2.3.0'
```

4. Add or update the `OpenApiConfig` bean if it doesn't exist:

```java
@Configuration
public class OpenApiConfig {

    @Bean
    public OpenAPI openAPI() {
        return new OpenAPI()
            .info(new Info()
                .title("${spring.application.name} API")
                .version("1.0.0")
                .description("REST API documentation")
                .contact(new Contact().name("Backend Team").email("dev@example.com"))
                .license(new License().name("Internal")))
            .components(new Components()
                .addSecuritySchemes("bearerAuth",
                    new SecurityScheme()
                        .type(SecurityScheme.Type.HTTP)
                        .scheme("bearer")
                        .bearerFormat("JWT")))
            .addSecurityItem(new SecurityRequirement().addList("bearerAuth"));
    }
}
```

5. For each controller provided (or changed in recent diff), add/update OpenAPI annotations:

```java
// Controller-level @Tag
@Tag(name = "Orders", description = "Order management — create, retrieve, update, cancel orders")
@RestController
@RequestMapping("/api/v1/orders")
public class OrderController {

    // Method-level @Operation
    @Operation(
        summary = "Create a new order",
        description = "Creates an order for the authenticated user. Items must reference valid product IDs.",
        responses = {
            @ApiResponse(responseCode = "201", description = "Order created",
                content = @Content(schema = @Schema(implementation = OrderResponse.class))),
            @ApiResponse(responseCode = "400", description = "Validation error",
                content = @Content(schema = @Schema(implementation = ApiResponse.class))),
            @ApiResponse(responseCode = "401", description = "Unauthenticated")
        })
    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public OrderResponse createOrder(@Valid @RequestBody CreateOrderRequest request) { ... }

    @Operation(summary = "Get order by ID")
    @ApiResponse(responseCode = "404", description = "Order not found")
    @GetMapping("/{id}")
    public ResponseEntity<OrderResponse> getOrder(@PathVariable Long id) { ... }
}
```

6. Annotate request/response DTOs:

```java
// ✅ @Schema on record fields
public record CreateOrderRequest(
    @Schema(description = "User ID placing the order", example = "42", requiredMode = REQUIRED)
    @NotNull Long userId,

    @Schema(description = "List of items to order", minItems = 1)
    @NotEmpty List<@Valid OrderItemRequest> items,

    @Schema(description = "Delivery address", example = "123 Main St, HCMC")
    @NotBlank String deliveryAddress
) {}

public record OrderResponse(
    @Schema(description = "Unique order ID", example = "1001")
    Long id,

    @Schema(description = "Order status", allowableValues = {"PENDING","CONFIRMED","SHIPPED","CANCELLED"})
    String status,

    @Schema(description = "Total order amount in USD", example = "99.99")
    BigDecimal totalAmount
) {}
```

7. Update `application.yml` for SpringDoc:

```yaml
springdoc:
  api-docs:
    path: /v3/api-docs
  swagger-ui:
    path: /swagger-ui.html
    operations-sorter: alpha
    tags-sorter: alpha
    display-request-duration: true
  show-actuator: false
```

8. Verify the documentation is accessible:

```bash
# Start the application and check Swagger UI
echo "Swagger UI: http://localhost:8080/swagger-ui.html"
echo "OpenAPI JSON: http://localhost:8080/v3/api-docs"
```

## Output

```
API Documentation updated:

Files modified:
- {list of modified files}

Endpoints documented:
- POST /api/v1/{resource} — {summary}
- GET  /api/v1/{resource}/{id} — {summary}
- ...

Access at: http://localhost:8080/swagger-ui.html (when running)

Missing documentation:
- {Any endpoints still lacking @Operation}
```
