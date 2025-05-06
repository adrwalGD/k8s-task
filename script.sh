#!/bin/bash
FOLDERS=(
    "src/adservice"
    "src/cartservice/src"
    "src/checkoutservice"
    "src/currencyservice"
    "src/emailservice"
    "src/frontend"
    "src/loadgenerator"
    "src/paymentservice"
    "src/productcatalogservice"
    "src/recommendationservice"
    "src/shippingservice"
    "src/shoppingassistantservice"
)
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
START_DIR=$(pwd)
if [ "$1" == "build" ]; then
    REGISTRY="adrwalacr.azurecr.io"
    TAG="latest"

    set -e
    set -o pipefail

    echo "Starting Docker build and push process..."
    echo "Registry: $REGISTRY"
    echo "Tag:      $TAG"
    echo "Folders:  ${FOLDERS[*]}"
    echo "----------------------------------------"

    for folder_name in "${FOLDERS[@]}"; do
        folder_path="$SCRIPT_DIR/$folder_name"

        if [ ! -d "$folder_path" ]; then
            folder_path="$START_DIR/$folder_name"
        fi

        echo ""
        echo "--- Processing folder: $folder_name ---"
        echo "Full path resolved to: $folder_path"

        # Check if the directory exists
        if [ ! -d "$folder_path" ]; then
            echo "Error: Directory '$folder_path' not found. Skipping."
            continue # Move to the next folder in the array
        fi

        echo "Changing directory to $folder_path"
        pushd "$folder_path" > /dev/null # '>' redirects stdout, '/dev/null' discards it

        if [ ! -f "Dockerfile" ]; then
            echo "Error: 'Dockerfile' not found in '$folder_path'. Skipping."
            # Navigate back out before continuing
            popd > /dev/null
            continue # Move to the next folder in the array
        fi

        # Construct the full Docker image name including registry and tag
        # Uses the folder name as the image name part
        full_image_name="${REGISTRY}/$(basename "$folder_name"):${TAG}"

        echo "Building image: $full_image_name"
        # Build the Docker image. '.' refers to the current directory as the build context.
        # The '-t' flag tags the image.
        docker build -t "$full_image_name" .

        echo "Pushing image: $full_image_name"
        # Push the tagged image to the configured registry
        docker push "$full_image_name"

        echo "Successfully built and pushed $full_image_name"

        # Return to the previous directory using popd
        popd > /dev/null

    done

    echo ""
    echo "----------------------------------------"
    echo "Script finished successfully."
    echo "----------------------------------------"

    exit 0
fi

if [ "$1" == "checkov" ]; then
    DOCKERFILE_NAME="Dockerfile.my"

    for folder_name in "${FOLDERS[@]}"; do
        folder_path="$SCRIPT_DIR/$folder_name"

        if [ ! -d "$folder_path" ]; then
            folder_path="$START_DIR/$folder_name"
        fi

        echo ""
        echo "--- Processing folder: $folder_name ---"
        echo "Full path resolved to: $folder_path"

        if [ ! -d "$folder_path" ]; then
            echo "Error: Directory '$folder_path' not found. Skipping."
            continue
        fi

        echo "Changing directory to $folder_path"
        pushd "$folder_path" > /dev/null

        if [ ! -f "$DOCKERFILE_NAME" ]; then
            echo "Error: '$DOCKERFILE_NAME' not found in '$folder_path'. Skipping."
            popd > /dev/null
            continue
        fi

        checkov -f "$folder_path/$DOCKERFILE_NAME" --framework dockerfile --quiet --skip-check CKV_DOCKER_2

        popd > /dev/null
    done
fi

if [ "$1" == "trivy" ]; then
    IMAGES=(
        "adrwalacr.azurecr.io/adservice:my"
        "adrwalacr.azurecr.io/cartservice:my"
        "adrwalacr.azurecr.io/checkoutservice:my"
        "adrwalacr.azurecr.io/currencyservice:my"
        "adrwalacr.azurecr.io/emailservice:my"
        "adrwalacr.azurecr.io/frontend:my"
        "adrwalacr.azurecr.io/loadgenerator:my"
        "adrwalacr.azurecr.io/paymentservice:my"
        "adrwalacr.azurecr.io/productcatalogservice:my"
        "adrwalacr.azurecr.io/recommendationservice:my"
        "adrwalacr.azurecr.io/shippingservice:my"
        "adrwalacr.azurecr.io/shoppingassistantservice:my"
    )
    for image in "${IMAGES[@]}"; do
        echo "============================================="
        echo "Scanning image: $image"
        trivy image --severity HIGH,CRITICAL --ignore-unfixed --quiet "$image"
        echo "============================================="
    done
fi
