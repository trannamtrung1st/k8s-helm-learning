#!/bin/bash

echo "Note: prefer ./scripts/helm-apply.sh (Helm umbrella). This script applies legacy Kustomize under devops/." >&2
kubectl apply --server-side --force-conflicts -k devops/