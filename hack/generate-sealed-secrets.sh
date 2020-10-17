#!/usr/bin/env bash

# Wire up the env and validations
__dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${__dir}/environment.sh"

# Create secrets file
# shellcheck disable=SC2129
cat >"${GENERATED_SECRETS}" <<-EOF
#
# Manifests auto-generated by secrets.sh -- DO NOT EDIT.
#
---
EOF

#
# Helm Secrets
#

# Generate Helm Secrets
for file in "${CLUSTER_ROOT}"/**/*.txt; do
    # Get the path and basename of the txt file
    # e.g. "deployments/default/pihole/pihole"
    secret_path="$(dirname "$file")/$(basename -s .txt "$file")"
    # Get the filename without extension
    # e.g. "pihole"
    secret_name=$(basename "${secret_path}")
    # Get the relative path of deployment
    deployment=${file#"${CLUSTER_ROOT}"}
    # Get the namespace (based on folder path of manifest)
    namespace=$(echo "${deployment}" | awk -F/ '{print $2}')
    echo "[*] Generating helm secret '${secret_name}' in namespace '${namespace}'..."
    # Create secret
    envsubst <"$file" |
        kubectl -n "${namespace}" create secret generic "${secret_name}-helm-values" \
            --from-file=/dev/stdin --dry-run=client -o json |
        kubeseal --format=yaml --cert="${PUB_CERT}" \
            >>"${GENERATED_SECRETS}"
    echo "---" >>"${GENERATED_SECRETS}"
done

# Replace stdin with values.yaml
sed -i 's/stdin\:/values.yaml\:/g' "${GENERATED_SECRETS}"

#
# Generic Secrets
#

# shellcheck disable=SC2129
cat >>"${GENERATED_SECRETS}" <<-EOF
#
# Generic Secrets auto-generated by secrets.sh -- DO NOT EDIT.
#
EOF

# Cloudflare API Key - cert-manager namespace
kubectl create secret generic cloudflare-api-key \
    --from-literal=api-key="${CF_API_KEY}" \
    --namespace cert-manager --dry-run=client -o json |
    kubeseal --format=yaml --cert="${PUB_CERT}" \
        >>"${GENERATED_SECRETS}"
echo "---" >>"${GENERATED_SECRETS}"

# longhorn backup secret
kubectl create secret generic longhorn-backup-secret \
    --from-literal=AWS_ACCESS_KEY_ID="${MINIO_ACCESS_KEY}" \
    --from-literal=AWS_SECRET_ACCESS_KEY="${MINIO_SECRET_KEY}" \
    --from-literal=AWS_ENDPOINTS="https://s3.${DOMAIN}" \
    --namespace longhorn-system --dry-run=client -o json |
    kubeseal --format=yaml --cert="${PUB_CERT}" \
        >>"${GENERATED_SECRETS}"
echo "---" >>"${GENERATED_SECRETS}"

# minio secret
kubectl create secret generic minio-secret \
    --from-literal=accesskey="${MINIO_ACCESS_KEY}" \
    --from-literal=secretkey="${MINIO_SECRET_KEY}" \
    --namespace utility --dry-run=client -o json |
    kubeseal --format=yaml --cert="${PUB_CERT}" \
        >>"${GENERATED_SECRETS}"
echo "---" >>"${GENERATED_SECRETS}"

# Github Runner
kubectl create secret generic controller-manager \
    --from-literal=github_token="${GITHUB_RUNNER_ACCESS_TOKEN}" \
    --namespace actions-runner-system --dry-run=client -o json |
    kubeseal --format=yaml --cert="${PUB_CERT}" \
        >>"${GENERATED_SECRETS}"
echo "---" >>"${GENERATED_SECRETS}"

# Remove empty new-lines
sed -i '/^[[:space:]]*$/d' "${GENERATED_SECRETS}"

# Validate Yaml
if ! yq validate "${GENERATED_SECRETS}" >/dev/null 2>&1; then
    echo "Errors in YAML"
    exit 1
fi

exit 0
