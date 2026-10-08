# frozen_string_literal: true

module SiteImport
  class ImportJob < ApplicationJob
    queue_as :default

    def perform(run_id)
      Run.find(run_id).import_now
    end
  end
end
