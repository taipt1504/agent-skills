---
name: summer-handler-api
description: SUMMER-SPECIFIC. Handler/REST API standards — Controller→Handler dispatch via SpringBus, BaseController.execute(), pagination via PageResponse, typed request/response DTOs, CommonResponse envelope. Loaded ONLY when project uses io.f8a.summer.
globs: "*.java"
applicability:
  always: false
  requires_summer: true
  triggers:
    project_profile: ["summer:true"]
    files_match: ["**/*Controller.java", "**/*Handler.java", "**/api/dto/request/**", "**/api/dto/response/**"]
    code_patterns: ["BaseController", "RequestHandler", "SpringBus", "this.execute(", "RequestContext.fromSecurityContext", "PageResponse", "CommonResponse"]
    task_keywords: ["Summer handler", "BaseController", "SpringBus", "request handler", "PageResponse", "CommonResponse"]
    related_rules:
      - rules/java/api-design.md
      - rules/summer/audit.md
relevance_assessment: |
  HIGH 100%: Summer project AND new/modified REST endpoint
  HIGH 80%+: Summer project AND handler/DTO changes
  MEDIUM 40-79%: Summer project, tangential touch (e.g., reads handler result)
  LOW 1-39%: Summer project, no controller/handler in scope
  ZERO: project does NOT use Summer — generic Spring patterns apply, see rules/java/api-design.md
---

# Handler API Standards (Summer SpringBus dispatch)

Cluster-wide REST handler conventions for Summer-based services. Mandatory for all 11 Summer services in ewallet cluster.

## Standard 0 — Controller → Handler dispatch via SpringBus (HARD BLOCK)

Controller MUST use `BaseController.execute(request)` → SpringBus dispatches to handler. CẤM inject Handler bean directly into Controller.

```java
@RestController
@RequestMapping("/internal/api/v1/foo")
@RequiredArgsConstructor
public class FooController extends BaseController {

    @PostMapping("/bar")
    public Mono<ResponseEntity<FooResponse>> bar(@Valid @RequestBody FooRequest request) {
        return this.execute(request);   // SpringBus auto-dispatch
    }
}
```

**Mandatory:**
1. Controller `extends BaseController`
2. Method body = `return this.execute(request);` — NO inline business logic
3. Controller MUST NOT inject Handler bean
4. Handler `extends RequestHandler<Req, Res>` + `@Component`
5. Each request type maps to EXACTLY 1 handler

## Standard 1 — Request DTO (one canonical POJO per use case)

1 use case → 1 request DTO at `api/dto/request/{domain}/{UseCase}Request.java`.


```java
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@FieldDefaults(level = AccessLevel.PRIVATE)
public class RejectOnboardingApplicationRequest {

    @JsonIgnore                                       // path variable
    String applicationId;

    @NotBlank @Size(min = 50, max = 500)              // body field
    String reason;
}
```

Field annotations:
- `@JsonIgnore` for path variable (injected via setter, not body)
- `@Hidden` (Springdoc) for hidden params
- `@JsonIgnore` for SecurityContext-derived fields

**POJO over `record`:** setter needed for path-variable injection. Records are immutable → constructor-in-controller = anti-pattern.

Controller body with path var:

```java
@PostMapping("/{id}/reject")
public Mono<ResponseEntity<OnboardingApplicationResponse>> reject(
    @PathVariable("id") String id,
    @Valid @RequestBody RejectOnboardingApplicationRequest request) {
  request.setApplicationId(id);
  return this.execute(request);
}
```

2-statement body OK — `setX(pathVar)` is mechanical glue, not business logic.

## Standard 2 — Handler accesses SecurityContext (NOT in request DTO)

```java
public class RejectOnboardingApplicationHandler
    extends RequestHandler<RejectOnboardingApplicationRequest, OnboardingApplicationResponse> {

    @Override
    public Mono<OnboardingApplicationResponse> handle(RejectOnboardingApplicationRequest req) {
        return RequestContext.fromSecurityContext()
            .flatMap(ctx -> service.reject(req, UUID.fromString(ctx.getActorId())));
    }
}
```

See `rules/summer/audit.md` for caller-aware context propagation.

## Standard 3 — Custom HTTP shapes

- Status code: `@ResponseStatus(HttpStatus.CREATED)` on POST create. NO `ResponseEntity` construction.
- Idempotent replay: encode in response body field (`alreadyExists: boolean`), not in header.
- Path var: wrap into DTO via setter. NOT a separate handler parameter.

## Standard 4 — Pagination via PageResponse

List endpoints on large-data domains MUST return `PageResponse<T>`. NEVER `List<T>` for unbounded lists.

```java
// core/model/request/PageableRequest.java
@Getter @Setter
public abstract class PageableRequest {
    @Min(0)
    private int page = 0;

    @Min(1) @Max(100)
    private int size = 20;

    private String sort;
}
```

Cluster-standard `PageResponse<T>` shape:

```json
{
  "content": [...],
  "page": 0,
  "size": 20,
  "totalElements": 1234,
  "totalPages": 62
}
```

## Standard 5 — Layering

Strict handler → service → repository. NEVER:
- Controller → service (skips handler)
- Handler → repository (skips service)
- Service → controller (reverse coupling)

## Anti-patterns (BUILD reject)

| Anti-pattern | Why blocked |
|---|---|
| `private final FooHandler fooHandler;` in Controller | Direct injection bypasses SpringBus dispatch |
| `return fooHandler.handle(request).map(...);` in Controller | Inline business logic in controller |
| Handler NOT extending `RequestHandler<Req, Res>` | Breaks SpringBus contract |
| Handler annotated `@Service` instead of `@Component` | Wrong stereotype for dispatch registry |
| Controller method > 5 LOC of business logic | Controller is dispatch only |
| Controller extracts `SecurityContext` | Handler's responsibility, not controller's |
| List endpoint returns `List<T>` directly (no pagination) | Unbounded — memory + latency risk |
| Path variable as separate Handler param (not in DTO) | DTO is single canonical request shape |
| Multiple handlers per request type | EXACTLY 1 handler per request type |

## Cross-skill integration

When this rule applies:
- Load `skills/summer-rest` for `BaseController` / `RequestHandler` deep dive
- Load `skills/summer-data` for cross-handler audit-field propagation
- Load `skills/api-design` for response envelope + RFC 7807 errors
- Load `rules/summer/audit.md` for caller-aware context

## Related

- `skills/summer-rest` — Summer REST patterns deep dive
- `skills/api-design` — generic REST conventions (apply alongside)
- `rules/java/api-design.md` — base REST rules
- `rules/summer/audit.md` — caller-aware audit field source
- `rules/summer/messaging.md` — handler-emitted events via outbox
