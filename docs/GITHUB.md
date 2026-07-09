# GitHub 上傳與 CI/CD 建議

## 建議 Repository 名稱

建議使用：`flowise-pgvector-installer`

## 首次上傳

```bash
git init
git branch -M main
git add .
git commit -m "Initial release"
git remote add origin https://github.com/<OWNER>/flowise-pgvector-installer.git
git push -u origin main
```

若你的 GitHub repository 啟用了「main 必須透過 Pull Request 修改」規則，請改用分支：

```bash
git checkout -b init-project
git add .
git commit -m "Initial release"
git push -u origin init-project
```

然後在 GitHub 建立 Pull Request 合併到 `main`。

## CI 設計原則

本專案的 CI 只做靜態驗證，不會在 GitHub Runner 真的啟動 Flowise 或 PostgreSQL，因此可避免：

- Docker image pull 網路不穩造成 CI 失敗
- GitHub-hosted runner 啟動資料庫逾時
- 測試流程產生 `.env` 或資料 volume
- 誤將真實密碼寫入 artifact

檢查內容包含：

- Bash 語法檢查
- ShellCheck
- Docker Compose config 驗證
- YAML 解析檢查
- `.env`、dump、備份檔與壓縮檔誤提交檢查

## 發版方式

建立 tag 即可觸發 release workflow：

```bash
git tag v1.0.4
git push origin v1.0.4
```

Release workflow 會產生：

- `flowise-pgvector-installer-1.0.4.tar.gz`
- `flowise-pgvector-installer-1.0.4.zip`
- `flowise-pgvector-installer-1.0.4-SHA256SUMS.txt`

Linux 使用者建議下載 `tar.gz`，可保留執行權限。
