# frozen_string_literal: true

require_relative './entry'

module Plugin::GithubReleaseWatch
  # 監視対象のrelease.atom
  class Watch < Diva::Model
    field.string :webhook_url, required: true
    field.string :request_url, required: true
    field.time :last_updated
    field.has :entries, [Plugin::GithubReleaseWatch::Entry]
  end
end
