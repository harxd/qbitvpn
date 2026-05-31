Summary Checklist
| Step | Command | Purpose |
|------|---------|---------|
| Build | `docker build -t name .` | Creates the image locally. |
| Tag | `docker tag name user/repo:tag` | Prepares the image for a specific repository. |
| Login | `docker login` | Authenticates your session. |
| Push | `docker push user/repo:tag` | Uploads the image to the cloud. |
| Compose Build | `docker compose build` | Builds the image using docker-compose.yml. |
| Compose Push | `docker compose push` | Pushes the built image to the docker repository. |