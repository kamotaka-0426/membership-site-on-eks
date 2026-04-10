# Membership Blog on EKS

AWS EKS (Kubernetes) 上に構築した、本番環境対応の会員制ブログシステムです。
インフラ全体を Terraform で管理し、Argo CD による GitOps で継続的デリバリーを実現しています。

## アーキテクチャ

```
ユーザー
  │
  ▼
CloudFront (HTTPS, CDN)
  ├── /          → S3 (React フロントエンド、OAC 保護)
  └── /api/*     → ALB (カスタムヘッダー検証)
                      │
                      ▼
                EKS Managed Node Group (t3.small × 2)
                  └── FastAPI Pod (replicas: 2)
                          │
                          ▼
                    RDS PostgreSQL (プライベートサブネット)
```

| レイヤー | 技術スタック |
|---|---|
| フロントエンド | React (Vite) + S3 + CloudFront (OAC) |
| バックエンド | FastAPI (Python 3.12) on EKS Managed Node Groups |
| データベース | Amazon RDS for PostgreSQL (プライベートサブネット) |
| ネットワーク | VPC, ALB (AWS Load Balancer Controller), Route53, ACM |
| セキュリティ | IRSA, ACM (TLS 1.2+), AWS Secrets Manager, カスタムオリジンヘッダー |
| GitOps | Argo CD (自動同期 + 自己修復) |
| IaC | Terraform (完全モジュール化) |
| CI/CD | GitHub Actions (OIDC — AWS 認証情報の保存なし) |

## 設計上の主要な決定事項

**1. 完全な Infrastructure as Code**
VPC から EKS クラスター、Kubernetes マニフェスト (Ingress, ConfigMap) まで、すべてを Terraform で管理しています。AWS コンソールでの手動操作は一切不要です。

**2. Argo CD による GitOps**
GitHub Actions がコンテナイメージをビルド・プッシュし、`k8s/overlays/dev/kustomization.yaml` に新しいイメージタグをコミットします。Argo CD がマニフェストの変更を検知し、自動的にクラスターへデプロイします。Git が唯一の信頼できるソースです。

**3. オリジン保護**
ALB への直接アクセスはブロックされています。CloudFront はすべてのリクエストに `X-Origin-Verify` ヘッダーとしてランダムなシークレットを付与します。FastAPI ミドルウェアはこのヘッダーが欠けたリクエストを拒否し (`/health` を除く)、CloudFront のバイパスを防止します。

**4. キーレス AWS 認証**
GitHub Actions は OIDC フェデレーションを通じて IAM ロールを引き受けます。長期間有効な AWS アクセスキーをシークレットとして保存する必要はありません。IAM ロールは特定の GitHub リポジトリのみにスコープされています。

**5. IRSA による最小権限 IAM**
Kubernetes Pod は、ノードレベルのインスタンスプロファイルではなく、IRSA (IAM Roles for Service Accounts) を通じて AWS サービス (Secrets Manager, ECR) にアクセスします。

**6. 軽量で再現性の高い Docker イメージ**
マルチステージビルドにより、ビルド環境 (`build-essential` を含む) とランタイムイメージを分離しています。Python 仮想環境 (`venv`) をステージ間でコピーすることで、小さくセキュアな最終イメージを生成します。

## リポジトリ構成

```
.
├── terraform/
│   ├── bootstrap/          # S3 バックエンド、Route53 ホストゾーン
│   ├── envs/dev/           # 環境エントリーポイント (main.tf, variables.tf)
│   └── modules/            # 再利用可能なモジュール
│       ├── vpc/            # VPC、サブネット、セキュリティグループ
│       ├── eks/            # EKS クラスター、ノードグループ、IRSA OIDC プロバイダー
│       ├── rds/            # RDS PostgreSQL
│       ├── ecr/            # ECR リポジトリ
│       ├── acm/            # ACM 証明書
│       ├── cloudfront/     # CloudFront ディストリビューション
│       ├── frontend/       # React 用 S3 バケット + CloudFront OAC
│       └── iam_oidc/       # GitHub Actions OIDC IAM ロール
├── k8s/
│   ├── base/               # Deployment, Service, Ingress (環境非依存)
│   └── overlays/
│       └── dev/            # Kustomize パッチ: レプリカ数、イメージタグ、ConfigMap
├── app/                    # FastAPI バックエンド (Python 3.12)
│   ├── routers/            # 認証、投稿
│   ├── services/           # ビジネスロジック
│   ├── core/config.py      # 設定 (pydantic-settings)
│   ├── Dockerfile          # マルチステージビルド
│   └── tests/              # pytest テストスイート
├── frontend/               # React (Vite) フロントエンド
├── argocd/                 # Argo CD Application マニフェスト
├── .github/workflows/
│   ├── infra-deploy.yml    # テスト → ビルド → ECR プッシュ → マニフェスト更新 → Argo CD 同期
│   └── frontend-deploy.yml # ビルド → S3 同期 → CloudFront キャッシュ無効化
├── setup-all.sh            # 環境構築スクリプト
└── destroy-all.sh          # 環境削除スクリプト
```

## CI/CD パイプライン

### バックエンド (`app/**` を `main` へプッシュ)

```
main へプッシュ
    │
    ▼
[test]  pytest (Python 3.12)
    │
    ▼ (成功時)
[deploy]
    ├── AWS 認証 (OIDC)
    ├── docker build & push → ECR (git SHA でタグ付け)
    ├── kustomize edit set image (kustomization.yaml を更新)
    └── git commit & push → Argo CD 同期をトリガー
```

### フロントエンド (`frontend/**` を `main` へプッシュ)

```
main へプッシュ
    │
    ▼
[front-deploy]
    ├── npm ci & build (Vite)
    ├── AWS 認証 (OIDC)
    ├── aws s3 sync → S3
    └── CloudFront キャッシュ無効化
```

## セキュリティの特徴

| 課題 | 実装 |
|---|---|
| AWS 認証情報の保存なし | GitHub Actions OIDC → IAM ロール引き受け |
| Pod レベルの AWS アクセス | IRSA (サービスアカウントごとの IAM ロール) |
| シークレット管理 | AWS Secrets Manager + Kubernetes Secrets (環境変数として注入) |
| ALB への直接アクセスバイパス | FastAPI ミドルウェアで `X-Origin-Verify` カスタムヘッダーを検証 |
| TLS の徹底 | ACM 証明書、CloudFront による HTTPS リダイレクト強制、TLS 1.2 以上 |
| プライベートデータベース | RDS はプライベートサブネット内、パブリックエンドポイントなし |

## デプロイガイド

### 前提条件
- `dev-infra-01` という名前のプロファイルで設定された AWS CLI
- Terraform >= 1.9、kubectl、Helm 3

### 自動セットアップ（推奨）

セットアップスクリプトを使用して、正しい順序でインフラ全体を構築します。

```bash
# 1. Terraform 変数ファイルをコピーして値を記入
cp terraform/envs/dev/terraform.tfvars.example terraform/envs/dev/terraform.tfvars

# 2. セットアップスクリプトを実行
./setup-all.sh
```

スクリプトは以下のステップを自動で実行します：
1. 必要なツール (`terraform`、`kubectl`、`helm`、`aws`) のインストール確認
2. Bootstrap 層のデプロイ (S3 ステートバックエンド、DynamoDB ロックテーブル、Route53 ホストゾーン)
3. Route53 のネームサーバーを表示して一時停止 — 続行前にドメインレジストラへ登録してください
4. 1回目の `terraform apply`: VPC、EKS、RDS、ECR、ACM、Argo CD を構築 (CloudFront 除く)
5. Argo CD の同期と ALB の起動を待機 (最大10分)
6. 2回目の `terraform apply`: CloudFront とフロントエンド S3 バケットを構築
7. GitHub Actions Secrets に必要な値とアクセス URL を表示

> **注意:** スクリプトはエラー発生時に即座に停止し、失敗メッセージを表示します。途中で失敗した場合は、AWS コンソールで作成済みリソースを確認してから再実行してください。

### 手動セットアップ

<details>
<summary>手動手順を展開する</summary>

#### Step 1 — Bootstrap (S3 ステートバックエンド + Route53)
```bash
cd terraform/bootstrap
terraform init && terraform apply
```

apply 後、表示された Route53 のネームサーバーをドメインレジストラに登録してください。

#### Step 2 — コアインフラ (EKS, RDS, Argo CD)
```bash
cd terraform/envs/dev
cp terraform.tfvars.example terraform.tfvars  # 値を記入
terraform init
# 1回目: CloudFront が ALB ホスト名を解決できるようになる前に EKS と Argo CD をデプロイ
terraform apply -target=module.vpc \
                -target=module.eks \
                -target=module.rds \
                -target=module.ecr \
                -target=helm_release.argocd \
                -target=kubernetes_manifest.argocd_app
# Argo CD の同期と ALB の作成を待機 (確認: kubectl get ingress -n dev)
# 2回目: 解決された ALB ホスト名で CloudFront をデプロイ
terraform apply
```

</details>

### Step 3 — CI/CD シークレット (GitHub Actions)

GitHub リポジトリに以下のシークレットを設定してください：

| シークレット | 説明 |
|---|---|
| `AWS_ROLE_ARN` | `terraform output github_actions_role_arn` で取得した IAM ロール ARN |
| `ECR_REPOSITORY` | ECR リポジトリ名 |
| `S3_BUCKET_NAME` | フロントエンド用 S3 バケット名 |
| `CLOUDFRONT_DISTRIBUTION_ID` | フロントエンド用 CloudFront ディストリビューション ID |
| `VITE_API_URL` | バックエンド API の URL (例: `https://api.example.com`) |

`setup-all.sh` を使用した場合、スクリプト終了時にこれらの値の多くが自動的に表示されます。

`main` ブランチへプッシュするとパイプラインが起動します。

## 環境削除

```bash
./destroy-all.sh
```

スクリプトは依存関係のエラーを避けるため、正しい順序で削除を実行します：
1. すべての Argo CD Application を削除 (Load Balancer Controller 経由で ALB の削除をトリガー)
2. AWS から ALB が完全に削除されるまで待機
3. メインインフラ (`envs/dev`) の `terraform destroy` を実行
4. Bootstrap 層の `terraform destroy` を実行

> **注意:** スクリプトはエラー発生時に即座に停止し、失敗メッセージを表示します。「🎉 All resources have been successfully deleted.」が表示されれば、削除が完全に完了したことを意味します。

---

**Author:** Takayuki Kotani ([GitHub](https://github.com/kamotaka-0426))
