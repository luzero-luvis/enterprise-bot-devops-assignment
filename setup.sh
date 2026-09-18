#!/usr/bin/env bash
# Create or reconcile the complete local demo environment.
set -Eeuo pipefail

readonly CLUSTER_NAME="demo"
readonly KUBE_CONTEXT="kind-${CLUSTER_NAME}"
readonly NAMESPACE="demo"
readonly RELEASE_NAME="demo"
readonly IMAGE_REPOSITORY="demo-service"
readonly IMAGE_TAG="local"
readonly IMAGE="${IMAGE_REPOSITORY}:${IMAGE_TAG}"
readonly INGRESS_NGINX_VERSION="v1.15.1"
readonly INGRESS_MANIFEST="https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-${INGRESS_NGINX_VERSION}/deploy/static/provider/kind/deploy.yaml"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! kind get clusters | grep -Fxq "${CLUSTER_NAME}"; then
  kind_config="$(mktemp "${TMPDIR:-/tmp}/kind-demo.XXXXXX.yaml")"
  trap 'rm -f "${kind_config}"' EXIT

  # Map the ingress controller's ports to localhost for `curl demo.local` tests.
  cat >"${kind_config}" <<'EOF'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    extraPortMappings:
      - containerPort: 80
        hostPort: 80
        protocol: TCP
      - containerPort: 443
        hostPort: 443
        protocol: TCP
EOF
  kind create cluster --name "${CLUSTER_NAME}" --config "${kind_config}" --wait 2m
else
  echo "Reusing existing kind cluster: ${CLUSTER_NAME}"
fi

kubectl --context "${KUBE_CONTEXT}" apply -f "${INGRESS_MANIFEST}"
kubectl --context "${KUBE_CONTEXT}" wait \
  --namespace ingress-nginx \
  --for=condition=Available deployment/ingress-nginx-controller \
  --timeout=5m

docker build --tag "${IMAGE}" "${repo_root}/service"
kind load docker-image "${IMAGE}" --name "${CLUSTER_NAME}"

helm upgrade --install "${RELEASE_NAME}" "${repo_root}/chart" \
  --kube-context "${KUBE_CONTEXT}" \
  --namespace "${NAMESPACE}" \
  --create-namespace \
  --set-string image.repository="${IMAGE_REPOSITORY}" \
  --set-string image.tag="${IMAGE_TAG}" \
  --wait \
  --timeout 5m

kubectl --context "${KUBE_CONTEXT}" rollout status \
  --namespace "${NAMESPACE}" \
  deployment/demo-demo-service \
  --timeout=2m

echo "Setup complete. Add '127.0.0.1 demo.local' to /etc/hosts, then run: curl http://demo.local/"
