#!/bin/bash
set -euo pipefail

trap '
    echo ""
    echo "=========================================="
    echo "❌ Script failed."
    echo "   Check the AWS console for any resources that were created."
    echo "=========================================="
' ERR

# --- Configuration ---
PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
DEV_DIR="$PROJECT_ROOT/terraform/envs/dev"
BOOTSTRAP_DIR="$PROJECT_ROOT/terraform/bootstrap"
TFVARS="$DEV_DIR/terraform.tfvars"
TFVARS_EXAMPLE="$DEV_DIR/terraform.tfvars.example"
DEV_MAIN_TF="$DEV_DIR/main.tf"

echo "=========================================="
echo "  Membership Blog on EKS - Setup Script"
echo "=========================================="
echo ""

# --- Prerequisites check ---
echo "=== Checking prerequisites... ==="
for cmd in terraform kubectl helm aws; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "❌ Error: '$cmd' is not installed."
        exit 1
    fi
done
echo "✅ All required tools are available."

# Check terraform.tfvars exists
if [ ! -f "$TFVARS" ]; then
    echo ""
    echo "⚠️  $TFVARS not found."
    echo "   Copy the example file and fill in your values:"
    echo ""
    echo "   cp $TFVARS_EXAMPLE $TFVARS"
    echo "   # Then edit $TFVARS"
    echo ""
    exit 1
fi
echo "✅ terraform.tfvars found."

echo ""
echo "Starting in 5 seconds... (Press Ctrl+C to cancel)"
sleep 5

# --- [STEP 1] Bootstrap (S3 backend + Route53) ---
echo ""
echo "=== [1/4] Deploying bootstrap layer (S3/DynamoDB/Route53)... ==="
if [ ! -d "$BOOTSTRAP_DIR" ]; then
    echo "❌ Error: $BOOTSTRAP_DIR not found."
    exit 1
fi
cd "$BOOTSTRAP_DIR"
terraform init -input=false
if ! terraform apply -auto-approve; then
    echo "❌ Failed to apply bootstrap layer."
    exit 1
fi
echo "✅ Bootstrap layer deployed successfully."

# --- [STEP 1b] Auto-update backend bucket name in envs/dev/main.tf ---
echo ""
echo "=== Updating backend config with the new S3 state bucket name... ==="
BUCKET_NAME=$(terraform -chdir="$BOOTSTRAP_DIR" output -raw terraform_state_bucket_name)
echo "  State bucket: $BUCKET_NAME"

# Replace the bucket = "..." line inside the backend "s3" block
sed -i "s|^\( *\)bucket *=.*\".*tfstate.*\"|\1bucket         = \"$BUCKET_NAME\"|" "$DEV_MAIN_TF"

echo "✅ $DEV_MAIN_TF backend bucket updated to: $BUCKET_NAME"

# --- NS record instructions ---
echo ""
echo "=========================================="
echo "  ⚠️  ACTION REQUIRED: Register NS Records"
echo "=========================================="
echo ""
echo "The Route53 hosted zone has been created with the following name servers."
echo "Go to your domain registrar (e.g. Google Domains, GoDaddy) and update"
echo "the nameservers for your domain to these values."
echo ""
DOMAIN=$(terraform -chdir="$BOOTSTRAP_DIR" output -raw domain_name)
echo "  Domain: $DOMAIN"
echo ""
echo "  Name Servers:"
terraform -chdir="$BOOTSTRAP_DIR" output -json route53_name_servers \
    | tr -d '[]"' | tr ',' '\n' | sed 's/^ */    /; s/[[:space:]]*$//'
echo ""
echo "Note: DNS propagation may take a few minutes up to 48 hours."
echo "=========================================="
echo ""
echo "Press Enter once you have registered the NS records at your registrar..."
read -r

# --- [STEP 2] First apply: EKS + Argo CD (excluding CloudFront) ---
echo ""
echo "=== [2/4] First apply: core infrastructure (EKS / RDS / Argo CD) ==="
echo "  Note: CloudFront will be provisioned in the second apply once the ALB hostname is available."
if [ ! -d "$DEV_DIR" ]; then
    echo "❌ Error: $DEV_DIR not found."
    exit 1
fi
cd "$DEV_DIR"
terraform init -input=false -reconfigure
if ! terraform apply -auto-approve \
    -target=module.vpc \
    -target=module.eks \
    -target=module.rds \
    -target=module.ecr \
    -target=module.iam_oidc \
    -target=module.acm_ingress \
    -target=helm_release.argocd \
    -target=kubernetes_manifest.argocd_app \
    -target=module.lb_controller_role \
    -target=helm_release.aws_lb_controller; then
    echo "❌ First apply failed."
    exit 1
fi
echo "✅ First apply complete. Waiting for Argo CD to create the Ingress and ALB..."

# --- [STEP 3] Wait for ALB to become available ---
echo ""
echo "=== [3/4] Waiting for ALB to become available (up to 10 minutes) ==="
MAX_RETRIES=30  # 20s × 30 = 10 minutes
RETRY_COUNT=0
while : ; do
    ALB_HOSTNAME=$(kubectl get ingress membership-blog-ingress -n dev \
        -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)

    if [ -n "$ALB_HOSTNAME" ]; then
        echo "✅ ALB is ready: $ALB_HOSTNAME"
        break
    fi

    if [ "$RETRY_COUNT" -ge "$MAX_RETRIES" ]; then
        echo "❌ Timeout: ALB did not become available within 10 minutes."
        echo "   Run 'kubectl get ingress -n dev' to check the status."
        exit 1
    fi

    echo "Waiting... ($((RETRY_COUNT * 20))s elapsed)"
    RETRY_COUNT=$((RETRY_COUNT + 1))
    sleep 20
done

# --- [STEP 4] Second apply: CloudFront + Frontend ---
echo ""
echo "=== [4/4] Second apply: CloudFront and Frontend ==="
cd "$DEV_DIR"
if ! terraform apply -auto-approve; then
    echo "❌ Second apply failed."
    exit 1
fi
echo "✅ All infrastructure deployed successfully."

# --- Completion message + GitHub Secrets outputs ---
echo ""
echo "=========================================="
echo "🎉 Setup complete!"
echo "=========================================="
echo ""
echo "--- GitHub Actions Secrets ---"
echo ""
terraform -chdir="$DEV_DIR" output github_actions_role_arn  | awk '{print "AWS_ROLE_ARN            = " $0}'
terraform -chdir="$DEV_DIR" output ecr_repository_url       | awk '{print "ECR_REPOSITORY          = " $0}'
terraform -chdir="$DEV_DIR" output frontend_url             | awk '{print "VITE_API_URL            = " $0 "/api"}'
echo ""
echo "S3_BUCKET_NAME and CLOUDFRONT_DISTRIBUTION_ID can be found in the"
echo "AWS console or via 'terraform output'."
echo ""
echo "--- Terraform State Bucket ---"
echo "  Bucket: $BUCKET_NAME  (already written to $DEV_MAIN_TF)"
echo ""
echo "--- Access URLs ---"
terraform -chdir="$DEV_DIR" output frontend_url | awk '{print "Frontend : " $0}'
terraform -chdir="$DEV_DIR" output api_url      | awk '{print "API      : " $0 "/health"}'
echo ""
