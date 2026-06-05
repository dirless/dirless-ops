require "../../dirless/ops/webui/responses"

class Nodes::IndexPage < MainLayout
  needs nodes : Array(Dirless::Ops::WebUI::NodeResponse)

  def content
    div class: "flex items-center justify-between mb-6" do
      h1 "Nodes", class: "text-2xl font-bold text-gray-900"
      a "+ Add Node", href: "/nodes/new",
        class: "bg-blue-600 text-white px-4 py-2 rounded text-sm hover:bg-blue-700"
    end

    if nodes.empty?
      para "No nodes configured.", class: "text-gray-500"
      return
    end

    div class: "bg-white rounded-lg shadow-sm border border-gray-200 overflow-hidden" do
      table class: "w-full text-sm" do
        thead do
          tr class: "bg-gray-50" do
            th "Name", class: "px-6 py-3 text-left font-medium text-gray-500"
            th "IP", class: "px-6 py-3 text-left font-medium text-gray-500"
            th "Region", class: "px-6 py-3 text-left font-medium text-gray-500"
            th "Provider", class: "px-6 py-3 text-left font-medium text-gray-500"
            th "CPU", class: "px-6 py-3 text-left font-medium text-gray-500"
            th "Memory", class: "px-6 py-3 text-left font-medium text-gray-500"
            th "Free Disk", class: "px-6 py-3 text-left font-medium text-gray-500"
            th "Load 5m", class: "px-6 py-3 text-left font-medium text-gray-500"
            th "Primary", class: "px-6 py-3 text-left font-medium text-gray-500"
            th "Health", class: "px-6 py-3 text-left font-medium text-gray-500"
            th "", class: "px-6 py-3"
          end
        end
        tbody do
          nodes.each do |node|
            tr class: "border-t border-gray-100 hover:bg-gray-50" do
              td node.name, class: "px-6 py-3 font-mono text-xs text-gray-900"
              td node.ip, class: "px-6 py-3 font-mono text-xs text-gray-600"
              td node.region, class: "px-6 py-3 text-gray-700"
              td node.provider, class: "px-6 py-3 text-gray-500"
              td node.cpu_count.try { |count| "#{count} cores" } || "—", class: "px-6 py-3 text-gray-500"
              td node.memory_gb.try { |gigabytes| "#{gigabytes} GB" } || "—", class: "px-6 py-3 text-gray-500"
              td node.free_disk_gb.try { |gigabytes| "#{gigabytes} GB" } || "—", class: "px-6 py-3 text-gray-500"
              td node.load_5m.try(&.round(2).to_s) || "—", class: "px-6 py-3 text-gray-500"
              td class: "px-6 py-3" do
                if node.is_primary
                  span "yes", class: "bg-blue-100 text-blue-700 px-2 py-0.5 rounded text-xs"
                else
                  span "no", class: "text-gray-400 text-xs"
                end
              end
              td class: "px-6 py-3" do
                if node.probe_error
                  span "●", class: "text-red-500", title: node.probe_error.not_nil!
                elsif lpa = node.last_probed_at
                  probed_at = Time.parse_rfc3339(lpa) rescue nil
                  stale = probed_at.nil? || probed_at < Time.utc - 15.minutes
                  span "●", class: stale ? "text-red-500" : "text-green-500",
                    title: stale ? "No probe in 15 minutes" : "Last probed #{lpa}"
                else
                  span "●", class: "text-gray-300", title: "Never probed"
                end
              end
              td class: "px-6 py-3 text-right" do
                form action: "/nodes/#{node.name}", method: "post" do
                  input type: "hidden", name: "_method", value: "DELETE"
                  button type: "submit", class: "text-red-600 hover:underline text-xs",
                    onclick: "return confirm('Delete #{node.name}?')" do
                    text "Delete"
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end
