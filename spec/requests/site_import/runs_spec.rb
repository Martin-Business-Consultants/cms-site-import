# frozen_string_literal: true

require "rails_helper"

RSpec.describe "LibrePublish Import", type: :request do
  let(:data_dir) { Dir.mktmpdir("site-import") }
  let(:admin) { create(:user) }

  around { |example| with_env("CMS_DATA_DIR" => data_dir) { example.run } }
  after { FileUtils.rm_rf(data_dir) }

  it "is 404 while the plugin is off" do
    sign_in_as admin

    get site_import_runs_path

    expect(response).to have_http_status(:not_found)
  end

  context "while on" do
    before { switch_plugin :site_import, on: true }

    it "is in the Tools menu, for admins only" do
      sign_in_as admin
      get site_import_runs_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("LibrePublish Import", "Import site", "From the old site")

      sign_in_as create(:user, admin: false)
      get site_import_runs_path
      expect(response).not_to have_http_status(:ok)
    end

    it "starts an import from an uploaded backup and follows it" do
      sign_in_as admin
      path = File.join(data_dir, "cms-backup-acme.tar.gz").tap { File.write(it, "bytes") }
      file = Rack::Test::UploadedFile.new(path, "application/gzip", true)

      post site_import_runs_path, params: {archive: file, confirm: "1"}

      run = SiteImport::Run.all.first
      expect(response).to redirect_to(site_import_run_path(run))
      follow_redirect!
      expect(response.body).to include("cms-backup-acme.tar.gz", 'data-controller="refresh"')
    end

    it "says what's wrong instead of starting one" do
      sign_in_as admin

      post site_import_runs_path, params: {url: "https://acme.test", token: "t"}

      expect(response).to redirect_to(site_import_runs_path)
      expect(flash[:alert]).to match(/confirm/)
      expect(SiteImport::Run.all).to be_empty
    end

    it "is 404 for an import that isn't there" do
      sign_in_as admin

      get site_import_run_path("nope")

      expect(response).to have_http_status(:not_found)
    end
  end
end
