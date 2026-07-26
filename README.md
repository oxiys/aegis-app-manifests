# aegis-mock-app

This repository contains the live workload (a mock 3-tier application) used to demonstrate the [Aegis DevSecOps Pipeline](https://github.com/gcrbr/aegis-pipeline).

The application is a deliberately simple Todo list designed specifically to act as a target for testing Kubernetes deployments, network policies, and CI/CD security scans.

## Architecture

* **Frontend**: Vanilla JS / HTML served via Nginx
* **Backend**: Python Flask API
* **Database**: PostgreSQL

## Kubernetes Deployment

The `k8s/` directory contains all the manifests required to deploy the application in a Kubernetes cluster. They are logically numbered for sequential deployment.

If you are applying them manually instead of relying on **Argo CD**:

```bash
kubectl apply -f k8s/
```