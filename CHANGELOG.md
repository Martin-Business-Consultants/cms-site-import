# Changelog

Releases are git tags (`v0.1.0`) with a GitHub release whose notes are the
section below.

## 0.1.0

- **Tools › LibrePublish Import**: replace this install's site with one from
  the old shared deployment, from its backup archive, uploaded or fetched from
  the old site with an API token. Runs the core's import in the background,
  follows it, and keeps its report. Admins only (`site_import:run`). Needs
  CMS 1.0.1.
