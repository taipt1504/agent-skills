#!/bin/bash
# Git Repository Analyzer
#
# Usage:
#   ./analyze-repo.sh              # Full analysis
#   ./analyze-repo.sh --status     # Status only
#   ./analyze-repo.sh --history    # History analysis
#   ./analyze-repo.sh --branches   # Branch analysis
#   ./analyze-repo.sh --help
#
# Analyzes current git repository and provides insights

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_header() {
    echo ""
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
}

print_subheader() {
    echo ""
    echo -e "${CYAN}── $1 ──${NC}"
}

print_usage() {
    echo "Git Repository Analyzer"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --status     Show working tree status"
    echo "  --staged     Show staged changes details"
    echo "  --history    Show commit history analysis"
    echo "  --branches   Show branch analysis"
    echo "  --remotes    Show remote information"
    echo "  --all        Full analysis (default)"
    echo "  --json       Output in JSON format"
    echo "  --help       Show this help"
}

check_git_repo() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo -e "${RED}Error: Not a git repository${NC}"
        exit 1
    fi
}

analyze_status() {
    print_header "REPOSITORY STATUS"

    # Basic info
    local branch=$(git branch --show-current 2>/dev/null || echo "detached")
    local repo_root=$(git rev-parse --show-toplevel)
    local repo_name=$(basename "$repo_root")

    echo ""
    echo -e "Repository:  ${GREEN}$repo_name${NC}"
    echo -e "Branch:      ${GREEN}$branch${NC}"
    echo -e "Root:        $repo_root"

    # Remote tracking
    local upstream=$(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null || echo "none")
    echo -e "Upstream:    $upstream"

    # Ahead/behind
    if [ "$upstream" != "none" ]; then
        local ahead=$(git rev-list --count @{u}..HEAD 2>/dev/null || echo "0")
        local behind=$(git rev-list --count HEAD..@{u} 2>/dev/null || echo "0")
        echo -e "Ahead:       ${GREEN}$ahead${NC} commits"
        echo -e "Behind:      ${YELLOW}$behind${NC} commits"
    fi

    print_subheader "Working Tree"

    # Staged files
    local staged=$(git diff --cached --name-only | wc -l | tr -d ' ')
    # Unstaged changes
    local unstaged=$(git diff --name-only | wc -l | tr -d ' ')
    # Untracked files
    local untracked=$(git ls-files --others --exclude-standard | wc -l | tr -d ' ')

    echo -e "Staged:      ${GREEN}$staged${NC} files"
    echo -e "Unstaged:    ${YELLOW}$unstaged${NC} files"
    echo -e "Untracked:   ${CYAN}$untracked${NC} files"

    # Show file list if any
    if [ "$staged" -gt 0 ]; then
        print_subheader "Staged Files"
        git diff --cached --name-status | while read status file; do
            case $status in
                A) echo -e "  ${GREEN}[+]${NC} $file" ;;
                M) echo -e "  ${YELLOW}[~]${NC} $file" ;;
                D) echo -e "  ${RED}[-]${NC} $file" ;;
                R*) echo -e "  ${BLUE}[R]${NC} $file" ;;
                *) echo -e "  [?] $file" ;;
            esac
        done
    fi

    if [ "$unstaged" -gt 0 ]; then
        print_subheader "Unstaged Changes"
        git diff --name-status | head -20 | while read status file; do
            case $status in
                M) echo -e "  ${YELLOW}[~]${NC} $file" ;;
                D) echo -e "  ${RED}[-]${NC} $file" ;;
                *) echo -e "  [?] $file" ;;
            esac
        done
        if [ "$unstaged" -gt 20 ]; then
            echo "  ... and $((unstaged - 20)) more"
        fi
    fi

    if [ "$untracked" -gt 0 ] && [ "$untracked" -lt 20 ]; then
        print_subheader "Untracked Files"
        git ls-files --others --exclude-standard | head -20 | while read file; do
            echo -e "  ${CYAN}[?]${NC} $file"
        done
    fi
}

analyze_staged() {
    print_header "STAGED CHANGES ANALYSIS"

    local staged=$(git diff --cached --name-only | wc -l | tr -d ' ')

    if [ "$staged" -eq 0 ]; then
        echo -e "${YELLOW}No staged changes${NC}"
        return
    fi

    # Stats
    print_subheader "Statistics"
    git diff --cached --shortstat

    # By file type
    print_subheader "By File Type"
    git diff --cached --name-only | sed 's/.*\.//' | sort | uniq -c | sort -rn | head -10

    # Changes breakdown
    print_subheader "Changes Breakdown"
    echo ""
    printf "%-50s %10s %10s\n" "File" "Added" "Removed"
    echo "──────────────────────────────────────────────────────────────────────"
    git diff --cached --numstat | while read added removed file; do
        if [ "$added" = "-" ]; then added="binary"; fi
        if [ "$removed" = "-" ]; then removed="binary"; fi
        printf "%-50s %10s %10s\n" "${file:0:50}" "$added" "$removed"
    done | head -20

    # Detect change type
    print_subheader "Detected Change Type"

    local has_feat=false
    local has_fix=false
    local has_docs=false
    local has_test=false
    local has_style=false
    local has_refactor=false

    # Check for new features (new files, new functions)
    if git diff --cached --name-status | grep -q '^A'; then
        has_feat=true
        echo -e "  ${GREEN}✓${NC} New files added (possible feat)"
    fi

    # Check for docs
    if git diff --cached --name-only | grep -qE '\.(md|txt|rst|doc)$'; then
        has_docs=true
        echo -e "  ${GREEN}✓${NC} Documentation changes"
    fi

    # Check for tests
    if git diff --cached --name-only | grep -qE '(test|spec)\.(js|ts|py|java|rb)$'; then
        has_test=true
        echo -e "  ${GREEN}✓${NC} Test files changed"
    fi

    # Check for style/config
    if git diff --cached --name-only | grep -qE '\.(json|ya?ml|toml|ini|eslintrc|prettierrc)$'; then
        has_style=true
        echo -e "  ${GREEN}✓${NC} Configuration/style files"
    fi

    # Check for potential bug fixes (small changes to existing files)
    local changes=$(git diff --cached --shortstat | grep -oE '[0-9]+ insertion|[0-9]+ deletion' | head -1)
    if [ -n "$changes" ]; then
        local num=$(echo "$changes" | grep -oE '[0-9]+')
        if [ "$num" -lt 20 ]; then
            echo -e "  ${YELLOW}?${NC} Small change (possible fix or refactor)"
        fi
    fi
}

analyze_history() {
    print_header "COMMIT HISTORY ANALYSIS"

    # Recent commits
    print_subheader "Recent Commits (last 10)"
    git log --oneline --graph -10

    # Commit frequency
    print_subheader "Commits by Author (last 30 days)"
    git shortlog -sn --since="30 days ago" | head -10

    # Commit types (if using conventional commits)
    print_subheader "Commit Types (last 50 commits)"
    git log --oneline -50 | grep -oE '^[a-f0-9]+ (feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)' | \
        cut -d' ' -f2 | sort | uniq -c | sort -rn || echo "No conventional commits detected"

    # Most changed files
    print_subheader "Most Changed Files (last 100 commits)"
    git log --pretty=format: --name-only -100 | sort | uniq -c | sort -rn | head -10
}

analyze_branches() {
    print_header "BRANCH ANALYSIS"

    # Current branch
    local current=$(git branch --show-current 2>/dev/null || echo "detached")
    echo -e "Current: ${GREEN}$current${NC}"

    # Local branches
    print_subheader "Local Branches"
    git branch -v | head -20

    # Remote branches
    print_subheader "Remote Branches"
    git branch -r | head -20

    # Merged branches
    print_subheader "Merged Branches (safe to delete)"
    git branch --merged | grep -v "^\*" | grep -v "main\|master\|develop" | head -10 || echo "None"

    # Stale branches (no commits in 30 days)
    print_subheader "Potentially Stale Branches"
    for branch in $(git branch --format='%(refname:short)' | head -20); do
        last_commit=$(git log -1 --format='%cr' "$branch" 2>/dev/null)
        if echo "$last_commit" | grep -qE '(month|year)'; then
            echo -e "  ${YELLOW}$branch${NC} - last commit: $last_commit"
        fi
    done
}

analyze_remotes() {
    print_header "REMOTE ANALYSIS"

    # List remotes
    print_subheader "Configured Remotes"
    git remote -v

    # Fetch status
    print_subheader "Remote Status"
    for remote in $(git remote); do
        echo -e "\n${CYAN}$remote:${NC}"
        git remote show "$remote" 2>/dev/null | grep -E '(Fetch|Push|HEAD|tracks)' | head -10
    done
}

output_json() {
    echo "{"
    echo "  \"repository\": \"$(basename $(git rev-parse --show-toplevel))\","
    echo "  \"branch\": \"$(git branch --show-current 2>/dev/null || echo 'detached')\","
    echo "  \"staged\": $(git diff --cached --name-only | wc -l | tr -d ' '),"
    echo "  \"unstaged\": $(git diff --name-only | wc -l | tr -d ' '),"
    echo "  \"untracked\": $(git ls-files --others --exclude-standard | wc -l | tr -d ' '),"
    echo "  \"ahead\": $(git rev-list --count @{u}..HEAD 2>/dev/null || echo 0),"
    echo "  \"behind\": $(git rev-list --count HEAD..@{u} 2>/dev/null || echo 0),"
    echo "  \"staged_files\": ["
    git diff --cached --name-only | sed 's/.*/"&"/' | paste -sd, -
    echo "  ]"
    echo "}"
}

# Main
main() {
    check_git_repo

    case "${1:-all}" in
        --help|-h)
            print_usage
            ;;
        --status)
            analyze_status
            ;;
        --staged)
            analyze_staged
            ;;
        --history)
            analyze_history
            ;;
        --branches)
            analyze_branches
            ;;
        --remotes)
            analyze_remotes
            ;;
        --json)
            output_json
            ;;
        --all|*)
            analyze_status
            analyze_staged
            analyze_branches
            ;;
    esac
}

main "$@"
