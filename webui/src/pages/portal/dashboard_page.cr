class Portal::DashboardPage < PortalLayout
  needs customer_name : String
  needs provisioned : Bool
  needs email_verified : Bool
  needs customer_info : Dirless::Ops::WebUI::CustomerResponse?
  needs customer_status : Dirless::Ops::WebUI::CustomerStatusResponse?

  def page_title : String
    "Dashboard"
  end

  def content
    raw "<style>#{extra_css}</style>"
    raw "<script>#{extra_js}</script>"

    subdomain = "#{@customer_name}.#{ENV.fetch("BACKEND_DOMAIN", "dirless.com")}"
    hmac_secret = @customer_info.try(&.hmac_secret) || ""
    aws_account_id = @customer_info.try(&.aws_account_id)
    tenant_id = @customer_info.try(&.tenant_id) || ""

    # Non-AWS (manually managed) customers have no EC2 IMDS to derive a tenant_id
    # from, so the enroll command must pin the stored tenant_id explicitly.
    # AWS customers (aws_account_id set) keep deriving it on the host from IMDS.
    manual_tenant = (aws_account_id.nil? || aws_account_id.empty?) && !tenant_id.empty?

    unless @email_verified
      div class: "banner banner-warn" do
        text "📧 Please verify your email address. Check your inbox for a link from info@dirless.com. "
        form action: "/resend-verification", method: "post", style: "display:inline" do
          button type: "submit", style: "background:none;border:none;color:inherit;text-decoration:underline;cursor:pointer;padding:0;font:inherit;" do
            text "Resend →"
          end
        end
      end
    end

    if @provisioned
      # Provisioned state

      # Compute aggregate stats from node statuses.
      # Agents are deduplicated by agent_id across backend nodes so the same
      # enrolled machine isn't counted twice (it may appear on primary + replica).
      total_users = 0
      seen_agent_ids = Set(String).new

      if cs = @customer_status
        cs.nodes.each do |node|
          # user_count is the same on every Raft replica — only count the primary
          # to avoid double (or triple) counting identical data.
          total_users += node.user_count || 0 if node.is_primary
          (node.agents || [] of Dirless::Ops::WebUI::AgentInfo).each do |agent|
            if id = agent.agent_id
              seen_agent_ids << id
            end
          end
        end
      end

      enrolled_count = seen_agent_ids.size

      div class: "stats-grid" do
        div class: "stat-card" do
          div class: "stat-value" do
            text enrolled_count.to_s
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

      # Tenant ID — only manually-managed (non-AWS) customers need this; it's the
      # value the enroll command pins below, and what manual directory data is
      # stored under on the backend.
      if manual_tenant
        div class: "info-section" do
          div class: "info-label" do
            text "Tenant ID"
          end
          div class: "code-box" do
            text tenant_id
          end
        end
      end

      # Build the enroll command, pinning --tenant-id for non-AWS customers.
      enroll_command = String.build do |io|
        io << %(<span class="c-cmd">dirless-cli enroll</span> \\\n)
        io << %(  <span class="c-flag">--server</span> <span class="c-val">https://#{subdomain}</span> \\\n)
        io << %(  <span class="c-flag">--token</span>  <span class="c-val">#{hmac_secret}</span>)
        if manual_tenant
          io << %( \\\n  <span class="c-flag">--tenant-id</span> <span class="c-val">#{tenant_id}</span>)
        end
      end

      # Enrollment instructions
      div class: "section-heading" do
        text "Enroll a node"
      end

      details class: "terminal-box terminal-collapsible" do
        summary class: "terminal-bar" do
          span class: "dot dot-r"
          span class: "dot dot-y"
          span class: "dot dot-g"
          span "Enroll a node in 30 seconds", class: "terminal-title"
          span " - Click to expand", class: "terminal-expand-hint"
        end
        div class: "terminal-body" do
          raw <<-HTML
<pre><span class="c-comment"># install (RHEL / Amazon Linux 2023)</span>
<span class="c-cmd">curl</span> <span class="c-flag">-fsSL</span> <span class="c-val">https://dirless.com/rpm/dirless.repo</span> \
  <span class="c-flag">-o</span> /etc/yum.repos.d/dirless.repo
<span class="c-cmd">dnf install</span> <span class="c-val">-y dirless-cli dirless-agent</span>

<span class="c-comment"># enroll this host (also writes /etc/dirless/dirless-agent.toml)</span>
#{enroll_command}

<span class="c-comment"># start the agent</span>
<span class="c-cmd">systemctl enable</span> <span class="c-flag">--now</span> <span class="c-val">dirless-agent</span></pre>
HTML
        end
      end

      # Syncer — install
      div class: "section-heading" do
        text "Install the syncer"
      end

      div class: "terminal-box" do
        div class: "terminal-bar" do
          span class: "dot dot-r"
          span class: "dot dot-y"
          span class: "dot dot-g"
          span "Install dirless-syncer", class: "terminal-title"
        end
        div class: "terminal-body" do
          raw <<-HTML
<pre><span class="c-comment"># Requires an EC2 instance with an IAM role granting identitystore:List* and sso:ListInstances</span>

<span class="c-comment"># install (RHEL / Amazon Linux 2023)</span>
<span class="c-cmd">curl</span> <span class="c-flag">-fsSL</span> <span class="c-val">https://dirless.com/rpm/dirless.repo</span> \\
  <span class="c-flag">-o</span> /etc/yum.repos.d/dirless.repo
<span class="c-cmd">dnf install</span> <span class="c-val">-y dirless-syncer</span></pre>
HTML
        end
      end

      # Syncer — configure
      div class: "section-heading" do
        text "Configure and start the syncer"
      end

      div class: "terminal-box" do
        div class: "terminal-bar" do
          span class: "dot dot-r"
          span class: "dot dot-y"
          span class: "dot dot-g"
          span "Configure dirless-syncer", class: "terminal-title"
        end
        div class: "terminal-body" do
          raw <<-HTML
<pre><span class="c-comment"># write config — the syncer self-enrolls on first start using the token below</span>
<span class="c-cmd">cat</span> &gt; /etc/dirless/dirless-syncer.toml &lt;&lt; <span class="c-val">'EOF'</span>
[backend]
url              = "<span class="c-val">https://#{subdomain}</span>"
enrollment_token = "<span class="c-val">#{hmac_secret}</span>"

<span class="c-comment"># [identity_center]                                      # normally auto-detected</span>
<span class="c-comment"># identity_store_id = "d-xxxxxxxxxx"                   # override if auto-detect fails</span>
<span class="c-comment"># region            = "us-east-1"                      # override if auto-detect fails</span>

[syncer]
<span class="c-comment"># id = "syncer-01"                                      # normally auto-detected from EC2 instance ID</span>
interval_seconds = 300
<span class="c-val">EOF</span>

<span class="c-comment"># start the syncer — it enrolls itself, then begins syncing</span>
<span class="c-cmd">systemctl enable</span> <span class="c-flag">--now</span> <span class="c-val">dirless-syncer</span></pre>
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
                  th "Sync"
                  th "Response"
                  th "Last Checked"
                end
              end
              tbody do
                cs.nodes.each do |node|
                  starting = node.status != "up" &&
                             !{"active", "failed"}.includes?(node.service_state)
                  status_class, status_label = if node.status == "up"
                                                 {"badge badge-ok", "Up"}
                                               elsif starting
                                                 {"badge badge-muted", "Starting"}
                                               else
                                                 {"badge badge-error", "Down"}
                                               end
                  tr do
                    td node.region
                    td node.node_name
                    td do
                      span status_label, class: status_class
                    end
                    td do
                      if node.is_primary
                        span "primary", class: "badge badge-muted"
                      elsif lag = node.replication_lag_seconds
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
    else
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
        div class: "token-summary", onclick: "toggleToken(this)", style: "cursor:pointer" do
          span "••••••••••••••••", class: "token-masked"
          span hmac_secret.empty? ? "(not yet available)" : hmac_secret,
            class: "token-value-inline code-box",
            style: "display:none;flex:1;margin:0;padding:0;background:none;border:none;"
          span "Reveal", class: "token-reveal-label"
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

    .section-heading {
      font-size: 1rem;
      font-weight: 700;
      color: var(--text);
      margin-bottom: 0.85rem;
      margin-top: 0.5rem;
    }

    .terminal-collapsible > summary {
      cursor: pointer;
      list-style: none;
      user-select: none;
    }

    .terminal-collapsible > summary::-webkit-details-marker { display: none; }

    .terminal-collapsible > summary::after {
      content: "▶";
      font-size: 0.6rem;
      color: var(--muted);
      margin-left: auto;
      transition: transform 0.15s ease;
    }

    .terminal-collapsible[open] > summary::after {
      transform: rotate(90deg);
    }

    .terminal-collapsible:not([open]) > summary {
      border-bottom: none;
    }

    .terminal-collapsible[open] .terminal-expand-hint { display: none; }

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

  private def extra_js : String
    <<-JS
    function toggleToken(el) {
      var masked = el.querySelector('.token-masked');
      var value  = el.querySelector('.token-value-inline');
      var label  = el.querySelector('.token-reveal-label');
      if (masked.style.display === 'none') {
        masked.style.display = '';
        value.style.display  = 'none';
        label.textContent    = 'Reveal';
      } else {
        masked.style.display = 'none';
        value.style.display  = '';
        label.textContent    = 'Hide';
      }
    }
    JS
  end
end
