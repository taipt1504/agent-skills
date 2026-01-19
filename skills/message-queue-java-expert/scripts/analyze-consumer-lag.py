#!/usr/bin/env python3
"""
Kafka Consumer Lag Analyzer

Analyzes consumer lag for Kafka consumer groups by comparing current offsets
with end offsets (high watermarks) for each partition.

Usage:
    python analyze-consumer-lag.py --bootstrap-servers localhost:9092 --group my-consumer-group
    python analyze-consumer-lag.py --bootstrap-servers localhost:9092 --all-groups
    python analyze-consumer-lag.py --bootstrap-servers localhost:9092 --group my-group --topic my-topic
    python analyze-consumer-lag.py --config kafka.properties --group my-group

Requirements:
    pip install kafka-python

Author: Message Queue Java Expert Skill
"""

import argparse
import sys
import json
from datetime import datetime
from typing import Dict, List, Optional, Tuple
from dataclasses import dataclass, asdict
from collections import defaultdict

try:
    from kafka import KafkaAdminClient, KafkaConsumer
    from kafka.admin import ConsumerGroupDescription
    from kafka.structs import TopicPartition
except ImportError:
    print("Error: kafka-python is required. Install with: pip install kafka-python")
    sys.exit(1)


@dataclass
class PartitionLag:
    """Represents lag information for a single partition."""
    topic: str
    partition: int
    current_offset: int
    end_offset: int
    lag: int
    consumer_id: Optional[str] = None
    host: Optional[str] = None


@dataclass
class ConsumerGroupLag:
    """Aggregated lag information for a consumer group."""
    group_id: str
    state: str
    total_lag: int
    partition_count: int
    topics: List[str]
    partitions: List[PartitionLag]
    timestamp: str


class KafkaLagAnalyzer:
    """Analyzes consumer lag for Kafka consumer groups."""

    def __init__(
        self,
        bootstrap_servers: str,
        config_file: Optional[str] = None,
        security_protocol: str = "PLAINTEXT",
        sasl_mechanism: Optional[str] = None,
        sasl_username: Optional[str] = None,
        sasl_password: Optional[str] = None
    ):
        """
        Initialize the Kafka Lag Analyzer.

        Args:
            bootstrap_servers: Comma-separated list of Kafka brokers
            config_file: Optional path to properties file with Kafka config
            security_protocol: Security protocol (PLAINTEXT, SSL, SASL_PLAINTEXT, SASL_SSL)
            sasl_mechanism: SASL mechanism (PLAIN, SCRAM-SHA-256, SCRAM-SHA-512)
            sasl_username: SASL username
            sasl_password: SASL password
        """
        self.config = self._build_config(
            bootstrap_servers,
            config_file,
            security_protocol,
            sasl_mechanism,
            sasl_username,
            sasl_password
        )
        self.admin_client = None
        self.consumer = None

    def _build_config(
        self,
        bootstrap_servers: str,
        config_file: Optional[str],
        security_protocol: str,
        sasl_mechanism: Optional[str],
        sasl_username: Optional[str],
        sasl_password: Optional[str]
    ) -> Dict:
        """Build Kafka configuration dictionary."""
        config = {
            "bootstrap_servers": bootstrap_servers.split(","),
        }

        # Load from properties file if provided
        if config_file:
            config.update(self._load_properties_file(config_file))

        # Override with command line arguments
        if security_protocol != "PLAINTEXT":
            config["security_protocol"] = security_protocol

        if sasl_mechanism:
            config["sasl_mechanism"] = sasl_mechanism
            config["sasl_plain_username"] = sasl_username
            config["sasl_plain_password"] = sasl_password

        return config

    def _load_properties_file(self, filepath: str) -> Dict:
        """Load Kafka properties from a Java properties file."""
        config = {}
        property_mapping = {
            "bootstrap.servers": "bootstrap_servers",
            "security.protocol": "security_protocol",
            "sasl.mechanism": "sasl_mechanism",
            "sasl.jaas.config": None,  # Parse separately
            "ssl.truststore.location": "ssl_cafile",
            "ssl.keystore.location": "ssl_certfile",
        }

        try:
            with open(filepath, "r") as f:
                for line in f:
                    line = line.strip()
                    if line and not line.startswith("#"):
                        if "=" in line:
                            key, value = line.split("=", 1)
                            key = key.strip()
                            value = value.strip()

                            if key in property_mapping and property_mapping[key]:
                                python_key = property_mapping[key]
                                if python_key == "bootstrap_servers":
                                    config[python_key] = value.split(",")
                                else:
                                    config[python_key] = value
        except FileNotFoundError:
            print(f"Warning: Config file {filepath} not found")

        return config

    def connect(self):
        """Establish connections to Kafka."""
        try:
            self.admin_client = KafkaAdminClient(**self.config)
            # Consumer for fetching end offsets
            consumer_config = self.config.copy()
            consumer_config["group_id"] = "__lag_analyzer_internal__"
            consumer_config["enable_auto_commit"] = False
            self.consumer = KafkaConsumer(**consumer_config)
        except Exception as e:
            print(f"Error connecting to Kafka: {e}")
            sys.exit(1)

    def close(self):
        """Close Kafka connections."""
        if self.admin_client:
            self.admin_client.close()
        if self.consumer:
            self.consumer.close()

    def list_consumer_groups(self) -> List[str]:
        """List all consumer groups in the cluster."""
        try:
            groups = self.admin_client.list_consumer_groups()
            return [g[0] for g in groups]
        except Exception as e:
            print(f"Error listing consumer groups: {e}")
            return []

    def get_group_description(self, group_id: str) -> Optional[Dict]:
        """Get description of a consumer group."""
        try:
            descriptions = self.admin_client.describe_consumer_groups([group_id])
            if descriptions:
                desc = descriptions[0]
                return {
                    "group_id": desc.group_id,
                    "state": desc.state,
                    "members": [
                        {
                            "member_id": m.member_id,
                            "client_id": m.client_id,
                            "host": m.host,
                            "assignment": self._parse_assignment(m.member_assignment) if m.member_assignment else []
                        }
                        for m in desc.members
                    ]
                }
        except Exception as e:
            print(f"Error describing consumer group {group_id}: {e}")
        return None

    def _parse_assignment(self, assignment_bytes: bytes) -> List[Tuple[str, int]]:
        """Parse member assignment to get topic-partition pairs."""
        # This is a simplified parser - kafka-python doesn't expose a clean way to parse this
        # In production, you might want to use the Java AdminClient or kafka-python internals
        return []

    def get_consumer_group_offsets(self, group_id: str) -> Dict[TopicPartition, int]:
        """Get committed offsets for a consumer group."""
        try:
            offsets = self.admin_client.list_consumer_group_offsets(group_id)
            return {tp: offset.offset for tp, offset in offsets.items()}
        except Exception as e:
            print(f"Error getting offsets for group {group_id}: {e}")
            return {}

    def get_end_offsets(self, topic_partitions: List[TopicPartition]) -> Dict[TopicPartition, int]:
        """Get end offsets (high watermarks) for topic partitions."""
        try:
            return self.consumer.end_offsets(topic_partitions)
        except Exception as e:
            print(f"Error getting end offsets: {e}")
            return {}

    def analyze_group_lag(
        self,
        group_id: str,
        topic_filter: Optional[str] = None
    ) -> Optional[ConsumerGroupLag]:
        """
        Analyze lag for a specific consumer group.

        Args:
            group_id: The consumer group ID
            topic_filter: Optional topic name to filter results

        Returns:
            ConsumerGroupLag object with lag analysis
        """
        # Get group description
        group_desc = self.get_group_description(group_id)
        if not group_desc:
            return None

        # Get committed offsets
        committed_offsets = self.get_consumer_group_offsets(group_id)
        if not committed_offsets:
            print(f"No committed offsets found for group {group_id}")
            return None

        # Filter by topic if specified
        if topic_filter:
            committed_offsets = {
                tp: offset for tp, offset in committed_offsets.items()
                if tp.topic == topic_filter
            }

        # Get end offsets
        topic_partitions = list(committed_offsets.keys())
        end_offsets = self.get_end_offsets(topic_partitions)

        # Build member assignment map
        member_map = {}
        for member in group_desc.get("members", []):
            for tp in member.get("assignment", []):
                key = (tp[0], tp[1])
                member_map[key] = {
                    "consumer_id": member["client_id"],
                    "host": member["host"]
                }

        # Calculate lag per partition
        partitions = []
        total_lag = 0
        topics = set()

        for tp, current_offset in committed_offsets.items():
            end_offset = end_offsets.get(tp, 0)
            lag = max(0, end_offset - current_offset)
            total_lag += lag
            topics.add(tp.topic)

            member_info = member_map.get((tp.topic, tp.partition), {})

            partitions.append(PartitionLag(
                topic=tp.topic,
                partition=tp.partition,
                current_offset=current_offset,
                end_offset=end_offset,
                lag=lag,
                consumer_id=member_info.get("consumer_id"),
                host=member_info.get("host")
            ))

        # Sort partitions by topic and partition number
        partitions.sort(key=lambda p: (p.topic, p.partition))

        return ConsumerGroupLag(
            group_id=group_id,
            state=group_desc.get("state", "Unknown"),
            total_lag=total_lag,
            partition_count=len(partitions),
            topics=sorted(topics),
            partitions=partitions,
            timestamp=datetime.now().isoformat()
        )


class OutputFormatter:
    """Formats lag analysis output."""

    @staticmethod
    def format_table(lag_data: ConsumerGroupLag, show_partitions: bool = True) -> str:
        """Format lag data as a human-readable table."""
        lines = []

        # Header
        lines.append("=" * 80)
        lines.append(f"Consumer Group: {lag_data.group_id}")
        lines.append(f"State: {lag_data.state}")
        lines.append(f"Timestamp: {lag_data.timestamp}")
        lines.append("=" * 80)

        # Summary
        lines.append("\nSUMMARY")
        lines.append("-" * 40)
        lines.append(f"Total Lag: {lag_data.total_lag:,} messages")
        lines.append(f"Partitions: {lag_data.partition_count}")
        lines.append(f"Topics: {', '.join(lag_data.topics)}")

        # Lag by topic
        topic_lags = defaultdict(lambda: {"lag": 0, "partitions": 0})
        for p in lag_data.partitions:
            topic_lags[p.topic]["lag"] += p.lag
            topic_lags[p.topic]["partitions"] += 1

        lines.append("\nLAG BY TOPIC")
        lines.append("-" * 40)
        lines.append(f"{'Topic':<40} {'Lag':>12} {'Partitions':>12}")
        lines.append("-" * 64)
        for topic, stats in sorted(topic_lags.items()):
            lines.append(f"{topic:<40} {stats['lag']:>12,} {stats['partitions']:>12}")

        # Partition details
        if show_partitions:
            lines.append("\nPARTITION DETAILS")
            lines.append("-" * 80)
            lines.append(f"{'Topic':<30} {'Part':>6} {'Current':>12} {'End':>12} {'Lag':>10}")
            lines.append("-" * 80)

            for p in lag_data.partitions:
                topic_display = p.topic[:28] + ".." if len(p.topic) > 30 else p.topic
                lag_indicator = " *" if p.lag > 1000 else ""
                lines.append(
                    f"{topic_display:<30} {p.partition:>6} {p.current_offset:>12,} "
                    f"{p.end_offset:>12,} {p.lag:>10,}{lag_indicator}"
                )

        # Warning for high lag
        high_lag_partitions = [p for p in lag_data.partitions if p.lag > 10000]
        if high_lag_partitions:
            lines.append("\nWARNINGS")
            lines.append("-" * 40)
            lines.append(f"Found {len(high_lag_partitions)} partition(s) with lag > 10,000:")
            for p in high_lag_partitions:
                lines.append(f"  - {p.topic}[{p.partition}]: {p.lag:,} messages behind")

        lines.append("")
        return "\n".join(lines)

    @staticmethod
    def format_json(lag_data: ConsumerGroupLag) -> str:
        """Format lag data as JSON."""
        data = asdict(lag_data)
        return json.dumps(data, indent=2)

    @staticmethod
    def format_prometheus(lag_data: ConsumerGroupLag) -> str:
        """Format lag data as Prometheus metrics."""
        lines = []

        # Help and type declarations
        lines.append("# HELP kafka_consumer_group_lag Consumer group lag per partition")
        lines.append("# TYPE kafka_consumer_group_lag gauge")

        for p in lag_data.partitions:
            labels = f'group="{lag_data.group_id}",topic="{p.topic}",partition="{p.partition}"'
            lines.append(f"kafka_consumer_group_lag{{{labels}}} {p.lag}")

        lines.append("")
        lines.append("# HELP kafka_consumer_group_total_lag Total consumer group lag")
        lines.append("# TYPE kafka_consumer_group_total_lag gauge")
        lines.append(f'kafka_consumer_group_total_lag{{group="{lag_data.group_id}"}} {lag_data.total_lag}')

        return "\n".join(lines)

    @staticmethod
    def format_csv(lag_data: ConsumerGroupLag) -> str:
        """Format lag data as CSV."""
        lines = ["group_id,topic,partition,current_offset,end_offset,lag"]
        for p in lag_data.partitions:
            lines.append(f"{lag_data.group_id},{p.topic},{p.partition},{p.current_offset},{p.end_offset},{p.lag}")
        return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(
        description="Analyze Kafka consumer group lag",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s --bootstrap-servers localhost:9092 --group my-consumer-group
  %(prog)s --bootstrap-servers kafka1:9092,kafka2:9092 --all-groups
  %(prog)s --bootstrap-servers localhost:9092 --group my-group --topic my-topic
  %(prog)s --config kafka.properties --group my-group --format json
  %(prog)s --bootstrap-servers localhost:9092 --all-groups --format prometheus
        """
    )

    # Connection options
    conn_group = parser.add_argument_group("Connection Options")
    conn_group.add_argument(
        "--bootstrap-servers", "-b",
        default="localhost:9092",
        help="Kafka bootstrap servers (comma-separated)"
    )
    conn_group.add_argument(
        "--config", "-c",
        help="Path to Kafka properties file"
    )
    conn_group.add_argument(
        "--security-protocol",
        default="PLAINTEXT",
        choices=["PLAINTEXT", "SSL", "SASL_PLAINTEXT", "SASL_SSL"],
        help="Security protocol"
    )
    conn_group.add_argument(
        "--sasl-mechanism",
        choices=["PLAIN", "SCRAM-SHA-256", "SCRAM-SHA-512"],
        help="SASL mechanism"
    )
    conn_group.add_argument("--sasl-username", help="SASL username")
    conn_group.add_argument("--sasl-password", help="SASL password")

    # Group selection options
    group_sel = parser.add_argument_group("Group Selection")
    group_sel.add_argument(
        "--group", "-g",
        help="Consumer group ID to analyze"
    )
    group_sel.add_argument(
        "--all-groups", "-a",
        action="store_true",
        help="Analyze all consumer groups"
    )
    group_sel.add_argument(
        "--topic", "-t",
        help="Filter by topic name"
    )

    # Output options
    output_group = parser.add_argument_group("Output Options")
    output_group.add_argument(
        "--format", "-f",
        default="table",
        choices=["table", "json", "prometheus", "csv"],
        help="Output format"
    )
    output_group.add_argument(
        "--no-partitions",
        action="store_true",
        help="Hide partition details in table output"
    )
    output_group.add_argument(
        "--output", "-o",
        help="Output file (default: stdout)"
    )

    # Filtering options
    filter_group = parser.add_argument_group("Filtering Options")
    filter_group.add_argument(
        "--min-lag",
        type=int,
        default=0,
        help="Only show groups with total lag >= this value"
    )
    filter_group.add_argument(
        "--exclude-internal",
        action="store_true",
        help="Exclude internal consumer groups (starting with __)"
    )

    args = parser.parse_args()

    # Validate arguments
    if not args.group and not args.all_groups:
        parser.error("Either --group or --all-groups must be specified")

    # Initialize analyzer
    analyzer = KafkaLagAnalyzer(
        bootstrap_servers=args.bootstrap_servers,
        config_file=args.config,
        security_protocol=args.security_protocol,
        sasl_mechanism=args.sasl_mechanism,
        sasl_username=args.sasl_username,
        sasl_password=args.sasl_password
    )

    try:
        analyzer.connect()

        # Get list of groups to analyze
        if args.all_groups:
            groups = analyzer.list_consumer_groups()
            if args.exclude_internal:
                groups = [g for g in groups if not g.startswith("__")]
        else:
            groups = [args.group]

        if not groups:
            print("No consumer groups found")
            sys.exit(0)

        # Analyze each group
        results = []
        for group_id in groups:
            lag_data = analyzer.analyze_group_lag(group_id, args.topic)
            if lag_data and lag_data.total_lag >= args.min_lag:
                results.append(lag_data)

        if not results:
            print("No lag data found for the specified criteria")
            sys.exit(0)

        # Format output
        formatter = OutputFormatter()
        output_lines = []

        for lag_data in results:
            if args.format == "table":
                output_lines.append(formatter.format_table(lag_data, not args.no_partitions))
            elif args.format == "json":
                output_lines.append(formatter.format_json(lag_data))
            elif args.format == "prometheus":
                output_lines.append(formatter.format_prometheus(lag_data))
            elif args.format == "csv":
                if not output_lines:  # Only add header once
                    output_lines.append(formatter.format_csv(lag_data))
                else:
                    # Skip header for subsequent groups
                    csv_output = formatter.format_csv(lag_data)
                    output_lines.append("\n".join(csv_output.split("\n")[1:]))

        output = "\n".join(output_lines)

        # Write output
        if args.output:
            with open(args.output, "w") as f:
                f.write(output)
            print(f"Output written to {args.output}")
        else:
            print(output)

    except KeyboardInterrupt:
        print("\nInterrupted by user")
        sys.exit(130)
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)
    finally:
        analyzer.close()


if __name__ == "__main__":
    main()
