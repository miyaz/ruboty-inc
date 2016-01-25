require 'addressable/uri'

module Ruboty
  module Inc
    module Helpers
      class Util
        # set const var
        SLACK_ENDPOINT  = "https://slack.com/api/chat.postMessage" 
        SLACK_API_TOKEN = ENV['SLACK_API_TOKEN']
        SLACK_USERNAME  = ENV['SLACK_USERNAME'] || "bot"

        def initialize(message)
          @message = message
          @channel = get_channel
        end

        def now
          Time.now.strftime("%Y/%m/%d %H:%M:%S.%L")
        end

        def get_channel
          @message.original[:from] ? @message.original[:from].split("@").first : "shell"
        end

        def get_time_diff(from_str, to_str = nil)
          to_str     = Time.now.to_s if to_str.nil?
          uptime_sec = Time.parse(to_str) - Time.parse(from_str)
          # 課金時間計算なので、1時間に満たないものも1と数える
          uptime_hour = (uptime_sec / 3600).to_i + 1
          return 0 if uptime_hour < 1
          uptime_hour
        end

        # 文字列の表示幅を求める.
        def print_size(string)
          string.each_char.map{|c| c.bytesize == 1 ? 1 : 2}.reduce(0, &:+)
        end

        # 指定された表示幅に合うようにパディングする.
        def pad_to_print_size(string, size)
          # パディングサイズを求める.
          padding_size = size - print_size(string)
          # string の表示幅が size より大きい場合はパディングサイズは 0 とする.
          padding_size = 0 if padding_size < 0

          # パディングする.
          string + ' ' * padding_size
        end

        def send_message(msg)
          if @channel == "shell"
            @message.reply(msg)
            return
          end
          uri   = Addressable::URI.parse(SLACK_ENDPOINT)
          query = {token: SLACK_API_TOKEN,
                   channel: "##{@channel}",
                   username: SLACK_USERNAME,
                   as_user: true,
                   link_names: 1,
                   text: msg}

          uri.query_values ||= {}
          uri.query_values   = uri.query_values.merge(query)

          Net::HTTP.get(URI.parse(uri))
        end
      end
    end
  end
end
