require "grip"

module Dirless
  module Ops
    module Controllers
      class Health
        include Grip::Controllers::HTTP

        def get(context : Context) : Context
          context.put_status(200).json({"status" => "ok"}).halt
        end
      end
    end
  end
end
