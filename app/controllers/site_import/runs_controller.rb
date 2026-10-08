# frozen_string_literal: true

module SiteImport
  class RunsController < ::ApplicationController
    include PluginGated
    plugin :site_import

    requires_capability "site_import:run"

    def index
      @runs = Run.all.first(10)
    end

    def create
      run =
        if params[:archive].present?
          Run.upload(params[:archive], by: Current.user, confirmed: params[:confirm])
        else
          Run.fetch(url: params[:url], token: params[:token], by: Current.user, confirmed: params[:confirm])
        end
      redirect_to site_import_run_path(run)
    rescue Run::Refused => e
      redirect_to site_import_runs_path, alert: e.message
    end

    def show
      @run = Run.find(params[:id])
    rescue Run::NotFound
      head :not_found
    end
  end
end
