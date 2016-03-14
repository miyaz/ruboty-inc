# -*- coding: utf-8 -*-
## Ruboty::Inc::Helpers::Brain

require 'time'

module Ruboty
  module Inc
    module Helpers
      class Brain
        CMN_NAMESPACE = 'common'
        GEM_NAMESPACE = 'inc'
        def initialize(message)
          @cmn_brain = message.robot.brain.data[CMN_NAMESPACE] ||= {}
          @gem_brain = message.robot.brain.data[GEM_NAMESPACE] ||= {}
        end

        def save_slack_user_list(user_infos)
          today = Time.now.strftime('%Y-%m-%d')
          @cmn_brain['slack'] ||= {}
          @cmn_brain['slack'][:last_update] = today
          @cmn_brain['slack'][:user_info]   = user_infos
          p @cmn_brain['slack']
        end

        def get_slack_user_list
          @cmn_brain['slack'] ||= {}
          p @cmn_brain['slack']
          @cmn_brain['slack']
        end

        def save_hibiki_id(hibiki_id)
          @cmn_brain['smartdb'] ||= {}
          @cmn_brain['smartdb']['hibiki_id'] = hibiki_id
          p @cmn_brain['smartdb']
        end

        def get_hibiki_id
          @cmn_brain['smartdb'] ||= {}
          hibiki_id = @cmn_brain['smartdb']['hibiki_id']
          p @cmn_brain['smartdb']
          return hibiki_id
        end
      end
    end
  end
end

