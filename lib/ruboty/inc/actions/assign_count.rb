module Ruboty
  module Inc
    module Actions
      class AssignCount < Ruboty::Actions::Base
        # set env var
        SDB_USER      = ENV['RUBOTY_SDB_USER']
        SDB_PASS      = ENV['RUBOTY_SDB_PASS']
        SDB_URL       = ENV['RUBOTY_SDB_URL']
        ISE_AUTH_PATH = ENV['RUBOTY_ISE_AUTH_PATH']
        SDB_AUTH_PATH = ENV['RUBOTY_SDB_AUTH_PATH']
        SKIP_STATUS   = ENV['RUBOTY_INC_SKIP_STATUS'] || "DUMMY"

        def call
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
          count_path  = "/hibiki/rest/1/binders/12609/views/10200/documents"
          url         = "#{SDB_URL}#{count_path}"
          headers     = {'Accept' =>'application/json', 'Cookie' => "HIBIKI=#{hibiki_id}"}
          resp_hash   = sdb.send_request(url, "get", headers, {})
          total_count = resp_hash['totalCount'].to_i if !resp_hash['totalCount'].nil?

          # get assign count
          assign_count = {}
          assign_total = 0
          page_size    = 10000
          max_page_num = (total_count/page_size.to_f).ceil
          (1..max_page_num).each do |num|
            url        = "#{SDB_URL}#{count_path}?pageSize=#{page_size}&pageNumber=#{num}"
            headers    = {'Accept' =>'application/json', 'Cookie' => "HIBIKI=#{hibiki_id}"}
            resp_hash  = sdb.send_request(url, "get", headers, {})
            resp_hash['document'].each do |inc|
              inc['item'].each do |item|
                if item['id'] == "10016" # Assigned Member
                  next if item['value'].nil?
                  member_ary = item['value']
                  member_ary = [item['value']] if !item['value'].is_a?(Array)
                  member_ary.each do |member|
                    member.each do |key, val|
                      next if key != "name"
                      assign_total += 1
                      if assign_count.has_key?(val)
                        assign_count[val] += 1
                      else
                        assign_count[val] = 1
                      end
                    end
                  end
                end
              end
            end
          end

          # get assign active count
          incpoint_count = {}
          active_count   = {}
          movable_count  = {}
          skip_status    = SKIP_STATUS.split(",")
          active_total   = 0
          movable_total  = 0
          active_path    = "/hibiki/rest/1/binders/12609/views/10141/documents"
          (1..max_page_num).each do |num|
            url       = "#{SDB_URL}#{active_path}?pageSize=#{page_size}&pageNumber=#{num}"
            headers   = {'Accept' =>'application/json', 'Cookie' => "HIBIKI=#{hibiki_id}"}
            resp_hash = sdb.send_request(url, "get", headers, {})
            resp_hash['document'].each do |inc|
              assigned_member = nil
              # 担当者別アクティブなインシデント数集計
              inc['item'].each do |item|
                if item['id'] == "10016" # Assigned Member
                  next if item['value'].nil?
                  member_ary = item['value']
                  member_ary = [item['value']] if !item['value'].is_a?(Array)
                  member_ary.each do |member|
                    member.each do |key, val|
                      next if key != "name"
                      assigned_member = val
                      active_total    += 1
                      if active_count.has_key?(val)
                        active_count[val] += 1
                      else
                        active_count[val] = 1
                      end
                    end
                  end
                end
              end
              next if assigned_member.nil?
              # 担当者別インシデントポイント集計
              inc['item'].each do |item|
                if item['id'] == "10612" # Incident Point
                  next if item['value'].nil? or item['value']['name'].nil?
                  incpoint_count[assigned_member] ||= 0
                  incpoint_count[assigned_member] += str2int(item['value']['name'])
                elsif item['id'] == "10048" # Status
                  next if item['value'].nil? or item['value']['name'].nil?
                  next if skip_status.include?(item['value']['name'])
                  movable_count[assigned_member] ||= 0
                  movable_count[assigned_member] += 1
                  movable_total                  += 1
                end
              end
            end
          end

          # make message
          # DA持ち率目標値(%)
          target_rate = 50
          msg_str     = "#{Time.now.strftime('%Y/%m/%d %H:%M')}時点のインシデント対応アサイン状況だよ\n"
          msg_str    << "IncidentPoint/DKC持ち/DA持ち/全件(DA持ち比率)の順に表示しているよ\n"
          msg_str    << sprintf(" point | %3d /%3d /%3d (%3d %%) %s %s\n",
                        movable_total, active_total, assign_total, active_total * 100 / assign_total,
                        pad_to_print_size("Total", 17), "#{target_rate}%まで")
          msg_str    << "-------+--------------------------------------------------"
          assign_count.sort {|(k1, v1), (k2, v2)| v2 <=> v1 }.each do |name, count|
            wk_point_cnt   = incpoint_count[name].to_i
            wk_movable_cnt = movable_count[name].to_i
            wk_act_cnt     = active_count[name].to_i
            wk_act_cnt     = 0 if active_count[name].nil?
            active_rate    = wk_act_cnt * 100 / count
            target_quota   = wk_act_cnt - ( count * target_rate / 100 )
            comment        = ""
            comment        = "あと#{target_quota}件" if target_quota > 0
            msg_str       << sprintf("\n%6d | %3d /%3d /%3d (%3d %%) %s %s",
                             wk_point_cnt, wk_movable_cnt, wk_act_cnt, count, active_rate,
                             pad_to_print_size(name, 17), comment)
          end

          # reply message
          message.reply(msg_str, code: true)
        rescue => e
          message.reply(e.message)
        end

        private

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

        # 数値を表す文字列であれば数値変換して返却、そうでなければ0を返却
        def str2int(str)
          Integer(str)
          str.to_i
        rescue ArgumentError
          0
        end
      end
    end
  end
end
