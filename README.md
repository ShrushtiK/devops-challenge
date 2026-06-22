# O&Si DevOps Challenge

## Overview

This project builds a containerized Nginx web server that displays the
required greeting and date. The image is published to Docker Hub and deployed
to Red Hat OpenShift Developer Sandbox through an automated GitHub Actions
pipeline.

![text](image.png)

The primary solution uses:

- Nginx to serve the static webpage.
- Docker to package the web server and webpage.
- Docker Hub as the container registry.
- GitHub Actions for continuous integration and deployment.
- Trivy for container vulnerability scanning.
- Helm to manage the OpenShift resources as one release.
- OpenShift Developer Sandbox as the deployment environment.

An additional GitOps implementation using Argo CD and k3d is available in the
[`argo-cd` branch](https://github.com/ShrushtiK/devops-challenge/tree/argo-cd).



## Architecture

```text
Push to main
     |
     v
GitHub Actions
  |
  +-- Build test image
  +-- Run smoke test
  +-- Scan with Trivy
  +-- Publish image to Docker Hub
  |     - latest
  |     - commit SHA
  |
  +-- Authenticate to OpenShift
  +-- Lint Helm chart
  +-- Deploy SHA-tagged image with Helm
  +-- Verify OpenShift Route
     |
     v
OpenShift Developer Sandbox
  - Deployment
  - Service
  - Route
     |
     v
Public webpage
```

The pipeline separates the process into two jobs. The first job validates the
image source, builds and publishes the release image, and assigns it the Git
commit SHA. The second job runs only after the image job succeeds and deploys
that SHA-tagged image to OpenShift.

## Web Server and Webpage

The webpage is defined in `index.html` and displays:

```text
Hello DevOps O&Si Shrushti Kaul
Date: <current date>
```

Nginx is used because the application consists only of static content and does
not require an application runtime or backend server.

## Docker Image

The `Dockerfile` packages Nginx and the webpage into a portable image:

```dockerfile
FROM nginxinc/nginx-unprivileged:stable-alpine-slim

COPY index.html /usr/share/nginx/html/index.html

EXPOSE 8080
```

The image uses `nginxinc/nginx-unprivileged:stable-alpine-slim` because:

- The Alpine variant is smaller than the Debian-based alternatives.
- Nginx is configured to run without root privileges.
- Port `8080` does not require privileged port access.
- The image is compatible with OpenShift's restricted container security
  model.

The image contains only the Nginx runtime and the required webpage. No
additional packages, build tools, credentials, or configuration files are
added.

The `.dockerignore` file reduces the build context by preventing unrelated
repository content from being sent to the Docker daemon.

## Build and Run Locally

The image can be built from the repository root before it is published or
deployed:

```powershell
docker build -t devops-challenge:local .
```

Run the locally built image:

```powershell
docker run --rm -p 8080:8080 devops-challenge:local
```

The port mapping connects port `8080` on the local machine to the Nginx
process listening on port `8080` inside the container.

Open:

```text
http://localhost:8080
```

The response can also be verified from a terminal:

```powershell
curl http://localhost:8080
```

## Container Registry

Docker Hub is used to distribute the validated image between the CI pipeline,
local Docker environments, and OpenShift.

The public image repository is [here](https://hub.docker.com/repository/docker/shrushti5/devops-challenge/general), namely:

```text
shrushti5/devops-challenge
```

The normal publication path is automated by GitHub Actions. For a manual
publication, authenticate with a Docker Hub username and Personal Access
Token:

```powershell
docker login
```

Build the image with its registry name and publish it:

```powershell
docker build -t shrushti5/devops-challenge:latest .
docker push shrushti5/devops-challenge:latest
```

The published image can then be run without building the repository locally:

```powershell
docker pull shrushti5/devops-challenge:latest
docker run --rm -p 8080:8080 shrushti5/devops-challenge:latest
```

The CI/CD pipeline publishes two tags:

```text
latest
<git-commit-sha>
```

`latest` provides a convenient reference to the newest published build. The
commit SHA provides a unique, traceable version and is treated as immutable by
the pipeline. OpenShift is deployed with the SHA tag rather than relying on the
mutable `latest` tag.

## CI/CD Pipeline

The workflow is defined in:

```text
.github/workflows/build-and-deploy.yaml
```

It runs on pushes to the `main` branch when a deployment-relevant file
changes.

### Image Build and Validation

The `build-and-push-image` job:

1. Checks out the repository.
2. Builds a temporary image named `devops-challenge:test`.
3. Starts the container locally on the GitHub-hosted runner.
4. Repeatedly checks Nginx until the page contains `Hello DevOps`.
5. Fails the job if the web server does not become available.
6. Scans the test image with Trivy.
7. Authenticates to Docker Hub.
8. Builds and publishes the release image with `latest` and commit SHA tags.

The smoke test confirms that
the container starts, Nginx responds on port `8080`, and the expected webpage
content is present.

Trivy scans operating-system and application-library vulnerabilities:

```text
Vulnerability types: os, library
Failure severities:  HIGH, CRITICAL
Unfixed findings:    ignored
```

A matching high or critical vulnerability causes the job to fail before the
image is published.

### OpenShift Deployment

The `deploy-on-openshift` job depends on the image job. It runs only after the
image has been built, tested, scanned, and published successfully.

The deployment job:

1. Checks out the repository.
2. Installs the OpenShift CLI.
3. Sets up Helm.
4. Authenticates to OpenShift Developer Sandbox.
5. Lints the Helm chart.
6. Installs or upgrades the application with the commit SHA image.
7. Retrieves the OpenShift Route.
8. Requests the Route URL to verify the deployed webpage.

The deployment step runs on GitHub's Ubuntu runner and uses:

```bash
helm upgrade --install vodafone-ziggo-demo helm/webserver \
  --namespace "$OPENSHIFT_NAMESPACE" \
  --set image.repository="$DOCKERHUB_USERNAME/devops-challenge" \
  --set image.tag="$GITHUB_SHA" \
  --rollback-on-failure \
  --timeout=60s
```

The workflow supplies these values from GitHub Actions expressions rather than
the illustrative shell variables above.

## GitHub Actions Configuration

The workflow requires repository variables for non-sensitive configuration
and repository secrets for credentials.

Repository variables:

| Name | Purpose |
| --- | --- |
| `DOCKERHUB_USERNAME` | Docker Hub account used to publish the image |
| `OPENSHIFT_NAMESPACE` | OpenShift Developer Sandbox project/namespace |

Repository secrets:

| Name | Purpose |
| --- | --- |
| `DOCKERHUB_PAT` | Docker Hub Personal Access Token used to push images |
| `OPENSHIFT_SERVER` | OpenShift API server URL |
| `OPENSHIFT_TOKEN` | Token used by the workflow to authenticate to OpenShift |

Configure them under:

```text
GitHub repository
-> Settings
-> Secrets and variables
-> Actions
```

Sensitive values are stored as secrets and are not committed to the
repository.

## OpenShift Developer Sandbox Access

From the OpenShift web console, obtain the login command through:

```text
User menu
-> Copy login command
-> Display token
```

The generated command has this form:

```powershell
oc login --token=<openshift-token> --server=<openshift-server-url>
```

Developer Sandbox tokens expire. If a deployment begins failing during the
OpenShift login step, generate a fresh token and update `OPENSHIFT_TOKEN`.

## Helm Chart

The chart is located in `helm/webserver`. The pipeline overrides its image
repository and tag so each deployment uses the image produced by the current
workflow run.

The chart creates three resources:

```text
Deployment -> Runs the Nginx container
Service    -> Exposes the container within the OpenShift namespace
Route      -> Exposes the Service outside the cluster
```

The Deployment uses a rolling-update strategy. Kubernetes creates the new pod
and replaces the previous pod as the new revision becomes available.

`revisionHistoryLimit: 5` retains a limited number of old ReplicaSets, while
`progressDeadlineSeconds: 60` prevents a rollout from waiting indefinitely.

## Deploy Manually to OpenShift

The GitHub Actions workflow is the primary deployment path. The same Helm chart
can also be deployed manually for testing or troubleshooting.

Prerequisites:

- The `oc` CLI is installed.
- Helm is installed.
- The image is available in Docker Hub.
- An active OpenShift Developer Sandbox token is available.

Log in:

```powershell
oc login --token=<openshift-token> --server=<openshift-server-url>
```

Select the project:

```powershell
oc project <openshift-namespace>
```

Install or upgrade the application:

```powershell
helm upgrade --install vodafone-ziggo-demo helm/webserver `
  --namespace <openshift-namespace> `
  --set image.repository=shrushti5/devops-challenge `
  --set image.tag=latest `
  --rollback-on-failure `
  --timeout=60s
```

## Verify the OpenShift Deployment

Inspect the application resources:

```powershell
oc get deployment,pods,service,route -n <openshift-namespace>
```

Check the rollout:

```powershell
oc rollout status deployment/vodafone-ziggo-demo `
  -n <openshift-namespace> `
  --timeout=60s
```

Retrieve the public hostname:

```powershell
oc get route vodafone-ziggo-demo `
  -n <openshift-namespace> `
  -o jsonpath='{.spec.host}'
```

Open the returned hostname over HTTP and ensure that the response contains the required greeting and current date.


## Helm Upgrade and Rollback

`helm upgrade --install` supports both the first deployment and later updates:

```text
Release does not exist -> install
Release exists         -> upgrade
```

The workflow uses:

```text
--rollback-on-failure
```

If the new release cannot become ready within the configured timeout, Helm
restores the previous successful release. The GitHub Actions job still fails,
which correctly signals that the requested version was not deployed.

Inspect the Helm release:

```powershell
helm list -n <openshift-namespace>
helm history vodafone-ziggo-demo -n <openshift-namespace>
```

Perform a manual rollback when required:

```powershell
helm rollback vodafone-ziggo-demo <revision> `
  -n <openshift-namespace>
```

## Additional Considerations

For a production implementation, further improvements could include:

- Adding readiness and liveness probes.
- Defining CPU and memory requests and limits.
- Enabling TLS on the OpenShift Route.
- Using a scoped OpenShift service account instead of a personal user token.
- Moving continuous deployment to a GitOps controller such as Argo CD.
