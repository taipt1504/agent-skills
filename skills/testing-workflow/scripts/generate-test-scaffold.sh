#!/usr/bin/env bash
# =============================================================================
# generate-test-scaffold.sh — Generate test class scaffold for a source file
# =============================================================================
# Usage: bash generate-test-scaffold.sh <source-file.java>
# Output: prints test class to stdout (redirect to save)
# Example:
#   bash generate-test-scaffold.sh src/main/java/com/example/order/application/CreateOrderUseCase.java
# =============================================================================
set -euo pipefail

SOURCE_FILE="${1:?Usage: generate-test-scaffold.sh <source-file.java>}"

if [ ! -f "$SOURCE_FILE" ]; then
  echo "ERROR: File not found: $SOURCE_FILE" >&2
  exit 1
fi

# Extract class info
PACKAGE=$(grep '^package ' "$SOURCE_FILE" | sed 's/package //;s/;//' | head -1)
CLASS_NAME=$(grep -oE '(class|interface|record)\s+\w+' "$SOURCE_FILE" | head -1 | awk '{print $2}')

if [ -z "$CLASS_NAME" ]; then
  echo "ERROR: Could not detect class name in $SOURCE_FILE" >&2
  exit 1
fi

# Detect if reactive (uses Mono/Flux)
IS_REACTIVE=false
if grep -qE 'Mono<|Flux<|Publisher<' "$SOURCE_FILE" 2>/dev/null; then
  IS_REACTIVE=true
fi

# Detect if it's a controller/handler
IS_CONTROLLER=false
if grep -qE '@RestController|@Controller|@RequestMapping|@Handler' "$SOURCE_FILE" 2>/dev/null; then
  IS_CONTROLLER=true
fi

# Detect injected dependencies (constructor params)
DEPS=$(grep -A 20 'class '"$CLASS_NAME" "$SOURCE_FILE" | \
  grep -oE '(private|final)\s+\w+\s+\w+' | \
  awk '{print $(NF-1), $NF}' | head -10)

# Detect public methods
METHODS=$(grep -E 'public\s+\w+(<[^>]+>)?\s+\w+\s*\(' "$SOURCE_FILE" | \
  grep -v 'class\|interface\|record' | \
  sed 's/.*public\s\+//' | sed 's/\s*{.*//' | head -15)

# Generate test class
TEST_CLASS="${CLASS_NAME}Test"

cat << JAVA
package ${PACKAGE};

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
JAVA

if [ "$IS_REACTIVE" = true ]; then
  echo "import reactor.test.StepVerifier;"
fi

if [ "$IS_CONTROLLER" = true ]; then
  echo "import org.springframework.test.web.reactive.server.WebTestClient;"
fi

cat << JAVA

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
@DisplayName("${CLASS_NAME}")
class ${TEST_CLASS} {

JAVA

# Generate @Mock fields for dependencies
while IFS= read -r dep; do
  [ -z "$dep" ] && continue
  DEP_TYPE=$(echo "$dep" | awk '{print $1}')
  DEP_NAME=$(echo "$dep" | awk '{print $2}')
  echo "    @Mock"
  echo "    private ${DEP_TYPE} ${DEP_NAME};"
  echo ""
done <<< "$DEPS"

cat << JAVA
    @InjectMocks
    private ${CLASS_NAME} sut;  // System Under Test

    @BeforeEach
    void setUp() {
        // Additional setup if needed
    }

JAVA

# Generate test method stubs for each public method
while IFS= read -r method; do
  [ -z "$method" ] && continue
  METHOD_NAME=$(echo "$method" | grep -oE '\w+\s*\(' | sed 's/\s*(//;s/($//')
  RETURN_TYPE=$(echo "$method" | awk '{print $1}')

  cat << JAVA
    @Nested
    @DisplayName("${METHOD_NAME}")
    class ${METHOD_NAME^}Tests {

        @Test
        @DisplayName("should succeed when valid input")
        void shouldSucceedWhenValidInput() {
            // given
            // TODO: setup test data and mock behaviors

            // when
JAVA

  if [ "$IS_REACTIVE" = true ] && echo "$RETURN_TYPE" | grep -qE 'Mono|Flux'; then
    cat << JAVA
            var result = sut.${METHOD_NAME}(/* TODO: params */);

            // then
            StepVerifier.create(result)
                .expectNextCount(1)  // TODO: adjust expectations
                .verifyComplete();
JAVA
  else
    cat << JAVA
            var result = sut.${METHOD_NAME}(/* TODO: params */);

            // then
            assertThat(result).isNotNull();
            // TODO: add specific assertions
JAVA
  fi

  cat << JAVA
        }

        @Test
        @DisplayName("should fail when invalid input")
        void shouldFailWhenInvalidInput() {
            // given
            // TODO: setup invalid test data

            // when / then
JAVA

  if [ "$IS_REACTIVE" = true ] && echo "$RETURN_TYPE" | grep -qE 'Mono|Flux'; then
    cat << JAVA
            StepVerifier.create(sut.${METHOD_NAME}(/* TODO: invalid params */))
                .expectError(/* TODO: ExpectedException.class */)
                .verify();
JAVA
  else
    cat << JAVA
            assertThatThrownBy(() -> sut.${METHOD_NAME}(/* TODO: invalid params */))
                .isInstanceOf(/* TODO: ExpectedException.class */);
JAVA
  fi

  cat << JAVA
        }
    }

JAVA
done <<< "$METHODS"

echo "}"
