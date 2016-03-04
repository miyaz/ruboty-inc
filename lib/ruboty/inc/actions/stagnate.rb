require 'net/http'
require 'openssl'
require 'json'
require 'time'

module Ruboty
  module Inc
    module Actions
      class Stagnate < Ruboty::Actions::Base
        # set env var
        SDB_USER      = ENV['RUBOTY_SDB_USER']
        SDB_PASS      = ENV['RUBOTY_SDB_PASS']
        SDB_URL       = ENV['RUBOTY_SDB_URL']
        ISE_AUTH_PATH = ENV['RUBOTY_ISE_AUTH_PATH']
        SDB_AUTH_PATH = ENV['RUBOTY_SDB_AUTH_PATH']
        SKIP_MEMBER   = ENV['RUBOTY_INC_SKIP_MEMBER'] || ""

        # smar@db view id
        INC_BINDER_ID      = "12609"
        INC_DABALL_VIEW_ID = "10141"

        # incident detail
        INC_DETAIL_PREFIX = "/hibiki/BRDDocument.do?func=view&binderId=#{INC_BINDER_ID}&recordId="

        def call
          puts "inc stagnate #{message[:who]} called"
          target = message[:who]
          stagnate(target)
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
              inc_info = {:rec_id => inc['id'], :title => inc['name']}
              inc_no   = nil
              inc['item'].each do |item|
                if item['id'] == "10027" # IINC_NO
                  next if item['value'].nil?
                  inc_no = item['value']
                elsif item['id'] == "10016" # Assigned Member
                  next if item['value'].nil?
                  inc_info[:m_name] = item['value']['name']
                  inc_info[:m_mail] = item['value']['email']
                elsif item['id'] == "10048" # Status
                  next if item['value'].nil?
                  inc_info[:status] = item['value']['name']
                elsif item['id'] == "10599" # Last Act Date
                  next if item['value'].nil?
                  inc_info[:last_action] = item['value']
                end
              end
              inc_infos[inc_no] = inc_info
            end
          end
          inc_infos
        end

        # インシデント滞留期間降順に担当者へ通知
        def stagnate(target)
          brain     = Ruboty::Inc::Helpers::Brain.new(message)
          util      = Ruboty::Inc::Helpers::Util.new(message)
          caller    = util.get_caller

          # Slackユーザ名/Emailの一覧取得（今日初であればSlackAPIで取得してRedis保存）
          today = Time.now.strftime('%Y-%m-%d')
          brain_user_list = brain.get_slack_user_list
          slack_user_list = nil
          if brain_user_list.empty? or brain_user_list[:last_update] != today
            puts "need to get slack user list by slack api"
            slack_user_list = util.get_slack_user_list
            brain.save_slack_user_list(slack_user_list)
          else
            puts "found slack user list in brain"
            slack_user_list = brain_user_list[:user_info]
          end
          valid_user_list = {}
          slack_user_list.each do |key, val|
            next if val[:disabled]
            valid_user_list[key] = val[:name]
          end

          inc_infos = get_current_inc_info(INC_DABALL_VIEW_ID)

          mem_inc_infos = {}
          inc_infos.each do |inc_no, inc_info|
            member        = inc_info[:m_name]
            email         = inc_info[:m_mail]
            slack_user    = valid_user_list[email]
            # Slackアカウントがないユーザは除外
            if slack_user.nil?
              puts "skip #{email}"
              next
            end
            # 引数指定なし時は実行ユーザの担当インシデントのみチャンネルへ投稿する
            if target.nil?
              next if caller != slack_user 
            end
            # 窓口Grp以外は除外
            if SKIP_MEMBER.split(",").include?(member)
              puts "skip #{member}"
              next
            end
            inc_url       = "#{SDB_URL}#{INC_DETAIL_PREFIX}#{inc_info[:rec_id]}"
            last_action   = inc_info[:last_action]
            stagnate_days = ((Time.parse(today) - Time.parse(last_action)) / 86400).to_i
            mem_inc_infos[member] ||= []
            mem_inc_infos[member] << {:inc_no => inc_no, :inc_url => inc_url, :m_name => member,
                                      :m_mail => email, :slack_user => valid_user_list[email],
                                      :last_action => last_action, :stagnate_days => stagnate_days,
                                      :status => inc_info[:status], :title => inc_info[:title]}
          end

          # インシデント担当者ごとにDM送付
          mem_inc_infos.each do |member, mem_incs|
            mem_incs_sorted = mem_incs.sort {|a, b| b[:stagnate_days] <=> a[:stagnate_days]}
            slack_user = nil
            msg_str    = "#{member}さんが担当しているインシデントだよ. (滞留日数が多い順)\n```\n"
            msg_str   << " Days | INC-No      | Status          | Title\n"
            msg_str   << "------+-------------+-----------------+-----------"
            mem_incs_sorted.each do |mem_inc|
              slack_user = mem_inc[:slack_user] if slack_user.nil?
              msg_str << sprintf("\n %4d | %s | %s | %s",
                                 mem_inc[:stagnate_days],
                                 "<#{mem_inc[:inc_url]}|#{mem_inc[:inc_no]}>",
                                 "#{util.pad_to_print_size(mem_inc[:status], 15)}",
                                 mem_inc[:title])
            end
            msg_str << "```"
            if target.nil?
              # 引数指定なし時は実行ユーザの担当インシデントのみチャンネルへ投稿する
              util.send_message(msg_str)
            else
              # 引数[all]指定時は、個別にDMで送付
              util.send_message(msg_str, slack_user)
            end
          end
        rescue => e
          message.reply(e.message)
        end

      end
    end
  end
end
