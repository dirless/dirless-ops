abstract class PortalLayout
  include Lucky::HTMLPage

  abstract def content
  abstract def page_title : String

  needs email : String
  needs company : String

  def render
    html_doctype
    html lang: "en" do
      head do
        title "Dirless — #{page_title}"
        meta charset: "utf-8"
        meta name: "viewport", content: "width=device-width, initial-scale=1"
        raw "<style>#{portal_css}</style>"
      end
      body do
        div class: "layout" do
          # Sidebar
          aside class: "sidebar" do
            div class: "sidebar-logo" do
              a href: "/dashboard" do
                span "dir", class: "logo-main"
                span "less", class: "logo-accent"
              end
            end
            nav class: "sidebar-nav" do
              a "Dashboard", href: "/dashboard", class: "nav-item nav-item-active"
            end
            div class: "sidebar-footer" do
              div class: "sidebar-user" do
                div class: "sidebar-company" do
                  text company
                end
                div class: "sidebar-email" do
                  text email
                end
              end
              form action: "/logout", method: "post" do
                button type: "submit", class: "signout-btn" do
                  text "Sign out"
                end
              end
            end
          end
          # Main
          main class: "main" do
            div class: "topbar" do
              h1 page_title, class: "page-title"
            end
            div class: "main-content" do
              content
            end
          end
        end
      end
    end
  end

  private def portal_css : String
    <<-CSS
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

    :root {
      --bg:       #0d1117;
      --surface:  #161b22;
      --surface2: #1c2330;
      --border:   #30363d;
      --accent:   #58a6ff;
      --accent2:  #3fb950;
      --muted:    #8b949e;
      --text:     #e6edf3;
      --text-dim: #c9d1d9;
      --danger:   #f85149;
      --warn:     #d29922;
    }

    html { scroll-behavior: smooth; }

    body {
      background: var(--bg);
      color: var(--text);
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
      font-size: 16px;
      line-height: 1.6;
    }

    a { color: var(--accent); text-decoration: none; }
    a:hover { text-decoration: underline; }

    .layout {
      display: flex;
      height: 100vh;
    }

    .sidebar {
      width: 240px;
      background: var(--surface);
      border-right: 1px solid var(--border);
      display: flex;
      flex-direction: column;
      position: fixed;
      height: 100vh;
      overflow-y: auto;
    }

    .sidebar-logo {
      padding: 1.25rem 1.25rem 1rem;
      border-bottom: 1px solid var(--border);
    }

    .sidebar-logo a {
      font-size: 1.2rem;
      font-weight: 700;
      letter-spacing: -0.5px;
      color: var(--text);
      text-decoration: none;
    }

    .sidebar-logo a:hover { text-decoration: none; }

    .logo-main {
      color: var(--text);
    }

    .logo-accent {
      color: var(--accent);
    }

    .sidebar-nav {
      flex: 1;
      padding: 0.75rem 0.75rem;
    }

    .nav-item {
      display: block;
      padding: 0.5rem 0.75rem;
      color: var(--muted);
      text-decoration: none;
      font-size: 0.9rem;
      border-radius: 6px;
      margin-bottom: 2px;
      transition: background 0.15s, color 0.15s;
    }

    .nav-item:hover {
      color: var(--text);
      background: var(--surface2);
      text-decoration: none;
    }

    .nav-item-active {
      color: var(--text);
      background: var(--surface2);
    }

    .sidebar-footer {
      padding: 1rem 1.25rem;
      border-top: 1px solid var(--border);
    }

    .sidebar-user {
      margin-bottom: 0.75rem;
    }

    .sidebar-company {
      font-weight: 600;
      color: var(--text);
      font-size: 0.9rem;
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
    }

    .sidebar-email {
      font-size: 0.8rem;
      color: var(--muted);
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
    }

    .signout-btn {
      background: none;
      border: none;
      color: var(--muted);
      cursor: pointer;
      font-size: 0.85rem;
      padding: 0.5rem 0;
      transition: color 0.15s;
      font-family: inherit;
    }

    .signout-btn:hover {
      color: var(--text);
    }

    .main {
      margin-left: 240px;
      flex: 1;
      display: flex;
      flex-direction: column;
      overflow-y: auto;
      min-height: 100vh;
    }

    .topbar {
      background: var(--surface);
      border-bottom: 1px solid var(--border);
      padding: 1rem 2rem;
    }

    .page-title {
      font-size: 1.25rem;
      font-weight: 700;
      color: var(--text);
      margin: 0;
    }

    .main-content {
      padding: 2rem;
    }
    CSS
  end
end
