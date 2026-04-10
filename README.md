# Membership Blog on EKS

[日本語版 README はこちら](README.ja.md)

A production-ready, secure, and scalable membership blog system built on AWS EKS (Kubernetes).
All infrastructure layers are managed with Terraform, and continuous delivery is achieved through GitOps with Argo CD.

## Architecture

```
Users
  │
  ▼
CloudFront (HTTPS, CDN)
  ├── /          → S3 (React frontend, OAC-secured)
  └── /api/*     → ALB (custom header verification)
                      │
                      ▼
                EKS Managed Node Group (t3.small × 2)
                  └── FastAPI Pod (replicas: 2)
                          │
                          ▼
                    RDS PostgreSQL (Private Subnet)
```

| Layer | Technology |
|---|---|
| Frontend | React (Vite) + S3 + CloudFront (OAC) |
| Backend | FastAPI (Python 3.12) on EKS Managed Node Groups |
| Database | Amazon RDS for PostgreSQL (Private Subnet) |
| Networking | VPC, ALB via AWS Load Balancer Controller, Route53, ACM |
| Security | IRSA, ACM (TLS 1.2+), AWS Secrets Manager, custom origin header |
| GitOps | Argo CD (automated sync + self-heal) |
| IaC | Terraform (fully modular) |
| CI/CD | GitHub Actions (OIDC — no stored AWS credentials) |

## Key Design Decisions

**1. Full Infrastructure as Code**
Everything from the VPC to EKS cluster to Kubernetes manifests (Ingress, ConfigMaps) is managed in Terraform. No manual AWS console operations.

**2. GitOps with Argo CD**
GitHub Actions builds and pushes a Docker image, then commits the new image tag into `k8s/overlays/dev/kustomization.yaml`. Argo CD detects the manifest change and automatically deploys to the cluster — keeping Git as the single source of truth.

**3. Secure Origin Protection**
Direct access to the ALB is blocked. CloudFront attaches a random secret to the `X-Origin-Verify` header on every request. The FastAPI middleware rejects any request missing this header (except `/health`), preventing users from bypassing CloudFront.

**4. Keyless AWS Authentication**
GitHub Actions assumes an IAM role via OIDC federation — no long-lived AWS access keys stored as secrets. The IAM role is scoped to only the specific GitHub repository.

**5. Minimal-Privilege IAM with IRSA**
Kubernetes pods access AWS services (Secrets Manager, ECR) via IAM Roles for Service Accounts (IRSA), not node-level instance profiles.

**6. Lightweight, Reproducible Docker Images**
Multi-stage builds separate the build environment (with `build-essential`) from the runtime image. A Python virtual environment (`venv`) is copied between stages, producing a small and secure final image.

## Repository Structure

```
.
├── terraform/
│   ├── bootstrap/          # S3 backend, Route53 hosted zone
│   ├── envs/dev/           # Environment entrypoint (main.tf, variables.tf)
│   └── modules/            # Reusable modules
│       ├── vpc/            # VPC, subnets, security groups
│       ├── eks/            # EKS cluster, node group, IRSA OIDC provider
│       ├── rds/            # RDS PostgreSQL
│       ├── ecr/            # ECR repository
│       ├── acm/            # ACM certificates
│       ├── cloudfront/     # CloudFront distributions
│       ├── frontend/       # S3 bucket + CloudFront OAC for React
│       └── iam_oidc/       # GitHub Actions OIDC IAM role
├── k8s/
│   ├── base/               # Deployment, Service, Ingress (environment-agnostic)
│   └── overlays/
│       └── dev/            # Kustomize patches: replicas, image tag, ConfigMap
├── app/                    # FastAPI backend (Python 3.12)
│   ├── routers/            # Auth, Posts
│   ├── services/           # Business logic
│   ├── core/config.py      # Settings (pydantic-settings)
│   ├── Dockerfile          # Multi-stage build
│   └── tests/              # pytest test suite
├── frontend/               # React (Vite) frontend
├── argocd/                 # Argo CD Application manifest
├── .github/workflows/
│   ├── infra-deploy.yml    # Test → Build → Push ECR → Update manifest → Argo CD sync
│   └── frontend-deploy.yml # Build → S3 sync → CloudFront invalidation
└── destroy-all.sh          # Safe full teardown script
```

## CI/CD Pipeline

### Backend (`app/**` push to `main`)

```
Push to main
    │
    ▼
[test]  pytest (Python 3.12)
    │
    ▼ (on success)
[deploy]
    ├── Configure AWS (OIDC)
    ├── docker build & push → ECR (tagged with git SHA)
    ├── kustomize edit set image (updates kustomization.yaml)
    └── git commit & push → triggers Argo CD sync
```

### Frontend (`frontend/**` push to `main`)

```
Push to main
    │
    ▼
[front-deploy]
    ├── npm ci & build (Vite)
    ├── Configure AWS (OIDC)
    ├── aws s3 sync → S3
    └── CloudFront cache invalidation
```

## Security Highlights

| Concern | Implementation |
|---|---|
| No stored AWS credentials | GitHub Actions OIDC → IAM role assumption |
| Pod-level AWS access | IRSA (per-service-account IAM roles) |
| Secret management | AWS Secrets Manager + Kubernetes Secrets (injected as env vars) |
| ALB direct-access bypass | `X-Origin-Verify` custom header validated in FastAPI middleware |
| TLS everywhere | ACM certificates, CloudFront enforces HTTPS redirect, TLS 1.2+ minimum |
| Private database | RDS in private subnets, no public endpoint |

## Deploy Guide

### Prerequisites
- AWS CLI configured with a profile named `dev-infra-01`
- Terraform >= 1.9, kubectl, Helm 3

### Automated Setup (Recommended)

Use the setup script to provision all infrastructure in the correct order:

```bash
# 1. Copy and fill in your Terraform variables
cp terraform/envs/dev/terraform.tfvars.example terraform/envs/dev/terraform.tfvars

# 2. Run the setup script
./setup-all.sh
```

The script performs the following steps automatically:
1. Checks that all required tools are installed (`terraform`, `kubectl`, `helm`, `aws`)
2. Deploys the bootstrap layer (S3 state backend, DynamoDB lock table, Route53 hosted zone)
3. Displays the Route53 name servers and pauses — register these at your domain registrar before continuing
4. First `terraform apply`: provisions VPC, EKS, RDS, ECR, ACM, and Argo CD (excluding CloudFront)
5. Waits for Argo CD to sync and the ALB to become available (up to 10 minutes)
6. Second `terraform apply`: provisions CloudFront and the frontend S3 bucket
7. Prints the values needed for GitHub Actions Secrets and the access URLs

> **Note:** The script stops immediately on any error and displays a failure message. If it fails mid-way, check the AWS console for any partially created resources before re-running.

### Manual Setup

<details>
<summary>Click to expand manual steps</summary>

#### Step 1 — Bootstrap (S3 state backend + Route53)
```bash
cd terraform/bootstrap
terraform init && terraform apply
```

After applying, register the displayed Route53 name servers at your domain registrar.

#### Step 2 — Core Infrastructure (EKS, RDS, Argo CD)
```bash
cd terraform/envs/dev
cp terraform.tfvars.example terraform.tfvars  # fill in your values
terraform init
# First pass: deploy EKS and Argo CD before CloudFront can resolve the ALB hostname
terraform apply -target=module.vpc \
                -target=module.eks \
                -target=module.rds \
                -target=module.ecr \
                -target=helm_release.argocd \
                -target=kubernetes_manifest.argocd_app
# Wait for Argo CD to sync and create the ALB (check: kubectl get ingress -n dev)
# Second pass: deploy CloudFront with the resolved ALB hostname
terraform apply
```

</details>

### Step 3 — CI/CD Secrets (GitHub Actions)

Set the following repository secrets in GitHub:

| Secret | Description |
|---|---|
| `AWS_ROLE_ARN` | IAM role ARN output from `terraform output github_actions_role_arn` |
| `ECR_REPOSITORY` | ECR repository name |
| `S3_BUCKET_NAME` | Frontend S3 bucket name |
| `CLOUDFRONT_DISTRIBUTION_ID` | CloudFront distribution ID for the frontend |
| `VITE_API_URL` | Backend API URL (e.g. `https://api.example.com`) |

When using `setup-all.sh`, most of these values are printed automatically at the end of the script.

Push to `main` to trigger the pipeline.

## Teardown

```bash
./destroy-all.sh
```

The script performs teardown in the correct order to avoid dependency errors:
1. Deletes all Argo CD Applications (triggers ALB deletion via the Load Balancer Controller)
2. Waits for the ALB to be fully removed from AWS
3. Runs `terraform destroy` on the main infrastructure (`envs/dev`)
4. Runs `terraform destroy` on the bootstrap layer

> **Note:** The script stops immediately on any error and displays a failure message, so a successful "🎉 All resources have been successfully deleted." message confirms full teardown.
>
> **If the script fails mid-way** (some resources deleted, some remaining), simply re-run `./destroy-all.sh`. Terraform reads the state file to determine what still exists and will only attempt to destroy the remaining resources — it is safe to re-run.

---

**Author:** Takayuki Kotani ([GitHub](https://github.com/kamotaka-0426))
