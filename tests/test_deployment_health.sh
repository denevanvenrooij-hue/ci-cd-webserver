#!/bin/bash
# Wait for deployment to become available

DEPLOYMENT_NAME=$1
VERSION_NAME=$2
MAX_RETRIES=${3:-30} # 30 tries
RETRY_INTERVAL=${4:-10} # every 10 seconds

echo "Checking deployment health: ${DEPLOYMENT_NAME}/${VERSION_NAME}"

for i in $(seq 1 $MAX_RETRIES); do
    echo "Attempt $i/$MAX_RETRIES..."
    
    STATUS=$(ubiops deployment_versions get "$VERSION_NAME" -d "$DEPLOYMENT_NAME" --format json | jq -r '.status')
    
    if [ "$STATUS" == "available" ]; then
        echo "Deployment is available"
        exit 0
    elif [ "$STATUS" == "failed" ]; then
        echo "Deployment build failed"
        exit 1
    fi
    
    echo "  Status: ${STATUS} - waiting ${RETRY_INTERVAL}s..."
    sleep $RETRY_INTERVAL
done

echo "Timeout: Deployment did not become available"
exit 1