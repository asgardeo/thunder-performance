#!/bin/bash
set -e

git config user.name "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"
git config pull.rebase true
git remote set-url origin https://x-access-token:${GITHUB_TOKEN}@${GITHUB_SERVER_URL#https://}/${GITHUB_REPOSITORY}

TIMESTAMP=$(date +%Y-%m-%d--%H-%M-%S)
BENCHMARK_DIR_PATH="benchmarks/$DEPLOYMENT/workflow-build-$BUILD_NUMBER"

mkdir -p "$BENCHMARK_DIR_PATH"

cp "$GITHUB_WORKSPACE/perf-scripts/$DEPLOYMENT/results-*/summary.csv" "$BENCHMARK_DIR_PATH/summary-$TIMESTAMP.csv"

if ls "$GITHUB_WORKSPACE/perf-scripts/$DEPLOYMENT/results-*/cloudwatch/*.png" 1>/dev/null 2>&1; then
  mkdir -p "$BENCHMARK_DIR_PATH/cloudwatch"
  cp "$GITHUB_WORKSPACE/perf-scripts/$DEPLOYMENT/results-*/cloudwatch/*.png" "$BENCHMARK_DIR_PATH/cloudwatch/"
fi

cat <<EOF >> "$BENCHMARK_DIR_PATH/readme.md"
Build Number: $BUILD_NUMBER

Build Date and Time: $TIMESTAMP

Thunder Pack URL: $THUNDER_PACK_URL

Deployment Pattern: $DEPLOYMENT

Thunder Instance Type: $THUNDER_INSTANCE_TYPE

Database Instance Type: $DB_INSTANCE_TYPE

Database Type: $DB_TYPE

Concurrency: $CONCURRENCY

Performance Repo: $GITHUB_SERVER_URL/$GITHUB_REPOSITORY

Performance Repo Branch: $GITHUB_REF_NAME

EOF

BENCHMARK_DIR_PATH="$BENCHMARK_DIR_PATH" python3 .github/scripts/generate-benchmark-readme.py

if [ -d "$BENCHMARK_DIR_PATH/cloudwatch" ]; then
  cat <<EOF >> "$BENCHMARK_DIR_PATH/readme.md"

## CloudWatch Metrics

### Thunder (EC2)
![Thunder EC2 Metrics](cloudwatch/thunder-ec2.png)

### Nginx (EC2)
![Nginx EC2 Metrics](cloudwatch/nginx-ec2.png)

### Bastion (EC2)
![Bastion EC2 Metrics](cloudwatch/bastion-ec2.png)

### RDS
![RDS Metrics](cloudwatch/rds.png)

EOF
fi

git add "$BENCHMARK_DIR_PATH/"
git commit -m "Add performance benchmarks from test at $TIMESTAMP"
git restore .
git pull origin "$GITHUB_REF_NAME"
git push -u origin "$GITHUB_REF_NAME"
