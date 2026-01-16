#!/bin/bash
# R2DBC Connection Pool Benchmark Script
#
# Usage:
#   ./benchmark.sh                    # Run with defaults
#   ./benchmark.sh --url "r2dbc:postgresql://localhost:5432/mydb" --user postgres
#   ./benchmark.sh --help
#
# Requirements:
#   - Java 17+
#   - Maven or Gradle project with R2DBC dependencies
#   - PostgreSQL running

set -e

# Default values
DB_URL="${DB_URL:-r2dbc:postgresql://localhost:5432/testdb}"
DB_USER="${DB_USER:-postgres}"
DB_PASSWORD="${DB_PASSWORD:-postgres}"
ITERATIONS=1000
CONCURRENCY=50
POOL_SIZES="5 10 20 50 100"
WARMUP=100

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --url URL          R2DBC connection URL (default: $DB_URL)"
    echo "  --user USER        Database user (default: $DB_USER)"
    echo "  --password PASS    Database password"
    echo "  --iterations N     Number of queries per test (default: $ITERATIONS)"
    echo "  --concurrency N    Concurrent requests (default: $CONCURRENCY)"
    echo "  --pool-sizes LIST  Pool sizes to test (default: '$POOL_SIZES')"
    echo "  --help             Show this help"
    echo ""
    echo "Example:"
    echo "  $0 --url 'r2dbc:postgresql://localhost:5432/mydb' --user postgres"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --url)
            DB_URL="$2"
            shift 2
            ;;
        --user)
            DB_USER="$2"
            shift 2
            ;;
        --password)
            DB_PASSWORD="$2"
            shift 2
            ;;
        --iterations)
            ITERATIONS="$2"
            shift 2
            ;;
        --concurrency)
            CONCURRENCY="$2"
            shift 2
            ;;
        --pool-sizes)
            POOL_SIZES="$2"
            shift 2
            ;;
        --help)
            print_usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            print_usage
            exit 1
            ;;
    esac
done

echo "=========================================="
echo "R2DBC Connection Pool Benchmark"
echo "=========================================="
echo "URL: $DB_URL"
echo "User: $DB_USER"
echo "Iterations: $ITERATIONS"
echo "Concurrency: $CONCURRENCY"
echo "Pool sizes: $POOL_SIZES"
echo ""

# Check Java
if ! command -v java &> /dev/null; then
    echo -e "${RED}Error: Java not found${NC}"
    exit 1
fi

JAVA_VERSION=$(java -version 2>&1 | head -1 | cut -d'"' -f2 | cut -d'.' -f1)
echo "Java version: $JAVA_VERSION"

if [[ $JAVA_VERSION -lt 17 ]]; then
    echo -e "${YELLOW}Warning: Java 17+ recommended for best R2DBC performance${NC}"
fi

# Create temporary benchmark project
TEMP_DIR=$(mktemp -d)
echo "Working directory: $TEMP_DIR"
cd "$TEMP_DIR"

# Create pom.xml
cat > pom.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>

    <groupId>com.benchmark</groupId>
    <artifactId>r2dbc-benchmark</artifactId>
    <version>1.0.0</version>
    <packaging>jar</packaging>

    <properties>
        <maven.compiler.source>17</maven.compiler.source>
        <maven.compiler.target>17</maven.compiler.target>
    </properties>

    <dependencies>
        <dependency>
            <groupId>io.r2dbc</groupId>
            <artifactId>r2dbc-postgresql</artifactId>
            <version>1.0.5.RELEASE</version>
        </dependency>
        <dependency>
            <groupId>io.r2dbc</groupId>
            <artifactId>r2dbc-pool</artifactId>
            <version>1.0.1.RELEASE</version>
        </dependency>
        <dependency>
            <groupId>io.projectreactor</groupId>
            <artifactId>reactor-core</artifactId>
            <version>3.6.2</version>
        </dependency>
        <dependency>
            <groupId>org.slf4j</groupId>
            <artifactId>slf4j-simple</artifactId>
            <version>2.0.11</version>
        </dependency>
    </dependencies>

    <build>
        <plugins>
            <plugin>
                <groupId>org.codehaus.mojo</groupId>
                <artifactId>exec-maven-plugin</artifactId>
                <version>3.1.0</version>
            </plugin>
        </plugins>
    </build>
</project>
EOF

# Create benchmark class
mkdir -p src/main/java/com/benchmark
cat > src/main/java/com/benchmark/R2dbcBenchmark.java << 'JAVA'
package com.benchmark;

import io.r2dbc.pool.ConnectionPool;
import io.r2dbc.pool.ConnectionPoolConfiguration;
import io.r2dbc.postgresql.PostgresqlConnectionConfiguration;
import io.r2dbc.postgresql.PostgresqlConnectionFactory;
import io.r2dbc.spi.ConnectionFactory;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.time.Duration;
import java.util.ArrayList;
import java.util.List;

public class R2dbcBenchmark {

    public static void main(String[] args) {
        String url = System.getProperty("db.url", "localhost");
        int port = Integer.parseInt(System.getProperty("db.port", "5432"));
        String database = System.getProperty("db.database", "testdb");
        String user = System.getProperty("db.user", "postgres");
        String password = System.getProperty("db.password", "postgres");
        int poolSize = Integer.parseInt(System.getProperty("pool.size", "20"));
        int iterations = Integer.parseInt(System.getProperty("iterations", "1000"));
        int concurrency = Integer.parseInt(System.getProperty("concurrency", "50"));
        int warmup = Integer.parseInt(System.getProperty("warmup", "100"));

        System.out.println("Starting benchmark with pool size: " + poolSize);

        // Create connection pool
        PostgresqlConnectionConfiguration pgConfig = PostgresqlConnectionConfiguration.builder()
            .host(url)
            .port(port)
            .database(database)
            .username(user)
            .password(password)
            .preparedStatementCacheQueries(256)
            .build();

        PostgresqlConnectionFactory connectionFactory = new PostgresqlConnectionFactory(pgConfig);

        ConnectionPoolConfiguration poolConfig = ConnectionPoolConfiguration.builder()
            .connectionFactory(connectionFactory)
            .initialSize(poolSize / 2)
            .maxSize(poolSize)
            .maxIdleTime(Duration.ofMinutes(5))
            .maxAcquireTime(Duration.ofSeconds(5))
            .acquireRetry(3)
            .validationQuery("SELECT 1")
            .build();

        ConnectionPool pool = new ConnectionPool(poolConfig);

        try {
            // Warmup
            System.out.println("Warming up (" + warmup + " queries)...");
            runQueries(pool, warmup, concurrency).block();

            // Benchmark
            System.out.println("Running benchmark (" + iterations + " queries, concurrency " + concurrency + ")...");

            long startTime = System.nanoTime();
            runQueries(pool, iterations, concurrency).block();
            long endTime = System.nanoTime();

            double durationMs = (endTime - startTime) / 1_000_000.0;
            double avgMs = durationMs / iterations;
            double rps = iterations / (durationMs / 1000.0);

            // Get pool metrics
            var metrics = pool.getMetrics().orElse(null);

            System.out.println();
            System.out.println("=== Results ===");
            System.out.println("Pool size: " + poolSize);
            System.out.println("Total time: " + String.format("%.2f", durationMs) + " ms");
            System.out.println("Avg query time: " + String.format("%.3f", avgMs) + " ms");
            System.out.println("Throughput: " + String.format("%.0f", rps) + " queries/sec");

            if (metrics != null) {
                System.out.println("Pool acquired: " + metrics.acquiredSize());
                System.out.println("Pool idle: " + metrics.idleSize());
                System.out.println("Pool pending: " + metrics.pendingAcquireSize());
            }

            // Output CSV format for easy parsing
            System.out.println();
            System.out.println("CSV:" + poolSize + "," + String.format("%.2f", durationMs) + "," +
                String.format("%.3f", avgMs) + "," + String.format("%.0f", rps));

        } finally {
            pool.dispose();
        }
    }

    private static Mono<Void> runQueries(ConnectionPool pool, int count, int concurrency) {
        return Flux.range(0, count)
            .flatMap(i -> executeQuery(pool), concurrency)
            .then();
    }

    private static Mono<Long> executeQuery(ConnectionPool pool) {
        return Mono.from(pool.create())
            .flatMap(connection ->
                Mono.from(connection.createStatement("SELECT 1 as num").execute())
                    .flatMap(result -> Mono.from(result.map((row, metadata) -> row.get("num", Long.class))))
                    .doFinally(signal -> connection.close().subscribe())
            );
    }
}
JAVA

echo ""
echo "Building benchmark..."
mvn -q compile exec:java -Dexec.mainClass="com.benchmark.R2dbcBenchmark" \
    -Dexec.classpathScope=compile \
    -Ddb.url="localhost" \
    -Ddb.port="5432" \
    -Ddb.database="testdb" \
    -Ddb.user="$DB_USER" \
    -Ddb.password="$DB_PASSWORD" \
    -Dpool.size="10" \
    -Diterations="$WARMUP" \
    -Dconcurrency="10" \
    -Dwarmup="0" > /dev/null 2>&1 || true

echo ""
echo "Running benchmarks..."
echo ""

RESULTS=()

for POOL_SIZE in $POOL_SIZES; do
    echo -e "${YELLOW}Testing pool size: $POOL_SIZE${NC}"

    OUTPUT=$(mvn -q exec:java -Dexec.mainClass="com.benchmark.R2dbcBenchmark" \
        -Dexec.classpathScope=compile \
        -Ddb.url="localhost" \
        -Ddb.port="5432" \
        -Ddb.database="testdb" \
        -Ddb.user="$DB_USER" \
        -Ddb.password="$DB_PASSWORD" \
        -Dpool.size="$POOL_SIZE" \
        -Diterations="$ITERATIONS" \
        -Dconcurrency="$CONCURRENCY" \
        -Dwarmup="$WARMUP" 2>&1)

    CSV_LINE=$(echo "$OUTPUT" | grep "^CSV:" | cut -d':' -f2)
    if [ -n "$CSV_LINE" ]; then
        RESULTS+=("$CSV_LINE")
        RPS=$(echo "$CSV_LINE" | cut -d',' -f4)
        echo -e "${GREEN}  Throughput: $RPS queries/sec${NC}"
    else
        echo -e "${RED}  Error running benchmark${NC}"
        echo "$OUTPUT"
    fi

    echo ""
done

# Print summary
echo "=========================================="
echo "Summary"
echo "=========================================="
echo ""
printf "%-12s %-15s %-15s %-15s\n" "Pool Size" "Total (ms)" "Avg (ms)" "RPS"
echo "------------------------------------------------------------"

for RESULT in "${RESULTS[@]}"; do
    POOL=$(echo "$RESULT" | cut -d',' -f1)
    TOTAL=$(echo "$RESULT" | cut -d',' -f2)
    AVG=$(echo "$RESULT" | cut -d',' -f3)
    RPS=$(echo "$RESULT" | cut -d',' -f4)
    printf "%-12s %-15s %-15s %-15s\n" "$POOL" "$TOTAL" "$AVG" "$RPS"
done

echo ""
echo "Recommendation: Choose pool size with best RPS that doesn't exhaust database connections."
echo ""

# Cleanup
cd - > /dev/null
rm -rf "$TEMP_DIR"

echo "Done!"
