# aegis-app-manifests

Deployment configuration for the mock application used by the
[Aegis DevSecOps Pipeline](https://github.com/oxiys/aegis-pipeline).

| Repository | Responsibility |
| --- | --- |
| [aegis-app-manifests](https://github.com/oxiys/aegis-app-manifests) | Kubernetes manifests, PostgreSQL deployment, RBAC, Cilium/OPA policies and Compose orchestration |
| [aegis-backend](https://github.com/oxiys/aegis-backend) | Flask API, Dockerfile, dependencies and backend image CI |
| [aegis-frontend](https://github.com/oxiys/aegis-frontend) | HTML/JavaScript UI, Nginx configuration, Dockerfile and frontend image CI |

## Kubernetes and GitOps

All Kubernetes resources stay in `k8s/`, including frontend, backend and database
deployments/services, namespace, service accounts, RBAC, configuration, database
secret, storage, Cilium policies and OPA/Gatekeeper policies.

An existing Argo CD Application targeting this repository, revision `main` and
path `k8s` keeps the same source configuration. No resource names, image references,
sync waves, ports or policies are changed by the migration. Cilium and Gatekeeper
must already be installed for their custom resources.

For manual application:

```bash
kubectl apply -f k8s/
```

The database secret contains the existing mock application's example credentials.

## Local development across three repositories

Clone all three repositories into the same parent directory:

```bash
git clone https://github.com/oxiys/aegis-app-manifests.git
git clone https://github.com/oxiys/aegis-backend.git
git clone https://github.com/oxiys/aegis-frontend.git
cd aegis-app-manifests
docker compose up --build
```

Compose builds `../aegis-backend` and `../aegis-frontend` and starts PostgreSQL.
Open http://localhost:3000. Service names remain `frontend`, `backend` and `db`.
Keep the existing Compose project name when reusing a local database volume:
`docker compose -p <previous-project-name> up --build` if the old checkout folder
had a different name. The `pgdata` volume name inside Compose is unchanged.

## Pipeline responsibilities

This repository scans secrets and Kubernetes configuration, checks the Compose
configuration, and tests the image updater. It does not build application images
or require Docker Hub credentials.

Each application repository builds and scans its own image, pushes it to the
existing Docker Hub image name, and commits its SHA tag to this repository:

| Producer | Image | Manifest |
| --- | --- | --- |
| `oxiys/aegis-backend` | `oxiys/backend:<commit-sha>` | `k8s/08-backend-deployment.yaml` |
| `oxiys/aegis-frontend` | `oxiys/frontend:<commit-sha>` | `k8s/09-frontend-deployment.yaml` |

The application workflows use a `GITOPS_TOKEN` with Contents read/write on this
repository. The token identity must be allowed to push to `main`, matching the
original direct-push deployment behavior. Branches requiring PRs need a PR-based
image update workflow before releases are enabled. Configure the secrets in each
application repository and set `RELEASE_ENABLED=true` there only after merging
the migration. See the application READMEs for the full setup.

The existing image tags are intentionally kept during migration: they already
identify published images. New tags use the respective application repository's
commit SHA after its first successful release.

To update a manifest explicitly:

```bash
python3 scripts/update_image.py backend oxiys/backend:<40-character-commit-sha>
python3 -m unittest discover -s tests -v
```

The updater validates the image name and SHA tag and changes only the matching
container's image line. It leaves formatting and all other resources intact.
