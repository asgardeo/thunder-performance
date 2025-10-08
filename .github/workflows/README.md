# VM Performance Test Workflow

This README provides information about the GitHub Actions workflow for running performance tests on AWS virtual machines for Thunder.

## Overview

The `vm-perf-workflow.yml` is designed to automate performance testing of Thunder deployments on AWS VMs. It allows configuring various parameters like deployment type, CPU cores, concurrency patterns, and more to evaluate Thunder's performance under different conditions.

## Workflow Triggers

This workflow is manually triggered using GitHub Actions' `workflow_dispatch` event, allowing users to run performance tests on-demand with customized parameters.

## Input Parameters

When triggering the workflow, you can configure the following parameters:

| Parameter | Description | Default Value | Required |
|-----------|-------------|--------------|----------|
| `THUNDER_PACK_URL` | URL to download the Thunder pack | `https://github.com/asgardeo/thunder/releases/download/v0.7.0/thunder-v0.7.0-linux-x64.zip` | Yes |
| `DEPLOYMENT` | Deployment type | `single-node` | Yes |
| `CPU_CORES` | Number of CPU cores for the VM | `4` (options: 2, 4, 8) | Yes |
| `ADDITIONAL_PARAMS_TO_RUN_PERFORMANCE_SCRIPT` | Additional parameters for the performance script | `-d 15 -w 5 -x false -y JWT` | Yes |
| `PERFORMANCE_REPO` | Performance repository URL | `https://github.com/asgardeo/thunder-performance` | Yes |
| `BRANCH` | Branch to use from the performance repository | `main` | Yes |
| `MODE` | Testing mode | `FULL` (options: FULL, QUICK) | Yes |
| `USE_DELAYS` | Enable delays in testing | `true` | Yes |
| `CONCURRENCY` | Concurrency pattern for load testing | `50-50` (various options available) | Yes |
| `DB_TYPE` | Database type | `postgres` | Yes |

## Workflow Steps

The workflow performs the following steps:

1. Checkout the repository
2. Configure AWS credentials for VM provisioning
3. Setup Java for performance testing
4. Execute VM performance tests using the configuration parameters
5. Upload test results as artifacts, which are retained for 30 days

## Usage

To run this workflow:

1. Navigate to the "Actions" tab in the GitHub repository
2. Select "VM Performance Test on AWS" workflow
3. Click "Run workflow"
4. Configure the parameters as needed
5. Click "Run workflow" to start the performance test

## Results

After the workflow completes, performance test results are uploaded as artifacts and can be downloaded from the GitHub Actions interface. These artifacts are named `performance-test-results-{run-number}` and contain detailed information about the test execution.

## Related Files

The workflow relies on the performance testing scripts located in the `perf-scripts` directory, particularly those in the `single-node` and `common` subdirectories based on the selected deployment type.
