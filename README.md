# Thunder Performance Testing

This repository contains the Infrastructure as Code (Terraform), pipeline definitions, and scripts which are utilized for Thunder performance testing.

## Overview

The Thunder Performance Testing repository provides the necessary tools and configurations to set up, deploy, and execute performance tests against Thunder environments. It includes automation pipelines, infrastructure definitions, and test scripts designed to evaluate performance under various conditions.

## Repository Structure

```
thunder-performance/
├── kubernetes/                  # Kubernetes deployment configurations
│   └── azure/                   # Azure-specific Kubernetes configurations
│       ├── devops-pipelines/    # Azure DevOps pipeline definitions
│       ├── diagrams/            # Architecture diagrams
│       └── terraform/           # Terraform scripts for Azure infrastructure
├── perf-scripts/                # Performance testing scripts
│   ├── common/                  # Common utilities for performance testing
│   ├── pre-provisioned/         # Scripts for pre-provisioned test environments
│   └── single-node/             # Scripts for single-node test environments
└── .github/                     # GitHub specific configurations and workflows
    └── workflows/               # GitHub Actions workflow definitions
```

## Key Components

### Kubernetes Azure Deployment

The `kubernetes/azure/` directory contains the infrastructure definitions and deployment pipelines for Azure. 

For detailed information about the Kubernetes deployment, please refer to the [Kubernetes Azure README](https://github.com/asgardeo/thunder-performance/blob/main/kubernetes/azure/README.md).


#### VM Performance Test Workflow

The repository includes GitHub Actions workflows for automated performance testing:
Located at `.github/workflows/vm-perf-workflow.yml`, this workflow automates performance testing on AWS virtual machines.

For detailed information, please refer to the [VM Performance Test Workflow README](https://github.com/asgardeo/thunder-performance/blob/main/.github/workflows/README.md)

### Performance Scripts

The `perf-scripts/` directory contains:

- **JMeter configurations**: Performance test definitions using Apache JMeter
- **Test scenarios**: Predefined test scenarios for different load patterns
- **Data processing tools**: Scripts for analyzing and reporting test results
