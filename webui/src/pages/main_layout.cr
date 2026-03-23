abstract class MainLayout
  include Lucky::HTMLPage

  abstract def content

  def render
    html_doctype
    html lang: "en" do
      head do
        title "Dirless Ops"
        meta charset: "utf-8"
        meta name: "viewport", content: "width=device-width, initial-scale=1"
        script src: "https://cdn.tailwindcss.com"
      end
      body class: "bg-gray-50 min-h-screen" do
        nav class: "bg-gray-900 text-white px-6 py-4" do
          div class: "max-w-6xl mx-auto flex items-center gap-8" do
            a "Dirless Ops", href: "/", class: "font-bold text-lg text-white no-underline"
            a "Status", href: "/", class: "text-gray-300 hover:text-white text-sm"
            a "Customers", href: "/customers", class: "text-gray-300 hover:text-white text-sm"
            a "Nodes", href: "/nodes", class: "text-gray-300 hover:text-white text-sm"
            a "Deployments", href: "/provision-jobs", class: "text-gray-300 hover:text-white text-sm"
            div class: "ml-auto" do
              form action: "/logout", method: "post" do
                input type: "hidden", name: "_method", value: "DELETE"
                button type: "submit",
                  class: "text-gray-400 hover:text-white text-sm" do
                  text "Sign out"
                end
              end
            end
          end
        end
        div class: "max-w-6xl mx-auto px-6 py-8" do
          content
        end
      end
    end
  end
end
