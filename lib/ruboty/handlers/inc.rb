require "ruboty/inc/actions/assign_count"

module Ruboty
  module Handlers
    class Inc < Base
      on /inc assign count/, name: 'assign_count', description: 'show the assignment of the incident'

      def assign_count(message)
        Ruboty::Inc::Actions::AssignCount.new(message).call
      end

    end
  end
end
