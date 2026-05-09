class Portal::DashboardPage < PortalLayout
  needs customer_name : String
  needs provisioned : Bool
  needs customer_info : Dirless::Ops::WebUI::CustomerResponse?
  needs customer_status : Dirless::Ops::WebUI::CustomerStatusResponse?

  def page_title : String
    "Dashboard"
  end

  def content
    raw "<style>#{extra_css}</style>"

    subdomain = "#{@customer_name}.dirless.com"
    hmac_secret = @customer_info.try(&.hmac_secret) || ""

    unless @provisioned
      # Pending provisioning state
      div class: "banner banner-warn" do
        text "⚙ Your backend is being provisioned. This usually takes a few minutes. You'll be able to enroll nodes once it's ready."
      end

      div class: "info-section" do
        div class: "info-label" do
          text "Your subdomain"
        end
        div class: "code-box" do
          text subdomain
        end
      end

      div class: "info-section" do
        div class: "info-label" do
          text "Enrollment token"
        end
        details class: "token-details" do
          summary class: "token-summary" do
            span "••••••••••••••••", class: "token-masked"
            span "Reveal", class: "token-reveal-label"
          end
          div class: "code-box token-value" do
            text hmac_secret.empty? ? "(not yet available)" : hmac_secret
          end
        end
      end

      div class: "stats-grid" do
        div class: "stat-card stat-card-dim" do
          div class: "stat-value" do
            text "0"
          end
          div class: "stat-label" do
            text "Enrolled nodes"
          end
        end
        div class: "stat-card stat-card-dim" do
          div class: "stat-value" do
            text "0"
          end
          div class: "stat-label" do
            text "Synced users"
          end
        end
        div class: "stat-card stat-card-dim" do
          div class: "stat-value stat-value-pending" do
            text "Pending"
          end
          div class: "stat-label" do
            text "Last sync"
          end
        end
      end

    else
      # Provisioned state

      # Compute aggregate stats from node statuses
      total_tenants  = 0
      total_users    = 0
      total_agents   = 0
      last_checked   = ""
      ok_nodes       = 0
      max_lag        = nil.as(Int32?)

      if cs = @customer_status
        cs.nodes.each do |n|
          total_tenants  += n.tenant_count || 0
          total_users    += n.user_count   || 0
          total_agents   += n.active_agents || 0
          ok_nodes       += 1 if n.status == "up"
          if last_checked.empty? && n.checked_at
            last_checked = n.checked_at.not_nil!
          end
          if (lag = n.replication_lag_seconds)
            max_lag = lag if max_lag.nil? || lag > max_lag.not_nil!
          end
        end
      end

      node_count = @customer_status.try(&.nodes.size) || 0

      div class: "stats-grid" do
        div class: "stat-card" do
          div class: "stat-value" do
            text node_count.to_s
          end
          div class: "stat-label" do
            text "Enrolled nodes"
          end
        end
        div class: "stat-card" do
          div class: "stat-value" do
            text total_users.to_s
          end
          div class: "stat-label" do
            text "Synced users"
          end
        end
        div class: "stat-card" do
          div class: "stat-value" do
            text total_agents.to_s
          end
          div class: "stat-label" do
            text "Active agents"
          end
        end
      end

      # Subdomain info
      div class: "info-section" do
        div class: "info-label" do
          text "Your subdomain"
        end
        div class: "code-box" do
          text subdomain
        end
      end

      # Enrollment token
      div class: "info-section" do
        div class: "info-label" do
          text "Enrollment token"
        end
        details class: "token-details" do
          summary class: "token-summary" do
            span "••••••••••••••••", class: "token-masked"
            span "Reveal", class: "token-reveal-label"
          end
          div class: "code-box token-value" do
            text hmac_secret
          end
        end
      end

      # Enrollment instructions
      div class: "section-heading" do
        text "Enroll a node"
      end

      div class: "terminal-box" do
        div class: "terminal-bar" do
          span class: "dot dot-r"
          span class: "dot dot-y"
          span class: "dot dot-g"
          span "Enroll a node in 30 seconds", class: "terminal-title"
        end
        div class: "terminal-body" do
          raw <<-HTML
<pre><span class="c-comment"># download dirless-cli (Linux x86_64)</span>
<span class="c-cmd">curl</span> <span class="c-flag">-fsSL</span> <span class="c-val">https://github.com/weirdbricks/dirless/releases/latest/download/dirless-cli</span> \
  <span class="c-flag">-o</span> /usr/local/bin/dirless-cli <span class="c-flag">&amp;&amp;</span> chmod <span class="c-val">+x</span> /usr/local/bin/dirless-cli

<span class="c-comment"># one-time enrollment per host</span>
<span class="c-cmd">dirless-cli enroll</span> \\
  <span class="c-flag">--server</span> <span class="c-val">https://#{subdomain}</span> \\
  <span class="c-flag">--token</span>  <span class="c-val">$ENROLLMENT_TOKEN</span></pre>
HTML
        end
      end

      # Nodes table
      if cs = @customer_status
        unless cs.nodes.empty?
          div class: "section-heading" do
            text "Node status"
          end
          div class: "table-wrap" do
            table class: "nodes-table" do
              thead do
                tr do
                  th "Region"
                  th "Node"
                  th "Status"
                  th "Replication Lag"
                  th "Response"
                  th "Last Checked"
                end
              end
              tbody do
                cs.nodes.each do |node|
                  status_class = node.status == "up" ? "badge badge-ok" : "badge badge-error"
                  tr do
                    td node.region
                    td node.node_name
                    td do
                      span node.status, class: status_class
                    end
                    td do
                      if node.is_primary
                        span "primary", class: "badge badge-muted"
                      elsif (lag = node.replication_lag_seconds)
                        lag_class = lag <= 120 ? "badge badge-ok" : "badge badge-error"
                        span format_lag(lag), class: lag_class
                      else
                        span "In sync", class: "badge badge-ok"
                      end
                    end
                    td do
                      if rt = node.response_time_ms
                        text "#{rt}ms"
                      else
                        text "—"
                      end
                    end
                    td(node.checked_at ? time_ago(node.checked_at.not_nil!) : "—")
                  end
                end
              end
            end
          end
        end
      end
    end
  end

  private def time_ago(rfc3339 : String) : String
    t = Time.parse_rfc3339(rfc3339)
    secs = (Time.utc - t).total_seconds.to_i
    secs = 0 if secs < 0
    if secs < 60
      "#{secs}s ago"
    elsif secs < 3600
      "#{secs // 60}m #{secs % 60}s ago"
    else
      "#{secs // 3600}h ago"
    end
  rescue
    rfc3339
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

  private def extra_css : String
    <<-CSS
    .banner {
      padding: 0.85rem 1.1rem;
      border-radius: 8px;
      font-size: 0.9rem;
      margin-bottom: 1.75rem;
      line-height: 1.6;
    }

    .banner-warn {
      background: rgba(210, 153, 34, 0.12);
      border: 1px solid rgba(210, 153, 34, 0.35);
      color: #e3b341;
    }

    .stats-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
      gap: 1rem;
      margin-bottom: 2rem;
    }

    .stat-card {
      background: var(--surface);
      border: 1px solid var(--border);
      border-radius: 10px;
      padding: 1.25rem 1.5rem;
    }

    .stat-card-dim {
      opacity: 0.5;
    }

    .stat-value {
      font-size: 2rem;
      font-weight: 800;
      color: var(--text);
      line-height: 1.1;
      margin-bottom: 0.35rem;
    }

    .stat-value-pending {
      color: var(--muted);
    }

    .stat-value-warn {
      color: #f85149;
    }

    .stat-label {
      font-size: 0.82rem;
      color: var(--muted);
      font-weight: 500;
    }

    .info-section {
      margin-bottom: 1.5rem;
    }

    .info-label {
      font-size: 0.82rem;
      font-weight: 600;
      color: var(--muted);
      text-transform: uppercase;
      letter-spacing: 0.06em;
      margin-bottom: 0.4rem;
    }

    .code-box {
      background: var(--surface);
      border: 1px solid var(--border);
      border-radius: 6px;
      padding: 0.65rem 0.9rem;
      font-family: "SFMono-Regular", Consolas, "Liberation Mono", Menlo, monospace;
      font-size: 0.88rem;
      color: var(--text-dim);
      word-break: break-all;
    }

    .token-details {
      background: transparent;
      border: none;
      padding: 0;
    }

    .token-summary {
      display: flex;
      align-items: center;
      gap: 0.75rem;
      cursor: pointer;
      list-style: none;
      background: var(--surface);
      border: 1px solid var(--border);
      border-radius: 6px;
      padding: 0.65rem 0.9rem;
      font-family: "SFMono-Regular", Consolas, "Liberation Mono", Menlo, monospace;
      font-size: 0.88rem;
      color: var(--text-dim);
    }

    .token-summary::-webkit-details-marker { display: none; }

    .token-masked {
      flex: 1;
      letter-spacing: 0.15em;
      color: var(--muted);
    }

    .token-reveal-label {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
      font-size: 0.8rem;
      color: var(--accent);
      font-weight: 600;
      flex-shrink: 0;
    }

    .token-value {
      margin-top: 0.4rem;
      border-top-left-radius: 6px;
      border-top-right-radius: 6px;
    }

    .section-heading {
      font-size: 1rem;
      font-weight: 700;
      color: var(--text);
      margin-bottom: 0.85rem;
      margin-top: 0.5rem;
    }

    .terminal-box {
      background: var(--surface);
      border: 1px solid var(--border);
      border-radius: 10px;
      overflow: hidden;
      margin-bottom: 2rem;
    }

    .terminal-bar {
      background: var(--surface2);
      border-bottom: 1px solid var(--border);
      padding: 0.6rem 1rem;
      font-size: 0.78rem;
      color: var(--muted);
      display: flex;
      align-items: center;
      gap: 0.5rem;
    }

    .terminal-title {
      margin-left: 0.5rem;
    }

    .dot {
      width: 10px;
      height: 10px;
      border-radius: 50%;
      display: inline-block;
      flex-shrink: 0;
    }

    .dot-r { background: #f85149; }
    .dot-y { background: #d29922; }
    .dot-g { background: #3fb950; }

    .terminal-body pre {
      padding: 1.25rem 1.5rem;
      font-family: "SFMono-Regular", Consolas, "Liberation Mono", Menlo, monospace;
      font-size: 0.85rem;
      line-height: 1.7;
      overflow-x: auto;
      color: var(--text-dim);
    }

    .c-comment { color: var(--muted); }
    .c-cmd     { color: #3fb950; }
    .c-flag    { color: var(--accent); }
    .c-val     { color: #d2a8ff; }

    .table-wrap {
      overflow-x: auto;
      margin-bottom: 2rem;
    }

    .nodes-table {
      width: 100%;
      border-collapse: collapse;
      font-size: 0.875rem;
    }

    .nodes-table thead tr {
      border-bottom: 1px solid var(--border);
    }

    .nodes-table th {
      text-align: left;
      padding: 0.6rem 0.85rem;
      font-size: 0.78rem;
      font-weight: 600;
      color: var(--muted);
      text-transform: uppercase;
      letter-spacing: 0.06em;
      white-space: nowrap;
    }

    .nodes-table td {
      padding: 0.65rem 0.85rem;
      color: var(--text-dim);
      border-bottom: 1px solid var(--border);
      white-space: nowrap;
    }

    .nodes-table tbody tr:last-child td {
      border-bottom: none;
    }

    .nodes-table tbody tr:hover td {
      background: var(--surface2);
    }

    .badge {
      display: inline-block;
      padding: 0.15rem 0.55rem;
      border-radius: 100px;
      font-size: 0.75rem;
      font-weight: 600;
    }

    .badge-ok {
      background: rgba(63, 185, 80, 0.15);
      color: #3fb950;
      border: 1px solid rgba(63, 185, 80, 0.3);
    }

    .badge-error {
      background: rgba(248, 81, 73, 0.15);
      color: #ff7b72;
      border: 1px solid rgba(248, 81, 73, 0.3);
    }

    .badge-muted {
      background: rgba(139, 148, 158, 0.12);
      color: var(--muted);
      border: 1px solid rgba(139, 148, 158, 0.25);
    }

    .badge-primary {
      display: inline-block;
      margin-left: 0.4rem;
      padding: 0.1rem 0.45rem;
      border-radius: 4px;
      font-size: 0.72rem;
      font-weight: 600;
      background: rgba(88, 166, 255, 0.12);
      color: var(--accent);
      border: 1px solid rgba(88, 166, 255, 0.25);
    }
    CSS
  end
end
