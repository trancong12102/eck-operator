#!/bin/bash
set -e

cd remote

# Get latest release tag
VERSION=$(curl -s "https://api.github.com/repos/elastic/cloud-on-k8s/releases/latest" | jq -r .tag_name)
if [ -z "$VERSION" ]; then
  echo "Failed to get latest release tag"
  exit 1
fi

REGISTRY=ghcr.io
REPO=elastic-ee/eck-operator
OPERATOR_IMAGE=$REGISTRY/$REPO:$VERSION
LATEST_IMAGE=$REGISTRY/$REPO:latest

# Check if the version is already built
TOKEN=$(curl -s https://ghcr.io/token\?scope\="repository:$REPO:pull" | jq -r .token)
if curl -f -s -H "Authorization: Bearer $TOKEN" https://ghcr.io/v2/$REPO/manifests/$VERSION >/dev/null; then
  echo "Image $OPERATOR_IMAGE already exists"
  exit 0
fi

git add .
git reset --hard
git fetch origin --tags
git checkout "$VERSION"
git pull origin "$VERSION"

# check.go file path
FILE="./pkg/controller/common/license/check.go"

# Remove the body of the method and keep only `return true, nil`
perl -0777 -pi -e 's/(func.*Valid.*\(bool, error\)) ({\n(.*\n)*?})/\1 { return true, nil }/' $FILE

# Remove "time" import
perl -0777 -pi -e 's/.*"time"\n//g' $FILE

SHA1=$(git rev-parse --short=8 --verify HEAD)
GO_LDFLAGS="-X github.com/elastic/cloud-on-k8s/v2/pkg/about.version=$VERSION \
  -X github.com/elastic/cloud-on-k8s/v2/pkg/about.buildHash=$SHA1 \
  -X github.com/elastic/cloud-on-k8s/v2/pkg/about.buildDate=$(date -u +'%Y-%m-%dT%H:%M:%SZ') \
  -X github.com/elastic/cloud-on-k8s/v2/pkg/about.buildSnapshot=false"

docker buildx build . \
  -f build/Dockerfile \
  --build-arg GO_LDFLAGS="$GO_LDFLAGS" \
  --build-arg GO_TAGS='' \
  --build-arg VERSION="$VERSION" \
  --push \
  --cache-from type=registry,ref=$LATEST_IMAGE \
  -t $OPERATOR_IMAGE

docker tag $OPERATOR_IMAGE $LATEST_IMAGE
docker push $LATEST_IMAGE

git add .
git reset --hard
