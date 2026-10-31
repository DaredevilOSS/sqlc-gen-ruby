#!/usr/bin/env bash
# Prints the version a release would get: next_version.sh <patch|minor|major> [explicit vX.Y.Z]
# The latest `vX.Y.Z` git tag is the current version (v0.0.0 when there is none yet).
set -euo pipefail

bump=${1:?usage: next_version.sh <patch|minor|major> [vX.Y.Z]}
explicit=${2:-}

latest=$(git tag --list 'v[0-9]*.[0-9]*.[0-9]*' | sort -V | tail -n 1)
latest=${latest:-v0.0.0}

if [[ -n "${explicit}" ]]; then
  [[ "${explicit}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "'${explicit}' is not of the form vX.Y.Z" >&2; exit 1; }
  next=${explicit}
else
  IFS=. read -r major minor patch <<< "${latest#v}"
  case "${bump}" in
    major) next="v$((major + 1)).0.0" ;;
    minor) next="v${major}.$((minor + 1)).0" ;;
    patch) next="v${major}.${minor}.$((patch + 1))" ;;
    *) echo "bump must be patch, minor or major (got '${bump}')" >&2; exit 1 ;;
  esac
fi

if git rev-parse -q --verify "refs/tags/${next}" > /dev/null; then
  echo "tag ${next} already exists" >&2; exit 1
fi
newest=$(printf '%s\n%s\n' "${latest}" "${next}" | sort -V | tail -n 1)
[[ "${newest}" == "${next}" ]] || { echo "${next} is not newer than the latest release ${latest}" >&2; exit 1; }

echo "latest=${latest}" >&2
echo "${next}"
