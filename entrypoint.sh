#!/bin/sh
set -eu

cd "${GITHUB_WORKSPACE}" || exit

# Apply hotfix for 'fatal: unsafe repository' error (see #10).
git config --global --add safe.directory "${GITHUB_WORKSPACE}"

if [ -z "${INPUT_TAG}" ]; then
  echo "[action-create-tag] No-tag was supplied! Please supply a tag."
  exit 1
fi

# Set up variables.
FLAGS=""
TAG=$(echo "${INPUT_TAG}" | sed 's/ /_/g')
ACTION_OUTPUT_MESSAGE="[action-create-tag] Push tag '${TAG}'"
MESSAGE="${INPUT_MESSAGE:-Release ${TAG}}"
FORCE_TAG="${INPUT_FORCE_PUSH_TAG:-false}"
TAG_EXISTS_ERROR="${INPUT_TAG_EXISTS_ERROR:-true}"
NO_VERIFY="${INPUT_NO_VERIFY_TAG:-false}"
SHA=${INPUT_COMMIT_SHA:-${GITHUB_SHA}}
GPG_PRIVATE_KEY="${INPUT_GPG_PRIVATE_KEY:-}"
GPG_PASSPHRASE="${INPUT_GPG_PASSPHRASE:-}"

# Configure git and gpg if GPG key is provided.
if [ -n "${GPG_PRIVATE_KEY}" ]; then
  # Import the GPG key.
  echo "[action-update-semver] Importing GPG key."
  echo "${GPG_PRIVATE_KEY}" | gpg --batch --yes --import

  # If GPG_PASSPHRASE is set, unlock the key.
  if [ -n "${GPG_PASSPHRASE}" ]; then
    echo "[action-update-semver] Unlocking GPG key."
    echo "${GPG_PASSPHRASE}" | gpg --batch --yes --pinentry-mode loopback --passphrase-fd 0 --output /dev/null --sign
  fi

  # Retrieve GPG key information.
  public_key_id=$(gpg --list-secret-keys --keyid-format=long | grep sec | awk '{print $2}' | cut -d'/' -f2)
  signing_key_email=$(gpg --list-keys --keyid-format=long "${public_key_id}" | grep uid | sed 's/.*<\(.*\)>.*/\1/')
  signing_key_username=$(gpg --list-keys --keyid-format=long "${public_key_id}" | grep uid | sed 's/uid\s*\[\s*.*\]\s*//; s/\s*(.*//')

  # Setup git user name, email, and signingkey.
  echo "[action-update-semver] Setup git user name, email, and signingkey."
  git config --global user.name "${signing_key_username}"
  git config --global user.email "${signing_key_email}"
  git config --global user.signingkey "${public_key_id}"
  git config --global commit.gpgsign true
  git config --global tag.gpgSign true
else
  # Setup git user name and email.
  echo "[action-update-semver] Setup git user name and email."
  git config --global user.name "${GITHUB_ACTOR}"
  git config --global user.email "${GITHUB_ACTOR}@users.noreply.github.com"
fi

# Check if tag already exists.
if [ "$(git tag -l "${TAG}")"  ]; then tag_exists=true; else tag_exists=false; fi
echo "tag_exists=${tag_exists}" >> "${GITHUB_OUTPUT}"
echo "TAG_EXISTS=${tag_exists}" >> "${GITHUB_ENV}"

# Create tag and handle force push action input.
echo "[action-create-tag] Create tag '${TAG}'."
[ "${tag_exists}" = 'true' ] && echo "[action-create-tag] Tag '${TAG}' already exists."
if [ "${FORCE_TAG}" = 'true' ]; then
  [ "${tag_exists}" = 'true' ] && echo "[action-create-tag] Overwriting tag '${TAG}' since 'force_push_tag' is set to 'true'."
  git tag -f "${TAG}" "${SHA}"
  FLAGS="${FLAGS} --force"
  ACTION_OUTPUT_MESSAGE="${ACTION_OUTPUT_MESSAGE}, with --force"
else
  if [ "${tag_exists}" = 'true' ]; then
    echo "[action-create-tag] Please set 'force_push_tag' to 'true' if you want to overwrite it."
    if [ "${TAG_EXISTS_ERROR}" = 'true' ]; then
      echo "[action-create-tag] Throwing an error. Please set 'tag_exists_error' to 'false' if you want to ignore this error."
      exit 1
    fi
    echo "[action-create-tag] Ignoring error since 'tag_exists_error' is set to 'false'."
  else
    git tag "${TAG}" "${SHA}"
  fi
fi

# Set up remote URL for checkout@v1 action.
if [ -n "${INPUT_GITHUB_TOKEN}" ]; then
  git remote set-url origin "https://${GITHUB_ACTOR}:${INPUT_GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git"
fi

# Handle no-verify action input.
if [ "${NO_VERIFY}" = 'true' ]; then
  FLAGS="${FLAGS} --no-verify"
  ACTION_OUTPUT_MESSAGE="${ACTION_OUTPUT_MESSAGE}, with --no-verify"
fi

# Push tag.
[ "${tag_exists}" = 'true' ] && [ "${FORCE_TAG}" = 'false' ] && exit 0
echo "${ACTION_OUTPUT_MESSAGE}"
# shellcheck disable=SC2086
git push $FLAGS origin "$TAG"
