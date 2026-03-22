module Dirless
  module Ops
    module WebUI
      module Auth
        def self.valid?(username : String, password : String) : Bool
          path = ENV.fetch("ADMIN_USERS_FILE", "/etc/dirless-ops/admin-users.toml")
          File.read(path).each_line do |line|
            line = line.strip
            next if line.empty? || line.starts_with?('#')
            parts = line.split(':', 2)
            next unless parts.size == 2
            return true if parts[0] == username && parts[1] == password
          end
          false
        rescue IO::Error
          false
        end
      end
    end
  end
end
