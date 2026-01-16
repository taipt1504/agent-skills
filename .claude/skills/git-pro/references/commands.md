# Git Commands Reference

## Basic Commands

### Status & Info

```bash
git status                    # Working tree status
git status -s                 # Short format
git status -sb                # Short + branch info

git log                       # Commit history
git log --oneline            # One line per commit
git log --graph              # ASCII graph
git log -n 10                # Last 10 commits
git log --stat               # With file stats
git log -p                   # With patches

git show <commit>            # Show commit details
git show --stat <commit>     # Commit with stats

git diff                     # Unstaged changes
git diff --staged            # Staged changes (--cached)
git diff <commit1> <commit2> # Between commits
git diff <branch1> <branch2> # Between branches
```

### Adding & Committing

```bash
git add <file>               # Stage specific file
git add .                    # Stage all changes
git add -p                   # Interactive staging
git add -A                   # Stage all (including deletes)

git commit -m "message"      # Commit with message
git commit -am "message"     # Add tracked + commit
git commit --amend           # Amend last commit
git commit --amend -m "new"  # Amend with new message
git commit --no-verify       # Skip hooks
git commit --allow-empty     # Empty commit
```

### Branches

```bash
git branch                   # List local branches
git branch -a                # List all branches
git branch -v                # With last commit
git branch <name>            # Create branch
git branch -d <name>         # Delete (safe)
git branch -D <name>         # Delete (force)
git branch -m <old> <new>    # Rename branch
git branch --merged          # Merged branches
git branch --no-merged       # Unmerged branches
```

### Checkout & Switch

```bash
git checkout <branch>        # Switch branch
git checkout -b <branch>     # Create & switch
git checkout -- <file>       # Discard changes
git checkout <commit>        # Detached HEAD

# Modern alternatives (Git 2.23+)
git switch <branch>          # Switch branch
git switch -c <branch>       # Create & switch
git restore <file>           # Discard changes
git restore --staged <file>  # Unstage file
```

---

## Remote Operations

### Remote Management

```bash
git remote                   # List remotes
git remote -v                # With URLs
git remote add <name> <url>  # Add remote
git remote remove <name>     # Remove remote
git remote rename <old> <new> # Rename
git remote set-url <name> <url> # Change URL
git remote show <name>       # Remote details
```

### Fetch & Pull

```bash
git fetch                    # Fetch all remotes
git fetch <remote>           # Fetch specific
git fetch --prune            # Prune stale refs
git fetch --all              # All remotes

git pull                     # Fetch + merge
git pull --rebase            # Fetch + rebase
git pull --ff-only           # Only fast-forward
git pull <remote> <branch>   # Specific remote/branch
```

### Push

```bash
git push                     # Push current branch
git push <remote> <branch>   # Push specific
git push -u origin <branch>  # Set upstream
git push --force             # Force push (DANGEROUS)
git push --force-with-lease  # Safer force push
git push --tags              # Push tags
git push --delete <remote> <branch> # Delete remote branch
```

---

## Merging & Rebasing

### Merge

```bash
git merge <branch>           # Merge branch
git merge --no-ff <branch>   # No fast-forward
git merge --squash <branch>  # Squash merge
git merge --abort            # Abort merge
git merge --continue         # Continue after resolve
```

### Rebase

```bash
git rebase <branch>          # Rebase onto branch
git rebase -i HEAD~n         # Interactive rebase
git rebase --onto <new> <old> # Rebase range
git rebase --abort           # Abort rebase
git rebase --continue        # Continue rebase
git rebase --skip            # Skip commit
```

### Interactive Rebase Commands

```
pick   - use commit
reword - change message
edit   - stop to amend
squash - meld into previous
fixup  - meld, discard message
exec   - run command
drop   - remove commit
```

---

## Stash

```bash
git stash                    # Stash changes
git stash push -m "message"  # Stash with message
git stash -u                 # Include untracked
git stash -a                 # Include ignored

git stash list               # List stashes
git stash show               # Show latest stash
git stash show -p            # Show with diff
git stash show stash@{n}     # Show specific

git stash apply              # Apply latest
git stash apply stash@{n}    # Apply specific
git stash pop                # Apply & drop
git stash drop               # Drop latest
git stash drop stash@{n}     # Drop specific
git stash clear              # Drop all
git stash branch <name>      # Create branch from stash
```

---

## Reset & Revert

### Reset

```bash
git reset HEAD <file>        # Unstage file
git reset --soft HEAD~1      # Undo commit, keep staged
git reset HEAD~1             # Undo commit, keep unstaged
git reset --hard HEAD~1      # Undo commit, discard all
git reset --hard <commit>    # Reset to commit
git reset --hard origin/main # Reset to remote
```

### Revert

```bash
git revert <commit>          # Revert commit
git revert -n <commit>       # Revert without commit
git revert HEAD~3..HEAD      # Revert range
git revert -m 1 <merge>      # Revert merge commit
```

---

## Tags

```bash
git tag                      # List tags
git tag -l "v1.*"            # Filter tags
git tag <name>               # Lightweight tag
git tag -a <name> -m "msg"   # Annotated tag
git tag -a <name> <commit>   # Tag specific commit

git show <tag>               # Show tag
git push origin <tag>        # Push tag
git push origin --tags       # Push all tags
git tag -d <name>            # Delete local
git push origin :refs/tags/<name> # Delete remote
```

---

## Advanced Commands

### Cherry-pick

```bash
git cherry-pick <commit>     # Apply commit
git cherry-pick -n <commit>  # Apply without commit
git cherry-pick -x <commit>  # Add "cherry picked" note
git cherry-pick A..B         # Range (exclusive A)
git cherry-pick A^..B        # Range (inclusive A)
git cherry-pick --abort      # Abort
git cherry-pick --continue   # Continue
```

### Bisect

```bash
git bisect start             # Start bisect
git bisect bad               # Mark bad
git bisect good <commit>     # Mark good
git bisect reset             # End bisect
git bisect run <script>      # Automated bisect
```

### Worktree

```bash
git worktree list            # List worktrees
git worktree add <path> <branch> # Add worktree
git worktree remove <path>   # Remove worktree
git worktree prune           # Cleanup
```

### Submodules

```bash
git submodule add <url> <path> # Add submodule
git submodule init           # Initialize
git submodule update         # Update
git submodule update --init --recursive # Init + update
git submodule foreach <cmd>  # Run command in each
```

---

## Search & Find

### Log Search

```bash
git log --grep="pattern"     # Search messages
git log -S "code"            # Search code changes
git log -G "regex"           # Search with regex
git log --author="name"      # By author
git log --since="2 weeks"    # By date
git log -- <path>            # By path
```

### Blame & Annotate

```bash
git blame <file>             # Line-by-line authorship
git blame -L 10,20 <file>    # Lines 10-20
git blame -w <file>          # Ignore whitespace
git annotate <file>          # Same as blame
```

### Find Files

```bash
git ls-files                 # Tracked files
git ls-files --others        # Untracked files
git ls-files --deleted       # Deleted files
git ls-tree -r HEAD          # Tree listing
```

---

## Cleanup

```bash
git clean -n                 # Dry run
git clean -f                 # Remove untracked files
git clean -fd                # Remove untracked + dirs
git clean -fx                # Include ignored

git gc                       # Garbage collect
git gc --aggressive          # Aggressive cleanup
git prune                    # Prune loose objects

git reflog                   # Reference logs
git reflog expire --expire=now --all # Expire reflogs
```

---

## Configuration

```bash
git config --list            # List all
git config --global --list   # Global only
git config <key>             # Get value
git config <key> <value>     # Set value
git config --unset <key>     # Remove key

# Scopes
--local                      # Repository
--global                     # User
--system                     # System-wide
```
