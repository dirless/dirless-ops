module Dirless
  module Ops
    module CLI
      module Table
        def self.print(headers : Array(String), rows : Array(Array(String))) : Nil
          widths = headers.map_with_index do |h, i|
            ([h.size] + rows.map { |r| r[i]?.try(&.size) || 0 }).max
          end

          puts headers.map_with_index { |h, i| h.ljust(widths[i]) }.join("  ")
          puts widths.map { |w| "-" * w }.join("  ")
          rows.each do |row|
            puts row.map_with_index { |cell, i| cell.ljust(widths[i]) }.join("  ")
          end
        end
      end

      ANSI_GREEN   = "\e[32m"
      ANSI_RED     = "\e[31m"
      ANSI_YELLOW  = "\e[33m"
      ANSI_RESET   = "\e[0m"

      def self.colorize_status(status : String) : String
        case status
        when "up"      then "#{ANSI_GREEN}#{status}#{ANSI_RESET}"
        when "down"    then "#{ANSI_RED}#{status}#{ANSI_RESET}"
        else                "#{ANSI_YELLOW}#{status}#{ANSI_RESET}"
        end
      end
    end
  end
end
