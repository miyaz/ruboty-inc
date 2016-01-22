require 'net/http'
require 'openssl'
require 'json'

module Ruboty
  module Inc
    module Helpers
      class Sdb
        def initialize(message)
          # @message = message
        end

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

      end
    end
  end
end
