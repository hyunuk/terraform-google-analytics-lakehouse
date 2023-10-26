#!/bin/bash

set -eu

# Should this script error, print out the line that was responsible
_error_report() {
  echo >&2 "Exited [$?] at line $(caller):"
  cat -n $0 | tail -n+$(($1 - 3)) | head -n7 | sed "4s/^\s*/>>> /"
}
trap '_error_report $LINENO' ERR

# Set variables
TF_PROJECT=$(grep -Po '(?<=project_id = ")[^"]*' terraform.tfvars)
CLOUDBUILD_SERVICE_ACCOUNT=$(gcloud projects list --format='value(PROJECT_NUMBER)' --filter=PROJECT_ID=${TF_PROJECT})@cloudbuild.gserviceaccount.com
STATE_GCS_BUCKET_NAME="${TF_PROJECT}-tf-states"

# Run the script with destroy parameter
echo "Destroying environment..."
gcloud builds submit ./ --project=${TF_PROJECT} \
    --config=./src/yaml/destroy.cloudbuild.yaml \
    --substitutions=_STATE_GCS_BUCKET_NAME=$STATE_GCS_BUCKET_NAME

# Define the list of roles to revoke from the service account
ROLES_TO_REVOKE=(
  "roles/serviceusage.serviceUsageAdmin"
  "roles/iam.serviceAccountAdmin"
  "roles/resourcemanager.projectIamAdmin"
  "roles/config.admin"
  "roles/bigquery.admin"
  "roles/dataplex.admin"
  "roles/compute.networkAdmin"
  "roles/workflows.admin"
  "roles/compute.securityAdmin"
  "roles/dataproc.admin"
  "roles/iam.serviceAccountUser"
  "roles/storage.admin"
)

# Revoke each role from the service account
for ROLE in "${ROLES_TO_REVOKE[@]}"; do
  gcloud projects remove-iam-policy-binding ${TF_PROJECT} \
    --member="serviceAccount:${CLOUDBUILD_SERVICE_ACCOUNT}" \
    --role=${ROLE} > /dev/null 2>&1
done