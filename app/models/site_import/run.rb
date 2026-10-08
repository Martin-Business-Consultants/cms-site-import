# frozen_string_literal: true

require "net/http"

module SiteImport
  # One import of a site from the old deployment's backup archive into this
  # install, by the core's TenantImport (bin/rails cms:import_tenant).
  #
  # An import replaces the database, so a run isn't a record in it: it's a
  # directory under the data directory (CMS_DATA_DIR/site_imports/<id>/)
  # holding run.json (what, who, how far), log.txt (what TenantImport said)
  # and, until it has been imported, the archive. A run fetching from the old
  # site also holds its API token there, written 0600 and deleted once used.
  #
  #   queued → fetching → importing → succeeded
  #                                 ↘ failed
  #
  # When it succeeds the install restarts (tmp/restart.txt), so every process
  # opens the new database, and everyone is signed out: the people who can
  # sign in now are the old site's.
  class Run
    class Refused < StandardError; end
    class NotFound < StandardError; end

    ACTIVE = %w[queued fetching importing].freeze
    # A run that stopped saying anything this long ago didn't finish (the
    # process was killed); it no longer holds up another.
    STALE_AFTER = 3.hours
    ID_FORMAT = /\A\d{14}-[0-9a-f]{6}\z/

    attr_reader :id

    class << self
      def root = Cms.data_dir.join("site_imports")

      def all
        return [] unless root.directory?

        root.children.select { it.directory? && it.basename.to_s.match?(ID_FORMAT) }
          .map { new(it.basename.to_s) }.select(&:exists?).sort_by(&:id).reverse
      end

      def find(id)
        run = new(id.to_s) if id.to_s.match?(ID_FORMAT)
        run&.exists? ? run : raise(NotFound, "No import #{id.inspect}")
      end

      def active = all.find(&:active?)

      # From an uploaded archive (an ActionDispatch::Http::UploadedFile).
      def upload(file, by:, confirmed:)
        refuse_unless_ready!(confirmed)
        raise Refused, "Choose the backup file to import." unless file.respond_to?(:path)

        start(source: file.original_filename.to_s, by:) do |run|
          FileUtils.cp(file.path, run.archive_path)
        end
      end

      # From the old site itself: its address and an API token whose role can
      # use Tools (tools:use), which the old site's /api/tools/backup needs.
      def fetch(url:, token:, by:, confirmed:)
        refuse_unless_ready!(confirmed)
        uri = URI.parse(url.to_s.strip)
        raise Refused, "Give the old site's address, like https://acme.librepublish.com." unless uri.is_a?(URI::HTTP) && uri.host.present?
        raise Refused, "Give an API token from the old site." if token.to_s.strip.empty?

        start(source: "#{uri.scheme}://#{uri.host}#{":#{uri.port}" unless uri.port == uri.default_port}", by:) do |run|
          File.open(run.token_path, "w", 0o600) { it.write(token.to_s.strip) }
        end
      end

      private

      def refuse_unless_ready!(confirmed)
        raise Refused, "Tick the box to confirm that the import replaces this site." unless ActiveModel::Type::Boolean.new.cast(confirmed)
        raise Refused, "An import is already running." if active
      end

      def start(source:, by:)
        run = new("#{Time.current.utc.strftime("%Y%m%d%H%M%S")}-#{SecureRandom.hex(3)}")
        run.dir.mkpath
        run.write(status: "queued", source:, requested_by: by&.email, created_at: Time.current.iso8601)
        yield run
        run.import_later
        run
      rescue
        FileUtils.rm_rf(run.dir) if run
        raise
      end
    end

    def initialize(id)
      @id = id
    end

    def dir = self.class.root.join(id)
    def archive_path = dir.join("archive.tar.gz")
    def token_path = dir.join("token")
    def log_path = dir.join("log.txt")
    def state_path = dir.join("run.json")

    def exists? = state_path.file?
    def to_param = id

    def state
      JSON.parse(state_path.read)
    rescue Errno::ENOENT, JSON::ParserError
      {}
    end

    def write(**changes)
      merged = state.merge(changes.stringify_keys).merge("updated_at" => Time.current.iso8601)
      tmp = dir.join("run.json.tmp")
      tmp.write(JSON.pretty_generate(merged))
      File.rename(tmp, state_path)
    end

    def status = state["status"]
    def source = state["source"]
    def requested_by = state["requested_by"]
    def error = state["error"]
    def created_at = time("created_at")
    def finished_at = time("finished_at")
    def log = log_path.file? ? log_path.read : ""

    def active?
      ACTIVE.include?(status) && (time("updated_at") || created_at).to_time > STALE_AFTER.ago
    end

    def import_later = SiteImport::ImportJob.perform_later(id)

    # Runs once: a job the restart interrupted and the queue hands out
    # again finds the run past "queued" and leaves it.
    def import_now
      return unless status == "queued"

      fetch_archive if token_path.file?
      write(status: "importing", started_at: Time.current.iso8601)
      File.open(log_path, "a") do |log|
        log.sync = true
        TenantImport.new(archive_path, force: true, out: log).call
      end
      # The plugin's on/off state was in the database that was just
      # replaced; switch it on in this one, so the report can be read.
      Cms::Plugins.switch!(:site_import, on: true)
      FileUtils.rm_f(archive_path)
      write(status: "succeeded", finished_at: Time.current.iso8601)
      restart
    rescue => e
      write(status: "failed", error: e.message, finished_at: Time.current.iso8601)
      Rails.logger.error("[SiteImport] #{id} failed: #{e.class}: #{e.message}")
    ensure
      FileUtils.rm_f(token_path)
    end

    private

    # POST <site>/api/tools/backup, streamed to disk: the archive carries
    # every file the site has, and the old site builds it before it sends.
    def fetch_archive
      write(status: "fetching")
      uri = URI.join(source, "/api/tools/backup")
      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{token_path.read.strip}"
      request["Accept"] = "application/gzip"

      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 15, read_timeout: 900) do |http|
        http.request(request) do |response|
          unless response.is_a?(Net::HTTPSuccess)
            raise Refused, case response.code.to_i
            when 401 then "The old site didn't accept the token (401)."
            when 403 then "The token's role on the old site can't make backups (403): it needs Tools."
            else "The old site answered #{response.code} #{response.message}."
            end
          end

          File.open(archive_path, "wb") { |file| response.read_body { file.write(it) } }
        end
      end
    rescue SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout, OpenSSL::SSL::SSLError => e
      raise Refused, "Couldn't reach #{source}: #{e.message}"
    end

    def restart
      FileUtils.touch(Rails.root.join("tmp/restart.txt"))
    end

    def time(key) = state[key].presence&.then { Time.zone.parse(it) }
  end
end
