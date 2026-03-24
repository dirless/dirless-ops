require "../../dirless/ops/webui/responses"

class Home::IndexPage < MainLayout
  needs statuses : Array(Dirless::Ops::WebUI::CustomerStatusResponse)

  def content
    h1 "Status", class: "text-2xl font-bold text-gray-900 mb-6"

    if statuses.empty?
      para "No customers configured.", class: "text-gray-500"
      return
    end

    statuses.each do |customer|
      div class: "mb-8 bg-white rounded-lg shadow-sm border border-gray-200" do
        div class: "px-6 py-4 border-b border-gray-200" do
          div class: "flex items-center justify-between" do
            div class: "flex items-center gap-3" do
              div do
                span customer.label || customer.name, class: "font-semibold text-gray-900"
                if customer.label
                  span " · Customer: #{customer.name}", class: "text-sm text-gray-500 ml-2"
                end
              end
              sync_badge(customer.nodes)
            end
            a "Details", href: "/customers/#{customer.name}",
              class: "text-sm text-blue-600 hover:underline"
          end
        end
        div class: "overflow-x-auto" do
          table class: "w-full text-sm" do
            thead do
              tr class: "bg-gray-50" do
                th "Node", class: "px-6 py-3 text-left font-medium text-gray-500"
                th "Region", class: "px-6 py-3 text-left font-medium text-gray-500"
                th "Status", class: "px-6 py-3 text-left font-medium text-gray-500"
                th "Enrolled Nodes", class: "px-6 py-3 text-left font-medium text-gray-500"
                th "Users", class: "px-6 py-3 text-left font-medium text-gray-500"
                th "Replication Lag", class: "px-6 py-3 text-left font-medium text-gray-500"
                th "Checked At", class: "px-6 py-3 text-left font-medium text-gray-500"
              end
            end
            tbody do
              customer.nodes.each do |node|
                tr class: "border-t border-gray-100" do
                  td class: "px-6 py-3" do
                    span node.node_name
                    if node.is_primary
                      span " primary", class: "ml-2 text-xs bg-blue-100 text-blue-700 px-2 py-0.5 rounded"
                    end
                  end
                  td node.region, class: "px-6 py-3 text-gray-600"
                  td class: "px-6 py-3" do
                    status_badge(node.status)
                  end
                  td node.tenant_count.try(&.to_s) || "-", class: "px-6 py-3 text-gray-600"
                  td node.user_count.try(&.to_s) || "-", class: "px-6 py-3 text-gray-600"
                  td class: "px-6 py-3" do
                    lag_badge(node)
                  end
                  td node.checked_at || "never", class: "px-6 py-3 text-gray-400 text-xs"
                end
              end
            end
          end
        end
      end
    end
  end

  private def sync_badge(nodes : Array(Dirless::Ops::WebUI::NodeStatusResponse))
    up_nodes = nodes.select { |n| n.status == "up" }
    return if up_nodes.size < 2

    max_lag = up_nodes.compact_map(&.replication_lag_seconds).max?

    if max_lag
      if max_lag <= 120
        span "In sync", class: "text-xs font-medium px-2 py-0.5 rounded bg-green-100 text-green-700"
      else
        span "Lag: #{format_lag(max_lag)}", class: "text-xs font-medium px-2 py-0.5 rounded bg-red-100 text-red-700"
      end
    else
      # Fall back to count comparison when lag data not yet available
      enrolled_counts = up_nodes.map(&.tenant_count).compact.uniq
      user_counts     = up_nodes.map(&.user_count).compact.uniq
      return if enrolled_counts.size == 0 && user_counts.size == 0
      in_sync = enrolled_counts.size <= 1 && user_counts.size <= 1
      if in_sync
        span "In sync", class: "text-xs font-medium px-2 py-0.5 rounded bg-green-100 text-green-700"
      else
        span "Out of sync", class: "text-xs font-medium px-2 py-0.5 rounded bg-red-100 text-red-700"
      end
    end
  end

  private def lag_badge(node : Dirless::Ops::WebUI::NodeStatusResponse)
    if node.is_primary
      span "primary", class: "text-xs text-gray-400"
    elsif (lag = node.replication_lag_seconds)
      css = lag <= 120 ? "bg-green-100 text-green-800" : "bg-red-100 text-red-800"
      span format_lag(lag), class: "px-2 py-0.5 rounded text-xs font-medium #{css}"
    else
      span "-", class: "text-gray-400"
    end
  end

  private def format_lag(seconds : Int32) : String
    if seconds < 60
      "#{seconds}s"
    elsif seconds < 3600
      "#{seconds // 60}m #{seconds % 60}s"
    else
      "#{seconds // 3600}h #{(seconds % 3600) // 60}m"
    end
  end

  private def status_badge(status : String)
    css = case status
          when "up"   then "bg-green-100 text-green-800"
          when "down" then "bg-red-100 text-red-800"
          else             "bg-gray-100 text-gray-600"
          end
    span status, class: "px-2 py-0.5 rounded text-xs font-medium #{css}"
  end
end
