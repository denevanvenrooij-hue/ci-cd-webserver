#!/bin/bash
# Wait for service endpoints to work

SERVICE_URL=$1
AUTH_TOKEN=$2
MAX_RETRIES=${3:-30} # 30 tries
RETRY_INTERVAL=${4:-10} # every 10 seconds

echo "Testing service endpoint: ${SERVICE_URL}"

for i in $(seq 1 $MAX_RETRIES); do
    echo "Attempt $i/$MAX_RETRIES..."

    # Health check
    HEALTH_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
        --max-time 30 \
        --request GET \
        --url "${SERVICE_URL}/health" \
        --header "Authorization: Token ${AUTH_TOKEN}")

    if [ "$HEALTH_RESPONSE" != "200" ]; then
        echo "Health check failed (HTTP ${HEALTH_RESPONSE})"
        sleep "$RETRY_INTERVAL"
        continue
    fi

    echo "Health check passed"

    # Service endpoint check
    ENDPOINT_RESPONSE=$(curl -s -w "\n%{http_code}" \
        --max-time 30 \
        --request GET \
        --url "${SERVICE_URL}/v1/model/info" \
        --header "Authorization: Token ${AUTH_TOKEN}" \
        --header 'Content-Type: application/json')

    HTTP_CODE=$(echo "$ENDPOINT_RESPONSE" | tail -n1)

    if [ "$HTTP_CODE" != "200" ]; then
        echo "Service endpoint failed (HTTP ${HTTP_CODE})"
        sleep "$RETRY_INTERVAL"
        continue
    fi

    echo "Service endpoint tests passed"
    exit 0
done

echo "Service did not become ready after $MAX_RETRIES attempts"
exit 1