# Flowise + PostgreSQL + pgvector 一鍵安裝包

在 Rocky Linux 9 上透過 Docker Compose 部署 Flowise，並使用 PostgreSQL + pgvector 作為 Flowise 系統資料庫與後續 RAG 向量資料庫。

## 架構

```text
Rocky Linux 9
└── Docker Compose
    ├── Flowise
    │   ├── Port 3000
    │   └── /root/.flowise volume
    └── PostgreSQL 17 + pgvector
        ├── Database: flowise
        └── Database: flowise_vector
```

預設版本：

| 元件 | 版本 |
|---|---|
| Flowise | `3.1.3` |
| pgvector image | `0.8.4-pg17-bookworm` |
| PostgreSQL | 17 |

## 快速安裝

```bash
tar -xzf flowise-pgvector-installer-1.0.4.tar.gz
cd flowise-pgvector-installer-1.0.4
sudo bash install.sh
```

安裝完成後開啟：

```text
http://RockyLinux-IP:3000
```

首次登入時依 Flowise 畫面建立管理員帳號。

## 測試環境全部刪除重建

```bash
sudo flowise-ctl reset-rebuild --yes --purge-backups
```

或從安裝包直接重建：

```bash
sudo bash install.sh --reset-rebuild --yes --purge-backups
```

## 常用管理指令

```bash
sudo flowise-ctl status
sudo flowise-ctl verify
sudo flowise-ctl logs flowise
sudo flowise-ctl logs postgres
sudo flowise-ctl backup
sudo flowise-ctl vector-info
```

## Flowise 內 pgvector Credential

在 Flowise 建立 Postgres Vector Store credential 時使用：

| 欄位 | 值 |
|---|---|
| Host | `postgres` |
| Port | `5432` |
| Database | `flowise_vector` |
| User | `flowise_vector` |
| Password | `sudo flowise-ctl secret VECTOR_DB_PASSWORD` |
| SSL | `false` |

PostgreSQL `5432` 預設不對主機或外部網路開放，只提供 Flowise 容器內部連線。

## GitHub CI/CD

本專案已內建 GitHub Actions：

- `.github/workflows/ci.yml`：PR / push 靜態驗證
- `.github/workflows/release.yml`：推送 `v*` tag 後產生 release package

CI 只做語法、ShellCheck、Compose config 與 secret 檢查，不會在 GitHub Runner 真正啟動 Flowise/PostgreSQL，因此上傳後較不容易因 Docker pull 或服務啟動 timeout 失敗。

更多說明請看：

- [GitHub 上傳與 CI/CD 建議](docs/GITHUB.md)
- [疑難排解](docs/TROUBLESHOOTING.md)
- [離線環境建議](docs/OFFLINE.md)

## 安全注意事項

不要提交以下檔案：

- `.env`
- `backups/`
- `*.dump`
- `*.sql`
- release 壓縮檔

`.env.example` 與 `env.template` 只保留 `CHANGE_ME` placeholder，可安全放到 GitHub。

## License

MIT
