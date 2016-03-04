require 'time'

module Ruboty
  module Inc
    module Helpers
      class Brain
        NAMESPACE = 'inc'
        def initialize(message)
          @brain = message.robot.brain.data[NAMESPACE] ||= {}
        end

        def save_slack_user_list(user_infos)
          today = Time.now.strftime('%Y-%m-%d')
          @brain['slack'] ||= {}
          @brain['slack'][:last_update] = today
          @brain['slack'][:user_info]   = user_infos
        end

        def get_slack_user_list
          @brain['slack'] ||= {}
          @brain['slack']
        end
      end
    end
  end
end

