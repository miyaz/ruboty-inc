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
        SKIP_STATUS2  = ENV['RUBOTY_INC_SKIP_STATUS2'] || "DUMMY"

        # smar@db view id
        INC_BINDER_ID      = "12609"
        INC_ALL_VIEW_ID    = "10200"
        INC_DABALL_VIEW_ID = "10141"

        # incident detail
        INC_DETAIL_PREFIX = "/hibiki/BRDDocument.do?func=view&binderId=#{INC_BINDER_ID}&recordId="

        def call
          cmd    = message[:cmd]
          period = message[:period].to_i if !message[:period].nil?
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
          brain        = Ruboty::Inc::Helpers::Brain.new(message)
          util         = Ruboty::Inc::Helpers::Util.new(message)
          to_inc_infos = get_current_inc_info(INC_ALL_VIEW_ID)
          fr_date      =  (Time.now - (86400 * period)).strftime("%Y-%m-%d %H:%M:%S");
          fr_inc_infos = brain.get_inc_info(fr_date)


          # Inc_Noをマージした配列
          all_inc_ary    = fr_inc_infos.keys | to_inc_infos.keys

          # インシデントステータス変動別にカウント
          change_count   = {}
          change_arrow   = " -> "
          nochange_count = {}
          all_inc_ary.each do |inc_no|
            fr_status = (fr_inc_infos[inc_no].nil? ? "登録なし(登録前)" : fr_inc_infos[inc_no][:status])
            to_status = (to_inc_infos[inc_no].nil? ? "登録なし(対処済)" : to_inc_infos[inc_no][:status])
            if fr_status == to_status
              nochange_count[fr_status] ||= 0
              nochange_count[fr_status]  += 1
            else
              change_status_str = "#{util.pad_to_print_size(fr_status, 18)}#{change_arrow}#{to_status}"
              change_count[change_status_str] ||= 0
              change_count[change_status_str]  += 1
            end
          end

          # 表示メッセージ作成
          msg_str = "#{period}日前[#{fr_date}時点]から現在までのステータス変動状況を調査してきたよ\n"
          if change_count.size > 0
            msg_str << "[ステータス変動あり]\n```\n"
            change_count.each do |status_str, status_cnt|
              msg_str << sprintf("%4d | %s\n", status_cnt, status_str)
            end
            msg_str << "```\n"
          end
          if nochange_count.size > 0
            msg_str << "[ステータス変動なし]\n```\n"
            nochange_count.each do |status_str, status_cnt|
              msg_str << sprintf("%4d | %s\n", status_cnt, status_str)
            end
            msg_str << "```\n"
          end

          # reply message
          message.reply(msg_str)
        rescue => e
          message.reply(e.message)
        end

        # 塩漬けインシデント(デフォルト7日動いていないもの)を表示
        def souse_info(period)
          util        = Ruboty::Inc::Helpers::Util.new(message)
          inc_infos   = get_current_inc_info(INC_DABALL_VIEW_ID)
          souse_date  =  (Time.now - (86400 * period)).strftime("%Y-%m-%d");
          skip_status = SKIP_STATUS2.split(",")

          # 滞留起点日が塩漬け基準日(デフォルト7日前)より過去で、かつ
          # SKIP_STATUS2で指定されたステータスを除いたインシデントを抽出
          souse_inc_infos = inc_infos.select do |inc_no, inc_info|
            inc_info[:last_action] <= souse_date and !skip_status.include?(inc_info[:status])
          end

          mem_inc_infos = {}
          souse_inc_infos.each do |inc_no, inc_info|
            inc_url     = "#{SDB_URL}#{INC_DETAIL_PREFIX}#{inc_info[:rec_id]}"
            member      = inc_info[:member]
            last_action = inc_info[:last_action]
            mem_inc_infos[member] ||= []
            mem_inc_infos[member] << {:inc_no => inc_no, :inc_url => inc_url, :last_action => last_action}
          end

          msg_str = "担当者別に、DAボールで滞留#{period}日以上のインシデントを調べてきたよ\n"
          util.send_message(msg_str)
          msg_str = "```"

          mem_inc_sorted = mem_inc_infos.sort {|(k1, v1), (k2, v2)| v2.size <=> v1.size}
          mem_inc_sorted.each do |member, inc_array|
            msg_str << "#{member} => "
            inc_array.sort {|a, b| a[:last_action] <=> b[:last_action]}.each do |mem_inc|
              # chat.postMessageがリクエストサイズ上限を上回らないように分割して投稿
              if msg_str.size > 3000
                msg_str << "``` "
                util.send_message(msg_str)
                msg_str = "```#{member} => "
              end
              msg_str << "<#{mem_inc[:inc_url]}|#{mem_inc[:inc_no]}> "
            end
            # chat.postMessageがリクエストサイズ上限を上回らないように分割して投稿
            if msg_str.size > 3000
              msg_str << "``` "
              util.send_message(msg_str)
              msg_str = "```"
            else
              msg_str << "\n"
            end
          end
          msg_str << "```"
          util.send_message(msg_str)
        rescue => e
          message.reply(e.message)
        end

      end
    end
  end
end
