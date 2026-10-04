#!/usr/bin/env bash
set -euo pipefail

# scripts/bump_version.sh
# Usage:
#   ./scripts/bump_version.sh <major|minor|patch> [--build <build-number>] [--tag] [--push]
# Examples:
#   ./scripts/bump_version.sh patch
#   ./scripts/bump_version.sh minor --build 10 --tag --push

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLIST_PATH="$REPO_ROOT/VibeScribe/Info.plist"
PBXPROJ_PATH="$REPO_ROOT/VibeScribe.xcodeproj/project.pbxproj"

if [ ! -f "$PLIST_PATH" ]; then
  echo "Info.plist not found at $PLIST_PATH"
  exit 1
fi

BUMP_PART=""
BUILD_NUMBER=""
BUILD_EXPLICIT=false
DO_TAG=false
DO_PUSH=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --build)
      if [[ $# -lt 2 ]]; then
        echo "Missing build number after --build"
        exit 1
      fi
      BUILD_NUMBER="$2"
      BUILD_EXPLICIT=true
      shift 2
      ;;
    --tag)
      DO_TAG=true
      shift
      ;;
    --push)
      DO_PUSH=true
      shift
      ;;
    -*|--*)
      echo "Unknown option $1"
      exit 1
      ;;
    *)
      if [ -z "$BUMP_PART" ]; then
        BUMP_PART="$1"
      else
        echo "Unexpected argument: $1"
        exit 1
      fi
      shift
      ;;
  esac
done

# Validate bump part
if [[ -z "$BUMP_PART" ]]; then
  echo "Usage: $0 <major|minor|patch> [--build <build-number>] [--tag] [--push]"
  exit 1
fi

if [[ ! "$BUMP_PART" =~ ^(major|minor|patch)$ ]]; then
  echo "Invalid bump part: $BUMP_PART. Use major, minor, or patch."
  exit 1
fi
if [[ "$BUILD_EXPLICIT" == true && ! "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "Build number must be a nonnegative integer"
  exit 1
fi

# Read MARKETING_VERSION from project.pbxproj (choose the highest X.Y.Z found, default 0.0.0)
if [ ! -f "$PBXPROJ_PATH" ]; then
  echo "Xcode project not found at $PBXPROJ_PATH"
  exit 1
fi

MV_LIST=$(grep -Eo 'MARKETING_VERSION = [0-9]+\.[0-9]+\.[0-9]+' "$PBXPROJ_PATH" | awk '{print $3}')
if [ -z "$MV_LIST" ]; then
  CURRENT_VERSION="0.0.0"
else
  CURRENT_VERSION="0.0.0"
  while IFS= read -r v; do
    if [[ "$v" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
      IFS='.' read -r a b c <<< "$v"
      IFS='.' read -r ca cb cc <<< "$CURRENT_VERSION"
      if (( a>ca || (a==ca && b>cb) || (a==ca && b==cb && c>cc) )); then
        CURRENT_VERSION="$v"
      fi
    fi
  done <<< "$MV_LIST"
fi

if [[ ! "$CURRENT_VERSION" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
  echo "Current MARKETING_VERSION ('$CURRENT_VERSION') is not in X.Y.Z format. Resetting to 0.0.0"
  MAJOR=0
  MINOR=0
  PATCH=0
else
  MAJOR=${BASH_REMATCH[1]}
  MINOR=${BASH_REMATCH[2]}
  PATCH=${BASH_REMATCH[3]}
fi

case "$BUMP_PART" in
  major)
    MAJOR=$((MAJOR + 1))
    MINOR=0
    PATCH=0
    ;;
  minor)
    MINOR=$((MINOR + 1))
    PATCH=0
    ;;
  patch)
    PATCH=$((PATCH + 1))
    ;;
esac

NEW_VERSION="$MAJOR.$MINOR.$PATCH"

# Resolve and validate the effective build before changing either version source.
PROJECT_BUILDS=$(grep -Eo 'CURRENT_PROJECT_VERSION = [0-9]+;' "$PBXPROJ_PATH" | sed -E 's/.*= ([0-9]+);/\1/' || true)
if [[ -z "$PROJECT_BUILDS" ]]; then
  echo "No numeric CURRENT_PROJECT_VERSION found in project"
  exit 1
fi
if [[ "$BUILD_EXPLICIT" == true ]]; then
  NEXT_BUILD="$BUILD_NUMBER"
else
  CURRENT_BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST_PATH" 2>/dev/null || echo "")
  if [[ "$CURRENT_BUILD" == '$(CURRENT_PROJECT_VERSION)' ]]; then
    CURRENT_BUILD=0
    while IFS= read -r build; do
      if (( 10#$build > CURRENT_BUILD )); then
        CURRENT_BUILD=$((10#$build))
      fi
    done <<< "$PROJECT_BUILDS"
  elif [[ "$CURRENT_BUILD" =~ ^[0-9]+$ ]]; then
    CURRENT_BUILD=$((10#$CURRENT_BUILD))
  else
    echo "CFBundleVersion must be numeric or \$(CURRENT_PROJECT_VERSION)"
    exit 1
  fi
  NEXT_BUILD=$((CURRENT_BUILD + 1))
  if (( NEXT_BUILD <= CURRENT_BUILD )); then
    echo "Build number cannot be incremented safely"
    exit 1
  fi
fi

echo "Bumping version: $CURRENT_VERSION -> $NEW_VERSION"

# Update MARKETING_VERSION in project.pbxproj (all occurrences)
echo "Updating MARKETING_VERSION in project to $NEW_VERSION"
LC_ALL=C sed -i '' -E "s/(MARKETING_VERSION = )[0-9]+\.[0-9]+\.[0-9]+;/\\1$NEW_VERSION;/g" "$PBXPROJ_PATH"
echo "Updating CURRENT_PROJECT_VERSION in project to $NEXT_BUILD"
LC_ALL=C sed -i '' -E "s/(CURRENT_PROJECT_VERSION = )[0-9]+;/\\1$NEXT_BUILD;/g" "$PBXPROJ_PATH"

# Ensure Info.plist uses $(MARKETING_VERSION) as CFBundleShortVersionString
PLIST_SHORT_VER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST_PATH" 2>/dev/null || echo "")
if [ "$PLIST_SHORT_VER" != '$(MARKETING_VERSION)' ]; then
  echo 'Setting Info.plist CFBundleShortVersionString to $(MARKETING_VERSION)'
  /usr/libexec/PlistBuddy -c 'Set :CFBundleShortVersionString $(MARKETING_VERSION)' "$PLIST_PATH"
fi

/usr/libexec/PlistBuddy -c 'Set :CFBundleVersion $(CURRENT_PROJECT_VERSION)' "$PLIST_PATH"

git -C "$REPO_ROOT" add "$PLIST_PATH" "$PBXPROJ_PATH"
echo "Review and commit the updated project files (Info.plist and project.pbxproj) manually."

# Tagging (tags are created on current HEAD; ensure you've committed changes before tagging)
if [ "$DO_TAG" = true ]; then
  TAG_NAME="v$NEW_VERSION"
  echo "Creating tag $TAG_NAME on current HEAD (ensure you've committed)."
  git -C "$REPO_ROOT" tag -a "$TAG_NAME" -m "Release $TAG_NAME"
  if [ "$DO_PUSH" = true ]; then
    echo "Pushing tag $TAG_NAME to origin"
    git -C "$REPO_ROOT" push origin "$TAG_NAME"
  fi
else
  if [ "$DO_PUSH" = true ]; then
    echo "Pushing current branch to origin"
    git -C "$REPO_ROOT" push
  fi
fi

echo "Done. Info.plist updated at $PLIST_PATH"
