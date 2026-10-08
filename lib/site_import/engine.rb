# frozen_string_literal: true

module SiteImport
  # A CMS plugin (docs/plugins.md in the core). It owns no tables: what it
  # knows about an import is kept on disk beside the database it replaces
  # (SiteImport::Run), so the record survives the import.
  class Engine < ::Rails::Engine
    initializer "site_import.routes" do |app|
      app.routes.append do
        scope "site_import", module: "site_import", as: "site_import" do
          resources :runs, only: [:index, :create, :show]
        end
      end
    end

    config.to_prepare do
      Cms::Plugins.register :site_import, name: "LibrePublish Import", version: SiteImport::VERSION,
        author: "Martin Business Consultants", enabled_by_default: false, requires: ">= 1.0.1",
        homepage: "https://github.com/Martin-Business-Consultants/cms-site-import",
        description: "Bring a site over from the old shared LibrePublish deployment: upload its backup, " \
                     "or fetch it from the old site, and this install becomes that site."
      Cms::Plugins.submenu :site_import, :tools, label: "LibrePublish Import", path: -> { site_import_runs_path },
        capability: "site_import:run"
      # No defaults: an import replaces the whole site, so only admins (who
      # hold every capability) can run one unless a role is given it.
      Cms::Plugins.permissions :site_import, "LibrePublish Import", %w[site_import:run]
    end
  end
end
