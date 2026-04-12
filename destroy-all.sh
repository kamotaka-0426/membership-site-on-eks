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
echo "Note: If the script fails mid-way, simply re-run it."
echo "      Terraform will only target resources that still remain."
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

# --- [STEP 2] Clean up ECR images ---
echo "=== [2/4] Cleaning up ECR images... ==="
ECR_REPO=$(terraform -chdir="$DEV_DIR" output -raw ecr_repository_name 2>/dev/null || echo "")
if [ -n "$ECR_REPO" ]; then
    IMAGE_IDS=$(aws ecr list-images --repository-name "$ECR_REPO" \
        --region ap-northeast-1 --profile dev-infra-01 \
        --query 'imageIds' --output json 2>/dev/null || echo "[]")
    if [ "$IMAGE_IDS" != "[]" ] && [ "$IMAGE_IDS" != "" ]; then
        aws ecr batch-delete-image --repository-name "$ECR_REPO" \
            --image-ids "$IMAGE_IDS" \
            --region ap-northeast-1 --profile dev-infra-01 > /dev/null 2>&1 || true
        echo "  Deleted all images from ECR: $ECR_REPO"
    else
        echo "  No images found in ECR: $ECR_REPO"
    fi
fi
echo "✅ ECR cleanup complete."

# --- [STEP 3] Destroy main infrastructure (envs/dev) ---
echo "=== [3/4] Destroying main infrastructure (envs/dev)... ==="
if [ ! -d "$DEV_DIR" ]; then
    echo "❌ Error: $DEV_DIR not found."
    exit 1
fi
cd "$DEV_DIR"
terraform init -input=false > /dev/null
if ! terraform destroy -auto-approve; then
    echo "❌ Failed to destroy envs/dev. Check the AWS console for remaining resources."
    echo "   Re-running this script is safe — Terraform will only target resources that still remain."
    exit 1
fi
echo "✅ envs/dev has been destroyed."

# --- [STEP 4] Destroy bootstrap layer (S3/DynamoDB) ---
echo "=== [4/4] Destroying bootstrap layer (S3/DynamoDB)... ==="
if [ ! -d "$BOOTSTRAP_DIR" ]; then
    echo "❌ Error: $BOOTSTRAP_DIR not found."
    exit 1
fi
cd "$BOOTSTRAP_DIR"
if ! terraform destroy -auto-approve; then
    echo "❌ Failed to destroy bootstrap layer."
    echo "   Re-running this script is safe — Terraform will only target resources that still remain."
    exit 1
fi
echo "✅ Bootstrap layer has been destroyed."

echo "=========================================="
echo "🎉 All resources have been successfully deleted."
echo "=========================================="
