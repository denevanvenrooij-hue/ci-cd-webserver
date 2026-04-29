# Set up CI/CD from Git with Services Integration
​
On this page we will show you how to automatically deploy your code to UbiOps, as well as directly create a service from this deployment. This guide extends the basic [Git CI/CD setup](https://ubiops.com/docs/howto/howto-deploygit-ubiops/) and ensures your deployment is fully operational before making it available as a service.
​
This guide will cover:
1. Creating an API Token with permissions to update deployments and services
2. Setting up test scripts for health checks and service validation
3. Configuring a CI workflow in GitLab, GitHub or Azure DevOps
4. Tips and tricks for production workflows
​
## Requirements
​
- A UbiOps account (you can create a free trial account [here](https://ubiops.com/) using your email address or a Google account)
- A Python deployment script that will be exposed as a service via UbiOps (for example, an LLM proxy, an API wrapper, a vLLM server, or data processing service)
- A GitLab, GitHub or Azure DevOps repository where your code is located
​
## Creating the API token
​
First we will create our API token in UbiOps. Start by going to **Permissions** in the sidebar, then navigate to the **API tokens** tab. Here you can click the **[+]Add** button to create a new API token. Give the new token a name, for instance "Git-CI-CD-Token".

![User & permissions](https://storage.googleapis.com/ubiops/public-docs-media/images/create_token.gif)
​
Now you will be prompted to add roles to the token. Click on the **[+]Assign roles to user** button and select the following roles:
- **deployment-editor**: Select the specific deployment you want to control with Git CI
- **service-user-editor**: Set the role level to **Project**
​
Lastly, copy the API token and save it in a secure spot. You will not be able to retrieve this token again.

## Repository structure
​
We will now start creating the files that we need to setup and test a CI/CD pipeline for UbiOps. In the end we will have the 
following folder structure:
​
```
your-repo/
├── deployment_package/
│   ├── config.yaml
│   ├── deployment.py
│   └── requirements.txt
├── config/
│   ├── deployment.yaml
│   ├── deployment_version.yaml
│   ├── service.yaml
│   └── environment_variables.yaml
├── tests/
│   ├── test_deployment_health.sh
│   └── test_service_endpoint.sh
├── .ubiops-ignore
├── .gitlab-ci.yml                  # Necessary for GitLab
├── .github/workflows/deploy.yml    # Necessary for GitHub
└── azure-pipelines.yml             # Necessary for Azure DevOps
```

## Deployment package files

For the Python deployment script in this how-to, we use an example of a simple [LiteLLM](https://docs.litellm.ai/docs/) configuration of which we can host the `/models` endpoint with [UbiOps Services](https://ubiops.com/docs/services/). We will need to create three files to create a deployment on UbiOps.

- **`config.yaml`**: herein the LiteLLM configuration is defined,
- **`requirements.txt`**: to define the Python packages that we need,
- **`deployment.py`**: contains a subprocess that can host a LiteLLM server. 

## Endpoints 

The LiteLLM proxy exposes a [`/v1/models`](https://docs.litellm.ai/docs/proxy/model_discovery) endpoint that mirrors the models that are denoted in the configuration file, as well as a [`/health`](https://docs.litellm.ai/docs/proxy/health) endpoint. Both are used in this example to illustrate that this CI/CD pipeline can check any endpoint that you make availble with your service, and specify in the `test_service_endpoint.sh`.
​
## Configuration files
​
Create the following configuration files in the `config/` directory:
​
### deployment.yaml
​
```yaml
deployment_name: "llm-proxy"
deployment_description: "LiteLLM proxy deployment"
deployment_labels:
  created-by: ci-cd
default_version: "v1"
input_type: "plain"
input_fields: []
output_type: "plain"
output_fields: []
```
​
### deployment_version.yaml
​
```yaml
deployment_name: llm-proxy
version_name: "v1"
version_description: "Deployed via CI/CD"
environment: "python3-12"
instance_type: "512mb"
minimum_instances: 1
maximum_instances: 1
maximum_idle_time: 300
request_retention_mode: "metadata"
request_retention_time: 2419200
```
​
### service.yaml
​
```yaml
service_name: llm-proxy
service_description: "Public endpoint for LLM proxy"
service_deployment: llm-proxy
port: 4001
authentication_required: true
authentication_method_token_enabled: true
request_logging_excluded_paths: "(health|status)$"
rate_limit_token: 300
```
​
### environment_variables.yaml
​
```yaml
environment_variables:
  - name: "UBIOPS_API_TOKEN"
    value: ""  # Set via CI/CD
    secret: true
```
​
## Test scripts
​
Create the following test scripts in the `tests/` directory and make them executable with `chmod +x tests/*.sh`:
​
### test_deployment_health.sh
​
```bash
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
```
​
### test_service_endpoint.sh
​
```bash
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
```

## Deployment package files

Here we create the files that will form our `deployment_package/`.

### config.yaml

```yaml
model_list:
  - model_name: test-model
    litellm_params:
      model: openai/ubiops-deployment/<deployment-name-1>//<version-name-1>
      api_base: https://api.ubiops.com/chat/openai-compatible/v1
```

### requirements.txt

```yaml
litellm[proxy]
requests
```

### deployment.py

```python
import subprocess
import time
import requests

class Deployment():
    def __init__(self, base_directory, context):
        self.port = 4001
        self.url = f"http://0.0.0.0:{self.port}"
        config_path = f"{base_directory}/config.yaml"
        
        self.process = subprocess.Popen(
            ["litellm", "--config", config_path, "--port", str(self.port)],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True)
        
        self.wait_for_server()

    def request(self, data):
        try:
            response = requests.get(f"{self.url}/health", timeout=5)
            return {"status": "healthy", "code": response.status_code}
        except Exception as e:
            return {"status": "unhealthy", "error": str(e)}
    
    def wait_for_server(self):
        max_retries = 60
        for _ in range(max_retries):
            if self.process.poll() is not None:
                raise RuntimeError(f"LiteLLM process exited: {self.process.poll()}")
            
            try:
                response = requests.get(f"{self.url}/health", timeout=5)
                if response.status_code == 200:
                    return
            except requests.exceptions.RequestException:
                time.sleep(5)
        
        raise RuntimeError("LiteLLM server failed to start")
```
​
## Setting up the CI workflow
​
Now that we have our token, deployment package, and test scripts ready, we can set up the Git CI. We will first cover GitLab, if you are interested in GitHub Actions or Azure DevOps, scroll down to the next section.
​
### GitLab
​
Go to the GitLab repository that contains the code you want to push to UbiOps. To make sure GitLab has the right permissions to push to UbiOps and create services, we need to add the API token we created as an environment variable to GitLab. You can do so by navigating to **Settings**, then clicking on the tab **CI/CD** and then going to **variables**. Name the variable key `UBIOPS_TOKEN` and paste the API token as the variable value in the format "abcd123", without the "Token " bearer in front, this will be added on automatically later. For more information on GitLab variables see [here](https://docs.gitlab.com/ee/ci/variables/).
​
Now that the token is added as a variable to your repository, we can make a `.gitlab-ci.yml` that pushes the code from our GitLab repository to UbiOps, validates the deployment, and creates a service. Below is the `.gitlab-ci.yml` we need.

!!! note "URL"
  If your UbiOps API does not have the standard UbiOps URL, make sure to insert the right URL after `--api` instead of the standard `https://api.ubiops.com/v2.1`.
​
```yaml
stages:
  - deploy
  - test
  - service

variables:
  DEPLOYMENT_NAME: llm-proxy
  ENVIRONMENT: python3-12
  DIR_PATH: ./deployment_package
  CONFIG_DIR: ./config

.ubiops_setup: &ubiops_setup
  image: python:3.12
  before_script:
    - pip install ubiops-cli
    - apt-get update && apt-get install -y jq
    - ubiops signin --token -p "Token ${UBIOPS_TOKEN}" --api https://api.ubiops.com/v2.1

deploy_version: 
  <<: *ubiops_setup
  stage: deploy
  script:
    - VERSION_NAME="v-${CI_COMMIT_SHA:0:7}"
    - echo "Deploying ${DEPLOYMENT_NAME} version ${VERSION_NAME}"
    - ubiops deployments get ${DEPLOYMENT_NAME} || ubiops deployments create -f ${CONFIG_DIR}/deployment.yaml
    - ubiops environment_variables create -d ${DEPLOYMENT_NAME} -f ${CONFIG_DIR}/environment_variables.yaml --overwrite
    - ubiops deployments deploy -f ${CONFIG_DIR}/deployment_version.yaml -dir ${DIR_PATH} 
      --version_name ${VERSION_NAME} --overwrite -y
      --labels git-user:${GITLAB_USER_LOGIN},git-commit:${CI_COMMIT_SHA}
    - echo "VERSION_NAME=${VERSION_NAME}" > version.env
  artifacts:
    reports:
      dotenv: version.env
  only:
    - main

test_deployment:
  <<: *ubiops_setup
  stage: test
  dependencies:
    - deploy_version
  script:
    - chmod +x tests/test_deployment_health.sh
    - ./tests/test_deployment_health.sh ${DEPLOYMENT_NAME} ${VERSION_NAME}
  only:
    - main

test_service:
  <<: *ubiops_setup
  stage: service
  dependencies:
    - deploy_version
  script:
    - ubiops deployments update ${DEPLOYMENT_NAME} --default_version ${VERSION_NAME}
    - ubiops services create -f ${CONFIG_DIR}/service.yaml --overwrite --format yaml
    - SERVICE_URL=$(ubiops services get ${DEPLOYMENT_NAME} --format json | jq -r '.endpoint')
    - echo 'Service URL:' ${SERVICE_URL}
    - chmod +x tests/test_service_endpoint.sh
    - TOKEN_CLEAN=$(echo "${UBIOPS_TOKEN}" | sed 's/^Token //')
    - ./tests/test_service_endpoint.sh ${SERVICE_URL} ${TOKEN_CLEAN}
  only:
    - main
```
​
The script performs the following steps every time new commits are pushed to the main branch:
​
1. **Deploy stage**: Creates a new deployment version with a version name constructed from the first seven characters of the Commit-SHA
2. **Test stage**: Waits for the deployment to become "available" and validates it's healthy
3. **Service stage**: Updates the default version, creates/updates the service, and runs endpoint tests
​
To make this script work, you need to configure the variables at the top. At minimum, you need to provide your deployment name, environment, and path to the deployment package in your repository:
​
```yaml
variables:
  DEPLOYMENT_NAME: llm-proxy
  ENVIRONMENT: python3-12
  DIR_PATH: ./deployment_package
  CONFIG_DIR: ./config
```
​
Use path `./` for `DIR_PATH` if your deployment file (the deployment.py) is in the root of your repository.
​
If you want, you can also specify additional parameters in your `deployment_version.yaml`, such as the instance type, and the minimum and maximum number of instances that you want to have running. For more information on that, please see [scaling and resource allocation](https://ubiops.com/docs/deployments/deployment-scaling/).
​
Once you have added the `.gitlab-ci.yml`, your CI workflow is all set up!

​
### GitHub
​
Go to the GitHub repository that contains the code you want to push to UbiOps. To make sure GitHub can communicate with UbiOps we need to add the API token as a repository secret. You can do so by navigating to **Settings**, then to **Secrets and variables**, then **Actions**, and lastly click the button **New repository secret**. Name the variable `UBIOPS_TOKEN` and paste the saved token as value in the format "Token abcd123" and click **Add secret**. For more information on repository secrets in GitHub see [here](https://docs.github.com/en/actions/security-guides/encrypted-secrets).
​
Now that the token is added as a secret to your repository, we can configure our workflow. Go to **Actions** and click **create a new workflow**. You will be redirected to `.github/workflows/deploy.yml`. Below is the `.yml` we need:
​
!!! note "URL"
  If your UbiOps API does not have the standard UbiOps URL, make sure to insert the right URL after `--api` instead of the standard `https://api.ubiops.com/v2.1`.

### .github/workflows/deploy.yml 

```yaml
name: Deploy a Service

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    env:
      DEPLOYMENT_NAME: llm-proxy
      ENVIRONMENT: python3-12
      DIR_PATH: ./deployment_package
      UBIOPS_TOKEN: ${{ secrets.UBIOPS_TOKEN }}
      CONFIG_DIR: ./config
    steps:
      - uses: actions/checkout@v3
      
      - name: Set up Python 3.12
        uses: actions/setup-python@v4
        with:
          python-version: '3.12'
      
      - name: Install dependencies
        run: |
          python -m pip install --upgrade pip
          pip install ubiops-cli
          sudo apt-get update && sudo apt-get install -y jq
      
      - name: Authenticate with UbiOps
        run: ubiops signin --token -p "Token ${{ secrets.UBIOPS_TOKEN }}" --api https://api.ubiops.com/v2.1
      
      - name: Set version name
        id: version
        run: |
          VERSION_NAME="v-${GITHUB_SHA:0:7}"
          echo "VERSION_NAME=${VERSION_NAME}" >> $GITHUB_ENV
      
      - name: Create and test a Deployment
        run: |
          ubiops deployments get ${DEPLOYMENT_NAME} || ubiops deployments create -f ${CONFIG_DIR}/deployment.yaml
          ubiops environment_variables create -d ${DEPLOYMENT_NAME} -f ${CONFIG_DIR}/environment_variables.yaml --overwrite
          ubiops deployments deploy -f ${CONFIG_DIR}/deployment_version.yaml -dir ${DIR_PATH} \
            --version_name ${VERSION_NAME} --overwrite -y \
            --labels git-user:${{ github.actor }},git-commit:${GITHUB_SHA}
          chmod +x tests/test_deployment_health.sh
          ./tests/test_deployment_health.sh ${DEPLOYMENT_NAME} ${VERSION_NAME}
      
      - name: Create and test a Service
        run : |
          ubiops deployments update ${DEPLOYMENT_NAME} --default_version ${VERSION_NAME}
          ubiops services create -f ${CONFIG_DIR}/service.yaml --overwrite --format yaml
          SERVICE_URL=$(ubiops services get ${DEPLOYMENT_NAME} --format json | jq -r '.endpoint')
          echo 'Service URL:' ${SERVICE_URL}
          chmod +x tests/test_service_endpoint.sh
          TOKEN_CLEAN=$(echo "${UBIOPS_TOKEN}" | sed 's/^Token //')
          ./tests/test_service_endpoint.sh ${SERVICE_URL} ${TOKEN_CLEAN}
```

If you want, you can also specify additional parameters, such as the instance type group and the minimum and maximum number of instances that you want to have running. For more information on that, please see
[scaling and resource allocation](../scaling-resource-settings.md).

When you've added the `.yml` file and configured your parameters you can click **Start commit** to add the new action
yaml to your repository. Your GitHub CI workflow is now all set up!


### Azure DevOps

For Azure DevOps, the process to configure CI/CD can be done through creating a `azure-pipelines.yml` file in your repository and creating a pipeline in Azure DevOps, which links to the `azure-pipelines.yml` file.

The process of setting up CI/CD on Azure DevOps involves two key steps:

1. Configure the `azure-pipelines.yml` file
2. Create a pipeline in Azure DevOps.

!!! note "URL"
  If your UbiOps API does not have the standard UbiOps URL, make sure to insert the right URL after `--api` instead of the standard `https://api.ubiops.com/v2.1`.

#### azure-pipeline.yml

```yaml
trigger:
- main

pool:
  vmImage: 'ubuntu-latest'

variables:
  DEPLOYMENT_NAME: llm-proxy
  ENVIRONMENT: python3-12
  DIR_PATH: ./deployment_package
  CONFIG_DIR: ./config

steps:
- task: UsePythonVersion@0
  inputs:
    versionSpec: '3.12'
  displayName: 'Set up Python 3.12'

- script: |
    python -m pip install --upgrade pip
    pip install ubiops-cli
    sudo apt-get update && sudo apt-get install -y jq
  displayName: 'Install dependencies'

- script: |
    ubiops signin --token -p "Token $(UBIOPS_TOKEN)" -- https://api.ubiops.com/v2.1
  displayName: 'Authenticate with UbiOps'
  env:
    UBIOPS_TOKEN: $(UBIOPS_TOKEN)

- script: |
    VERSION_NAME="v-$(echo $(Build.SourceVersion) | cut -c1-7)"
    echo "##vso[task.setvariable variable=VERSION_NAME]$VERSION_NAME"
    echo "Version name set to: $VERSION_NAME"
  displayName: 'Set version name'

- script: |
    ubiops deployments get $(DEPLOYMENT_NAME) || ubiops deployments create -f $(CONFIG_DIR)/deployment.yaml
    ubiops environment_variables create -d $(DEPLOYMENT_NAME) -f $(CONFIG_DIR)/environment_variables.yaml --overwrite
    ubiops deployments deploy -f $(CONFIG_DIR)/deployment_version.yaml -dir $(DIR_PATH) \
      --version_name $(VERSION_NAME) --overwrite -y \
      --labels git-user:$(Build.RequestedFor),git-commit:$(Build.SourceVersion)
    chmod +x tests/test_deployment_health.sh
    ./tests/test_deployment_health.sh $(DEPLOYMENT_NAME) $(VERSION_NAME)
  displayName: 'Create and test a Deployment'
  env:
    UBIOPS_TOKEN: $(UBIOPS_TOKEN)

- script: |
    ubiops deployments update $(DEPLOYMENT_NAME) --default_version $(VERSION_NAME)
    ubiops services create -f $(CONFIG_DIR)/service.yaml --overwrite --format yaml
    SERVICE_URL=$(ubiops services get $(DEPLOYMENT_NAME) --format json | jq -r '.endpoint')
    echo "Service URL: $SERVICE_URL"
    chmod +x tests/test_service_endpoint.sh
    TOKEN_CLEAN=$(echo "$(UBIOPS_TOKEN)" | sed 's/^Token //')
    ./tests/test_service_endpoint.sh $SERVICE_URL $TOKEN_CLEAN
  displayName: 'Create and test a Service'
  env:
    UBIOPS_TOKEN: $(UBIOPS_TOKEN)
```

The script deploys the deployment package in your repository as a new version of the given deployment every time new commits are pushed to the main branch. The version name is constructed automatically from the first seven characters of the `Commit-SHA`. We create a new deployment version using the [UbiOps CLI](https://ubiops.com/docs/ubiops_cli/). Inside the script part of this `.yaml` file you can call any function of the CLI, as long as your used token permits it.  

To make this script work, you first need to configure some variables. At minimum, you need to provide your deployment
name, environment and path to the deployment package in your repository. Use path `./` if your deployment file
(the `deployment.py`) is in the root of your repository. 

If you want, you can also specify additional parameters, such as the instance type group and the minimum and maximum number of instances that you want to have running. For more information on that, please see
[scaling and resource allocation](../scaling-resource-settings.md).

#### Create a pipeline in Azure DevOps

To create a pipeline in Azure DevOps, do the following steps:

1. Go to your Azure DevOps project and click on **Pipelines** in the left menu
2. Click on **New pipeline**
3. Select `Use the classic editor` and configure your repository
4. Select `YAML` and click on **Apply**
5. Set the name, agent pool and specify the path to your `azure-pipelines.yml` file
6. Go to the variables tab and add a variable `UBIOPS_TOKEN` with your UbiOps API token (as a secret variable)
7. Click on **Save&queue** and then on **Save&run** to save and run your pipeline

Your Azure DevOps CI workflow is now all set up! You can now push new commits to your repository and see the pipeline
running. If you want, you can also specify additional parameters, like memory allocation and maximum number of
instances. For more information on that, please see
[scaling and resource allocation](../scaling-resource-settings.md).
