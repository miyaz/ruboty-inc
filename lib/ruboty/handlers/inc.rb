require "ruboty/inc/helpers/brain"
require "ruboty/inc/helpers/smartdb"
require "ruboty/inc/helpers/slack"
require "ruboty/inc/helpers/util"
require "ruboty/inc/actions/assign_count"
require "ruboty/inc/actions/assign_point"
require "ruboty/inc/actions/status"
require "ruboty/inc/actions/stagnate"

module Ruboty
  module Handlers
    class Inc < Base
      $stdout.sync = true

      on /inc +assign +count *\z/, name: 'assign_count', description: 'show the assignment of the incident'
      on /inc +assign +point*\z/,  name: 'assign_point', description: 'show the summary of incident point'
      on(/inc +status +(?<cmd>save|change|souse) *(?<period>\d+)*\z/,
                                   name: 'status',       description: 'show the status detail of the incident')
      on(/inc +stagnate *(?<who>all)*\z/,
                                   name: 'stagnate',     description: 'show the stagnate status of the incident')

      def assign_count(message)
        Ruboty::Inc::Actions::AssignCount.new(message).call
      end

      def assign_point(message)
        Ruboty::Inc::Actions::AssignPoint.new(message).call
      end

      def status(message)
        Ruboty::Inc::Actions::Status.new(message).call
      end

      def stagnate(message)
        Ruboty::Inc::Actions::Stagnate.new(message).call
      end

    end
  end
end
