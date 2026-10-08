# frozen_string_literal: true

require "site_import/version"
require "site_import/engine"

# LibrePublish Import: replaces this install's site with one from the old
# shared deployment, from its backup archive (uploaded, or fetched from the
# old site with an API token). The import itself is the core's TenantImport;
# this plugin is the button, the fetch and the record of how it went.
module SiteImport
end
