# O&Si DevOps Challenge

## Overview

This project builds a Dockerized web server that serves a simple webpage and deploys it on OpenShift.

![alt text](image.png)

The application is containerized with Docker, published to Docker Hub, and deployed to Red Hat OpenShift Developer Sandbox using GitHub Actions and Helm.

The solution uses:

- Nginx to serve the webpage
- Docker to containerize the application
- Docker Hub as the container registry
- GitHub Actions for CI/CD
- Helm to deploy the application
- Red Hat OpenShift Developer Sandbox as the deployment environment

## Solution Flow

The main deployment flow is:

```text
Push to main
↓
GitHub Actions pipeline starts
↓
Docker image is built
↓
Container is smoke-tested
↓
Image is scanned with Trivy
↓
Image is pushed to Docker Hub
↓
Helm deploys/updates OpenShift deployment with new image
↓
OpenShift Route exposes the webpage
```

## Web Server and Webpage

The static web page can be found in `index.html`. It displays the required greeting and date. Nginx is used as the web server here because the application is a static webpage and does not require a backend runtime.

## Docker Image Build and Registry

The application is packaged as a Docker image so it can run consistently in different environments, including a local Docker installation and OpenShift.

The image is built from the repository root using the `Dockerfile`. Docker starts from an unprivileged Nginx Alpine image and copies the static webpage into the Nginx web root.

```dockerfile
FROM nginxinc/nginx-unprivileged:stable-alpine

COPY index.html /usr/share/nginx/html/index.html

EXPOSE 8080
```

This keeps the image minimal: it contains the Nginx runtime and the static `index.html` page only.

Before publishing the image, it can be built and tested locally:

```bash
docker build -t devops-challenge:local .
docker run --rm -p 8080:8080 devops-challenge:local
```

The webpage is then available at:

```text
http://localhost:8080
```

Docker Hub is used as the container registry. This allows the same image to be pulled by OpenShift during deployment or by anyone running the container locally.

The image repository is [here](https://hub.docker.com/repository/docker/shrushti5/devops-challenge/general), namely:

```text
shrushti5/devops-challenge
```

For a manual publish, the image is tagged with the Docker Hub repository name and pushed after authenticating with Docker Hub with your username and a personal access token:

```bash
docker login
docker build -t shrushti5/devops-challenge:latest .
docker push shrushti5/devops-challenge:latest
```

After publishing, the image can be pulled and run from Docker Hub:

```bash
docker pull shrushti5/devops-challenge:latest
docker run --rm -p 8080:8080 shrushti5/devops-challenge:latest
```

In the automated pipeline, GitHub Actions performs the same build and publish process. It logs in to Docker Hub using a Personal Access Token, builds the image, and publishes it with both a `latest` tag and a Git commit SHA tag. The SHA tag is used for the OpenShift deployment so the running version can be traced back to a specific commit.

## CI/CD Pipeline

The CI/CD pipeline is implemented with GitHub Actions.

The workflow runs on pushes to the `main` branch for deployment-relevant changes, such as:

```text
Dockerfile
.dockerignore
index.html
helm/**
.github/workflows/**
```

README-only changes are not deployed because they do not change the application image or OpenShift deployment.

The pipeline performs the following stages:

1. Checks out the repository
2. Builds a test Docker image
3. Runs the container and performs a smoke test
4. Scans the image for high and critical vulnerabilities using Trivy
5. Logs in to Docker Hub
6. Builds and pushes the image to Docker Hub
7. Logs in to OpenShift Developer Sandbox
8. Lints the Helm chart
9. Deploys the application to OpenShift using Helm
10. Verifies that the OpenShift Route is accessible

The image is pushed with two tags:

```text
latest
<git-commit-sha>
```

The OpenShift deployment uses the commit SHA tag, so the running version can be traced back to a specific Git commit.

## GitHub Actions Configuration

The workflow uses GitHub repository variables for non-sensitive values:

```text
DOCKERHUB_USERNAME
OPENSHIFT_NAMESPACE
```

The workflow uses GitHub repository secrets for sensitive values:

```text
DOCKERHUB_PAT
OPENSHIFT_SERVER
OPENSHIFT_TOKEN
```

`DOCKERHUB_PAT` is a Docker Hub Personal Access Token used to push the image.

`OPENSHIFT_SERVER` and `OPENSHIFT_TOKEN` come from the OpenShift Developer Sandbox login command.

To get the OpenShift token:

```text
OpenShift web console
→ user menu
→ Copy login command
→ Display token
```

The login command looks like:

```bash
oc login --token=<openshift-token> --server=<openshift-server-url>
```

The token and server URL are stored in GitHub Actions secrets and are not committed to the repository.

## OpenShift Deployment

The application is deployed to Red Hat OpenShift Developer Sandbox.

Deployment is managed with a Helm chart located at:

```text
helm/webserver
```

The Helm chart creates:

```text
Deployment
Service
Route
```

The Deployment runs the Nginx container.

The Service exposes the container inside the OpenShift namespace.

The Route exposes the Service externally so the webpage can be opened in a browser.

## Manual OpenShift Deployment

Log in to OpenShift:

```bash
oc login --token=<openshift-token> --server=<openshift-server-url>
```

Select or verify the namespace:

```bash
oc project <openshift-namespace>
```

Deploy with Helm:

```bash
helm upgrade --install vodafone-ziggo-demo helm/webserver \
  --namespace <openshift-namespace> \
  --set image.repository=shrushti5/devops-challenge \
  --set image.tag=latest \
  --rollback-on-failure \
  --timeout=60s
```

Check the deployed resources:

```bash
oc get deployment,svc,route,pods -n <openshift-namespace>
```

Get the route:

```bash
oc get route vodafone-ziggo-demo -n <openshift-namespace> -o jsonpath='{.spec.host}'
```
Open the route URL in a browser and verify that the webpage is accessible.

## Helm Deployment and Rollback

Helm is used to manage the OpenShift resources as one release.

This provides:

- A single install/upgrade command
- Release history
- Easier rollback
- Configurable image repository and tag
- A cleaner deployment model than manually applying separate YAML files

The pipeline uses:

```bash
helm upgrade --install
```

with:

```bash
--rollback-on-failure
```

If a new deployment fails, Helm rolls back to the previous successful release. The GitHub Actions job still fails in that case because the new version was not deployed successfully.

Useful Helm commands:

```bash
helm list -n <openshift-namespace>
helm history vodafone-ziggo-demo -n <openshift-namespace>
helm rollback vodafone-ziggo-demo <revision> -n <openshift-namespace>
```

## Additional Considerations

The OpenShift Developer Sandbox token may expire, so the `OPENSHIFT_TOKEN` GitHub secret may need to be refreshed before future deployments.

The deployment uses SHA-based image tags for traceability instead of relying only on `latest`.

The Docker image is smoke-tested before being pushed and scanned before deployment.
