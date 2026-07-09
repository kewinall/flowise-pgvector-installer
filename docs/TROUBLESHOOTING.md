# 疑難排解

## Flowise 一直 Restarting

先看 Flowise log：

```bash
sudo flowise-ctl logs flowise
```

若看到：

```text
password authentication failed for user "flowise_app"
```

請執行：

```bash
sudo flowise-ctl reconcile-db
sudo docker rm -f flowise
sudo flowise-ctl start
```

## PostgreSQL healthy，但 Flowise 無法連線

確認 Compose 狀態：

```bash
sudo flowise-ctl status
```

測試 Flowise DB 帳密：

```bash
cd /opt/flowise-pgvector
set -a
source .env
set +a
sudo docker compose --env-file .env -f compose.yaml exec -T \
  -e PGPASSWORD="$FLOWISE_DB_PASSWORD" postgres \
  psql -h 127.0.0.1 -U "$FLOWISE_DB_USER" -d "$FLOWISE_DB_NAME" \
  -c "SELECT current_database(), current_user;"
```

## 測試環境全部重建

```bash
sudo flowise-ctl reset-rebuild --yes --purge-backups
```

此操作會刪除 Flowise 帳號、流程、Credential、上傳檔案與 pgvector 資料。
