# Enterprise Linux Platform Performance

A lightweight performance baseline and tuning utility for enterprise Linux systems.

## Features

- Collects CPU, memory, disk, and network metrics
- Generates a structured JSON baseline report
- Produces a readable summary with status indicators
- Identifies performance issues and provides recommendations
- Apply mode writes an optimized `sysctl` tuning configuration
- Stores historical baselines for trend comparison

## Installation

```bash
mkdir -p /opt/enterprise-linux-platform/performance
cp perf-baseline.sh /opt/enterprise-linux-platform/performance/
chmod +x /opt/enterprise-linux-platform/performance/perf-baseline.sh
```

## Usage

### Run baseline:
```bash
/opt/enterprise-linux-platform/performance/perf-baseline.sh
```

### Apply recommended tuning:
```bash
/opt/enterprise-linux-platform/performance/perf-baseline.sh --tune
```