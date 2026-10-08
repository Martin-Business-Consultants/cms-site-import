# frozen_string_literal: true

require "rails_helper"

# The import itself is the core's TenantImport (spec/models/tenant_import_spec.rb
# there); here it's stood in for, since the real one replaces the database.
RSpec.describe SiteImport::Run do
  include ActiveJob::TestHelper

  let(:data_dir) { Dir.mktmpdir("site-import") }
  let(:user) { create(:user, email: "ted@example.test") }
  let(:upload) do
    path = File.join(Dir.mktmpdir("upload"), "cms-backup-acme.tar.gz").tap { File.write(it, "archive bytes") }
    Rack::Test::UploadedFile.new(path, "application/gzip", true)
  end

  around { |example| with_env("CMS_DATA_DIR" => data_dir) { example.run } }
  after { FileUtils.rm_rf(data_dir) }

  def tenant_import(&behaviour)
    allow(TenantImport).to receive(:new) do |path, force:, out:|
      expect(force).to be(true)
      double(call: behaviour ? behaviour.call(path, out) : out.puts("Imported"))
    end
  end

  def without_restart(run)
    allow(run).to receive(:restart)
    allow(described_class).to receive(:find).with(run.id).and_return(run)
    run
  end

  describe ".upload" do
    it "keeps the archive in the data directory and queues the import" do
      run = described_class.upload(upload, by: user, confirmed: "1")

      expect(run.archive_path.read).to eq("archive bytes")
      expect(run.archive_path.to_s).to start_with(data_dir)
      expect(run).to have_attributes(status: "queued", source: "cms-backup-acme.tar.gz", requested_by: "ted@example.test")
      expect(SiteImport::ImportJob).to have_been_enqueued.with(run.id)
    end

    it "wants it confirmed, a file, and no other import running" do
      expect { described_class.upload(upload, by: user, confirmed: "0") }.to raise_error(described_class::Refused, /confirm/)
      expect { described_class.upload(nil, by: user, confirmed: "1") }.to raise_error(described_class::Refused, /Choose the backup file/)

      described_class.upload(upload, by: user, confirmed: "1")
      expect { described_class.upload(upload, by: user, confirmed: "1") }.to raise_error(described_class::Refused, /already running/)
    end
  end

  describe ".fetch" do
    it "keeps the old site's address, and its token only in a file of its own" do
      run = described_class.fetch(url: " https://acme.librepublish.com/admin ", token: "mbc_secret", by: user, confirmed: true)

      expect(run.source).to eq("https://acme.librepublish.com")
      expect(run.token_path.read).to eq("mbc_secret")
      expect(run.token_path.stat.mode & 0o777).to eq(0o600)
      expect(run.state_path.read).not_to include("mbc_secret")
    end

    it "wants a web address and a token" do
      expect { described_class.fetch(url: "ftp://x", token: "t", by: user, confirmed: true) }.to raise_error(described_class::Refused, /address/)
      expect { described_class.fetch(url: "https://x.test", token: " ", by: user, confirmed: true) }.to raise_error(described_class::Refused, /token/)
    end
  end

  describe "#import_now" do
    it "imports the archive, switches the plugin on in the new database, tidies up and restarts" do
      run = without_restart(described_class.upload(upload, by: user, confirmed: "1"))
      imported = nil
      tenant_import do |path, out|
        imported = path
        out.puts("blobs: 1 copied")
      end

      perform_enqueued_jobs

      expect(imported).to eq(run.archive_path)
      expect(run).to have_attributes(status: "succeeded", log: "blobs: 1 copied\n")
      expect(run.finished_at).to be_present
      expect(run.archive_path).not_to exist
      expect(Cms::Plugins.switched_on?(Cms::Plugins.manifests[:site_import])).to be(true)
      expect(run).to have_received(:restart)
    end

    it "fetches the backup from the old site first, and drops the token" do
      run = without_restart(described_class.fetch(url: "https://acme.test", token: "mbc_secret", by: user, confirmed: true))
      fetched = nil
      tenant_import { |path, _| fetched = path.read }
      sent = nil
      http = double
      allow(http).to receive(:request) do |request, &block|
        sent = request
        response = Net::HTTPOK.new("1.1", "200", "OK")
        allow(response).to receive(:read_body).and_yield("fetched ").and_yield("archive")
        block.call(response)
      end
      allow(Net::HTTP).to receive(:start).with("acme.test", 443, hash_including(use_ssl: true)).and_yield(http)

      run.import_now

      expect(fetched).to eq("fetched archive")
      expect(sent).to be_a(Net::HTTP::Post)
      expect(sent.path).to eq("/api/tools/backup")
      expect(sent["Authorization"]).to eq("Bearer mbc_secret")
      expect(run.status).to eq("succeeded")
      expect(run.token_path).not_to exist
    end

    it "says why when the old site won't give it the backup" do
      run = without_restart(described_class.fetch(url: "https://acme.test", token: "mbc_wrong", by: user, confirmed: true))
      http = double
      allow(http).to receive(:request) { |_, &block| block.call(Net::HTTPForbidden.new("1.1", "403", "Forbidden")) }
      allow(Net::HTTP).to receive(:start).and_yield(http)
      allow(TenantImport).to receive(:new)

      run.import_now

      expect(run).to have_attributes(status: "failed", error: a_string_matching(/needs Tools/))
      expect(TenantImport).not_to have_received(:new)
      expect(run.token_path).not_to exist
      expect(run).not_to have_received(:restart)
    end

    it "records a failed import and doesn't restart" do
      run = without_restart(described_class.upload(upload, by: user, confirmed: "1"))
      tenant_import { raise TenantImport::Error, "No main.sqlite3 in the archive" }

      run.import_now

      expect(run).to have_attributes(status: "failed", error: "No main.sqlite3 in the archive")
      expect(run).not_to have_received(:restart)
      expect(described_class.active).to be_nil
    end

    # The restart can interrupt the job before the queue hears it finished,
    # and the queue hands it out again.
    it "runs once" do
      run = without_restart(described_class.upload(upload, by: user, confirmed: "1"))
      tenant_import

      2.times { run.import_now }

      expect(TenantImport).to have_received(:new).once
    end
  end

  it "stops counting a run that went quiet as running" do
    run = described_class.upload(upload, by: user, confirmed: "1")

    travel_to(4.hours.from_now) do
      expect(run.active?).to be(false)
      expect(described_class.active).to be_nil
    end
  end

  it "finds only runs that exist, by a well-formed id" do
    expect { described_class.find("../../etc") }.to raise_error(described_class::NotFound)
    expect { described_class.find("20260101000000-abcdef") }.to raise_error(described_class::NotFound)
  end
end
