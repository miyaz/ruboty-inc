require 'net/http'
require 'openssl'
require 'json'

module Ruboty
  module Inc
    module Actions
      class Status < Ruboty::Actions::Base
        # set env var
        SDB_USER      = ENV['RUBOTY_SDB_USER']
        SDB_PASS      = ENV['RUBOTY_SDB_PASS']
        SDB_URL       = ENV['RUBOTY_SDB_URL']
        ISE_AUTH_PATH = ENV['RUBOTY_ISE_AUTH_PATH']
        SDB_AUTH_PATH = ENV['RUBOTY_SDB_AUTH_PATH']

        # smar@db view id
        INC_BINDER_ID      = "12609"
        INC_ALL_VIEW_ID    = "10200"
        INC_DABALL_VIEW_ID = "10141"

        def call
          cmd    = message[:cmd]
          period = message[:period]
          period = 7 if cmd == "souse"  and period.nil?
          period = 1 if cmd == "change" and period.nil?

          status_save         if cmd == "save"
          change_info(period) if cmd == "change"
          souse_info(period)  if cmd == "souse"
        end

        private

        def get_current_inc_info(view_id)
          # SDBアクセス、その他ユーティリティのインスタンス化
          sdb   = Ruboty::Inc::Helpers::Sdb.new(message)

          # get ise session key
          url        = "#{SDB_URL}#{ISE_AUTH_PATH}"
          headers    = {'Accept' =>'application/json'}
          data       = {'user' => SDB_USER, 'pass' => SDB_PASS}
          resp_hash  = sdb.send_request(url, "post", headers, data)
          ise_cookie = resp_hash['cookie']

          # get sdb session key
          url        = "#{SDB_URL}#{SDB_AUTH_PATH}"
          headers    = {'Accept' =>'application/json', 'Cookie' => "INSUITE-Enterprise=#{ise_cookie}"}
          resp_hash  = sdb.send_request(url, "get", headers, {})
          hibiki_id  = resp_hash['cookie']['value']
          csrf_token = resp_hash['csrfToken']

          # get total record count
          count_path  = "/hibiki/rest/1/binders/#{INC_BINDER_ID}/views/#{view_id}/documents"
          url         = "#{SDB_URL}#{count_path}"
          headers     = {'Accept' =>'application/json', 'Cookie' => "HIBIKI=#{hibiki_id}"}
          resp_hash   = sdb.send_request(url, "get", headers, {})
          total_count = resp_hash['totalCount'].to_i if !resp_hash['totalCount'].nil?

          # get inc info
          inc_infos    = {}
          page_size    = 10000
          max_page_num = (total_count/page_size.to_f).ceil
          (1..max_page_num).each do |num|
            url        = "#{SDB_URL}#{count_path}?pageSize=#{page_size}&pageNumber=#{num}"
            headers    = {'Accept' =>'application/json', 'Cookie' => "HIBIKI=#{hibiki_id}"}
            resp_hash  = sdb.send_request(url, "get", headers, {})
            resp_hash['document'].each do |inc|
              inc_info = {:rec_id => inc['id']}
              inc_no   = nil
              inc['item'].each do |item|
                if item['id'] == "10027" # IINC_NO
                  next if item['value'].nil?
                  inc_no = item['value']
                elsif item['id'] == "10016" # Assigned Member
                  next if item['value'].nil?
                  member_ary = item['value']
                  member_ary = [item['value']] if !item['value'].is_a?(Array)
                  member_ary.each do |member|
                    member.each do |key, val|
                      next if !inc_info[:member].nil? or key != "name"
                      inc_info[:member] = val
                    end
                  end
                elsif item['id'] == "10048" # Status
                  next if item['value'].nil?
                  inc_info[:status] = item['value']['name']
                elsif item['id'] == "10599" # Last Act Date
                  next if item['value'].nil?
                  inc_info[:last_action] = item['value']
                end
                inc_info[:last_action] = "2000-01-01" if inc_info[:last_action].nil?
              end
              inc_infos[inc_no] = inc_info
            end
          end
          inc_infos
        end

        def status_save
          brain     = Ruboty::Inc::Helpers::Brain.new(message)
          inc_infos = get_current_inc_info(INC_ALL_VIEW_ID)

          brain.save_inc_info(inc_infos)
        rescue => e
          message.reply(e.message)
        end

        def change_info(period)
          brain     = Ruboty::Inc::Helpers::Brain.new(message)
          inc_infos = get_current_inc_info(INC_ALL_VIEW_ID)

          # reply message
          #message.reply(msg_str, code: true)
        rescue => e
          message.reply(e.message)
        end

        def souse_info(period)
          inc_infos = get_current_inc_info(INC_DABALL_VIEW_ID)

          # reply message
          #message.reply(msg_str, code: true)
        rescue => e
          message.reply(e.message)
        end

      end
    end
  end
end
