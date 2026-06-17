# O&Si DevOps Challenge (with ArgoCD)


## Overview

This branch extends the primary OpenShift implementation with a GitOps-based
deployment model.  In this implementation, GitHub Actions handles continuous integration and image
publication, while Argo CD handles continuous deployment to a local Kubernetes
cluster.

This document focuses on the GitOps deployment flow: running Kubernetes
locally with k3d, defining the desired state with Helm, and using Argo CD to
reconcile that state automatically.

The shared application, Docker image, Docker Hub, and image validation details
are documented in the
[main branch](https://github.com/ShrushtiK/devops-challenge/tree/main).

## Architecture

```text
Application change
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
  +-- Update image tag in Helm values.yaml
  +-- Commit the updated desired state to Git
        |
        v
Argo CD detects the change
        |
        v
Argo CD renders the Helm chart
and synchronizes the resources
        |
        v
k3d Kubernetes cluster
  - Deployment
  - Service
  - Ingress
        |
        v
http://devops.localhost:8082
```

Git is the source of truth for the deployment. GitHub Actions does not connect
to the Kubernetes cluster or run `helm upgrade`. Instead, it publishes a new
image and records its commit-SHA tag in `helm/webserver/values.yaml`.
Argo CD observes that Git change and reconciles the cluster.

## Prerequisites

The local implementation was tested on Windows and assumes the following
tools are already installed:

- Docker Desktop running Linux containers.
- PowerShell.
- `kubectl`.
- k3d.
- Git.

Docker must be running because k3d creates the Kubernetes nodes as Docker
containers.

Verify that the required tools are available:

```powershell
docker version
k3d version
kubectl version --client
```

## Create the Local Kubernetes Cluster

Create a single local k3d cluster and map port `8082` on Windows to port `80`
on the k3d load balancer:

```powershell
k3d cluster create vodafone-ziggo-argocd -p "8082:80@loadbalancer"
```

k3d updates the local kubeconfig automatically. Confirm that the node is
available:

```powershell
kubectl get nodes
```

The node should report `Ready`.

The cluster includes Traefik as its default Ingress controller. The port
mapping allows the application Ingress to be reached through
`localhost:8082`.

Useful cluster commands:

```powershell
k3d cluster list
k3d cluster stop vodafone-ziggo-argocd
k3d cluster start vodafone-ziggo-argocd
```

## Install Argo CD

Create the namespace used by Argo CD:

```powershell
kubectl create namespace argocd
```

Install Argo CD using its official installation manifest:

```powershell
kubectl apply -n argocd --server-side --force-conflicts `
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

Wait for the Argo CD components to become ready:

```powershell
kubectl get pods -n argocd
kubectl wait --for=condition=Ready pods --all -n argocd --timeout=300s
```

## Access Argo CD with Port Forwarding

The `argocd-server` Service is created as `ClusterIP`, so it is only accessible
inside the Kubernetes cluster by default. Use `kubectl port-forward` to expose
it temporarily on port `8081` of the Windows machine:

```powershell
kubectl port-forward service/argocd-server -n argocd 8081:443
```

Open:

```text
https://localhost:8081
```

The browser may display a warning because the local endpoint uses Argo CD's
self-signed certificate.

The username is:

```text
admin
```

Retrieve and decode the initial password in PowerShell:

```powershell
$encodedPassword = kubectl -n argocd get secret argocd-initial-admin-secret `
  -o jsonpath="{.data.password}"

[System.Text.Encoding]::UTF8.GetString(
  [System.Convert]::FromBase64String($encodedPassword)
)
```

This command forwards:

```text
Windows localhost:8081 -> argocd-server:443
```

The PowerShell session running the command must remain open while the Argo CD
interface is being accessed. This forwarding is only for the Argo CD
interface; the web application uses its Ingress at
`http://devops.localhost:8082`.

## Bootstrap the Application

The Argo CD Application is defined declaratively in:

```text
argocd/application.yaml
```

Apply it to the cluster:

```powershell
kubectl apply -f argocd/application.yaml
```

This resource configures Argo CD to:

- Read this repository.
- Track the `argo-cd` branch.
- Render the chart in `helm/webserver`.
- Deploy into the `devops-challenge` namespace.
- Create the destination namespace when it does not exist.
- Synchronize changes automatically.
- Remove managed resources that are deleted from Git.
- Correct manual changes made directly in the cluster.

These behaviors are configured by:

```yaml
syncPolicy:
  automated:
    prune: true
    selfHeal: true
  syncOptions:
    - CreateNamespace=true
```

Because Argo CD and the application run in the same cluster, the destination
server is the in-cluster Kubernetes API:

```text
https://kubernetes.default.svc
```

No external cluster registration is required.

Check the Application:

```powershell
kubectl get applications -n argocd
kubectl describe application devops-challenge -n argocd
```

A successfully reconciled application should report:

```text
SYNC STATUS     Synced
HEALTH STATUS   Healthy
```

## Helm and Argo CD

The chart in `helm/webserver` defines the desired Kubernetes resources:

- A `Deployment` that runs the web server image.
- A `Service` that exposes the container on port `8080` inside the cluster.
- An `Ingress` that routes `devops.localhost` to the Service.

In this implementation, Helm is used as a templating and packaging format.
Argo CD renders the chart and owns the deployment lifecycle. There is no Helm
release managed through a direct `helm upgrade` command.

This distinction is important:

```text
Direct Helm deployment: Helm performs the deployment.
Argo CD deployment:     Argo CD renders Helm and reconciles the resources.
```

Changes to the Helm chart are therefore deployed directly by Argo CD after
they are committed to the `argo-cd` branch. They do not require an image build
or a GitHub Actions deployment step.

## GitHub Actions CI Workflow

The workflow is defined in:

```text
.github/workflows/build-image-gitops.yaml
```

It runs for pushes to the `argo-cd` branch only when an image-producing file
changes:

```yaml
paths:
  - Dockerfile
  - .dockerignore
  - index.html
```

Documentation-only and Helm-only changes do not rebuild the image.

The job also ignores commits whose message contains `Update image tag to`.
This protects the image-tag commit created by the workflow from being treated
as a new application build.

The workflow performs the following stages:

1. Checks out the repository.
2. Builds a temporary test image.
3. Starts the container and smoke-tests the Nginx webpage.
4. Scans the image with Trivy for high and critical vulnerabilities.
5. Authenticates to Docker Hub.
6. Builds and publishes the release image with `latest` and a Git commit SHA
   tag.
7. Updates the image repository and tag in `helm/webserver/values.yaml`.
8. Commits the updated desired state back to the `argo-cd` branch.

The workflow requires this repository variable:

```text
DOCKERHUB_USERNAME
```

It also requires this repository secret:

```text
DOCKERHUB_PAT
```

`DOCKERHUB_PAT` is a Docker Hub Personal Access Token with permission to push
to the image repository.

The workflow needs:

```yaml
permissions:
  contents: write
```

This allows it to commit the new image tag to the repository. Under repository
**Settings > Actions > General > Workflow permissions**, GitHub Actions must
also be allowed read and write access. Branch protection rules must permit the
chosen automated update approach.

The workflow commits a change similar to:

```yaml
image:
  repository: shrushti5/devops-challenge
  tag: <git-commit-sha>
```

Using the commit SHA rather than deploying only `latest` gives the image a
unique, traceable version. The pipeline treats SHA tags as immutable release
identifiers.

## Access and Verify the Application

After Argo CD synchronizes the chart, inspect the deployed resources:

```powershell
kubectl get deployment,pods,service,ingress -n devops-challenge
```

Open the application:

```text
http://devops.localhost:8082
```

It can also be verified from PowerShell:

```powershell
curl.exe http://devops.localhost:8082
```

The page should contain:

```text
Hello DevOps O&Si Shrushti Kaul
```

Confirm which versioned image is deployed:

```powershell
kubectl get deployment vodafone-ziggo-demo `
  -n devops-challenge `
  -o jsonpath="{.spec.template.spec.containers[0].image}"
```

The result should contain the Git commit SHA written into `values.yaml`.

## Reconciliation and Pruning

Argo CD continuously compares the resources in Git with the live resources in
the cluster.

With `selfHeal: true`, a managed resource changed manually with `kubectl` is
restored to the state declared in Git.

With `prune: true`, a managed resource removed from the Helm chart is also
removed from the cluster during synchronization. This avoids the orphaned
resource behavior that can occur when repeatedly using only
`kubectl apply -f`.

## Rollback

Rollback in this implementation is Git-based. Git remains the source of truth,
so the desired state is restored by reverting the commit that introduced the
problem:

```powershell
git revert <bad-commit-sha>
git push origin argo-cd
```

Argo CD detects the revert and reconciles the cluster back to the previous
image tag or chart configuration.

This differs from the primary OpenShift implementation, where the pipeline
uses Helm's `--rollback-on-failure` option. Argo CD does not automatically
change Git to an earlier application version when a deployment becomes
unhealthy.

For production progressive delivery, Argo Rollouts could be added to provide
canary or blue-green deployments and automated
rollback.



## Production Considerations

This environment is intended as a local GitOps demonstration. A production
implementation should additionally consider:

- Adding readiness and liveness probes.
- Defining CPU and memory requests and limits.
- Enabling TLS for external access.
- Using Argo Rollouts for progressive delivery and automated rollback.
