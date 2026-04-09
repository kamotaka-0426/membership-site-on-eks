# Production-Ready EKS Membership Blog Infrastructure

AWS EKS (Kubernetes) 上に構築された、セキュアでスケーラブルな会員制ブログシステムのフルスタック・インフラストラクチャです。
インフラの全レイヤーを Terraform で管理し、Argo CD による GitOps 運用を実現しています。

## 🏗 アーキテクチャ (Architecture)

- **Frontend**: React (Vite) + S3 + CloudFront (OACによるセキュアな配信)
- **Backend**: FastAPI (Python 3.12) on EKS (Managed Node Groups)
- **Database**: Amazon RDS for PostgreSQL (Private Subnet)
- **Networking**: 
  - VPC (Public/Private Subnets)
  - Application Load Balancer (AWS Load Balancer Controller)
  - CloudFront + ALB (カスタムヘッダーによるオリジン保護)
- **Security**: 
  - IAM Roles for Service Accounts (IRSA) による最小権限原則
  - ACM による SSL/TLS 暗号化
  - AWS Secrets Manager による秘匿情報管理
- **GitOps**: Argo CD による継続的デリバリー

## ✨ 注目ポイント (Key Features)

1. **完全な IaC (Infrastructure as Code)**:
   VPCからEKSクラスター、アプリケーションのK8sリソース（Ingress, ConfigMap等）まで、すべて Terraform で一元管理されています。
2. **Argo CD を活用した GitOps**:
   マニフェストの変更を検知して自動デプロイ。インフラとアプリのライフサイクルを分離しつつ、整合性を維持します。
3. **セキュアなバックエンド通信**:
   ALBへの直接アクセスを遮断し、CloudFrontからの特定ヘッダーを持つリクエストのみを許可する構成を実装しています。
4. **堅牢な Docker イメージ**:
   マルチステージビルドと Python 仮想環境 (venv) の活用により、バイナリ依存関係を解決した軽量で安全なイメージを作成しています。

## 🚀 デプロイガイド

詳細な手順は [GEMINI.md](./GEMINI.md) を参照してください。

### クイックスタート
1. **Bootstrap**: `terraform/bootstrap` で S3/Route53 を作成
2. **Infrastructure**: `terraform/envs/dev` で EKS/RDS/Argo CD を構築
3. **CI/CD**: GitHub Actions Secrets を設定してコードを push

## 🧹 クリーンアップ
`destroy-all.sh` スクリプトを実行することで、ALB の削除待機を含めた全リソースの安全な一括削除が可能です。

---
**Author:** kamotaka-0426
