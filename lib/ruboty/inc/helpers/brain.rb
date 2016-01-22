require 'time'

module Ruboty
  module Inc
    module Helpers
      class Brain
        NAMESPACE = 'inc'
        def initialize(message)
          @brain = message.robot.brain.data[NAMESPACE] ||= {}
          p @brain
        end

        def save_inc_info(inc_infos)
          now = Time.now.strftime('%Y-%m-%d %H:%M:%S')
          inc_infos.each do |inc_no, inc_info|
            if @brain[inc_no].nil?
              @brain[inc_no] = {}
              @brain[inc_no][:status] = {}
              @brain[inc_no][:status][now] = inc_info[:status]
              puts "   add inc_no[#{inc_no}] member[#{inc_info[:member]}] status[#{inc_info[:status]}]"
            else
              saved_last_status = @brain[inc_no][:status].max.last
              if saved_last_status != inc_info[:status]
                @brain[inc_no][:status][now] = inc_info[:status]
                puts "update inc_no[#{inc_no}] member[#{inc_info[:member]}] status[#{saved_last_status} => #{inc_info[:status]}]"
              end
            end
          end
        end
      end
    end
  end
end

