# -*- coding: utf-8 -*-
## Ruboty::Inc::Helpers::Slack

require 'addressable/uri'

module Ruboty
  module Inc
    module Helpers
      class Slack
        # set const var
        SLACK_ENDPOINT  = "https://slack.com/api/chat.postMessage" 
        SLACK_USERS_API = "https://slack.com/api/users.list"
        SLACK_API_TOKEN = ENV['SLACK_API_TOKEN']

        def initialize(message)
          @message = message
          @channel = get_channel
        end

        def get_channel
          @message.original[:from] ? @message.original[:from].split("@").first : "shell"
        end

        # Slack通知メソッド
        def send_message(msg, dests = nil)
          if @channel == "shell"
            @message.reply(msg)
            return
          end
          end_point = SLACK_ENDPOINT
          dests     = ["##{@channel}"] if dests.nil? or !dests.is_a?(Array)

          dests.each do |send_to|
            uri     = Addressable::URI.parse(SLACK_ENDPOINT)
            query   = {token: SLACK_API_TOKEN,
                       channel: send_to,
                       as_user: true,
                       link_names: 1,
                       text: msg}
  
            uri.query_values ||= {}
            uri.query_values   = uri.query_values.merge(query)
  
            puts "slack通知 to:#{send_to} msg:#{msg}"
            Net::HTTP.get(URI.parse(uri))
          end
        end

        # Slack APIを使用してUserList取得
        def get_slack_user_list
          uri   = Addressable::URI.parse(SLACK_USERS_API)
          query = {token: SLACK_API_TOKEN, presence: 0}
    
          uri.query_values ||= {}
          uri.query_values   = uri.query_values.merge(query)
    
          res_json = Net::HTTP.get(URI.parse(uri))
          res_hash = JSON.parse(res_json, {:symbolize_names => true})
          users_hash = {}
          res_hash[:members].each do |mem_hash|
            next if mem_hash[:profile][:email].nil? or mem_hash[:profile][:email].empty?
            next if mem_hash[:name].nil? or mem_hash[:name].empty?
            email = mem_hash[:profile][:email]
            name  = mem_hash[:name]
            flag  = mem_hash[:deleted]
            users_hash[email] = {:email => email, :name => name, :disabled => flag}
          end
          raise "api response : #{res_hash}" if res_hash.nil? or !res_hash[:ok]
          users_hash
        end
      end
    end
  end
end
