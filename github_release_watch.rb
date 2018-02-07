# frozen_string_literal: true

require 'httpclient'
require 'json'
require 'rexml/document'
require 'time'
require 'uri'

require_relative 'model'

Plugin.create(:github_release_watch) do

  # 絵文字コード生成
  # 指定された絵文字のフォーマットをする
  # @param code [String] 絵文字コード
  # @return 整形済み絵文字コード
  def emoji(code)
    code = ":#{code}:" unless code =~ /:.+:/
    code
  end

  @timeout = 86_400
  @channel = UserConfig[:github_release_watch_slack_channel]
  @username = UserConfig[:github_release_watch_slack_username]
  @webhook_url = UserConfig[:github_release_watch_webhook_url]
  @request_url = UserConfig[:github_release_watch_monitor_url]
  @emoji = emoji(UserConfig[:github_release_watch_slack_emoji] || ':fried_shrimp:')

  # Slackに投稿するためのペイロードを生成する
  # @param version [String] バージョン文字列
  # @param url [String] リリースページのURL
  # @return JSON formatted payload
  def payload(version, url)
    url = URI.join('https://github.com/', url).to_s unless url =~ %r{https://github.com/?[\w-]+}
    status = {
      channel: @channel,
      username: @username,
      text: "新しいバージョン出た: #{version}\n#{url}",
      icon_emoji: @emoji
    }
    status.to_json
  end

  # Slackに投稿する
  # @param title [String] バージョン
  # @param link [String] リリースリンク
  # @return HTTPClient::Response
  def post_slack(title, link)
    HTTPClient.new.post(
      @webhook_url,
      payload(title, link),
      'Content-Type' => 'application/x-www-form-urlencoded'
    )
  end

  # GitHubのrelease.atomをパースして最新のバージョンを確認する
  def monitor_release
    Thread.new {
      doc = open(@request_url).read
      xml = REXML::Document.new(doc)
      entries = []
      xml.elements.each('feed/entry') do |entry|
        entries << Plugin::GithubReleaseWatch::Entry.new(title: entry.elements['title'].text,
                                                         updated: Time.parse(entry.elements['updated'].text),
                                                         author: entry.elements['author/name'].text,
                                                         link: entry.elements['link'].attribute('href'))
      end
      entry = entries.max_by { |e| e.updated.to_i }
      updated = entry.updated.to_i
      response = nil
      response = post_slack(entry.title, entry.link) if updated > @last_updated
      [response, entry]
    }.next { |response, entry|
      next if response.nil?
      if response.code == 200
        @last_updated = entry.updated.to_i
        UserConfig[:github_release_watch_last_updated] = @last_updated
        notice 'Post to Slack Succeeded'
      else
        Delayer::Deferred.fail(response.reason)
      end
    }.trap { |err|
      error err
    }
  end

  # monitor_release を定期実行する
  def tick
    notice 'start tick'
    monitor_release
    Reserver.new(@timeout) { tick }
  end

  # 実行開始
  def start
    notice 'github_release_watch has been loaded!'
    @last_updated = UserConfig[:github_release_watch_last_updated] || 0
    tick
  rescue StandardError => err
    error err
  end

  # キック
  start

  ## 設定
  settings('GitHubリリース監視') do
    input('監視URL', :github_release_watch_monitor_url)
    settings('Slack連携') do
      input('webhook_url', :github_release_watch_webhook_url)
      input('投稿チャンネル', :github_release_watch_slack_channel)
      input('投稿ユーザー名', :github_release_watch_slack_username)
      input('投稿アイコン（絵文字コード）', :github_release_watch_slack_emoji)
    end
  end
end
