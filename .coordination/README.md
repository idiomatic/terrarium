# Coordination

How agents working on this project at once share what they're doing and claim what only one may use. This README and [lock.zig](lock.zig) are committed; `sessions/` and `locks/` are ignored and live only in the main worktree's `.coordination/` (`<root>`, the parent of `git rev-parse --path-format=absolute --git-common-dir`), so every worktree shares them.

* **Worktrees:** every change, small fixes too, is made in a worktree of its own, on a branch (a detached one has nothing to merge), and lands on `main` by fast-forward; the main worktree's files are only merged into, never edited, so no agent's edits meet another's merge.
* **Sessions:** `<root>/.coordination/sessions/<session>.md`, one per agent: its work, worktree, and claims; deleted when done. Read them all before starting.
* **Locks:** `zig run .coordination/lock.zig -- COMMAND` (Zig 0.17, from any worktree) takes, renews, releases, and lists them. Locks are advisory. Each has an owner (the session), an expiry (30 minutes by default; renew long ones), and a note (`LOCK_NOTE`); an expired one may be taken over, as its owner may have crashed. The tool runs from source, not prebuilt, so it can't go stale (about 70 ms cached).
* **What to lock:** shared resources, not files (worktrees keep those apart):
  * `main`: merging into `main`, folding, and proposing pushes; not building or testing, which a worktree does first
  * `support`: the shared support directory (`~/Library/Application Support/terrarium`) when changing what other sessions use (removing or replacing images and layers, `network --remove`); VMs started there need no lock, as `ps` tells whose each is, and tests with `$TERRARIUM_SUPPORT` use a directory of their own
  * `vm-memory`: starting a macOS or Windows VM, as two at once with the others can push the Mac into swap
* **Quiet:** don't report notes, locks, or other sessions' routine work; mention coordination only when it changes what the user gets: waiting on another session's lock (what, and for whom), a conflict, or a stale lock taken over.
