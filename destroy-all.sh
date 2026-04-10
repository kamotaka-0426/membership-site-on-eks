#!/bin/bash
set -euo pipefail

trap '
    echo ""
    echo "=========================================="
    echo "❌ Script failed."
    echo "   Check the AWS console for remaining resources."
    echo "=========================================="
' ERR

# --- Configuration ---
ARGOCD_NS="argocd"
PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
DEV_DIR="$PROJECT_ROOT/terraform/envs/dev"
BOOTSTRAP_DIR="$PROJECT_ROOT/terraform/bootstrap"

echo "⚠️  Warning: This script will delete ALL infrastructure. This cannot be undone."
echo "Starting in 5 seconds... (Press Ctrl+C to cancel)"
sleep 5

# --- [STEP 1] Clean up Argo CD managed resources ---
echo "=== [1/3] Deleting Argo CD Applications ==="
kubectl delete application --all -n $ARGOCD_NS --cascade=foreground --timeout=60s 2>/dev/null

MAX_RETRIES=18 # Wait up to 3 minutes
RETRY_COUNT=0
while : ; do
    STILL_EXISTS=$(kubectl get applications -n $ARGOCD_NS -o name 2>/dev/null)
    if [ -z "$STILL_EXISTS" ]; then
        echo "✅ All Argo CD Applications have been deleted."
        break
    fi

    if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
        echo "⚠️  Timeout: Force-removing finalizers to proceed with deletion."
        kubectl get applications -n $ARGOCD_NS -o name | xargs -I {} kubectl patch {} -n $ARGOCD_NS -p '{"metadata":{"finalizers":null}}' --type merge 2>/dev/null
        break
    fi

    echo "Waiting... remaining resources: $(echo $STILL_EXISTS | wc -w)"
    RETRY_COUNT=$((RETRY_COUNT + 1))
    sleep 10
done

# --- Wait for AWS ALB to be fully deleted ---
echo "=== Waiting for AWS Load Balancer (ALB) to be removed... ==="
while : ; do
    ALB_ARN=$(aws elbv2 describe-load-balancers --query "LoadBalancers[?contains(LoadBalancerName, 'membership-blog')].LoadBalancerArn" --output text --region ap-northeast-1 --profile dev-infra-01 2>/dev/null)

    if [ -z "$ALB_ARN" ]; then
        echo "✅ AWS Load Balancer has been fully deleted."
        break
    fi

    echo "Waiting... load balancer still exists: $ALB_ARN"
    sleep 20
done

# --- [STEP 2] Destroy main infrastructure (envs/dev) ---
echo "=== [2/3] Destroying main infrastructure (envs/dev)... ==="
if [ ! -d "$DEV_DIR" ]; then
    echo "❌ Error: $DEV_DIR not found."
    exit 1
fi
cd "$DEV_DIR"
terraform init -input=false > /dev/null
if ! terraform destroy -auto-approve; then
    echo "❌ Failed to destroy envs/dev. Check the AWS console for remaining resources."
    exit 1
fi
echo "✅ envs/dev has been destroyed."

# --- [STEP 3] Destroy bootstrap layer (S3/DynamoDB) ---
echo "=== [3/3] Destroying bootstrap layer (S3/DynamoDB)... ==="
if [ ! -d "$BOOTSTRAP_DIR" ]; then
    echo "❌ Error: $BOOTSTRAP_DIR not found."
    exit 1
fi
cd "$BOOTSTRAP_DIR"
if ! terraform destroy -auto-approve; then
    echo "❌ Failed to destroy bootstrap layer."
    exit 1
fi
echo "✅ Bootstrap layer has been destroyed."

echo "=========================================="
echo "🎉 All resources have been successfully deleted."
echo "=========================================="
