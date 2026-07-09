# 離線環境建議

目前此專案主流程是線上安裝，會從 Docker 官方 repository 安裝 Docker，並從 Docker Hub 拉取：

- `flowiseai/flowise`
- `pgvector/pgvector`

若要離線部署，建議在線上機器先準備：

```bash
docker pull flowiseai/flowise:3.1.3
docker pull pgvector/pgvector:0.8.4-pg17-bookworm
mkdir -p offline-images
docker save flowiseai/flowise:3.1.3 | gzip > offline-images/flowise-3.1.3.tar.gz
docker save pgvector/pgvector:0.8.4-pg17-bookworm | gzip > offline-images/pgvector-0.8.4-pg17-bookworm.tar.gz
```

離線機器匯入：

```bash
gunzip -c offline-images/flowise-3.1.3.tar.gz | docker load
gunzip -c offline-images/pgvector-0.8.4-pg17-bookworm.tar.gz | docker load
sudo bash install.sh --skip-docker-install
```

Docker Engine 與 RPM 依賴套件的完整離線包會依環境 repository 狀態不同，建議另行製作 OS 對應的 RPM repository mirror。
