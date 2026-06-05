require "../../dirless/ops/webui/responses"

class Customers::ShowPage < MainLayout
  needs customer : Dirless::Ops::WebUI::CustomerResponse
  needs node_statuses : Array(Dirless::Ops::WebUI::NodeStatusResponse)

  def content
    div class: "mb-6" do
      a "← Customers", href: "/customers", class: "text-blue-600 hover:underline text-sm"
    end

    div class: "flex items-start justify-between mb-6" do
      div do
        h1 customer.company || customer.name, class: "text-2xl font-bold text-gray-900"
        para customer.name, class: "text-gray-500 font-mono text-sm mt-1"
      end
      form action: "/customers/#{customer.name}", method: "post" do
        input type: "hidden", name: "_method", value: "DELETE"
        button type: "submit", class: "text-red-600 border border-red-200 px-3 py-1.5 rounded text-sm hover:bg-red-50",
          onclick: "return confirm('Delete #{customer.name}?')" do
          text "Delete"
        end
      end
    end

    div class: "bg-white rounded-lg shadow-sm border border-gray-200 divide-y divide-gray-100 mb-8" do
      field_row("Name", customer.name, mono: true)
      field_row("Email", customer.email || "-")
      field_row("Company", customer.company || "-")
      field_row("Port", customer.port.to_s)
      field_row("AWS Account ID", customer.aws_account_id || "-")
      field_row("Notes", customer.notes || "-")
      field_row("Created", customer.created_at || "-")
      field_row("Updated", customer.updated_at || "-")
    end

    div class: "flex items-center gap-3 mb-3" do
      h2 "Servers", class: "text-lg font-semibold text-gray-900"
      sync_badge(node_statuses)
    end

    if node_statuses.empty?
      para "No nodes registered.", class: "text-gray-500 text-sm"
    else
      div class: "bg-white rounded-lg shadow-sm border border-gray-200 overflow-hidden" do
        table class: "w-full text-sm" do
          thead do
            tr class: "bg-gray-50" do
              th "Node", class: "px-6 py-3 text-left font-medium text-gray-500"
              th "Region", class: "px-6 py-3 text-left font-medium text-gray-500"
              th "Status", class: "px-6 py-3 text-left font-medium text-gray-500"
              th "Service", class: "px-6 py-3 text-left font-medium text-gray-500"
              th "Enrolled Nodes", class: "px-6 py-3 text-left font-medium text-gray-500"
              th "Users", class: "px-6 py-3 text-left font-medium text-gray-500"
              th "Active Agents", class: "px-6 py-3 text-left font-medium text-gray-500"
              th "Replication Lag", class: "px-6 py-3 text-left font-medium text-gray-500"
              th "Latency", class: "px-6 py-3 text-left font-medium text-gray-500"
              th "Last Checked", class: "px-6 py-3 text-left font-medium text-gray-500"
            end
          end
          tbody do
            node_statuses.each do |node|
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
                td class: "px-6 py-3" do
                  service_badge(node.service_state)
                end
                td class: "px-6 py-3" do
                  if tc = node.tenant_count
                    span tc.to_s, class: "font-medium #{tc > 0 ? "text-gray-900" : "text-gray-400"}"
                  else
                    span "-", class: "text-gray-400"
                  end
                end
                td node.user_count.try(&.to_s) || "-", class: "px-6 py-3 text-gray-600"
                td class: "px-6 py-3" do
                  agents_badge(node)
                end
                td class: "px-6 py-3" do
                  lag_badge(node)
                end
                td node.response_time_ms.try { |millis| "#{millis}ms" } || "-", class: "px-6 py-3 text-gray-500"
                td node.checked_at || "never", class: "px-6 py-3 text-gray-400 text-xs"
              end
            end
          end
        end
      end
    end

    # Agents detail: collect all agents from the primary node's data
    primary_agents = node_statuses
      .find(&.is_primary)
      .try(&.agents)

    if primary_agents && !primary_agents.empty?
      h2 "Connected Agents", class: "text-lg font-semibold text-gray-900 mt-8 mb-3"
      div class: "bg-white rounded-lg shadow-sm border border-gray-200 overflow-hidden" do
        table class: "w-full text-sm" do
          thead do
            tr class: "bg-gray-50" do
              th "Agent ID", class: "px-6 py-3 text-left font-medium text-gray-500"
              th "Hostname", class: "px-6 py-3 text-left font-medium text-gray-500"
              th "Last Seen", class: "px-6 py-3 text-left font-medium text-gray-500"
            end
          end
          tbody do
            primary_agents.each do |agent|
              tr class: "border-t border-gray-100" do
                td agent.agent_id || "-", class: "px-6 py-3 font-mono text-sm"
                td agent.hostname || "-", class: "px-6 py-3 text-gray-600"
                td agent.last_seen_at || "-", class: "px-6 py-3 text-gray-400 text-xs"
              end
            end
          end
        end
      end
    end
  end

  private def agents_badge(node : Dirless::Ops::WebUI::NodeStatusResponse)
    if count = node.active_agents
      css = count > 0 ? "text-gray-900 font-medium" : "text-gray-400"
      span count.to_s, class: css
    else
      span "-", class: "text-gray-400"
    end
  end

  private def sync_badge(nodes : Array(Dirless::Ops::WebUI::NodeStatusResponse))
    up_nodes = nodes.select { |node| node.status == "up" }
    return if up_nodes.size < 2

    max_lag = up_nodes.compact_map(&.replication_lag_seconds).max?
    if max_lag
      if max_lag <= 120
        span "In sync", class: "text-xs font-medium px-2 py-0.5 rounded bg-green-100 text-green-700"
      else
        span "Lag: #{format_lag(max_lag)}", class: "text-xs font-medium px-2 py-0.5 rounded bg-red-100 text-red-700"
      end
    else
      enrolled_counts = up_nodes.compact_map(&.tenant_count).uniq!
      user_counts = up_nodes.compact_map(&.user_count).uniq!
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
    elsif lag = node.replication_lag_seconds
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

  private def service_badge(state : String?)
    label, css = case state
                 when "active"           then {"active", "bg-green-100 text-green-800"}
                 when "failed"           then {"failed", "bg-red-100 text-red-800"}
                 when "inactive", "dead" then {state.not_nil!, "bg-gray-100 text-gray-600"}
                 when nil                then {"unknown", "bg-gray-100 text-gray-400"}
                 else                         {state.not_nil!, "bg-yellow-100 text-yellow-800"}
                 end
    span label, class: "px-2 py-0.5 rounded text-xs font-medium #{css}"
  end

  private def status_badge(status : String)
    css = case status
          when "up"   then "bg-green-100 text-green-800"
          when "down" then "bg-red-100 text-red-800"
          else             "bg-gray-100 text-gray-600"
          end
    span status, class: "px-2 py-0.5 rounded text-xs font-medium #{css}"
  end

  private def field_row(label : String, value : String, mono : Bool = false, sensitive : Bool = false)
    div class: "px-6 py-4 flex" do
      span label, class: "w-40 text-sm font-medium text-gray-500 shrink-0"
      if sensitive
        div class: "flex items-center gap-2" do
          span value, class: "font-mono text-sm text-gray-900 blur-sm hover:blur-none transition-all cursor-pointer",
            title: "Click to reveal"
        end
      elsif mono
        span value, class: "text-sm text-gray-900 font-mono"
      else
        span value, class: "text-sm text-gray-900"
      end
    end
  end
end
