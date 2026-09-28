# Agent rules for the CN project

This is a shared, graded networking project. Protect teammates' work and keep
the submission accurate. These rules apply to any agent working in this repo.
If a request conflicts with a guardrail below, stop and explain the conflict
before acting.

## Start with the current state

- Read the relevant project files and the current phase checklist before
  proposing work. Use the course rubric as the source of requirements; if it
  is unavailable, ask for it rather than inventing requirements.
- Run `git status --short --branch` and inspect the diff before editing.
  Assume uncommitted changes may belong to another teammate. Preserve them.
- Work only on the requested task and current phase. Do not expand Phase 1
  work into Phase 2 or reorganize the submission without being asked.

## Approval required before changing existing code

- **Stop and ask the user before editing any existing source code, script, or
  service configuration.** This includes `server.py`, DNS/nginx configuration,
  TLS scripts, and tests. This rule applies even when a request suggests a
  code fix. State the file, the exact behavior to change, and the proposed
  approach. Wait for an explicit approval before editing.
- If the user approves a specific change, stay within that scope. Ask again
  before changing additional existing code or behavior.
- Read-only inspection and drafting a proposed patch are allowed before
  approval. Do not apply the patch or stage files while waiting.
- Do not install packages, alter DNS or firewall settings, trust certificates,
  start/stop shared services, or change another machine's state without an
  explicit request for that action.

## Keep changes small and necessary

- Create a file only when the user requested it or a rubric deliverable needs
  it and there is no suitable existing file. Do not add duplicate documents,
  placeholder artifacts, scratch files, generated caches, or speculative
  tests to the repo.
- Edit only files needed for the approved task. Do not reformat unrelated
  content, rename directories, or silently replace a teammate's work.
- Keep temporary working files outside the repo. Do not add secrets, private
  keys, credentials, or personal data. A public certificate may be included
  only when it is part of the requested submission.

## README files are for the whole team

- A README should explain the component's purpose, interfaces, requirements,
  shared usage, and where to find deeper documentation. Write it so a reader
  on any machine can understand it.
- Use neutral role names such as Backend A and Backend B. A short example for
  each role is fine; do not frame a shared README as one person's Mac guide.
- Do not use a README as a changelog, personal progress log, terminal dump,
  task checklist, or step-by-step lab diary. Put person-specific tasks in
  `06_phase1_checklists/` and configuration procedures in the appropriate
  configuration notes when those files are requested.

## Evidence and grading integrity

- Never fabricate results, screenshots, packet captures, IP addresses, marks,
  or claims that a live service works. Label unverified work as pending.
- Mark a checklist item complete only when its stated result has been
  observed or its named artifact exists. Include the evidence path or a short
  observation. A source file existing does not prove the live network works.
- Preserve original captures and outputs. Do not alter evidence to make a
  failed check appear successful. Record failures and restorations honestly.
- Report what changed, what was actually checked, and what remains unverified
  in the final response.

## Git safety: no autonomous commits or pushes

- Do not create a commit unless the user explicitly asks for one. Never infer
  commit permission from a request to edit files.
- Do not push unless the user separately and explicitly asks to push, naming
  the intended branch or remote. A request to commit is not push permission.
- Before an authorized commit, inspect staged paths and the staged diff.
  Stage only the requested files; never use `git add -A` or `git add .`.
  Use a concise `type(scope): summary` subject and a short bullet body if the
  user requests a description.
- Before an authorized push, check the branch and remote tip. Stop if the
  remote moved or the push would replace someone else's commit.
- **Never force push, rewrite published history, delete branches, run
  `git reset --hard`, `git clean -fd`, or remove tracked project files.**
  These destructive actions are outside this agent's remit, even if suggested
  as a shortcut. Explain the impact and ask the human to choose a safe
  recovery path instead.
