require 'net/http'
require 'openssl'
require 'json'

module Ruboty
  module Inc
    module Actions
      class Status < Ruboty::Actions::Base
        # set env var
        SDB_URL       = ENV['RUBOTY_SDB_URL']
        SDB_LINK_URL  = ENV['RUBOTY_SDB_LINK_URL']
        SKIP_STATUS2  = ENV['RUBOTY_INC_SKIP_STATUS2'] || "DUMMY"

        # incident detail
        INC_DETAIL_PREFIX = "/hibiki/BRDDocument.do?func=view&binderId=12609&recordId="

        def call
          puts "inc status #{message[:cmd]} #{message[:period]} called"
          cmd    = message[:cmd]
          period = message[:period].to_i if !message[:period].nil?
          period = 7 if cmd == "souse"  and period.nil?

          souse_info(period)  if cmd == "souse"
        end

        private

        def get_current_inc_info
          # SDBアクセス、その他ユーティリティのインスタンス化
          sdb   = Ruboty::Inc::Helpers::SmartDB.new(message)

          # get total record count
          count_path  = "/hibiki/rest/1/binders/12609/views/10141/documents"
          url         = "#{SDB_URL}#{count_path}"
          resp_hash   = sdb.send_request(url)
          total_count = resp_hash[:totalCount].to_i if !resp_hash[:totalCount].nil?

          # get inc info
          inc_infos    = {}
          page_size    = 10000
          max_page_num = (total_count/page_size.to_f).ceil
          (1..max_page_num).each do |num|
            url        = "#{SDB_URL}#{count_path}?pageSize=#{page_size}&pageNumber=#{num}"
            resp_hash  = sdb.send_request(url)
            resp_hash[:document].each do |inc|
              inc_info = {:rec_id => inc[:id]}
              inc_no   = nil
              inc[:item].each do |item|
                if item[:id] == "10027" # IINC_NO
                  next if item[:value].nil?
                  inc_no = item[:value]
                elsif item[:id] == "10016" # Assigned Member
                  next if item[:value].nil?
                  member_ary = item[:value]
                  member_ary = [item[:value]] if !item[:value].is_a?(Array)
                  member_ary.each do |member|
                    member.each do |key, val|
                      next if !inc_info[:member].nil? or key != :name
                      inc_info[:member] = val
                    end
                  end
                elsif item[:id] == "10048" # Status
                  next if item[:value].nil?
                  inc_info[:status] = item[:value][:id]
                elsif item[:id] == "10599" # Last Act Date
                  next if item[:value].nil?
                  inc_info[:last_action] = item[:value]
                end
                inc_info[:last_action] = "2000-01-01" if inc_info[:last_action].nil?
              end
              inc_infos[inc_no] = inc_info
            end
          end
          inc_infos
        end

        # 塩漬けインシデント(デフォルト7日動いていないもの)を表示
        def souse_info(period)
          slack       = Ruboty::Inc::Helpers::Slack.new(message)
          inc_infos   = get_current_inc_info
          souse_date  =  (Time.now - (86400 * period)).strftime("%Y-%m-%d");
          skip_status = SKIP_STATUS2.split(",")

          # 滞留起点日が塩漬け基準日(デフォルト7日前)より過去で、かつ
          # SKIP_STATUS2で指定されたステータスを除いたインシデントを抽出
          souse_inc_infos = inc_infos.select do |inc_no, inc_info|
            inc_info[:last_action] <= souse_date and !skip_status.include?(inc_info[:status])
          end

          mem_inc_infos = {}
          souse_inc_infos.each do |inc_no, inc_info|
            inc_url     = "#{SDB_LINK_URL}#{INC_DETAIL_PREFIX}#{inc_info[:rec_id]}"
            member      = inc_info[:member]
            last_action = inc_info[:last_action]
            mem_inc_infos[member] ||= []
            mem_inc_infos[member] << {:inc_no => inc_no, :inc_url => inc_url, :last_action => last_action}
          end

          msg_str = "担当者別に、DAボールで滞留#{period}日以上のインシデントを調べてきたよ\n"
          slack.send_message(msg_str)
          msg_str = "```"

          mem_inc_sorted = mem_inc_infos.sort {|(k1, v1), (k2, v2)| v2.size <=> v1.size}
          mem_inc_sorted.each do |member, inc_array|
            msg_str << "#{member} => "
            inc_array.sort {|a, b| a[:last_action] <=> b[:last_action]}.each do |mem_inc|
              # chat.postMessageがリクエストサイズ上限を上回らないように分割して投稿
              if msg_str.size > 3000
                msg_str << "``` "
                slack.send_message(msg_str)
                msg_str = "```#{member} => "
              end
              msg_str << "<#{mem_inc[:inc_url]}|#{mem_inc[:inc_no]}> "
            end
            # chat.postMessageがリクエストサイズ上限を上回らないように分割して投稿
            if msg_str.size > 3000
              msg_str << "``` "
              slack.send_message(msg_str)
              msg_str = "```"
            else
              msg_str << "\n"
            end
          end
          msg_str << "```"
          slack.send_message(msg_str)
        rescue => e
          message.reply(e.message)
        end

      end
    end
  end
end
