# frozen_string_literal: true

module Plugin::GithubReleaseWatch
  # release.atomの各エントリのモデル
  class Entry < Diva::Model
    field.string :title, required: true
    field.time :updated, required: true
    field.string :author
    field.string :link

    def version
      title
    end
  end
end
