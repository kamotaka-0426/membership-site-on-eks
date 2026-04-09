# Membership Blog on EKS - Project Summary & Operations Guide

このプロジェクトは、AWS EKS上で動作する会員制ブログシステムを、Terraformによるインフラ管理とArgo CDによるGitOps（運用自動化）を組み合わせて構築したものです。

## 1. システム構成図 (Architecture)
- **Frontend**: React (Vite) + S3 + CloudFront
- **Backend**: FastAPI (Python 3.12) + EKS (Fargate/NodeGroup)
- **Database**: Amazon RDS (PostgreSQL)
- **Networking**: VPC (Public/Private), ALB (AWS Load Balancer Controller), Route53, ACM
- **CI/CD & GitOps**: GitHub Actions (Build/Push), Argo CD (Continuous Delivery)

## 2. 構築時の主要なトラブルシューティングと解決策

### A. Argo CD のプライベートリポジトリ認証
- **課題**: `rpc error: code = Unknown desc = authentication required` が発生。
- **解決**: GitHubのPersonal Access Token (PAT) を作成し、KubernetesのSecretとして `argocd` ネームスペースに登録。さらに `argocd.argoproj.io/secret-type=repository` ラベルを付与。

### B. AWS Load Balancer Controller のサブネット自動検出
- **課題**: Ingressを作成しても `ADDRESS` が割り当てられない。
- **原因**: サブネットに特定のタグがなかったため、コントローラーがALBを作成する場所を特定できなかった。
- **解決**: 
  - パブリックサブネットに `"kubernetes.io/role/elb" = "1"` を追加。
  - プライベートサブネットに `"kubernetes.io/role/internal-elb" = "1"` を追加。

### C. Python 実行環境のエラー (ModuleNotFoundError)
- **課題**: コンテナ起動時に `ModuleNotFoundError: No module named 'app'` や `pydantic_core` のエラーが発生。
- **解決**: 
  - Dockerfileを `venv`（仮想環境）ごとコピーする方式に刷新。
  - ソースコードを `/app/app` に配置し、`python3 -m app.main` でモジュールとして実行するよう修正。

### D. Pydantic Settings の環境変数パースエラー
- **課題**: `ALLOWED_ORIGINS` の読み込みで `JSONDecodeError` が発生。
- **解決**: `app/core/config.py` に `field_validator` を導入し、JSONリスト形式とカンマ区切り文字列の両方を柔軟に解釈できるように修正。

### E. データベース名の不一致
- **課題**: RDS接続時に `FATAL: database "membership_db_dev" does not exist` が発生。
- **解決**: RDSモジュールで定義された `membership_db` とマニフェスト側の `DB_NAME` を一致させた。

## 3. 運用・デプロイ手順

### インフラの更新 (Terraform)
1. `terraform/envs/dev` へ移動。
2. 変更を加え、`terraform apply --auto-approve` を実行。
   ※ Argo CDのCRD依存により、初回は `-target=helm_release.argocd` が必要な場合があります。

### アプリケーションの更新 (GitOps)
1. `app/` 以下のコードを修正。
2. `main` ブランチに push。
3. GitHub Actions がイメージをビルドし、`k8s/overlays/dev/kustomization.yaml` のタグを自動更新。
4. Argo CD が変更を検知し、数分以内にクラスターへ反映。

### 強制同期・トラブル確認コマンド
```bash
# Argo CD の強制リフレッシュ (キャッシュクリア)
kubectl patch application membership-blog-dev -n argocd --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'

# ログの確認
kubectl logs -l app=membership-blog -n dev --tail=50

# Ingress (ALB) アドレスの確認
kubectl get ingress -n dev
```

## 4. クリーンアップ (削除手順)
**注意:** `terraform destroy` を実行する前に、必ず以下の順序を守ってください。
1. `kubectl delete application membership-blog-dev -n argocd --cascade=foreground`
2. AWSコンソールで ALB が消えたことを確認。
3. `./destroy-all.sh` スクリプトを実行（または手動で envs/dev → bootstrap の順に destroy）。

---
**Domain:** [https://kamotaka.net](https://kamotaka.net)
**API Endpoint:** [https://api.kamotaka.net/health](https://api.kamotaka.net/health)
