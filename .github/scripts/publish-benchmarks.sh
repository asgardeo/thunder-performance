#!/bin/bash
set -e

git config user.name "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"
git config pull.rebase true
git remote set-url origin https://x-access-token:${GITHUB_TOKEN}@${GITHUB_SERVER_URL#https://}/${GITHUB_REPOSITORY}

TIMESTAMP=$(date +%Y-%m-%d--%H-%M-%S)
THUNDER_VERSION=$(echo "$THUNDER_PACK_URL" | grep -oP '(?<=/releases/download/)[^/]+'  )
BENCHMARK_DIR_PATH="benchmarks/$THUNDER_VERSION/$DEPLOYMENT/workflow-build-$BUILD_NUMBER"

mkdir -p "$BENCHMARK_DIR_PATH"

cp $GITHUB_WORKSPACE/perf-scripts/$DEPLOYMENT/results-*/summary.csv "$BENCHMARK_DIR_PATH/summary-$TIMESTAMP.csv"

if ls $GITHUB_WORKSPACE/perf-scripts/$DEPLOYMENT/results-*/cloudwatch/*.png 1>/dev/null 2>&1; then
  mkdir -p "$BENCHMARK_DIR_PATH/cloudwatch"
  cp $GITHUB_WORKSPACE/perf-scripts/$DEPLOYMENT/results-*/cloudwatch/*.png "$BENCHMARK_DIR_PATH/cloudwatch/"
fi

cat <<EOF >> "$BENCHMARK_DIR_PATH/readme.md"
Build Number: $BUILD_NUMBER

Build Date and Time: $TIMESTAMP

Thunder Pack URL: $THUNDER_PACK_URL

Deployment Pattern: $DEPLOYMENT

Thunder Instance Type: $THUNDER_INSTANCE_TYPE

Nginx Instance Type: $NGINX_INSTANCE_TYPE

Bastion Instance Type: $BASTION_INSTANCE_TYPE

Database Instance Type: $DB_INSTANCE_TYPE

Database Type: $DB_TYPE

Concurrency: $CONCURRENCY

Thunder Instance ID: $THUNDER_INSTANCE_ID

Nginx Instance ID: $NGINX_INSTANCE_ID

Bastion Instance ID: $BASTION_INSTANCE_ID

RDS Instance ID: $RDS_INSTANCE_ID

Performance Repo: $GITHUB_SERVER_URL/$GITHUB_REPOSITORY

Pipeline Definition Branch: $GITHUB_REF_NAME

Checkout Ref (code under test): ${REPO_REF:-$GITHUB_REF_NAME}

Checkout Commit SHA: $(git rev-parse HEAD)

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
