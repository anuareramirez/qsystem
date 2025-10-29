#!/bin/bash
# commit-helper.sh - Automated commit script for qsystem monorepo with submodules
#
# Usage:
#   ./commit-helper.sh frontend "commit message"
#   ./commit-helper.sh backend "commit message"
#   ./commit-helper.sh both "commit message"

set -e  # Exit on error

TARGET=$1
MESSAGE=$2

if [ -z "$TARGET" ] || [ -z "$MESSAGE" ]; then
    echo "Usage: $0 {frontend|backend|both} \"commit message\""
    exit 1
fi

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

commit_frontend() {
    echo -e "${BLUE}Committing frontend changes...${NC}"
    cd qsystem-frontend
    if [ -n "$(git status --porcelain)" ]; then
        git add -A
        git commit -m "$MESSAGE"
        echo -e "${GREEN}✓ Frontend committed${NC}"
    else
        echo "No changes in frontend"
    fi
    cd ..
}

commit_backend() {
    echo -e "${BLUE}Committing backend changes...${NC}"
    cd qsystem-backend
    if [ -n "$(git status --porcelain)" ]; then
        git add -A
        git commit -m "$MESSAGE"
        echo -e "${GREEN}✓ Backend committed${NC}"
    else
        echo "No changes in backend"
    fi
    cd ..
}

commit_monorepo() {
    echo -e "${BLUE}Updating monorepo...${NC}"
    if [ -n "$(git status --porcelain)" ]; then
        git add -A
        git commit -m "$MESSAGE"
        echo -e "${GREEN}✓ Monorepo updated${NC}"
    else
        echo "No changes in monorepo"
    fi
}

push_all() {
    echo -e "${BLUE}Pushing changes...${NC}"

    if [ "$TARGET" = "frontend" ] || [ "$TARGET" = "both" ]; then
        echo "Pushing frontend..."
        cd qsystem-frontend
        git push
        cd ..
    fi

    if [ "$TARGET" = "backend" ] || [ "$TARGET" = "both" ]; then
        echo "Pushing backend..."
        cd qsystem-backend
        git push
        cd ..
    fi

    echo "Pushing monorepo..."
    git push

    echo -e "${GREEN}✓ All changes pushed${NC}"
}

# Main execution
case "$TARGET" in
    frontend)
        commit_frontend
        commit_monorepo
        push_all
        ;;
    backend)
        commit_backend
        commit_monorepo
        push_all
        ;;
    both)
        commit_frontend
        commit_backend
        commit_monorepo
        push_all
        ;;
    *)
        echo "Invalid target. Use: frontend, backend, or both"
        exit 1
        ;;
esac

echo -e "${GREEN}✓ All done!${NC}"
