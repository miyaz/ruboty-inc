module Ruboty
  module Inc
    module Actions
      class AssignPoint < Ruboty::Actions::Base
        # set env var
        SDB_URL       = ENV['RUBOTY_SDB_URL']
        # エスカステータス
        SKIP_STATUS   = ENV['RUBOTY_INC_SKIP_STATUS']  || "DUMMY"
        # 塩漬け除外ステータス
        SKIP_STATUS2  = ENV['RUBOTY_INC_SKIP_STATUS2'] || "DUMMY"
        # AEは除外
        SKIP_MEMBER   = ENV['RUBOTY_INC_SKIP_MEMBER']  || ""
        POINT_FACTOR  = ENV['RUBOTY_INC_POINT_FACTOR'] || "2.0"

        def call
          puts "inc assign point called"
          # SDBアクセス、その他ユーティリティのインスタンス化
          sdb   = Ruboty::Inc::Helpers::SmartDB.new(message)
          util  = Ruboty::Inc::Helpers::Util.new(message)

          # get total record count
          count_path  = "/hibiki/rest/1/binders/12609/views/10141/documents"
          url         = "#{SDB_URL}#{count_path}"
          resp_hash   = sdb.send_request(url)
          total_count = resp_hash[:totalCount].to_i if !resp_hash[:totalCount].nil?

          # get incident info (da ball)
          inc_infos    = []
          page_size    = 10000
          max_page_num = (total_count/page_size.to_f).ceil
          (1..max_page_num).each do |num|
            url        = "#{SDB_URL}#{count_path}?pageSize=#{page_size}&pageNumber=#{num}"
            resp_hash  = sdb.send_request(url)
            resp_hash[:document].each do |inc|
              inc_info = {:rec_id => inc[:id], :inc_point => 0}
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
                elsif item[:id] == "10612" # Incident Point
                  next if item[:value].nil?
                  inc_info[:inc_point] = str2int(item[:value][:name])
                elsif item[:id] == "10048" # Status
                  next if item[:value].nil?
                  inc_info[:status] = item[:value][:id]
                elsif item[:id] == "10599" # Last Act Date
                  next if item[:value].nil?
                  inc_info[:last_action] = item[:value]
                end
                inc_info[:last_action] = "2000-01-01" if inc_info[:last_action].nil?
              end
              inc_infos << inc_info
            end
          end

          # get assign point summary
          assign_point    = {}
          souse_date      = (Time.now - (86400 * 30)).strftime("%Y-%m-%d");
          esca_status     = SKIP_STATUS.split(",")
          no_souse_status = SKIP_STATUS2.split(",")
          skip_member     = SKIP_MEMBER.split(",")
          inc_infos.each do |inc|
            member = inc[:member]
            next if skip_member.include?(member)
            # ポイント初期値設定
            if assign_point[member].nil?
              assign_point[member] = {}
              assign_point[member][:stagnate_count] = 0
              assign_point[member][:stagnate_point] = 0
              assign_point[member][:souse_count]    = 0
              assign_point[member][:souse_point]    = 0
              assign_point[member][:esca_count]     = 0
              assign_point[member][:esca_point]     = 0
            end
            # DA持ち数カウント
            assign_point[member][:stagnate_count]  += 1
            # DA持ち数インシデントポイント合算
            assign_point[member][:stagnate_point]  += inc[:inc_point]
            if inc[:last_action] <= souse_date and !no_souse_status.include?(inc[:status])
              # 塩漬け数(エスカ含む)
              assign_point[member][:souse_count]   += 1
              # エスカポイント
              assign_point[member][:souse_point]   += inc[:inc_point]
            elsif esca_status.include?(inc[:status])
              # エスカ数(塩漬け除く)
              assign_point[member][:esca_count]    += 1
              # エスカポイント
              assign_point[member][:esca_point]    += inc[:inc_point]
            end
          end

          # make message
          # ステータス別インシデントポイント集計
          msg_str = "#{Time.now.strftime('%Y/%m/%d %H:%M')}時点のインシデントポイント集計結果だよ\n"
          msg_str << "滞留数/滞留pt/エスカ数/エスカpt/塩漬数/塩漬pt/実質数/実質ptの順に表示しているよ\n"
          msg_str << " StgC | StgP | EscC | EscP | SosC | SosP | ActC | ActP | Member\n"
          msg_str << "------+------+------+------+------+------+------+------+---------------"
          assign_point.sort {|(k1, v1), (k2, v2)| k1 <=> k2 }.each do |member, point_data|
            stg_count = point_data[:stagnate_count]
            stg_point = point_data[:stagnate_point]
            esc_count = point_data[:esca_count]
            esc_point = point_data[:esca_point]
            sos_count = point_data[:souse_count]
            sos_point = point_data[:souse_point]
            act_count = stg_count - (esc_count/POINT_FACTOR.to_f).ceil - sos_count
            act_point = stg_point - (esc_point/POINT_FACTOR.to_f).ceil - sos_point
            msg_str       << sprintf("\n %4d | %4d | %4d | %4d | %4d | %4d | %4d | %4d | %s",
                             stg_count, stg_point, esc_count, esc_point, sos_count, sos_point,
                             act_count, act_point, member)
          end

          # reply message
          message.reply(msg_str, code: true)
        rescue => e
          message.reply(e.message)
        end

        private

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
