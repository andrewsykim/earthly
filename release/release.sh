#!/bin/bash
set -ex

# earthly does not (yet) have fine control over controlling the order of RUN --push commands (they all happen at the end)
# Our release process requires the following commands be done in order:
# - uploading binaries to github (as a --push command)
# - pushing a new commit to the earthly/earthly-homebrew repo
# - downloading the binaries from github and existing binaries from s3 buckets
# - signing those apt and yum packages containing those binaries
# - and pushing signed up to s3 buckets (which back our apt and yum repos)

# Args
#   Required
#     RELEASE_TAG
#   Optional
#     GITHUB_USER         override the default earthly github user
#     DOCKERHUB_USER      override the default earthly dockerhub user
#     EARTHLY_REPO        override the default earthly repo name
#     BREW_REPO           override the default homebrew-earthly repo name
#     GITHUB_SECRET_PATH  override the default +secrets/earthly-technologies/github/griswoldthecat/token secrets location where the github token is stored
#
# for example
#  RELEASE_TAG=v0.5.10 GITHUB_USER=alexcb DOCKERHUB_USER=alexcb132 EARTHLY_REPO=earthly BREW_REPO=homebrew-earthly-1 ./release.sh

SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
cd $SCRIPT_DIR

test -n "$RELEASE_TAG" || (echo "ERROR: RELEASE_TAG is not set" && exit 1);
(echo "$RELEASE_TAG" | grep '^v[0-9]\+.[0-9]\+.[0-9]\+$' > /dev/null) || (echo "ERROR: RELEASE_TAG must be formatted as v1.2.3; instead got \"$RELEASE_TAG\""; exit 1);

# Set default values
export GITHUB_USER=${GITHUB_USER:-earthly}
export DOCKERHUB_USER=${DOCKERHUB_USER:-earthly}
export EARTHLY_REPO=${EARTHLY_REPO:-earthly}
export BREW_REPO=${BREW_REPO:-homebrew-earthly}
export GITHUB_SECRET_PATH=$GITHUB_SECRET_PATH

../earthly upgrade

if [ -n "$GITHUB_SECRET_PATH" ]; then
    GITHUB_SECRET_PATH_BUILD_ARG="--build-arg GITHUB_SECRET_PATH=$GITHUB_SECRET_PATH"
else
    (../earthly secrets ls /earthly-technologies >/dev/null) || (echo "ERROR: current user does not have access to earthly-technologies shared secrets"; exit 1);
fi

(../earthly secrets get /user/earthly-technologies/aws/credentials >/dev/null) || (echo "ERROR: user-secrets /user/earthly-technologies/aws/credentials does not exist"; exit 1);

existing_release=$(curl -s https://api.github.com/repos/earthly/earthly/releases/tags/$RELEASE_TAG | jq -r .tag_name)
if [ "$existing_release" != "null" ]; then
    test "$OVERWRITE_RELEASE" = "1" || (echo "a release for $RELEASE_TAG already exists, to proceed with overwriting this release set OVERWRITE_RELEASE=1" && exit 1);
    echo "overwriting existing release for $RELEASE_TAG"
fi

../earthly --push --build-arg DOCKERHUB_USER --build-arg RELEASE_TAG +release-dockerhub
../earthly --push --build-arg GITHUB_USER --build-arg EARTHLY_REPO --build-arg BREW_REPO --build-arg DOCKERHUB_USER --build-arg RELEASE_TAG $GITHUB_SECRET_PATH_BUILD_ARG +release-github
../earthly --push --build-arg GITHUB_USER --build-arg EARTHLY_REPO --build-arg BREW_REPO --build-arg DOCKERHUB_USER --build-arg RELEASE_TAG $GITHUB_SECRET_PATH_BUILD_ARG +release-homebrew

# TODO pass along a RELEASE_REPO_TEST_SUFFIX which would cause us to host our yum/apt repos under https://test-pkg.earthly.dev/$RELEASE_REPO_TEST_SUFFIX/...
# and when it is empty, we would use https://pkg.earthly.dev/...
#../earthly --push --build-arg GITHUB_USER --build-arg EARTHLY_REPO --build-arg BREW_REPO --build-arg DOCKERHUB_USER --build-arg RELEASE_TAG +release-repo
# until then, we will just print this out:
echo "TODO: the apt/yum release must be triggered seperately; until we get https://test-pkg.earthly.dev/ setup"
