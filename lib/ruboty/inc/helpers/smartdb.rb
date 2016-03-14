# -*- coding: utf-8 -*-
## Ruboty::Inc::Helpers::SmartDB

require 'addressable/uri'
require 'net/http'
require 'openssl'
require 'json'
require 'time'

module Ruboty
  module Inc
    module Helpers
      class SmartDB
        # set env var
        SDB_USER      = ENV['RUBOTY_SDB_USER']
        SDB_PASS      = ENV['RUBOTY_SDB_PASS']
        SDB_URL       = ENV['RUBOTY_SDB_URL']
        ISE_AUTH_PATH = ENV['RUBOTY_ISE_AUTH_PATH']
        SDB_AUTH_PATH = ENV['RUBOTY_SDB_AUTH_PATH']

        def initialize(message)
          @brain = Brain.new(message)
        end
    
        # SDB REST APIアクセス共通メソッド(json形式応答をhash化して返却)
        def send_request(url, method = nil, data = nil)
          retry_limit   = 3
          retry_counter = 0
          begin
            # 引数urlからuriオブジェクト生成
            uri = URI.parse(url)
    
            # headersオブジェクト生成
            hibiki_id = get_session_key
            headers   = {'Accept' =>'application/json', 'Cookie' => "HIBIKI=#{hibiki_id}"}
    
            # 引数methodからrequestオブジェクト生成
            request = Net::HTTP::Post.new(uri.request_uri, initheader = headers) if method == "post"
            request = Net::HTTP::Get.new(uri.request_uri, initheader = headers) if method != "post"
    
            # 引数dataからpostするbodyデータを生成
            if !data.nil? and data.is_a?(Hash)
              data_str = ""
              data.each do |key,val|
                data_str << "&" if data_str != ""
                data_str << "#{key}=#{val}"
              end
              request.body = data_str if data_str != ""
            end
    
            http = Net::HTTP.new(uri.host, uri.port)
            if !url.index("https").nil?
              http.use_ssl = true
              http.verify_mode = OpenSSL::SSL::VERIFY_NONE
            end
            #http.set_debug_output $stderr
            res_json = ""
            http.start do |h|
              response  = h.request(request)
              res_json << response.body
            end
            res_hash = JSON.parse(res_json, {:symbolize_names => true})
            raise UnauthorizedError if !res_hash[:code].nil? and res_hash[:code] == 401
            res_hash
          rescue UnauthorizedError => e
            retry_counter += 1
            if retry_counter <= retry_limit
              sleep(1)
              # セッションキーがエラーになったのでhibiki_idを再取得してリトライします
              @brain.save_hibiki_id(nil)
              puts "send_request failed. #{retry_counter} times retrying: #{e.message}"
              retry
            else
              puts "send_request failed. retried #{retry_limit} times: #{e.message}"
            end
          rescue => e
            raise "send_request failed : #{e.message}"
          end
        end
    
        # hibiki id を取得する
        def get_session_key
          # hibiki_idがRedisに存在すればそこからセッションキーを返却
          hibiki_id = @brain.get_hibiki_id
          if !hibiki_id.nil?
            puts "hibiki id (from redis) => [#{hibiki_id}]"
            return hibiki_id
          end
    
          hibiki_id     = ""
          retry_limit   = 3
          retry_counter = 0
          begin
            ise_key = ""
            uri     = URI.parse("#{SDB_URL}#{ISE_AUTH_PATH}")
            request = Net::HTTP::Post.new(uri.request_uri,
                        initheader = {
                          'Accept' =>'application/json'
                        })
            request.body = "user=#{SDB_USER}&pass=#{SDB_PASS}"
    
            http = Net::HTTP.new(uri.host, uri.port)
            http.use_ssl = true
            http.verify_mode = OpenSSL::SSL::VERIFY_NONE
            #http.set_debug_output $stderr
            http.start do |h|
              response = h.request(request)
              res_hash = JSON.parse(response.body, {:symbolize_names => true})
              ise_key = res_hash[:cookie]
            end
    
            uri     = URI.parse("#{SDB_URL}#{SDB_AUTH_PATH}")
            request = Net::HTTP::Post.new(uri.request_uri,
                        initheader = {
                          'Accept' =>'application/json',
                          'Cookie' => "INSUITE-Enterprise=#{ise_key}"
                        })
            http = Net::HTTP.new(uri.host, uri.port)
            http.use_ssl = true
            http.verify_mode = OpenSSL::SSL::VERIFY_NONE
            #http.set_debug_output $stderr
            http.start do |h|
              response   = h.request(request)
              res_hash   = JSON.parse(response.body, {:symbolize_names => true})
              hibiki_id  = res_hash[:cookie][:value]
            end
            puts "hibiki id (from moe) => [#{hibiki_id}]"
            @brain.save_hibiki_id(hibiki_id)
            return hibiki_id
          rescue => e
            retry_counter += 1
            if retry_counter <= retry_limit
              sleep(1)
              puts "get insuite&hibiki id failed. #{retry_counter} times retrying: #{e.message}"
              retry
            else
              raise "get hibiki id failed. retried #{retry_limit} times: #{e.message}"
            end
          end
        end
      end
    
      # moe認証エラー時独自例外
      class UnauthorizedError < StandardError; end
    
    end
  end
end   

