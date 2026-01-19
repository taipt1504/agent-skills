#!/usr/bin/env bash
#
# Reactive Endpoint Benchmark Script
#
# This script benchmarks reactive endpoints, measuring throughput, latency,
# and comparing with blocking baseline when available.
#
# Usage:
#   ./benchmark-reactive.sh [options] <base-url>
#
# Examples:
#   ./benchmark-reactive.sh http://localhost:8080
#   ./benchmark-reactive.sh --duration 60 --connections 100 http://localhost:8080
#   ./benchmark-reactive.sh --endpoints /api/users,/api/products http://localhost:8080
#

set -euo pipefail

# Default configuration
DURATION=30
CONNECTIONS=50
THREADS=4
ENDPOINTS="/api/health"
OUTPUT_DIR="./benchmark-results"
WARMUP_DURATION=10
RPS_LIMIT=0  # 0 = unlimited

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print usage information
usage() {
    cat << EOF
Usage: $(basename "$0") [options] <base-url>

Options:
    -d, --duration <seconds>     Test duration (default: 30)
    -c, --connections <num>      Concurrent connections (default: 50)
    -t, --threads <num>          Number of threads (default: 4)
    -e, --endpoints <list>       Comma-separated list of endpoints (default: /api/health)
    -o, --output <dir>           Output directory (default: ./benchmark-results)
    -w, --warmup <seconds>       Warmup duration (default: 10)
    -r, --rps <num>              Rate limit (requests per second, 0 = unlimited)
    -h, --help                   Show this help message

Examples:
    $(basename "$0") http://localhost:8080
    $(basename "$0") -d 60 -c 100 -e /api/users,/api/orders http://localhost:8080
    $(basename "$0") --endpoints "/api/users?page=0&size=10" http://localhost:8080

Requirements:
    - wrk (https://github.com/wg/wrk)
    - curl
    - jq (optional, for JSON processing)
EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--duration)
                DURATION="$2"
                shift 2
                ;;
            -c|--connections)
                CONNECTIONS="$2"
                shift 2
                ;;
            -t|--threads)
                THREADS="$2"
                shift 2
                ;;
            -e|--endpoints)
                ENDPOINTS="$2"
                shift 2
                ;;
            -o|--output)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            -w|--warmup)
                WARMUP_DURATION="$2"
                shift 2
                ;;
            -r|--rps)
                RPS_LIMIT="$2"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            -*)
                echo -e "${RED}Error: Unknown option $1${NC}" >&2
                usage
                exit 1
                ;;
            *)
                BASE_URL="$1"
                shift
                ;;
        esac
    done

    if [[ -z "${BASE_URL:-}" ]]; then
        echo -e "${RED}Error: Base URL is required${NC}" >&2
        usage
        exit 1
    fi
}

# Check dependencies
check_dependencies() {
    local missing=()

    if ! command -v wrk &> /dev/null; then
        missing+=("wrk")
    fi

    if ! command -v curl &> /dev/null; then
        missing+=("curl")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo -e "${RED}Error: Missing required dependencies: ${missing[*]}${NC}" >&2
        echo "Please install them and try again."
        exit 1
    fi

    if ! command -v jq &> /dev/null; then
        echo -e "${YELLOW}Warning: jq not found. JSON parsing will be limited.${NC}"
    fi
}

# Check if server is available
check_server() {
    local url="$1"
    echo -e "${BLUE}Checking server availability at $url...${NC}"

    if ! curl -s --connect-timeout 5 "$url" > /dev/null 2>&1; then
        echo -e "${RED}Error: Cannot connect to $url${NC}" >&2
        exit 1
    fi

    echo -e "${GREEN}Server is available.${NC}"
}

# Generate wrk Lua script for advanced metrics
generate_lua_script() {
    local script_file="$OUTPUT_DIR/benchmark.lua"
    cat > "$script_file" << 'LUASCRIPT'
-- Benchmark Lua script for wrk
-- Tracks latency distribution and errors

local counter = 0
local errors = 0
local http_errors = 0
local latencies = {}

request = function()
    counter = counter + 1
    return wrk.request()
end

response = function(status, headers, body)
    if status >= 400 then
        http_errors = http_errors + 1
    end
    if status >= 500 then
        errors = errors + 1
    end
end

done = function(summary, latency, requests)
    local p50 = latency:percentile(50) / 1000
    local p90 = latency:percentile(90) / 1000
    local p95 = latency:percentile(95) / 1000
    local p99 = latency:percentile(99) / 1000
    local p999 = latency:percentile(99.9) / 1000
    local max = latency.max / 1000
    local mean = latency.mean / 1000
    local stdev = latency.stdev / 1000

    io.write("---\n")
    io.write(string.format("requests: %d\n", summary.requests))
    io.write(string.format("duration_ms: %.2f\n", summary.duration / 1000))
    io.write(string.format("bytes: %d\n", summary.bytes))
    io.write(string.format("errors_connect: %d\n", summary.errors.connect))
    io.write(string.format("errors_read: %d\n", summary.errors.read))
    io.write(string.format("errors_write: %d\n", summary.errors.write))
    io.write(string.format("errors_status: %d\n", summary.errors.status))
    io.write(string.format("errors_timeout: %d\n", summary.errors.timeout))
    io.write(string.format("http_errors: %d\n", http_errors))
    io.write(string.format("latency_mean_ms: %.2f\n", mean))
    io.write(string.format("latency_stdev_ms: %.2f\n", stdev))
    io.write(string.format("latency_max_ms: %.2f\n", max))
    io.write(string.format("latency_p50_ms: %.2f\n", p50))
    io.write(string.format("latency_p90_ms: %.2f\n", p90))
    io.write(string.format("latency_p95_ms: %.2f\n", p95))
    io.write(string.format("latency_p99_ms: %.2f\n", p99))
    io.write(string.format("latency_p999_ms: %.2f\n", p999))
    io.write(string.format("rps: %.2f\n", summary.requests / (summary.duration / 1000000)))
    io.write(string.format("throughput_mbps: %.2f\n", (summary.bytes / 1024 / 1024) / (summary.duration / 1000000)))
end
LUASCRIPT
    echo "$script_file"
}

# Run warmup phase
run_warmup() {
    local url="$1"
    echo -e "${BLUE}Running warmup for ${WARMUP_DURATION}s...${NC}"

    wrk -t2 -c10 -d"${WARMUP_DURATION}s" "$url" > /dev/null 2>&1

    echo -e "${GREEN}Warmup complete.${NC}"
    sleep 2  # Brief pause after warmup
}

# Run benchmark for a single endpoint
run_benchmark() {
    local endpoint="$1"
    local url="${BASE_URL}${endpoint}"
    local result_file="$OUTPUT_DIR/$(echo "$endpoint" | tr '/' '_' | tr '?' '_').txt"
    local lua_script

    lua_script=$(generate_lua_script)

    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}Benchmarking: $url${NC}"
    echo -e "${BLUE}Duration: ${DURATION}s, Connections: ${CONNECTIONS}, Threads: ${THREADS}${NC}"
    echo -e "${BLUE}========================================${NC}"

    # Run warmup
    run_warmup "$url"

    # Build wrk command
    local wrk_cmd="wrk -t${THREADS} -c${CONNECTIONS} -d${DURATION}s --latency -s ${lua_script}"

    if [[ "$RPS_LIMIT" -gt 0 ]]; then
        # Calculate delay between requests per thread
        local delay=$((1000000 * THREADS / RPS_LIMIT))
        wrk_cmd="$wrk_cmd -R${RPS_LIMIT}"
    fi

    wrk_cmd="$wrk_cmd $url"

    echo -e "${YELLOW}Running: $wrk_cmd${NC}"
    echo ""

    # Run benchmark and capture output
    local output
    output=$(eval "$wrk_cmd" 2>&1)

    echo "$output" | tee "$result_file"

    # Parse and display summary
    echo -e "\n${GREEN}Results saved to: $result_file${NC}"

    # Extract key metrics from the Lua output
    parse_results "$result_file" "$endpoint"
}

# Parse and display results
parse_results() {
    local result_file="$1"
    local endpoint="$2"

    # Extract metrics from the custom Lua output
    local rps latency_p95 latency_p99 errors

    rps=$(grep "^rps:" "$result_file" 2>/dev/null | awk '{print $2}' || echo "N/A")
    latency_p95=$(grep "^latency_p95_ms:" "$result_file" 2>/dev/null | awk '{print $2}' || echo "N/A")
    latency_p99=$(grep "^latency_p99_ms:" "$result_file" 2>/dev/null | awk '{print $2}' || echo "N/A")
    errors=$(grep "^http_errors:" "$result_file" 2>/dev/null | awk '{print $2}' || echo "0")

    echo -e "\n${BLUE}Summary for $endpoint:${NC}"
    echo -e "  Requests/sec: ${GREEN}${rps}${NC}"
    echo -e "  Latency p95:  ${GREEN}${latency_p95}ms${NC}"
    echo -e "  Latency p99:  ${GREEN}${latency_p99}ms${NC}"
    echo -e "  HTTP Errors:  ${RED}${errors}${NC}"
}

# Run streaming endpoint test
run_streaming_test() {
    local endpoint="$1"
    local url="${BASE_URL}${endpoint}"
    local duration="$2"
    local result_file="$OUTPUT_DIR/streaming_$(echo "$endpoint" | tr '/' '_').txt"

    echo -e "\n${BLUE}Testing streaming endpoint: $url${NC}"
    echo -e "${BLUE}Duration: ${duration}s${NC}"

    local start_time end_time event_count
    start_time=$(date +%s%N)

    # Use curl to receive SSE events
    event_count=$(timeout "${duration}s" curl -s -N \
        -H "Accept: text/event-stream" \
        "$url" 2>/dev/null | grep -c "^data:" || echo "0")

    end_time=$(date +%s%N)

    local duration_ns=$((end_time - start_time))
    local duration_s=$(echo "scale=2; $duration_ns / 1000000000" | bc)
    local events_per_sec=$(echo "scale=2; $event_count / $duration_s" | bc 2>/dev/null || echo "N/A")

    echo -e "  Events received: ${GREEN}${event_count}${NC}"
    echo -e "  Events/sec:      ${GREEN}${events_per_sec}${NC}"

    # Save results
    cat > "$result_file" << EOF
endpoint: $endpoint
duration_s: $duration_s
events: $event_count
events_per_sec: $events_per_sec
EOF
}

# Generate comparison report
generate_report() {
    local report_file="$OUTPUT_DIR/report.md"

    echo -e "\n${BLUE}Generating benchmark report...${NC}"

    cat > "$report_file" << EOF
# Reactive Endpoint Benchmark Report

## Configuration

- **Base URL**: $BASE_URL
- **Duration**: ${DURATION}s
- **Connections**: $CONNECTIONS
- **Threads**: $THREADS
- **Warmup**: ${WARMUP_DURATION}s
- **Date**: $(date)

## Results

| Endpoint | RPS | p50 (ms) | p95 (ms) | p99 (ms) | Errors |
|----------|-----|----------|----------|----------|--------|
EOF

    # Add results for each endpoint
    IFS=',' read -ra ENDPOINT_ARRAY <<< "$ENDPOINTS"
    for endpoint in "${ENDPOINT_ARRAY[@]}"; do
        local result_file="$OUTPUT_DIR/$(echo "$endpoint" | tr '/' '_' | tr '?' '_').txt"

        if [[ -f "$result_file" ]]; then
            local rps p50 p95 p99 errors
            rps=$(grep "^rps:" "$result_file" 2>/dev/null | awk '{print $2}' || echo "N/A")
            p50=$(grep "^latency_p50_ms:" "$result_file" 2>/dev/null | awk '{print $2}' || echo "N/A")
            p95=$(grep "^latency_p95_ms:" "$result_file" 2>/dev/null | awk '{print $2}' || echo "N/A")
            p99=$(grep "^latency_p99_ms:" "$result_file" 2>/dev/null | awk '{print $2}' || echo "N/A")
            errors=$(grep "^http_errors:" "$result_file" 2>/dev/null | awk '{print $2}' || echo "0")

            echo "| $endpoint | $rps | $p50 | $p95 | $p99 | $errors |" >> "$report_file"
        fi
    done

    cat >> "$report_file" << EOF

## Recommendations

Based on the benchmark results:

1. **High Latency (p99 > 500ms)**: Consider adding caching or optimizing database queries
2. **High Error Rate (> 1%)**: Check connection pool sizing and timeout configurations
3. **Low RPS**: Verify proper use of non-blocking operations and scheduler usage

## Command Used

\`\`\`bash
$(basename "$0") -d $DURATION -c $CONNECTIONS -t $THREADS -e "$ENDPOINTS" $BASE_URL
\`\`\`
EOF

    echo -e "${GREEN}Report saved to: $report_file${NC}"
}

# Quick health check with metrics
quick_check() {
    local health_url="${BASE_URL}/actuator/health"
    local metrics_url="${BASE_URL}/actuator/metrics"

    echo -e "\n${BLUE}Quick health check...${NC}"

    # Check health endpoint
    if curl -s "$health_url" 2>/dev/null | grep -q "UP"; then
        echo -e "  Health: ${GREEN}UP${NC}"
    else
        echo -e "  Health: ${YELLOW}Unknown (health endpoint not available)${NC}"
    fi

    # Check for reactive scheduler metrics
    if curl -s "$metrics_url/reactor.scheduler.tasks.pending" 2>/dev/null | grep -q "measurements"; then
        echo -e "  Reactor metrics: ${GREEN}Available${NC}"
    else
        echo -e "  Reactor metrics: ${YELLOW}Not available${NC}"
    fi
}

# Main function
main() {
    parse_args "$@"
    check_dependencies
    check_server "$BASE_URL"

    # Create output directory
    mkdir -p "$OUTPUT_DIR"

    # Quick health check
    quick_check

    # Run benchmarks for each endpoint
    IFS=',' read -ra ENDPOINT_ARRAY <<< "$ENDPOINTS"
    for endpoint in "${ENDPOINT_ARRAY[@]}"; do
        # Trim whitespace
        endpoint=$(echo "$endpoint" | xargs)

        # Check if it's a streaming endpoint
        if [[ "$endpoint" == *"/stream"* ]] || [[ "$endpoint" == *"/events"* ]]; then
            run_streaming_test "$endpoint" "$DURATION"
        else
            run_benchmark "$endpoint"
        fi
    done

    # Generate report
    generate_report

    echo -e "\n${GREEN}Benchmark complete!${NC}"
    echo -e "Results directory: $OUTPUT_DIR"
}

# Run main function
main "$@"
