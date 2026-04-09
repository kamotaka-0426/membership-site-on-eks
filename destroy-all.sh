#!/bin/bash

# --- 設定 ---
ARGOCD_NS="argocd"
# スクリプトの場所を基準に相対パスで設定
PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
DEV_DIR="$PROJECT_ROOT/terraform/envs/dev"
BOOTSTRAP_DIR="$PROJECT_ROOT/terraform/bootstrap"

echo "⚠️  警告: このスクリプトは全てのインフラを削除します。復元はできません。"
echo "5秒後に開始します... (中止する場合は Ctrl+C)"
sleep 5

# --- [STEP 1] ArgoCD 管理リソースのクリーンアップ ---
echo "=== [1/3] ArgoCD Application の削除と確認 ==="
kubectl delete application --all -n $ARGOCD_NS --cascade=foreground --timeout=60s 2>/dev/null

# 削除完了の判定ループ
MAX_RETRIES=18 # 3分間待機
RETRY_COUNT=0
while : ; do
    STILL_EXISTS=$(kubectl get applications -n $ARGOCD_NS -o name 2>/dev/null)
    if [ -z "$STILL_EXISTS" ]; then
        echo "✅ ArgoCD Application はすべて削除されました。"
        break
    fi

    if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
        echo "⚠️  タイムアウト: ファイナライザーを強制解除して削除を強行します。"
        kubectl get applications -n $ARGOCD_NS -o name | xargs -I {} kubectl patch {} -n $ARGOCD_NS -p '{"metadata":{"finalizers":null}}' --type merge 2>/dev/null
        break
    fi

    echo "待機中... 残存リソース: $(echo $STILL_EXISTS | wc -w) 件"
    RETRY_COUNT=$((RETRY_COUNT + 1))
    sleep 10
done

# --- [NEW] AWS ALB の削除完了を待機 ---
echo "=== AWS Load Balancer (ALB) の削除反映を待っています... ==="
while : ; do
    # 'membership-blog' を含む名前のロードバランサーを検索
    ALB_ARN=$(aws elbv2 describe-load-balancers --query "LoadBalancers[?contains(LoadBalancerName, 'membership-blog')].LoadBalancerArn" --output text --region ap-northeast-1 --profile dev-infra-01 2>/dev/null)
    
    if [ -z "$ALB_ARN" ]; then
        echo "✅ AWS Load Balancer は完全に削除されました。"
        break
    fi
    
    echo "待機中... ロードバランサーがまだ存在します: $ALB_ARN"
    sleep 20
done

# --- [STEP 2] メインインフラ (envs/dev) の削除 ---
echo "=== [2/3] メインインフラ (envs/dev) を削除中... ==="
if [ -d "$DEV_DIR" ]; then
    cd "$DEV_DIR" || exit 1
    # 削除を確実にするため一度 init
    terraform init -input=false > /dev/null
    terraform destroy -auto-approve
else
    echo "❌ エラー: $DEV_DIR が見つかりません。"
fi

# --- [STEP 3] 土台 (Bootstrap) の削除 ---
echo "=== [3/3] Bootstrap層 (S3/DynamoDB) を削除中... ==="
if [ -d "$BOOTSTRAP_DIR" ]; then
    cd "$BOOTSTRAP_DIR" || exit 1
    terraform destroy -auto-approve
else
    echo "❌ エラー: $BOOTSTRAP_DIR が見つかりません。"
fi

echo "=========================================="
echo "🎉 すべての削除プロセスが完了しました。"
echo "=========================================="
