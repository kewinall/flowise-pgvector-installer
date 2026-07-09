# Changelog

## 1.0.4 - GitHub-ready project layout

- Added GitHub Actions CI workflow for Bash syntax, ShellCheck, Docker Compose config, YAML parse, and secret checks.
- Added tag-based release workflow to package tar.gz, zip, and SHA-256 checksum files.
- Added `.env.example`, `.gitattributes`, `.editorconfig`, MIT license, and GitHub documentation.
- Kept 1.0.3 runtime behavior that resolved stale exported environment variable issues.


## 1.0.3

- 修正 `install.sh --reset-rebuild` 在同一個 shell 曾經 `source .env` 後，Docker Compose 可能讀到舊的 exported DB 密碼，造成 Flowise 啟動時出現 `password authentication failed for user "flowise_app"`。
- 在 Compose 操作前重新載入目前 `/opt/flowise-pgvector/.env`，避免 shell 環境變數覆蓋 `--env-file`。
- 加強 reset cleanup，額外清理舊版可能留下的 Flowise/PostgreSQL volume 名稱。

## 1.0.2 - 2026-07-09

- 新增 `sudo flowise-ctl reset-rebuild`，可在測試環境將 Flowise、PostgreSQL、pgvector 的容器、Volume、`.env` 全部刪除後重新建立空白環境。
- `reset-rebuild` 會重新產生 PostgreSQL 密碼、JWT、Session、Token Hash 與 Flowise Credential 加密金鑰。
- 新增 `install.sh --reset-rebuild`，可直接由新版安裝包執行「刪除既有環境並重裝」。
- 新增選項 `--yes`、`--purge-backups`、`--remove-images`，支援測試環境自動化重建。

## 1.0.1 - 2026-07-09

- 修正首次啟動時 PostgreSQL 初始化時間較長，導致 `docker compose up` 因 Flowise dependency 提前失敗的問題。
- 新增 `scripts/reconcile-db.sh` 與 `sudo flowise-ctl reconcile-db`，可同步目前 `.env` 內的 DB 密碼、role、database 與 pgvector extension。
- 安裝流程改為先啟動 PostgreSQL、同步 DB 設定，再啟動 Flowise，避免 Flowise 使用錯誤或舊密碼反覆 Restarting。

## 1.0.0 - 2026-07-08

- Rocky Linux 9 一鍵安裝 Docker Engine、Flowise、PostgreSQL 17 與 pgvector。
- 分離 `flowise` 與 `flowise_vector` 資料庫及應用帳號。
- 自動產生資料庫密碼、JWT、Session 與 Credential 加密金鑰。
- 提供健康檢查、備份、還原、Flowise 升級和保留資料解除安裝。
