require 'net/http'
require 'openssl'
require 'json'

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

        def call
          # get ise session key
          url        = "#{SDB_URL}#{ISE_AUTH_PATH}"
          headers    = {'Accept' =>'application/json'}
          data       = {'user' => SDB_USER, 'pass' => SDB_PASS}
          resp_hash  = send_request(url, "post", headers, data)
          ise_cookie = resp_hash['cookie']

          # get sdb session key
          url        = "#{SDB_URL}#{SDB_AUTH_PATH}"
          headers    = {'Accept' =>'application/json', 'Cookie' => "INSUITE-Enterprise=#{ise_cookie}"}
          resp_hash  = send_request(url, "get", headers, {})
          hibiki_id  = resp_hash['cookie']['value']
          csrf_token = resp_hash['csrfToken']

          # get total record count
          count_path  = "/hibiki/rest/1/binders/12609/views/10200/documents"
          url         = "#{SDB_URL}#{count_path}"
          headers     = {'Accept' =>'application/json', 'Cookie' => "HIBIKI=#{hibiki_id}"}
          resp_hash   = send_request(url, "get", headers, {})
          total_count = resp_hash['totalCount'].to_i if !resp_hash['totalCount'].nil?

          # get assign count
          assign_count = {}
          assign_total = 0
          page_size    = 10000
          max_page_num = (total_count/page_size.to_f).ceil
          (1..max_page_num).each do |num|
            url        = "#{SDB_URL}#{count_path}?pageSize=#{page_size}&pageNumber=#{num}"
            headers    = {'Accept' =>'application/json', 'Cookie' => "HIBIKI=#{hibiki_id}"}
            resp_hash  = send_request(url, "get", headers, {})
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
          active_count = {}
          active_total = 0
          active_path  = "/hibiki/rest/1/binders/12609/views/10141/documents"
          (1..max_page_num).each do |num|
            url        = "#{SDB_URL}#{active_path}?pageSize=#{page_size}&pageNumber=#{num}"
            headers    = {'Accept' =>'application/json', 'Cookie' => "HIBIKI=#{hibiki_id}"}
            resp_hash  = send_request(url, "get", headers, {})
            resp_hash['document'].each do |inc|
              inc['item'].each do |item|
                if item['id'] == "10016" # Assigned Member
                  next if item['value'].nil?
                  member_ary = item['value']
                  member_ary = [item['value']] if !item['value'].is_a?(Array)
                  member_ary.each do |member|
                    member.each do |key, val|
                      next if key != "name"
                      active_total += 1
                      if active_count.has_key?(val)
                        active_count[val] += 1
                      else
                        active_count[val] = 1
                      end
                    end
                  end
                end
              end
            end
          end

          # make message
          msg_str     = "#{Time.now.strftime('%Y/%m/%d %H:%M')}時点のインシデント対応アサイン状況だよ\n"
          msg_str    << sprintf("%7d / %-3d (%3d %%) %s\n", active_total, assign_total, active_total * 100 / assign_total, "Total")
          msg_str    << "------------------------------------------------------"
          # DA持ち率目標値(%)
          target_rate = 50
          assign_count.sort {|(k1, v1), (k2, v2)| v2 <=> v1 }.each do |name, count|
            wk_act_cnt   = active_count[name].to_i
            wk_act_cnt   = 0 if active_count[name].nil?
            active_rate  = wk_act_cnt * 100 / count
            target_quota = wk_act_cnt - ( count * target_rate / 100 )
            comment      = ""
            comment      = "#{target_rate}% まであと #{target_quota}件" if target_quota > 0
            msg_str << sprintf("\n%7d / %-3d (%3d %%) %s %s", wk_act_cnt, count, active_rate, pad_to_print_size(name, 17), comment)
          end

          # reply message
          message.reply(msg_str, code: true)
        rescue => e
          message.reply(e.message)
        end

        private

        # SDBバインダ情報取得
        def send_request(url, method, headers = {}, data = {})
          uri = URI.parse(url)
          req = Net::HTTP::Get.new(uri.request_uri, initheader = headers) if method == "get"
          req = Net::HTTP::Post.new(uri.request_uri, initheader = headers) if method == "post"
          data_str = ""
          data.each do |key,val|
            data_str << "&" if data_str != ""
            data_str << "#{key}=#{val}"
          end
          req.body = data_str if data_str != ""

          http = Net::HTTP.new(uri.host, uri.port)
          if !url.index("https").nil?
            http.use_ssl = true
            http.verify_mode = OpenSSL::SSL::VERIFY_NONE 
          end
          resp_json = ""
          http.start do |h|
            resp = h.request(req)
            resp_json << resp.body
          end
          resp_hash = JSON.parse(resp_json)
        rescue => e
          message.reply(e.message)
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
      end
    end
  end
end
