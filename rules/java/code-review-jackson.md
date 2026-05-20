---
name: code-review-jackson
description: Jackson JSON serialization code review rules — ObjectMapper lifecycle, module registration, annotations, polymorphism, date/time, BigDecimal/money, streaming, error handling, security, performance, Spring integration, records, testing, versioning. Rule IDs JKS-*. Load when project uses Jackson. Cite by ID in review.
globs: "*.java,*.yml"
applicability:
  always: false
  triggers:
    files_match: ["**/*.java", "**/application*.yml", "**/build.gradle*"]
    code_patterns: ["ObjectMapper", "JsonMapper", "@JsonProperty", "@JsonIgnore", "@JsonCreator", "@JsonTypeInfo", "@JsonFormat", "JavaTimeModule", "TypeReference", "JacksonTester"]
    task_keywords: ["jackson", "json", "ObjectMapper", "serialization", "deserialization", "@JsonProperty", "JavaTimeModule"]
    related_rules:
      - rules/java/code-review-core.md
      - rules/java/code-review-mvc.md
      - rules/java/code-review-webflux.md
      - rules/java/security.md
relevance_assessment: |
  HIGH 95%+: project uses Jackson (default in Spring Boot — verified: jackson-databind in build.gradle)
  HIGH 90%+: any DTO with @JsonProperty / @JsonFormat / @JsonTypeInfo annotations
  MEDIUM 50%: REST API project (Jackson is implicit dependency)
  ZERO: project explicitly uses non-Jackson JSON lib (Gson, Moshi)
---

# Code Review — Jackson (`JKS-*`)

> Jackson JSON rules. Spring Boot uses Jackson by default. Cite ID in review (`[P0][JKS-MNY-001]`).

**Severity tags inline per rule**: [P0] Blocker, [P1] Critical, [P2] Major, [P3] Minor.

## 1. ObjectMapper Lifecycle (`JKS-OBJ`)

### JKS-OBJ-001 — ObjectMapper is thread-safe, reuse as singleton [P1]

**Bad**
```java
public String toJson(Object obj) {
    ObjectMapper mapper = new ObjectMapper();   // ❌ created every call
    return mapper.writeValueAsString(obj);
}
```

**Good**
```java
@Bean
public ObjectMapper objectMapper() {
    return JsonMapper.builder()
        .addModule(new JavaTimeModule())
        .disable(SerializationFeature.WRITE_DATES_AS_TIMESTAMPS)
        .build();
}
```

`ObjectMapper` construction is expensive (registers serializers, type cache). Thread-safe once configured. Spring Boot provides one bean — inject instead of creating new.

### JKS-OBJ-002 — Do not mutate after configuration [P1]

**Bad**
```java
public String serialize(Order order, boolean pretty) {
    if (pretty) {
        mapper.enable(SerializationFeature.INDENT_OUTPUT);   // ❌ mutates shared instance
    }
    return mapper.writeValueAsString(order);
}
```

**Good — use ObjectWriter**
```java
public String serialize(Order order, boolean pretty) {
    ObjectWriter writer = pretty
        ? mapper.writerWithDefaultPrettyPrinter()
        : mapper.writer();
    return writer.writeValueAsString(order);
}
```

`ObjectMapper.enable/disable` not thread-safe after first use. Use immutable `ObjectReader`/`ObjectWriter` for per-call config.

### JKS-OBJ-003 — Builder pattern instead of construct-then-configure [P2]

**Bad — deprecated style**
```java
ObjectMapper mapper = new ObjectMapper();
mapper.registerModule(new JavaTimeModule());
mapper.disable(SerializationFeature.WRITE_DATES_AS_TIMESTAMPS);
```

**Good — Jackson 2.10+ builder**
```java
ObjectMapper mapper = JsonMapper.builder()
    .addModule(new JavaTimeModule())
    .addModule(new Jdk8Module())
    .disable(SerializationFeature.WRITE_DATES_AS_TIMESTAMPS)
    .propertyNamingStrategy(PropertyNamingStrategies.SNAKE_CASE)
    .build();
```

Builder produces immutable, fully-configured mapper. Thread-safe. Catches invalid config early.

### JKS-OBJ-004 — Use JsonMapper.builder() instead of ObjectMapper directly [P2]

```java
// ❌ Old
ObjectMapper mapper = new ObjectMapper();
// ✅ New (Jackson 2.10+)
ObjectMapper mapper = JsonMapper.builder().build();
```

For other formats: `XmlMapper.builder()`, `YAMLMapper.builder()`, `CBORMapper.builder()`.

## 2. Module Registration (`JKS-MOD`)

### JKS-MOD-001 — Register JavaTimeModule for java.time.* [P0]

**Bad**: `mapper.writeValueAsString(LocalDateTime.now());` → output non-deterministic, may throw

**Good**
```java
ObjectMapper mapper = JsonMapper.builder()
    .addModule(new JavaTimeModule())
    .disable(SerializationFeature.WRITE_DATES_AS_TIMESTAMPS)   // ✅ ISO-8601 string
    .build();
```

Default Jackson serializes `LocalDateTime` as timestamp array `[2026,5,20,10,30]` or throws — not ISO-8601. `JavaTimeModule` from `jackson-datatype-jsr310` fixes this.

### JKS-MOD-002 — Disable WRITE_DATES_AS_TIMESTAMPS [P1]

Default = true → serialize as epoch millis number. ISO-8601 string is more portable, easier to debug, cross-language compatible.

### JKS-MOD-003 — Module dependencies for fintech stack [P1]

```xml
<dependency>
    <groupId>com.fasterxml.jackson.datatype</groupId>
    <artifactId>jackson-datatype-jsr310</artifactId>
</dependency>
<dependency>
    <groupId>com.fasterxml.jackson.datatype</groupId>
    <artifactId>jackson-datatype-jdk8</artifactId>
</dependency>
<dependency>
    <groupId>com.fasterxml.jackson.module</groupId>
    <artifactId>jackson-module-parameter-names</artifactId>
</dependency>
```

Spring Boot auto-registers these if on classpath.

### JKS-MOD-004 — Auto-discover modules via findAndRegisterModules [P3]

```java
ObjectMapper mapper = JsonMapper.builder()
    .findAndAddModules()    // ✅ scan classpath for Jackson modules
    .build();
```

Convenient for prototype. Production prefers explicit (avoid surprise modules).

## 3. Annotations Essentials (`JKS-ANN`)

### JKS-ANN-001 — @JsonProperty for field naming [P2]

```java
public class Customer {
    @JsonProperty("customer_id") private String customerId;
    @JsonProperty("full_name") private String fullName;
}
```

Or global strategy:
```java
JsonMapper.builder().propertyNamingStrategy(PropertyNamingStrategies.SNAKE_CASE).build();
```

Pick one style project-wide: snake_case (banking, REST standard), camelCase (JS-friendly), kebab-case (rare). Document in API spec.

### JKS-ANN-002 — @JsonIgnore vs @JsonIgnoreProperties [P1]

**@JsonIgnore** — ignore a specific field on the class
```java
public class User {
    @JsonIgnore
    private String passwordHash;   // ✅ not serialized
}
```

**@JsonIgnoreProperties** — ignore on deserialize (unknown fields)
```java
@JsonIgnoreProperties(ignoreUnknown = true)
public class UserDto { ... }
```

**@JsonIgnoreProperties on field** — ignore when serializing nested
```java
public class Order {
    @JsonIgnoreProperties({"orders", "internalNote"})
    private Customer customer;
}
```

### JKS-ANN-003 — @JsonProperty access mode for write/read-only [P0]

Write-only (deserialize accepts, do not serialize):
```java
@JsonProperty(access = Access.WRITE_ONLY)
private String password;   // ✅ accept on POST, hide on GET
```

Read-only (serialize, do not accept input):
```java
@JsonProperty(access = Access.READ_ONLY)
private Instant createdAt;   // ✅ client cannot set
```

**Critical**: Password leak via serialize is a classic bug. Always check.

### JKS-ANN-004 — @JsonInclude for null/empty handling [P2]

```java
@JsonInclude(JsonInclude.Include.NON_NULL)   // skip null
@JsonInclude(JsonInclude.Include.NON_EMPTY)  // skip null + empty collection/string
@JsonInclude(JsonInclude.Include.NON_DEFAULT)// skip default (0, false)
```

Or global: `.serializationInclusion(JsonInclude.Include.NON_NULL)`.

Trade-off: NON_NULL = cleaner output. But if API spec requires field present with `null` (explicit absent vs missing), keep ALWAYS.

### JKS-ANN-005 — @JsonFormat for date/number format [P1]

```java
public class Order {
    @JsonFormat(shape = JsonFormat.Shape.STRING, pattern = "yyyy-MM-dd")
    private LocalDate orderDate;

    @JsonFormat(shape = JsonFormat.Shape.STRING)
    private BigDecimal amount;   // serialize as string, avoid JS precision loss

    @JsonFormat(timezone = "Asia/Ho_Chi_Minh")
    private ZonedDateTime createdAt;
}
```

**Critical for money** [P0]: `@JsonFormat(shape = JsonFormat.Shape.STRING)` on BigDecimal. JavaScript uses IEEE 754 double for numbers → loses precision for BigDecimal > 2^53. Serialize as string is the fintech standard.

### JKS-ANN-006 — @JsonCreator for constructor deserialization [P2]

```java
public class Money {
    @JsonCreator
    public Money(
            @JsonProperty("amount") BigDecimal amount,
            @JsonProperty("currency") Currency currency) {
        this.amount = Objects.requireNonNull(amount);
        this.currency = Objects.requireNonNull(currency);
    }
}
```

**Record** [Jackson 2.12+]:
```java
public record Money(BigDecimal amount, Currency currency) {}   // ✅ auto-works
```

Record + `jackson-module-parameter-names` → no need for `@JsonCreator`/`@JsonProperty`.

### JKS-ANN-007 — @JsonValue for enum/value object serialize [P2]

```java
public enum OrderStatus {
    DRAFT("draft"), SUBMITTED("submitted"), APPROVED("approved");
    private final String value;
    OrderStatus(String value) { this.value = value; }

    @JsonValue
    public String getValue() { return value; }   // serialize as "draft"
}
```

Output: `"status": "draft"` instead of `"status": "DRAFT"`.

### JKS-ANN-008 — @JsonAlias for backward compatibility [P2]

```java
@JsonProperty("full_name")
@JsonAlias({"fullName", "name"})   // accept old field names on deserialize
private String fullName;
```

When renaming fields, use `@JsonAlias` to preserve back-compat. Output remains `full_name`; input accepts all three.

### JKS-ANN-009 — Avoid field-level annotation conflict [P2]

**Bad**
```java
public class User {
    @JsonProperty("user_name") private String name;
    @JsonProperty("userName") public String getName() { return name; }    // ❌ conflict
}
```

Pick one location: field, getter, or constructor parameter. Consistent project-wide.

**Recommendation**: Annotate field for mutable POJO; constructor parameter for record/immutable.

## 4. Polymorphic Types (`JKS-POL`)

### JKS-POL-001 — @JsonTypeInfo for polymorphism [P2]

```java
@JsonTypeInfo(use = JsonTypeInfo.Id.NAME, property = "type")
@JsonSubTypes({
    @JsonSubTypes.Type(value = CardPayment.class, name = "card"),
    @JsonSubTypes.Type(value = BankTransferPayment.class, name = "bank"),
    @JsonSubTypes.Type(value = EWalletPayment.class, name = "wallet")
})
public abstract class Payment { ... }
```

### JKS-POL-002 — NEVER use JsonTypeInfo.Id.CLASS [P0 SECURITY]

**Bad — CVE risk**
```java
@JsonTypeInfo(use = JsonTypeInfo.Id.CLASS)   // ❌ attacker controls class instantiated
```

Attacker sends `{"@class":"com.evil.RCE"}` → Jackson instantiates arbitrary class → RCE. Root cause of multiple Jackson CVEs 2017-2019 (e.g., CVE-2017-7525, CVE-2018-7489).

**Good**: use NAME with explicit whitelist via `@JsonSubTypes`.

### JKS-POL-003 — Disable default typing [P0 SECURITY]

**Bad**
```java
mapper.enableDefaultTyping();   // ❌ DEPRECATED + UNSAFE
mapper.activateDefaultTyping(LaissezFaireSubTypeValidator.instance);   // ❌ allow all
```

**Good — if default typing genuinely needed**
```java
PolymorphicTypeValidator ptv = BasicPolymorphicTypeValidator.builder()
    .allowIfSubType("com.f8a.party.events")
    .allowIfSubType("com.f8a.common.dto")
    .build();

ObjectMapper mapper = JsonMapper.builder()
    .activateDefaultTyping(ptv, ObjectMapper.DefaultTyping.NON_FINAL)
    .build();
```

Best practice: **do not enable default typing** except in special cases. Use explicit `@JsonTypeInfo` per base class.

### JKS-POL-004 — Sealed class with Jackson 2.16+ [P3]

```java
@JsonTypeInfo(use = JsonTypeInfo.Id.NAME, property = "type")
@JsonSubTypes({
    @JsonSubTypes.Type(value = CardPayment.class, name = "card"),
    @JsonSubTypes.Type(value = BankTransfer.class, name = "bank"),
    @JsonSubTypes.Type(value = EWallet.class, name = "wallet")
})
public sealed interface PaymentMethod permits CardPayment, BankTransfer, EWallet {}
```

Sealed type + Jackson for exhaustive polymorphism. Compiler verifies permits list.

## 5. Date/Time Handling (`JKS-TIM`)

### JKS-TIM-001 — Standard format for java.time [P1]

```java
public class Audit {
    private OffsetDateTime occurredAt;          // "2026-05-20T10:30:00+07:00"
    private Instant timestamp;                   // "2026-05-20T03:30:00Z"

    @JsonFormat(pattern = "yyyy-MM-dd'T'HH:mm:ss")
    private LocalDateTime localTime;

    @JsonFormat(pattern = "yyyy-MM-dd")
    private LocalDate businessDate;
}
```

### JKS-TIM-002 — Instant for event/audit timestamps [P1]

```java
public record OrderEvent(String orderId, Instant occurredAt, String type) {}
```

`Instant` = UTC point in time. No timezone. Unambiguous. Prefer for event log, audit, cross-service messages.

### JKS-TIM-003 — LocalDate for business dates [P1]

```java
public record Transfer(Money amount, LocalDate transferDate) {}
```

For accounting dates, reporting dates. No timezone confusion since it's a logical date.

### JKS-TIM-004 — ZonedDateTime or OffsetDateTime for user-facing [P2]

`ZonedDateTime` preserves zone ID (`Asia/Ho_Chi_Minh`). `OffsetDateTime` preserves offset (`+07:00`). Pick based on DST handling needs.

### JKS-TIM-005 — Do not use java.util.Date [P2]

**Bad**: `private Date timestamp;` — legacy, mutable, not thread-safe
**Good**: `private Instant timestamp;`

Migrate to `java.time.*`.

### JKS-TIM-006 — Disable timestamp serialization features [P1]

```java
JsonMapper.builder()
    .addModule(new JavaTimeModule())
    .disable(SerializationFeature.WRITE_DATES_AS_TIMESTAMPS)              // ISO string, not array
    .disable(DeserializationFeature.ADJUST_DATES_TO_CONTEXT_TIME_ZONE)    // no auto TZ conversion
    .build();
```

## 6. BigDecimal & Money (`JKS-MNY`)

### JKS-MNY-001 — BigDecimal serialize as string [P0 — Fintech]

**Bad**
```java
public record Money(BigDecimal amount, String currency) {}
// Output: { "amount": 99999999999.99 }   ❌ JS loses precision
```

**Good — global**
```java
JsonMapper.builder()
    .enable(JsonGenerator.Feature.WRITE_BIGDECIMAL_AS_PLAIN)
    .build();
```

**Good — per-field**
```java
public record Money(
    @JsonFormat(shape = JsonFormat.Shape.STRING) BigDecimal amount,
    String currency
) {}
// Output: { "amount": "99999999999.99" }   ✅ exact
```

Decimal in JSON = JavaScript Number = IEEE 754 double. Loses precision for values > 2^53 or many digits. String preserves exact representation.

### JKS-MNY-002 — Deserialize string → BigDecimal [P1]

```java
JsonMapper.builder()
    .enable(DeserializationFeature.USE_BIG_DECIMAL_FOR_FLOATS)
    .enable(DeserializationFeature.USE_BIG_INTEGER_FOR_INTS)
    .build();
```

Default Jackson parses `1.5` as `Double`. Enable flag → parse as `BigDecimal`, preserve precision.

### JKS-MNY-003 — Scale & rounding explicit [P1]

```java
public record TransferRequest(
    @JsonFormat(shape = JsonFormat.Shape.STRING) BigDecimal amount,
    String currency
) {
    public TransferRequest {
        Objects.requireNonNull(amount);
        if (amount.scale() > 2) throw new IllegalArgumentException("Amount scale must be <= 2");
        amount = amount.setScale(2, RoundingMode.HALF_EVEN);
    }
}
```

Compact constructor validates + normalizes in one place.

### JKS-MNY-004 — Strip trailing zero or preserve per currency [P2]

```java
BigDecimal normalized = amount.setScale(getCurrencyScale(currency), RoundingMode.HALF_EVEN);
```

VND has no decimals (`100`), USD has 2 (`100.00`), JPY has none (`100`). Define `Currency.scale()` and normalize before serialize.

## 7. Streaming API (`JKS-STR`)

### JKS-STR-001 — Streaming for large data [P1]

**Bad — load all into memory**
```java
List<Order> orders = mapper.readValue(file, new TypeReference<List<Order>>(){});
// ❌ OOM for large files
```

**Good — streaming**
```java
try (JsonParser parser = mapper.createParser(file)) {
    if (parser.nextToken() != JsonToken.START_ARRAY) throw new IllegalStateException("Expected array");
    while (parser.nextToken() != JsonToken.END_ARRAY) {
        Order order = mapper.readValue(parser, Order.class);
        process(order);   // ✅ process each record, no accumulation
    }
}
```

Critical for batch import, large report files, multi-million-record export.

### JKS-STR-002 — Reactive stream with Jackson + WebFlux [P2]

```java
@PostMapping(value = "/import", consumes = MediaType.APPLICATION_NDJSON_VALUE)
public Mono<ImportResult> importNdjson(@RequestBody Flux<Order> orders) {
    return orders
        .buffer(100)
        .flatMap(batch -> repository.saveAll(batch).then())
        .then(Mono.just(new ImportResult("OK")));
}
```

NDJSON (newline-delimited JSON) = 1 JSON per line. Stream-friendly, Jackson + WebFlux handle natively.

### JKS-STR-003 — Generator API for large output [P2]

```java
try (JsonGenerator gen = mapper.getFactory().createGenerator(outputStream)) {
    gen.writeStartArray();
    repository.streamAll().forEach(order -> {
        try { mapper.writeValue(gen, order); }
        catch (IOException e) { throw new UncheckedIOException(e); }
    });
    gen.writeEndArray();
}
```

For export endpoints returning large files.

## 8. Error Handling (`JKS-ERR`)

### JKS-ERR-001 — Catch JsonProcessingException at boundary [P2]

**Bad**: `catch (JsonProcessingException e) { return "{}"; }` — silent swallow

**Good**
```java
try { return mapper.writeValueAsString(order); }
catch (JsonProcessingException e) {
    log.error("serialization failed for order={}", order.getId(), e);
    throw new SerializationException("Failed to serialize order", e);
}
```

Or map via `@RestControllerAdvice` → 400.

### JKS-ERR-002 — Distinguish exception types [P2]

```java
try { return mapper.readValue(input, Type.class); }
catch (JsonParseException e) { throw new BadRequestException("INVALID_JSON", e); }      // syntax error
catch (JsonMappingException e) { throw new BadRequestException("MAPPING_ERROR", e); }   // type mismatch
catch (IOException e) { throw new InternalException("IO_ERROR", e); }
```

Different exception → different user message and HTTP status.

### JKS-ERR-003 — Validation separate from deserialization [P2]

**Bad**: throw in `@JsonCreator` — stuck in Jackson layer

**Good — use Bean Validation**
```java
public record Order(
    @NotNull @DecimalMin("0.01") BigDecimal amount,
    @NotBlank String currency
) {}
```

Jackson parses only. Validation is a separate concern (JSR-380). Cleaner error messages, framework-integrated.

### JKS-ERR-004 — No internal info leakage in error messages [P1]

```java
@ExceptionHandler(JsonMappingException.class)
public ResponseEntity<ErrorResponse> handle(JsonMappingException e) {
    log.warn("mapping error", e);   // ✅ full detail server side

    String path = e.getPath().stream()
        .map(JsonMappingException.Reference::getFieldName)
        .collect(Collectors.joining("."));

    return ResponseEntity.badRequest().body(new ErrorResponse(
        "MAPPING_ERROR",
        "Invalid field: " + path,    // ✅ field name only, no stack trace/class
        List.of()
    ));
}
```

Stack trace, internal class name, file path MUST NOT be exposed to client.

## 9. Security (`JKS-SEC`)

### JKS-SEC-001 — Disable default typing (recap) [P0]

Covered in `JKS-POL-002`, `JKS-POL-003`. Most critical rule in this set.

### JKS-SEC-002 — FAIL_ON_UNKNOWN_PROPERTIES per context [P2]

```java
// External API — strict
.enable(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES);

// Internal service-to-service — lenient for evolution
.disable(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES);
```

**Recommendation**:
- External-facing API: strict (catch typos, unknown fields early)
- Event consumer (Kafka): lenient (producer can add fields without breaking consumer)
- Internal API: depends on contract management

### JKS-SEC-003 — Limit input size [P1]

```java
factory.setStreamReadConstraints(StreamReadConstraints.builder()
    .maxStringLength(10_000_000)
    .maxNumberLength(1000)
    .maxNestingDepth(50)
    .build());
```

Jackson 2.15+ has defaults. Configure as needed. Protects against DoS via abnormal payload (infinite string, deeply nested).

### JKS-SEC-004 — Sanitize before serializing/logging [P0]

```java
public class User {
    private String username;

    @JsonIgnore
    private String password;             // ✅ never serialized

    @JsonProperty(access = Access.WRITE_ONLY)
    private String ssn;                  // ✅ accept input, no output

    @JsonSerialize(using = MaskingSerializer.class)
    private String creditCard;            // ✅ masked on serialize
}
```

```java
public class MaskingSerializer extends JsonSerializer<String> {
    @Override
    public void serialize(String value, JsonGenerator gen, SerializerProvider sp) throws IOException {
        if (value == null || value.length() < 10) { gen.writeNull(); return; }
        gen.writeString(value.substring(0, 6) + "******" + value.substring(value.length() - 4));
    }
}
```

### JKS-SEC-005 — Validate before unmarshal [P1]

```java
public Order parse(String json) {
    if (json == null || json.length() > MAX_JSON_SIZE) throw new BadRequestException("JSON too large");
    return mapper.readValue(json, Order.class);
}
```

Especially for endpoints accepting JSON from untrusted source.

### JKS-SEC-006 — Avoid deserializing to Object/Map when possible [P2]

```java
// ❌ Loose typing
Map<String, Object> data = mapper.readValue(json, Map.class);
String name = (String) data.get("name");   // unsafe cast, runtime error

// ✅ Strong typing
UserDto user = mapper.readValue(json, UserDto.class);
```

Strong typing catches errors early, prevents injection via unexpected fields.

## 10. Performance (`JKS-PRF`)

### JKS-PRF-001 — Reuse ObjectReader/ObjectWriter for hot paths [P2]

```java
// ❌ Lookup type info every call
mapper.readValue(json, Order.class);

// ✅ Cache reader
private static final ObjectReader ORDER_READER = mapper.readerFor(Order.class);
Order order = ORDER_READER.readValue(json);
```

`ObjectReader`/`ObjectWriter` cache type info, faster for repeat use. Material in hot paths (e.g., Kafka consumers).

### JKS-PRF-002 — TypeReference for generics [P1]

```java
// ❌ Type erasure problem
List<Order> orders = mapper.readValue(json, List.class);   // List<Object>, not List<Order>

// ✅ TypeReference preserves generic type
List<Order> orders = mapper.readValue(json, new TypeReference<List<Order>>(){});

// ✅ Cache TypeReference
private static final TypeReference<List<Order>> ORDER_LIST = new TypeReference<>(){};
List<Order> orders = mapper.readValue(json, ORDER_LIST);
```

### JKS-PRF-003 — Afterburner/Blackbird module for performance [P3]

```java
JsonMapper.builder()
    .addModule(new BlackbirdModule())   // ✅ JVM bytecode optimization
    .build();
```

Blackbird (Java 11+) or Afterburner (Java 8) generate optimized accessors → faster getter/setter calls. 20-30% improvement in hot paths.

### JKS-PRF-004 — Avoid Map<String, Object> on hot paths [P3]

```java
// ❌ Slow + boxing overhead
Map<String, Object> data = mapper.readValue(json, Map.class);
// ✅ Typed POJO faster
OrderDto data = mapper.readValue(json, OrderDto.class);
```

Map<String, Object> creates HashMap, autoboxes primitives, no cached structure. POJO has compile-time known structure, faster.

### JKS-PRF-005 — Streaming for large data in microservices [P2]

For batch processing: NDJSON streaming > loading full list. Especially for payment gateway file imports.

## 11. Spring Integration (`JKS-SPR`)

### JKS-SPR-001 — Inject ObjectMapper from Spring [P1]

```java
@Service
@RequiredArgsConstructor
public class OrderService {
    private final ObjectMapper objectMapper;   // ✅ inject from context
}
```

Do NOT `new ObjectMapper()` in service. Spring Boot configures one bean with modules auto-discovered.

### JKS-SPR-002 — Customize via Jackson2ObjectMapperBuilderCustomizer [P2]

```java
@Bean
public Jackson2ObjectMapperBuilderCustomizer customizer() {
    return builder -> builder
        .serializationInclusion(JsonInclude.Include.NON_NULL)
        .featuresToDisable(SerializationFeature.WRITE_DATES_AS_TIMESTAMPS)
        .modulesToInstall(new JavaTimeModule());
}
```

Spring Boot applies customizer when building the mapper. Cleaner than replacing the bean.

### JKS-SPR-003 — Multiple ObjectMappers when needed [P3]

```java
@Bean @Primary
public ObjectMapper webMapper() {
    return JsonMapper.builder().propertyNamingStrategy(PropertyNamingStrategies.SNAKE_CASE).build();
}

@Bean @Qualifier("kafka")
public ObjectMapper kafkaMapper() {
    return JsonMapper.builder()
        .propertyNamingStrategy(PropertyNamingStrategies.LOWER_CAMEL_CASE)
        .enable(SerializationFeature.WRITE_BIGDECIMAL_AS_PLAIN)
        .build();
}
```

Web API and internal message broker may have different conventions.

### JKS-SPR-004 — application.yml properties [P2]

```yaml
spring:
  jackson:
    date-format: yyyy-MM-dd'T'HH:mm:ss
    time-zone: UTC
    property-naming-strategy: SNAKE_CASE
    default-property-inclusion: non_null
    serialization:
      write-dates-as-timestamps: false
    deserialization:
      fail-on-unknown-properties: false
      use-big-decimal-for-floats: true
```

For simple config, YAML is enough. Code customizer for complex logic.

### JKS-SPR-005 — WebFlux codec for non-default mapper [P2]

```java
@Override
public void configureHttpMessageCodecs(ServerCodecConfigurer configurer) {
    configurer.defaultCodecs().jackson2JsonEncoder(new Jackson2JsonEncoder(customMapper));
    configurer.defaultCodecs().jackson2JsonDecoder(new Jackson2JsonDecoder(customMapper));
}
```

## 12. Records & Modern Java (`JKS-REC`)

### JKS-REC-001 — Records are first-class with Jackson 2.12+ [P2]

```java
public record CreateOrderRequest(
    String customerId,
    @JsonFormat(shape = Shape.STRING) BigDecimal amount,
    String currency,
    List<LineItem> items
) {}
```

No `@JsonCreator`, no `@JsonProperty` (when names match). Compact, immutable, fits DTO use cases.

### JKS-REC-002 — Validation in compact constructor [P2]

```java
public record Money(BigDecimal amount, String currency) {
    public Money {
        Objects.requireNonNull(amount, "amount");
        Objects.requireNonNull(currency, "currency");
        if (amount.signum() < 0) throw new IllegalArgumentException("amount must be non-negative");
    }
}
```

Fail fast at Jackson deserialization boundary.

### JKS-REC-003 — Record with Bean Validation [P2]

```java
public record TransferRequest(
    @NotBlank String fromAccount,
    @NotBlank String toAccount,
    @NotNull @DecimalMin("0.01") BigDecimal amount,
    @NotBlank String currency
) {}

@PostMapping
public Mono<TransferResponse> transfer(@Valid @RequestBody TransferRequest req) { ... }
```

`@Valid` works with records natively. Annotation on canonical constructor parameters.

### JKS-REC-004 — Sealed + record + Jackson [P3]

```java
@JsonTypeInfo(use = JsonTypeInfo.Id.NAME, property = "type")
@JsonSubTypes({
    @JsonSubTypes.Type(value = OrderPlaced.class, name = "placed"),
    @JsonSubTypes.Type(value = OrderCancelled.class, name = "cancelled"),
    @JsonSubTypes.Type(value = OrderCompleted.class, name = "completed")
})
public sealed interface Event permits OrderPlaced, OrderCancelled, OrderCompleted {}

public record OrderPlaced(String orderId, Instant at) implements Event {}
public record OrderCancelled(String orderId, String reason, Instant at) implements Event {}
public record OrderCompleted(String orderId, Instant at) implements Event {}
```

Exhaustive event hierarchy with polymorphic JSON.

## 13. Testing (`JKS-TST`)

### JKS-TST-001 — @JsonTest slice for Jackson config [P2]

```java
@JsonTest
class OrderDtoJsonTest {
    @Autowired
    private JacksonTester<OrderDto> json;

    @Test
    void serialize() throws IOException {
        OrderDto order = new OrderDto("ORD-001", new BigDecimal("99.99"));

        assertThat(json.write(order))
            .extractingJsonPathStringValue("$.amount").isEqualTo("99.99");   // ✅ string, not number
    }
}
```

Spring Boot `@JsonTest` slice is fast, no full context needed.

### JKS-TST-002 — Round-trip test per DTO [P2]

```java
@Test
void roundTrip() throws IOException {
    Order original = new Order(...);
    String json = mapper.writeValueAsString(original);
    Order deserialized = mapper.readValue(json, Order.class);
    assertThat(deserialized).isEqualTo(original);
}
```

Catches bugs like missing `@JsonCreator`, asymmetric field naming.

### JKS-TST-003 — Test backward compatibility [P2]

```java
@Test
void deserializeOldVersion() throws IOException {
    String oldJson = "{\"fullName\":\"Nguyen Van A\"}";
    User user = mapper.readValue(oldJson, User.class);
    assertThat(user.getFullName()).isEqualTo("Nguyen Van A");
}
```

Ensures `@JsonAlias` works, doesn't break old consumers.

### JKS-TST-004 — Contract test with golden file [P2]

```java
@Test
void matchGoldenFile() throws IOException {
    OrderResponse response = service.getOrder("ORD-001");
    String actual = mapper.writeValueAsString(response);

    String expected = Files.readString(Path.of("src/test/resources/order-response.json"));
    JSONAssert.assertEquals(expected, actual, JSONCompareMode.STRICT);
}
```

JSON golden file = contract. Change format → test fails, forces conscious decision.

## 14. Migration & Versioning (`JKS-VER`)

### JKS-VER-001 — Field rename via @JsonAlias [P2]

```java
// V1: public record User(@JsonProperty("name") String name) {}
// V2 — rename
public record User(
    @JsonProperty("full_name")
    @JsonAlias({"name", "fullName"})
    String fullName
) {}
```

### JKS-VER-002 — Schema evolution [P1]

**Compatible changes** (no consumer break):
- Add optional field
- Add enum value (if consumer ignores unknown)
- Loosen validation

**Breaking changes** (require version):
- Remove field
- Rename field (without alias)
- Change type
- Remove enum value (consumer may have serialized)
- Tighten validation

### JKS-VER-003 — API versioning with Jackson [P2]

Path-based:
```java
@RestController @RequestMapping("/v1/orders")
public class OrderControllerV1 { ... }

@RestController @RequestMapping("/v2/orders")
public class OrderControllerV2 { ... }
```

Each version has its own DTO. Avoid sharing DTOs across versions via Jackson tricks.

## 15. Anti-Patterns Recap (`JKS-PIT`)

| Anti-pattern | Rule ID | Severity | Fix |
|---|---|---|---|
| `new ObjectMapper()` per call | JKS-OBJ-001 | P1 | Inject from Spring |
| `enableDefaultTyping()` | JKS-POL-003 | P0 | Explicit `@JsonTypeInfo` with NAME |
| `@JsonTypeInfo(use = Id.CLASS)` | JKS-POL-002 | P0 | Use NAME + subtypes |
| BigDecimal as JSON number | JKS-MNY-001 | P0 (fintech) | `@JsonFormat(shape = STRING)` |
| `java.util.Date` | JKS-TIM-005 | P2 | `java.time.Instant`/`LocalDate` |
| Missing `JavaTimeModule` | JKS-MOD-001 | P0 | Register module |
| Password serialized | JKS-ANN-003 | P0 | `@JsonIgnore` or `WRITE_ONLY` |
| Silently swallow `JsonProcessingException` | JKS-ERR-001 | P2 | Log + wrap business exception |
| Validation in `@JsonCreator` | JKS-ERR-003 | P2 | Bean Validation `@Valid` |
| Mutate shared `ObjectMapper` | JKS-OBJ-002 | P1 | `ObjectReader`/`Writer` per-call |
| Map<String, Object> on hot path | JKS-PRF-004 | P3 | Strong-typed POJO |
| Field + getter annotation conflict | JKS-ANN-009 | P2 | Pick one location |
| Missing TypeReference for generic | JKS-PRF-002 | P1 | `new TypeReference<>(){}` |
| No max size limit | JKS-SEC-003 | P1 | StreamReadConstraints |
| Leak stack trace in error | JKS-ERR-004 | P1 | Sanitize message |

## 16. Recommended Spring Boot Config

```java
@Configuration
public class JacksonConfig {

    @Bean
    public Jackson2ObjectMapperBuilderCustomizer jacksonCustomizer() {
        return builder -> builder
            .modulesToInstall(new JavaTimeModule(), new Jdk8Module())
            .propertyNamingStrategy(PropertyNamingStrategies.SNAKE_CASE)
            .serializationInclusion(JsonInclude.Include.NON_NULL)
            .featuresToDisable(
                SerializationFeature.WRITE_DATES_AS_TIMESTAMPS,
                SerializationFeature.WRITE_DURATIONS_AS_TIMESTAMPS,
                DeserializationFeature.ADJUST_DATES_TO_CONTEXT_TIME_ZONE
            )
            .featuresToEnable(
                JsonParser.Feature.USE_FAST_BIG_DECIMAL_PARSER,
                DeserializationFeature.USE_BIG_DECIMAL_FOR_FLOATS,
                JsonGenerator.Feature.WRITE_BIGDECIMAL_AS_PLAIN
            )
            .featuresToDisable(
                DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES
            );
    }

    @Bean
    public ObjectMapper objectMapper(Jackson2ObjectMapperBuilder builder) {
        ObjectMapper mapper = builder.build();
        mapper.getFactory().setStreamReadConstraints(StreamReadConstraints.builder()
            .maxStringLength(10_000_000)
            .maxNumberLength(1000)
            .maxNestingDepth(50)
            .build());
        return mapper;
    }
}
```

## 17. Rule ID Index

| Domain | Prefix | Count |
|---|---|---|
| ObjectMapper lifecycle | JKS-OBJ | 4 |
| Module registration | JKS-MOD | 4 |
| Annotations | JKS-ANN | 9 |
| Polymorphism | JKS-POL | 4 |
| Date/Time | JKS-TIM | 6 |
| Money/BigDecimal | JKS-MNY | 4 |
| Streaming | JKS-STR | 3 |
| Error handling | JKS-ERR | 4 |
| Security | JKS-SEC | 6 |
| Performance | JKS-PRF | 5 |
| Spring integration | JKS-SPR | 5 |
| Records | JKS-REC | 4 |
| Testing | JKS-TST | 4 |
| Versioning | JKS-VER | 3 |
| Anti-patterns | JKS-PIT | (catalog) |

Total: **65 rules** with ID, severity, code examples.

## Related

- `rules/java/code-review-core.md` — CORE-* foundation (CORE-NUM-001 BigDecimal pairs with JKS-MNY-001, CORE-LOG-002 with JKS-SEC-004)
- `rules/java/code-review-mvc.md` — MVC-RSP-001 DTO + MVC-VAL-* `@Valid` pair with JKS-REC-003
- `rules/java/code-review-webflux.md` — WFL-WC-* WebClient + JKS-STR-002 NDJSON
- `rules/java/code-review-crosscut.md` — XCT-* + checklist + severity P0-P4
- `rules/java/security.md` — JKS-POL-002/003 (deserialization RCE) + JKS-SEC-004 (mask sensitive)
- `skills/coding-standards` (aka code-review) — unified enforcement skill
