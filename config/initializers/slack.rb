require 'slack'
require 'json'

HOT_URL = 'https://www.reddit.com/r/me_irl.json?count=100'

Slack.configure do |config|
  config.token = ENV['SLACK_API_TOKEN']
end

client = Slack.client
realtime = client.realtime

realtime.on :hello do
  puts 'Successfully connected.'
end

realtime.on :message do |data|
  case data['text']
  when /[^|\s]?me[ |_]irl[$|\s]?/

    new_post_urls = Rails.cache.fetch('hot', expires_in: 20.minutes) do
      j = JSON.parse(HTTParty.get(HOT_URL).body)
      j['data']['children'].filter { |e|
        e['type'] == 't3_'
      }.map { |e|
        e['data']['url']
      }
    end

    client.chat_postMessage(
      channel: data['channel'],
      text: new_post_urls.sample,
      as_user: true,
      unfurl_media: true,
    )

  end

end

realtime.start