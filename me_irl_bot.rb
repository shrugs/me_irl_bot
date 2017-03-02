require 'slack-ruby-client'
require 'json'
require 'cache'
require 'httparty'
require 'andand'
require 'pry'

require './iterator'

require 'dotenv'
Dotenv.load

USER_AGENT = ENV.fetch('BOT_USER_AGENT', 'me_irl_bot by /u/shrugs')

EXCLUDED_MEDIA_TYPES = ['.gifv']
MEME_SUBREDDITS = [
  'me_irl',
  'meirl',
  'wholesomememes'
]
CACHE_KEY = 'hot'

bot_id = nil
last_messages = {}
me_irl_regex = /[^|\s]?me[ |_]*irl[$|\s]?/i
delete_message_regex = /^delete$/i

def hot_url(subreddit)
  "https://www.reddit.com/r/#{subreddit}.json?count=500"
end

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
  new_post_urls = MEME_SUBREDDITS
    .map { |sub| hot_url(sub) }
    .map { |url|
      j = JSON.parse(HTTParty.get(url, headers: {
        'User-Agent' => USER_AGENT
      }).body)

      return [] if j['error']

      new_post_urls = j.andand['data'].andand['children'].select { |e|
        e['kind'] == 't3' && is_optimal_media(e['data']['url'])
      }.map { |e|
        e['data']['url']
      }
    }
    .flatten

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

client = Slack::RealTime::Client.new

client.on :hello do
  bot_id = client.self['id']
  delete_message_regex = /^@#{bot_id}:? delete$/i

  client.web_client.chat_postMessage({
    channel: ENV['BOT_ADMIN'],
    text: "Oh hey, I've been connected. My ID is #{bot_id}",
    as_user: true
  }) if ENV.has_key?('BOT_ADMIN')
end

client.on :message do |data|

  is_normal_message = data['type'] == 'message' && !data.has_key?('subtype')

  # we only care about raw messages, not updates or anything
  next if !is_normal_message || !data.has_key?('text')

  text = Slack::Messages::Formatting.unescape(data['text'])

  case text
  when me_irl_regex

    client.typing channel: data['channel']

    new_post_iterator = cache.fetch CACHE_KEY do
      get_new_posts_iterator
    end

    next_link = new_post_iterator.next

    if next_link
      meta = client.web_client.chat_postMessage({
        channel: data['channel'],
        text: next_link,
        as_user: true,
        unfurl_media: true
      })
      last_messages[data['channel']] = meta
    else
      cache.invalidate CACHE_KEY
    end

  when delete_message_regex
    this_channel = data['channel']
    meta = last_messages[this_channel]

    if meta
      # delete the last message
      client.web_client.chat_delete({
        ts: meta['ts'],
        channel: this_channel
      })
      last_messages[this_channel] = nil
    end
  end

end

client.on :closed do |_data|
  client.web_client.chat_postMessage({
    channel: ENV['BOT_ADMIN'],
    text: "Oh hey, I've been disconnected. Fix that or something. Or don't. Whatever.",
    as_user: true
  }) if ENV.has_key?('BOT_ADMIN')

  # kill self, ideally something will restart this container
  exit 2
end

client.start!
