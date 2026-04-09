# --- Stage 1: Build ---
FROM python:3.12-slim AS builder
WORKDIR /app

# ビルドに必要なツールをインストール（バイナリ拡張用）
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# 仮想環境の作成
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# ソースコードのコピー
COPY . /app/app

# --- Stage 2: Runtime ---
FROM python:3.12-slim
WORKDIR /app

# ビルドステージから仮想環境とソースをコピー
COPY --from=builder /opt/venv /opt/venv
COPY --from=builder /app/app /app/app

# 環境変数の設定
ENV PATH="/opt/venv/bin:$PATH"
ENV PYTHONPATH="/app"

EXPOSE 8000
# モジュール名として実行
ENTRYPOINT ["python3", "-m", "app.main"]
