#!/bin/bash
#
# Message Queue Throughput Benchmark Script
#
# Benchmarks message throughput and latency for Kafka and RabbitMQ brokers.
# Supports configurable message counts, sizes, and various benchmark modes.
#
# Usage:
#   ./benchmark-throughput.sh --broker kafka --bootstrap-servers localhost:9092
#   ./benchmark-throughput.sh --broker rabbitmq --host localhost --port 5672
#   ./benchmark-throughput.sh --broker kafka --messages 100000 --size 1024
#
# Requirements:
#   - Kafka: kafka-producer-perf-test.sh, kafka-consumer-perf-test.sh (from Kafka distribution)
#   - RabbitMQ: rabbitmq-perf-test (PerfTest tool from RabbitMQ)
#
# Author: Message Queue Java Expert Skill
#

set -euo pipefail

# =============================================================================
# Configuration Defaults
# =============================================================================

BROKER_TYPE=""
BOOTSTRAP_SERVERS="localhost:9092"
RABBITMQ_HOST="localhost"
RABBITMQ_PORT="5672"
RABBITMQ_USER="guest"
RABBITMQ_PASS="guest"
RABBITMQ_VHOST="/"

MESSAGE_COUNT=100000
MESSAGE_SIZE=1024
BATCH_SIZE=16384
LINGER_MS=0
ACKS="all"
COMPRESSION="none"

TOPIC_NAME="benchmark-topic"
QUEUE_NAME="benchmark-queue"
NUM_PARTITIONS=6
REPLICATION_FACTOR=1

PRODUCER_THREADS=1
CONSUMER_THREADS=1
WARMUP_COUNT=10000

OUTPUT_DIR="./benchmark-results"
OUTPUT_FORMAT="text"
VERBOSE=false
CLEANUP=true

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# =============================================================================
# Helper Functions
# =============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

print_header() {
    echo ""
    echo "=============================================================================="
    echo " $1"
    echo "=============================================================================="
    echo ""
}

print_separator() {
    echo "------------------------------------------------------------------------------"
}

usage() {
    cat << EOF
Message Queue Throughput Benchmark Script

Usage: $(basename "$0") [OPTIONS]

Broker Selection:
  --broker TYPE           Broker type: kafka, rabbitmq (required)

Kafka Options:
  --bootstrap-servers     Kafka bootstrap servers (default: localhost:9092)
  --topic                 Topic name for benchmark (default: benchmark-topic)
  --partitions            Number of partitions (default: 6)
  --replication-factor    Replication factor (default: 1)
  --acks                  Producer acks setting: 0, 1, all (default: all)
  --compression           Compression type: none, gzip, snappy, lz4, zstd (default: none)
  --batch-size            Producer batch size in bytes (default: 16384)
  --linger-ms             Producer linger time in ms (default: 0)

RabbitMQ Options:
  --host                  RabbitMQ host (default: localhost)
  --port                  RabbitMQ port (default: 5672)
  --user                  RabbitMQ username (default: guest)
  --pass                  RabbitMQ password (default: guest)
  --vhost                 RabbitMQ virtual host (default: /)
  --queue                 Queue name for benchmark (default: benchmark-queue)

Benchmark Options:
  --messages N            Number of messages to send (default: 100000)
  --size BYTES            Message size in bytes (default: 1024)
  --producer-threads N    Number of producer threads (default: 1)
  --consumer-threads N    Number of consumer threads (default: 1)
  --warmup N              Warmup message count (default: 10000)

Output Options:
  --output-dir DIR        Directory for results (default: ./benchmark-results)
  --format FORMAT         Output format: text, json, csv (default: text)
  --verbose               Enable verbose output
  --no-cleanup            Don't cleanup test topic/queue after benchmark

General:
  -h, --help              Show this help message

Examples:
  # Benchmark Kafka with default settings
  $(basename "$0") --broker kafka

  # Benchmark Kafka with custom settings
  $(basename "$0") --broker kafka --bootstrap-servers kafka1:9092,kafka2:9092 \\
                   --messages 500000 --size 2048 --compression lz4 --partitions 12

  # Benchmark RabbitMQ
  $(basename "$0") --broker rabbitmq --host rabbit.example.com --user admin --pass secret

  # Compare different compression types
  for comp in none gzip snappy lz4 zstd; do
    $(basename "$0") --broker kafka --compression \$comp --messages 100000
  done

EOF
    exit 0
}

check_dependencies() {
    local missing=()

    if [[ "$BROKER_TYPE" == "kafka" ]]; then
        # Check for Kafka tools
        if ! command -v kafka-producer-perf-test.sh &> /dev/null && \
           ! command -v kafka-producer-perf-test &> /dev/null; then
            # Check common installation paths
            local kafka_found=false
            for path in /opt/kafka/bin /usr/local/kafka/bin /opt/homebrew/opt/kafka/bin "$KAFKA_HOME/bin" 2>/dev/null; do
                if [[ -x "$path/kafka-producer-perf-test.sh" ]]; then
                    export PATH="$path:$PATH"
                    kafka_found=true
                    break
                fi
            done
            if [[ "$kafka_found" == "false" ]]; then
                missing+=("kafka-producer-perf-test.sh (Kafka distribution)")
            fi
        fi
    elif [[ "$BROKER_TYPE" == "rabbitmq" ]]; then
        if ! command -v rabbitmq-perf-test &> /dev/null && \
           ! command -v java &> /dev/null; then
            missing+=("rabbitmq-perf-test or java (for PerfTest JAR)")
        fi
    fi

    if ! command -v bc &> /dev/null; then
        missing+=("bc (for calculations)")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing dependencies:"
        for dep in "${missing[@]}"; do
            echo "  - $dep"
        done
        echo ""
        echo "Installation instructions:"
        if [[ "$BROKER_TYPE" == "kafka" ]]; then
            echo "  Kafka tools: Download from https://kafka.apache.org/downloads"
            echo "  Or install via package manager: brew install kafka (macOS)"
        elif [[ "$BROKER_TYPE" == "rabbitmq" ]]; then
            echo "  RabbitMQ PerfTest: https://rabbitmq.github.io/rabbitmq-perf-test/stable/htmlsingle/"
            echo "  Or: java -jar rabbitmq-perf-test-*.jar"
        fi
        exit 1
    fi
}

generate_payload() {
    local size=$1
    # Generate a payload of specified size
    head -c "$size" /dev/urandom | base64 | head -c "$size"
}

format_number() {
    printf "%'d" "$1" 2>/dev/null || echo "$1"
}

format_bytes() {
    local bytes=$1
    if (( bytes >= 1073741824 )); then
        echo "$(echo "scale=2; $bytes / 1073741824" | bc) GB"
    elif (( bytes >= 1048576 )); then
        echo "$(echo "scale=2; $bytes / 1048576" | bc) MB"
    elif (( bytes >= 1024 )); then
        echo "$(echo "scale=2; $bytes / 1024" | bc) KB"
    else
        echo "$bytes bytes"
    fi
}

# =============================================================================
# Kafka Benchmark Functions
# =============================================================================

kafka_create_topic() {
    log_info "Creating Kafka topic: $TOPIC_NAME"

    # Try to delete existing topic first
    kafka-topics.sh --bootstrap-server "$BOOTSTRAP_SERVERS" \
        --delete --topic "$TOPIC_NAME" 2>/dev/null || true

    sleep 2

    # Create topic
    kafka-topics.sh --bootstrap-server "$BOOTSTRAP_SERVERS" \
        --create --topic "$TOPIC_NAME" \
        --partitions "$NUM_PARTITIONS" \
        --replication-factor "$REPLICATION_FACTOR" \
        --config retention.ms=300000 \
        2>/dev/null || log_warn "Topic might already exist"

    sleep 2
}

kafka_delete_topic() {
    if [[ "$CLEANUP" == "true" ]]; then
        log_info "Cleaning up Kafka topic: $TOPIC_NAME"
        kafka-topics.sh --bootstrap-server "$BOOTSTRAP_SERVERS" \
            --delete --topic "$TOPIC_NAME" 2>/dev/null || true
    fi
}

kafka_producer_benchmark() {
    local result_file="$OUTPUT_DIR/kafka-producer-results.txt"

    print_header "Kafka Producer Benchmark"

    log_info "Configuration:"
    echo "  Bootstrap Servers: $BOOTSTRAP_SERVERS"
    echo "  Topic: $TOPIC_NAME"
    echo "  Messages: $(format_number $MESSAGE_COUNT)"
    echo "  Message Size: $(format_bytes $MESSAGE_SIZE)"
    echo "  Total Data: $(format_bytes $((MESSAGE_COUNT * MESSAGE_SIZE)))"
    echo "  Partitions: $NUM_PARTITIONS"
    echo "  Acks: $ACKS"
    echo "  Compression: $COMPRESSION"
    echo "  Batch Size: $(format_bytes $BATCH_SIZE)"
    echo "  Linger MS: $LINGER_MS"
    echo "  Producer Threads: $PRODUCER_THREADS"
    print_separator

    log_info "Starting producer benchmark..."

    local start_time=$(date +%s.%N)

    # Run Kafka producer performance test
    kafka-producer-perf-test.sh \
        --topic "$TOPIC_NAME" \
        --num-records "$MESSAGE_COUNT" \
        --record-size "$MESSAGE_SIZE" \
        --throughput -1 \
        --producer-props \
            bootstrap.servers="$BOOTSTRAP_SERVERS" \
            acks="$ACKS" \
            compression.type="$COMPRESSION" \
            batch.size="$BATCH_SIZE" \
            linger.ms="$LINGER_MS" \
        2>&1 | tee "$result_file"

    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc)

    print_separator
    log_success "Producer benchmark completed in ${duration}s"

    # Parse results
    parse_kafka_producer_results "$result_file"
}

kafka_consumer_benchmark() {
    local result_file="$OUTPUT_DIR/kafka-consumer-results.txt"

    print_header "Kafka Consumer Benchmark"

    log_info "Configuration:"
    echo "  Bootstrap Servers: $BOOTSTRAP_SERVERS"
    echo "  Topic: $TOPIC_NAME"
    echo "  Messages: $(format_number $MESSAGE_COUNT)"
    echo "  Consumer Threads: $CONSUMER_THREADS"
    print_separator

    log_info "Starting consumer benchmark..."

    local start_time=$(date +%s.%N)

    # Run Kafka consumer performance test
    kafka-consumer-perf-test.sh \
        --bootstrap-server "$BOOTSTRAP_SERVERS" \
        --topic "$TOPIC_NAME" \
        --messages "$MESSAGE_COUNT" \
        --threads "$CONSUMER_THREADS" \
        --group "benchmark-consumer-group-$$" \
        --from-latest \
        2>&1 | tee "$result_file"

    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc)

    print_separator
    log_success "Consumer benchmark completed in ${duration}s"

    # Parse results
    parse_kafka_consumer_results "$result_file"
}

parse_kafka_producer_results() {
    local file=$1

    # Extract metrics from the last line of output
    local metrics_line=$(tail -1 "$file")

    if [[ "$metrics_line" =~ ([0-9.]+)\ records/sec ]]; then
        PRODUCER_RECORDS_PER_SEC="${BASH_REMATCH[1]}"
    fi

    if [[ "$metrics_line" =~ \(([0-9.]+)\ MB/sec\) ]]; then
        PRODUCER_MB_PER_SEC="${BASH_REMATCH[1]}"
    fi

    if [[ "$metrics_line" =~ avg\ latency:\ ([0-9.]+)\ ms ]]; then
        PRODUCER_AVG_LATENCY="${BASH_REMATCH[1]}"
    fi

    if [[ "$metrics_line" =~ max\ latency:\ ([0-9.]+)\ ms ]]; then
        PRODUCER_MAX_LATENCY="${BASH_REMATCH[1]}"
    fi

    if [[ "$metrics_line" =~ 50th:\ ([0-9.]+) ]]; then
        PRODUCER_P50_LATENCY="${BASH_REMATCH[1]}"
    fi

    if [[ "$metrics_line" =~ 99th:\ ([0-9.]+) ]]; then
        PRODUCER_P99_LATENCY="${BASH_REMATCH[1]}"
    fi
}

parse_kafka_consumer_results() {
    local file=$1

    # Parse consumer results (format varies by Kafka version)
    local data_line=$(grep -E "^[0-9]" "$file" | tail -1)

    if [[ -n "$data_line" ]]; then
        # Expected format: start.time, end.time, data.consumed.in.MB, MB.sec, data.consumed.in.nMsg, nMsg.sec, rebalance.time.ms, fetch.time.ms, fetch.MB.sec, fetch.nMsg.sec
        CONSUMER_MB_PER_SEC=$(echo "$data_line" | awk -F',' '{print $4}' | tr -d ' ')
        CONSUMER_RECORDS_PER_SEC=$(echo "$data_line" | awk -F',' '{print $6}' | tr -d ' ')
    fi
}

run_kafka_benchmark() {
    kafka_create_topic

    # Run producer first to populate the topic
    kafka_producer_benchmark

    echo ""

    # Then run consumer benchmark
    kafka_consumer_benchmark

    kafka_delete_topic

    # Generate summary
    generate_kafka_summary
}

generate_kafka_summary() {
    print_header "Kafka Benchmark Summary"

    echo "PRODUCER METRICS"
    echo "  Throughput: ${PRODUCER_RECORDS_PER_SEC:-N/A} records/sec"
    echo "  Bandwidth:  ${PRODUCER_MB_PER_SEC:-N/A} MB/sec"
    echo "  Latency (avg): ${PRODUCER_AVG_LATENCY:-N/A} ms"
    echo "  Latency (max): ${PRODUCER_MAX_LATENCY:-N/A} ms"
    echo "  Latency (p50): ${PRODUCER_P50_LATENCY:-N/A} ms"
    echo "  Latency (p99): ${PRODUCER_P99_LATENCY:-N/A} ms"
    print_separator
    echo "CONSUMER METRICS"
    echo "  Throughput: ${CONSUMER_RECORDS_PER_SEC:-N/A} records/sec"
    echo "  Bandwidth:  ${CONSUMER_MB_PER_SEC:-N/A} MB/sec"
    print_separator
    echo "CONFIGURATION"
    echo "  Messages: $(format_number $MESSAGE_COUNT)"
    echo "  Message Size: $(format_bytes $MESSAGE_SIZE)"
    echo "  Partitions: $NUM_PARTITIONS"
    echo "  Compression: $COMPRESSION"
    echo "  Acks: $ACKS"
    echo ""

    # Save summary to file
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        cat > "$OUTPUT_DIR/kafka-summary.json" << EOF
{
  "broker": "kafka",
  "timestamp": "$(date -Iseconds)",
  "configuration": {
    "bootstrap_servers": "$BOOTSTRAP_SERVERS",
    "topic": "$TOPIC_NAME",
    "messages": $MESSAGE_COUNT,
    "message_size": $MESSAGE_SIZE,
    "partitions": $NUM_PARTITIONS,
    "replication_factor": $REPLICATION_FACTOR,
    "acks": "$ACKS",
    "compression": "$COMPRESSION",
    "batch_size": $BATCH_SIZE,
    "linger_ms": $LINGER_MS
  },
  "producer": {
    "records_per_sec": ${PRODUCER_RECORDS_PER_SEC:-null},
    "mb_per_sec": ${PRODUCER_MB_PER_SEC:-null},
    "avg_latency_ms": ${PRODUCER_AVG_LATENCY:-null},
    "max_latency_ms": ${PRODUCER_MAX_LATENCY:-null},
    "p50_latency_ms": ${PRODUCER_P50_LATENCY:-null},
    "p99_latency_ms": ${PRODUCER_P99_LATENCY:-null}
  },
  "consumer": {
    "records_per_sec": ${CONSUMER_RECORDS_PER_SEC:-null},
    "mb_per_sec": ${CONSUMER_MB_PER_SEC:-null}
  }
}
EOF
        log_info "JSON summary saved to $OUTPUT_DIR/kafka-summary.json"
    fi
}

# =============================================================================
# RabbitMQ Benchmark Functions
# =============================================================================

find_rabbitmq_perf_test() {
    # Try to find rabbitmq-perf-test
    if command -v rabbitmq-perf-test &> /dev/null; then
        echo "rabbitmq-perf-test"
        return 0
    fi

    # Check for JAR file
    local jar_locations=(
        "./rabbitmq-perf-test.jar"
        "/opt/rabbitmq/perf-test/rabbitmq-perf-test.jar"
        "$HOME/rabbitmq-perf-test.jar"
    )

    for jar in "${jar_locations[@]}"; do
        if [[ -f "$jar" ]]; then
            echo "java -jar $jar"
            return 0
        fi
    done

    return 1
}

run_rabbitmq_benchmark() {
    local perf_test_cmd

    if ! perf_test_cmd=$(find_rabbitmq_perf_test); then
        log_error "RabbitMQ PerfTest not found"
        echo ""
        echo "Installation options:"
        echo "  1. Download from: https://github.com/rabbitmq/rabbitmq-perf-test/releases"
        echo "  2. Run with Docker: docker run -it --rm pivotalrabbitmq/perf-test:latest"
        echo "  3. Use Java JAR: java -jar rabbitmq-perf-test-*.jar"
        exit 1
    fi

    local result_file="$OUTPUT_DIR/rabbitmq-results.txt"
    local uri="amqp://$RABBITMQ_USER:$RABBITMQ_PASS@$RABBITMQ_HOST:$RABBITMQ_PORT$RABBITMQ_VHOST"

    print_header "RabbitMQ Benchmark"

    log_info "Configuration:"
    echo "  Host: $RABBITMQ_HOST:$RABBITMQ_PORT"
    echo "  Virtual Host: $RABBITMQ_VHOST"
    echo "  Queue: $QUEUE_NAME"
    echo "  Messages: $(format_number $MESSAGE_COUNT)"
    echo "  Message Size: $(format_bytes $MESSAGE_SIZE)"
    echo "  Total Data: $(format_bytes $((MESSAGE_COUNT * MESSAGE_SIZE)))"
    echo "  Producer Threads: $PRODUCER_THREADS"
    echo "  Consumer Threads: $CONSUMER_THREADS"
    print_separator

    log_info "Starting RabbitMQ benchmark..."

    local start_time=$(date +%s.%N)

    # Calculate duration based on message count (estimate ~10k msgs/sec baseline)
    local estimated_duration=$((MESSAGE_COUNT / 10000 + 30))

    # Run RabbitMQ PerfTest
    $perf_test_cmd \
        --uri "$uri" \
        --queue "$QUEUE_NAME" \
        --producers "$PRODUCER_THREADS" \
        --consumers "$CONSUMER_THREADS" \
        --size "$MESSAGE_SIZE" \
        --pmessages "$MESSAGE_COUNT" \
        --cmessages "$MESSAGE_COUNT" \
        --confirm \
        --auto-delete \
        --json-body \
        --metrics-prometheus \
        2>&1 | tee "$result_file" &

    local perf_pid=$!

    # Monitor progress
    local elapsed=0
    while kill -0 $perf_pid 2>/dev/null; do
        sleep 5
        elapsed=$((elapsed + 5))
        if [[ "$VERBOSE" == "true" ]]; then
            echo "  Running... ${elapsed}s elapsed"
        fi
        # Timeout after estimated duration + buffer
        if (( elapsed > estimated_duration * 2 )); then
            log_warn "Benchmark taking longer than expected, continuing..."
        fi
    done

    wait $perf_pid || true

    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $start_time" | bc)

    print_separator
    log_success "RabbitMQ benchmark completed in ${duration}s"

    # Parse and display results
    parse_rabbitmq_results "$result_file"
    generate_rabbitmq_summary
}

parse_rabbitmq_results() {
    local file=$1

    # RabbitMQ PerfTest outputs summary at the end
    # Format: id: test-..., sending rate avg: X msg/s

    if grep -q "sending rate avg" "$file"; then
        RABBITMQ_SEND_RATE=$(grep "sending rate avg" "$file" | tail -1 | grep -oE "[0-9]+ msg/s" | head -1)
    fi

    if grep -q "receiving rate avg" "$file"; then
        RABBITMQ_RECV_RATE=$(grep "receiving rate avg" "$file" | tail -1 | grep -oE "[0-9]+ msg/s" | head -1)
    fi

    # Try to extract latency metrics
    if grep -q "latency" "$file"; then
        RABBITMQ_LATENCY=$(grep -i "latency" "$file" | tail -1)
    fi
}

generate_rabbitmq_summary() {
    print_header "RabbitMQ Benchmark Summary"

    echo "THROUGHPUT METRICS"
    echo "  Send Rate: ${RABBITMQ_SEND_RATE:-N/A}"
    echo "  Receive Rate: ${RABBITMQ_RECV_RATE:-N/A}"
    if [[ -n "${RABBITMQ_LATENCY:-}" ]]; then
        echo "  Latency: $RABBITMQ_LATENCY"
    fi
    print_separator
    echo "CONFIGURATION"
    echo "  Messages: $(format_number $MESSAGE_COUNT)"
    echo "  Message Size: $(format_bytes $MESSAGE_SIZE)"
    echo "  Producers: $PRODUCER_THREADS"
    echo "  Consumers: $CONSUMER_THREADS"
    echo ""

    # Save summary to file
    if [[ "$OUTPUT_FORMAT" == "json" ]]; then
        cat > "$OUTPUT_DIR/rabbitmq-summary.json" << EOF
{
  "broker": "rabbitmq",
  "timestamp": "$(date -Iseconds)",
  "configuration": {
    "host": "$RABBITMQ_HOST",
    "port": $RABBITMQ_PORT,
    "vhost": "$RABBITMQ_VHOST",
    "queue": "$QUEUE_NAME",
    "messages": $MESSAGE_COUNT,
    "message_size": $MESSAGE_SIZE,
    "producer_threads": $PRODUCER_THREADS,
    "consumer_threads": $CONSUMER_THREADS
  },
  "results": {
    "send_rate": "${RABBITMQ_SEND_RATE:-null}",
    "receive_rate": "${RABBITMQ_RECV_RATE:-null}"
  }
}
EOF
        log_info "JSON summary saved to $OUTPUT_DIR/rabbitmq-summary.json"
    fi
}

# =============================================================================
# Comparison Benchmark
# =============================================================================

run_comparison_benchmark() {
    print_header "Message Queue Comparison Benchmark"

    log_info "This will run benchmarks against both Kafka and RabbitMQ"
    log_info "Ensure both brokers are running and accessible"
    echo ""

    # Kafka benchmark
    BROKER_TYPE="kafka"
    run_kafka_benchmark

    echo ""
    echo ""

    # RabbitMQ benchmark
    BROKER_TYPE="rabbitmq"
    run_rabbitmq_benchmark

    # Generate comparison report
    generate_comparison_report
}

generate_comparison_report() {
    print_header "Comparison Report"

    echo "| Metric               | Kafka              | RabbitMQ           |"
    echo "|---------------------|--------------------|--------------------|"
    printf "| Producer Rate       | %-18s | %-18s |\n" "${PRODUCER_RECORDS_PER_SEC:-N/A} rec/s" "${RABBITMQ_SEND_RATE:-N/A}"
    printf "| Consumer Rate       | %-18s | %-18s |\n" "${CONSUMER_RECORDS_PER_SEC:-N/A} rec/s" "${RABBITMQ_RECV_RATE:-N/A}"
    printf "| Producer Bandwidth  | %-18s | %-18s |\n" "${PRODUCER_MB_PER_SEC:-N/A} MB/s" "N/A"
    printf "| Avg Latency         | %-18s | %-18s |\n" "${PRODUCER_AVG_LATENCY:-N/A} ms" "N/A"
    printf "| P99 Latency         | %-18s | %-18s |\n" "${PRODUCER_P99_LATENCY:-N/A} ms" "N/A"
    echo ""
    echo "Test Configuration:"
    echo "  Messages: $(format_number $MESSAGE_COUNT)"
    echo "  Message Size: $(format_bytes $MESSAGE_SIZE)"
    echo ""
}

# =============================================================================
# Main Script
# =============================================================================

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --broker)
                BROKER_TYPE="$2"
                shift 2
                ;;
            --bootstrap-servers)
                BOOTSTRAP_SERVERS="$2"
                shift 2
                ;;
            --topic)
                TOPIC_NAME="$2"
                shift 2
                ;;
            --partitions)
                NUM_PARTITIONS="$2"
                shift 2
                ;;
            --replication-factor)
                REPLICATION_FACTOR="$2"
                shift 2
                ;;
            --acks)
                ACKS="$2"
                shift 2
                ;;
            --compression)
                COMPRESSION="$2"
                shift 2
                ;;
            --batch-size)
                BATCH_SIZE="$2"
                shift 2
                ;;
            --linger-ms)
                LINGER_MS="$2"
                shift 2
                ;;
            --host)
                RABBITMQ_HOST="$2"
                shift 2
                ;;
            --port)
                RABBITMQ_PORT="$2"
                shift 2
                ;;
            --user)
                RABBITMQ_USER="$2"
                shift 2
                ;;
            --pass)
                RABBITMQ_PASS="$2"
                shift 2
                ;;
            --vhost)
                RABBITMQ_VHOST="$2"
                shift 2
                ;;
            --queue)
                QUEUE_NAME="$2"
                shift 2
                ;;
            --messages)
                MESSAGE_COUNT="$2"
                shift 2
                ;;
            --size)
                MESSAGE_SIZE="$2"
                shift 2
                ;;
            --producer-threads)
                PRODUCER_THREADS="$2"
                shift 2
                ;;
            --consumer-threads)
                CONSUMER_THREADS="$2"
                shift 2
                ;;
            --warmup)
                WARMUP_COUNT="$2"
                shift 2
                ;;
            --output-dir)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            --format)
                OUTPUT_FORMAT="$2"
                shift 2
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --no-cleanup)
                CLEANUP=false
                shift
                ;;
            -h|--help)
                usage
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                ;;
        esac
    done
}

validate_arguments() {
    if [[ -z "$BROKER_TYPE" ]]; then
        log_error "Broker type is required. Use --broker kafka or --broker rabbitmq"
        exit 1
    fi

    case "$BROKER_TYPE" in
        kafka|rabbitmq|compare)
            ;;
        *)
            log_error "Invalid broker type: $BROKER_TYPE"
            log_error "Supported brokers: kafka, rabbitmq, compare"
            exit 1
            ;;
    esac

    if [[ "$MESSAGE_COUNT" -lt 1000 ]]; then
        log_warn "Message count ($MESSAGE_COUNT) is very low. Consider using at least 10000 for meaningful results."
    fi

    if [[ "$MESSAGE_SIZE" -lt 1 ]]; then
        log_error "Message size must be at least 1 byte"
        exit 1
    fi
}

main() {
    parse_arguments "$@"
    validate_arguments

    # Create output directory
    mkdir -p "$OUTPUT_DIR"

    print_header "Message Queue Throughput Benchmark"
    echo "Broker: $BROKER_TYPE"
    echo "Output Directory: $OUTPUT_DIR"
    echo "Timestamp: $(date)"
    print_separator

    check_dependencies

    case "$BROKER_TYPE" in
        kafka)
            run_kafka_benchmark
            ;;
        rabbitmq)
            run_rabbitmq_benchmark
            ;;
        compare)
            run_comparison_benchmark
            ;;
    esac

    print_header "Benchmark Complete"
    log_success "Results saved to $OUTPUT_DIR"
    echo ""
}

# Run main function
main "$@"
