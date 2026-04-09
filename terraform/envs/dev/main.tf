# ---------------------------------------------
# Terraform configuration
# ---------------------------------------------
terraform {
  required_version = ">=0.13"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.15"
    }
  }
  backend "s3" {
    bucket         = "membership-site-on-eks-tfstate-c2e21569"
    key            = "dev/terraform.tfstate"
    region         = "ap-northeast-1"
    dynamodb_table = "terraform-state-locking"
    encrypt        = true
    profile        = "dev-infra-01"
  }
}

# ---------------------------------------------
# Providers
# ---------------------------------------------
provider "aws" {
  region  = "ap-northeast-1"
  profile = "dev-infra-01"
}

provider "aws" {
  alias   = "us_east_1"
  region  = "us-east-1"
  profile = "dev-infra-01"
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    args        = ["eks", "get-token", "--cluster-name", "membership-blog-cluster", "--profile", "dev-infra-01"]
    command     = "aws"
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      args        = ["eks", "get-token", "--cluster-name", "membership-blog-cluster", "--profile", "dev-infra-01"]
      command     = "aws"
    }
  }
}

# ---------------------------------------------
# Module calls
# ---------------------------------------------
module "vpc" {
  source = "../../modules/vpc"
}

module "ecr" {
  source = "../../modules/ecr"
}

module "iam_oidc" {
  source      = "../../modules/iam_oidc"
  github_repo = var.github_repo
}

module "rds" {
  source             = "../../modules/rds"
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
}

module "eks" {
  source                  = "../../modules/eks"
  vpc_id                  = module.vpc.vpc_id
  private_subnet_ids      = module.vpc.private_subnet_ids
  public_subnet_ids       = module.vpc.public_subnet_ids
  eks_nodes_sg_id         = module.vpc.eks_nodes_sg_id
  github_actions_role_arn = module.iam_oidc.github_actions_role_arn
}

data "terraform_remote_state" "bootstrap" {
  backend = "local"
  config = {
    path = "../../bootstrap/terraform.tfstate"
  }
}

locals {
  domain_name     = data.terraform_remote_state.bootstrap.outputs.domain_name
  route53_zone_id = data.terraform_remote_state.bootstrap.outputs.route53_zone_id
}

module "frontend" {
  source          = "../../modules/frontend"
  bucket_name     = var.frontend_bucket_name
  domain_name     = local.domain_name
  route53_zone_id = local.route53_zone_id

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }
}

module "acm_ingress" {
  source          = "../../modules/acm"
  domain_name     = local.domain_name
  route53_zone_id = local.route53_zone_id
}

module "cloudfront" {
  source               = "../../modules/cloudfront"
  origin_verify_secret = random_uuid.origin_verify_secret.result
  origin_domain_name   = "k8s-dev-membersh-7bdcd6eb81-2055686610.ap-northeast-1.elb.amazonaws.com"
  domain_name          = "api.${local.domain_name}"
  route53_zone_id      = local.route53_zone_id

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }
}

resource "random_uuid" "origin_verify_secret" {}

resource "random_password" "jwt_secret" {
  length  = 64
  special = false
}

resource "random_id" "jwt_secret_suffix" {
  byte_length = 4
}

resource "aws_secretsmanager_secret" "jwt_secret" {
  name                    = "membership-blog-eks-jwt-secret-${random_id.jwt_secret_suffix.hex}"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "jwt_secret" {
  secret_id     = aws_secretsmanager_secret.jwt_secret.id
  secret_string = random_password.jwt_secret.result
}

resource "kubernetes_namespace_v1" "dev" {
  metadata {
    name = "dev"
  }
}

resource "kubernetes_secret_v1" "app_secrets" {
  metadata {
    name      = "membership-blog-app-secrets"
    namespace = kubernetes_namespace_v1.dev.metadata[0].name
  }

  data = {
    db_password           = module.rds.db_password_raw
    db_host               = module.rds.db_instance_endpoint
    jwt_secret            = random_password.jwt_secret.result
    origin_verify_secret  = random_uuid.origin_verify_secret.result
    allowed_origins       = "https://${local.domain_name}"
  }

  type = "Opaque"
}

# ---------------------------------------------
# Argo CD Installation & Application
# ---------------------------------------------
resource "kubernetes_namespace_v1" "argocd" {
  metadata {
    name = "argocd"
  }
}

resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  namespace  = kubernetes_namespace_v1.argocd.metadata[0].name
  version    = "7.3.11"

  set {
    name  = "server.service.type"
    value = "LoadBalancer"
  }
}

resource "kubernetes_manifest" "argocd_app" {
  depends_on = [helm_release.argocd]
  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "membership-blog-dev"
      namespace = "argocd"
    }
    spec = {
      project = "default"
      source = {
        repoURL        = "https://github.com/${var.github_repo}.git"
        targetRevision = "HEAD"
        path           = "k8s/overlays/dev"
        # ハードコードを排除し、証明書 ARN を動的に注入
        kustomize = {
          commonAnnotations = {
            "alb.ingress.kubernetes.io/certificate-arn" = module.acm_ingress.certificate_arn
          }
        }
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = kubernetes_namespace_v1.dev.metadata[0].name
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
        syncOptions = ["CreateNamespace=true"]
      }
    }
  }
}

# ---------------------------------------------
# 11. AWS Load Balancer Controller
# ---------------------------------------------
module "lb_controller_role" {
  source    = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version   = "~> 5.0"
  role_name = "aws-load-balancer-controller"

  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}

resource "helm_release" "aws_lb_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "1.8.1"

  set {
    name  = "clusterName"
    value = module.eks.cluster_name
  }

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.lb_controller_role.iam_role_arn
  }
}

# ---------------------------------------------
# Outputs
# ---------------------------------------------
output "github_actions_role_arn" {
  value = module.iam_oidc.github_actions_role_arn
}

output "ecr_repository_url" {
  value = module.ecr.repository_url
}

output "frontend_url" {
  value = "https://${local.domain_name}"
}

output "api_url" {
  value = "https://api.${local.domain_name}"
}

output "temporary_db_password" {
  value     = module.rds.db_password_raw
  sensitive = true
}
