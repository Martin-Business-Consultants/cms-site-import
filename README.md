# LibrePublish Import

A plugin for the CMS (see `docs/plugins.md` in [opencms](https://github.com/Martin-Business-Consultants/opencms))
that brings a site over from the old shared LibrePublish deployment: one
button, and this install becomes that site.

Tools › LibrePublish Import takes the old site's backup archive, either

- **fetched from the old site**: its address and an API token whose role can
  use Tools there. The install pulls the backup itself, so a large media
  library never goes through a browser upload, which the proxy in front of
  the CMS may refuse; or
- **uploaded**: the `.tar.gz` from the old site's Tools › Backup ("Backup
  site") or `cms backup > site.tar.gz`.

It then runs the core's import (`TenantImport`, the same as
`bin/rails "cms:import_tenant[PATH]"`): the old site's database replaces this
install's, the migrations it's behind on run, and every file is copied in and
checked. The install's previous database is kept beside the new one. The
page follows the import and shows its report: files the old site couldn't
find, and encrypted values this install can't read (give it the old
deployment's `SECRET_KEY_BASE`, see the core's `docs/install.md`).

**It replaces everything**: pages, collections, globals, media, settings and
users become the old site's. When it's done the CMS restarts and everyone is
signed out; sign back in with your account from the old site.

Only admins can run it, unless a role is given `site_import:run`. What it
knows about an import is kept on disk, under the data directory
(`CMS_DATA_DIR/site_imports/`), so the record outlives the database it
replaces. The API token, when one is given, is kept there (0600) only until
the backup has been fetched.

## Install

Needs CMS 1.0.1 or newer.

    bin/rails "plugins:install[https://github.com/Martin-Business-Consultants/cms-site-import,v0.1.0]"

or, for a Docker install, add the URL (with `#v0.1.0`) to `CMS_PLUGINS`. Then
switch it on in Settings › Plugins; it's in the Tools menu.

## Development

Its specs run inside the CMS, with the plugin in `plugins/`:

    ln -s ../../cms-plugins/site_import plugins/site_import
    bin/rspec plugins/site_import/spec

Licensed under the Functional Source License (FSL-1.1-MIT, `LICENSE.md`).
