require 'slack-ruby-client'
require 'json'
require 'cache'
require 'httparty'
require 'andand'
require 'pry'

require './iterator'

require 'dotenv'
Dotenv.load

EXCLUDED_MEDIA_TYPES = ['.gifv']
HOT_URL = 'https://www.reddit.com/r/me_irl+meirl.json?count=100'
CACHE_KEY = 'hot'

bot_id = nil
last_messages = {}
delete_message_regex = /^delete$/i

def is_direct_link(url)
  # could potentially check for specific extensions
  # but then we're playing a losing battle with whitelisting
  # this is _probably_ fine
  url.split(//).last(5).include?('.')
end

def excluded_media_types(url)
  EXCLUDED_MEDIA_TYPES.any? { |t|
    url.include?(t)
  }
end

def is_optimal_media(url)
  is_direct_link(url) && !excluded_media_types(url)
end

def get_new_posts_iterator
  j = JSON.parse(HTTParty.get(HOT_URL, headers: {
    'User-Agent' => 'me_irl_bot by /u/shrugs'
  }).body)

  return Iterator.new if j['error']

  all_new_posts = j.andand['data'].andand['children']

  new_post_urls = all_new_posts.select { |e|
    e['kind'] == 't3' && is_optimal_media(e['data']['url'])
  }.map { |e|
    e['data']['url']
  }
  return Iterator.new new_post_urls.shuffle
end

cache = Cache.new(nil, nil, 100, 60 * 10)  # 10 minutes

# imgur_client = Imgurapi::Session.new(
#   client_id: ENV['IMGUR_CLIENT_ID'],
#   client_secret: ENV['IMGUR_CLIENT_SECRET'],
#   refresh_token: ENV['IMGUR_REFRESH_TOKEN'],
# )

Slack.configure do |config|
  config.token = ENV.fetch('SLACK_API_TOKEN')
end

realtime_client = Slack::RealTime::Client.new
web_client = Slack::Web::Client.new

realtime_client.on :hello do
  bot_id = realtime_client.self['id']
  delete_message_regex = /^<@#{bot_id}>: delete\s?/i
end

realtime_client.on :message do |data|

  # if the message is from this bot, store it as the last message
  if data['user'] == bot_id
    last_messages[data['channel']] = data
  end

  case data['text']
  when /[^|\s]?me[ |_]irl[$|\s]?/i

    realtime_client.typing channel: data['channel']

    new_post_iterator = cache.fetch CACHE_KEY do
      get_new_posts_iterator
    end

    next_link = new_post_iterator.next

    if next_link
      realtime_client.message(
        channel: data['channel'],
        text: next_link,
        as_user: true,
        unfurl_media: true,
      )
    else
      cache.invalidate CACHE_KEY
    end

  when delete_message_regex
    this_channel = data['channel']
    meta = last_messages[this_channel]
    if meta
      # delete the last message
      web_client.chat_delete({
        ts: meta['ts'],
        channel: this_channel
      })
      last_messages[this_channel] = nil
    end
  end

end

realtime_client.start!

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
