require 'slack-ruby-client'
require 'json'
require 'cache'
require 'httparty'

require 'dotenv'
Dotenv.load

def is_direct_link(url)
  # could potentially check for specific extensions
  # but then we're playing a losing battle with whitelisting
  # this is _probably_ fine
  url.split(//).last(5).include?('.')
end

EXCLUDED_MEDIA_TYPES = ['.gifv']

def excluded_media_types(url)
  EXCLUDED_MEDIA_TYPES.any? { |t|
    url.include?(t)
  }
end

def is_optimal_media(url)
  is_direct_link(url) && !excluded_media_types(url)
end

HOT_URL = 'https://www.reddit.com/r/me_irl.json?count=100'

cache = Cache.new(nil, nil, 100, 60 * 20)

# imgur_client = Imgurapi::Session.new(
#   client_id: ENV['IMGUR_CLIENT_ID'],
#   client_secret: ENV['IMGUR_CLIENT_SECRET'],
#   refresh_token: ENV['IMGUR_REFRESH_TOKEN'],
# )

Slack.configure do |config|
  config.token = ENV['SLACK_API_TOKEN']
end

client = Slack::RealTime::Client.new

client.on :hello do
  puts 'Successfully connected.'
end

client.on :message do |data|
  case data['text']
  when /[^|\s]?me[ |_]irl[$|\s]?/i

    client.typing channel: data['channel']

    new_post_urls = cache.fetch 'hot' do
      j = JSON.parse(HTTParty.get(HOT_URL).body)
      j['data']['children'].select { |e|
        e['kind'] == 't3' && is_optimal_media(e['data']['url'])
      }.map { |e|
        e['data']['url']
      }
    end

    client.message(
      channel: data['channel'],
      text: new_post_urls.sample,
      as_user: true,
      unfurl_media: true,
    )

  end

end

client.start!

# class ImgurUnfurler

#   def work_magic(url)
#     # returns a valid url ideally pointing to a direct image
#     return yield(url) if is_direct_link(url) or !can_be_unfurled(url)

#     unfurl_url(url) { |u|
#       yield u
#     }

#   end

#   def is_direct_link(url)
#     # could potentially check for specific extensions
#     # but then we're playing a losing battle with whitelisting
#     # this is _probably_ fine
#     url.split(//).last(5).include?('.')
#   end

#   def can_be_unfurled(url)
#     url.include?('/image/') || url.include?('/gallery/')
#   end

#   def unfurl_url(url)
#     yield url
#   end

# end