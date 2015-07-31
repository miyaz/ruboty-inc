require 'net/http'
require 'openssl'
require 'json'

module Ruboty
  module Inc
    module Actions
      class AssignCount < Ruboty::Actions::Base
        # set env var
        SDB_USER      = ENV['SDB_USER']
        SDB_PASS      = ENV['SDB_PASS']
        SDB_URL       = ENV['SDB_URL']
        ISE_AUTH_PATH = ENV['ISE_AUTH_PATH']
        SDB_AUTH_PATH = ENV['SDB_AUTH_PATH']

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
          resp_hash  = send_request(url, "post", headers, {})
          hibiki_id  = resp_hash['cookie']['value']
          csrf_token = resp_hash['csrfToken']

          # get total record count
          view_path   = "/hibiki/rest/1/binders/12609/views/10200/documents"
          url         = "#{SDB_URL}#{view_path}"
          headers     = {'Accept' =>'application/json', 'Cookie' => "HIBIKI=#{hibiki_id}"}
          resp_hash   = send_request(url, "get", headers, {})
          total_count = resp_hash['totalCount'].to_i if !resp_hash['totalCount'].nil?

          # get assign count
          assign_count = {}
          page_size    = 1000
          max_page_num = (total_count/page_size.to_f).ceil
          (1..max_page_num).each do |num|
            url        = "#{SDB_URL}#{view_path}?pageSize=#{page_size}&pageNumber=#{num}"
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

          # reply message
          msg_str = "#{Time.now.strftime('%Y/%m/%d %H:%M')}時点のインシデント対応アサイン状況です。\n"
          assign_count.sort {|(k1, v1), (k2, v2)| v2 <=> v1 }.each do |name, count|
            msg_str << sprintf("%7d  %s\n", count, name)
          end
          message.reply(msg_str, code: true)
        rescue => e
          message.reply(e.message)
        end

        private

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
      end
    end
  end
end
