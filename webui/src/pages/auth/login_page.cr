class LoginPage
  include Lucky::HTMLPage
  needs error : String?

  def render
    html_doctype
    html lang: "en" do
      head do
        title "Dirless Ops - Login"
        meta charset: "utf-8"
        meta name: "viewport", content: "width=device-width, initial-scale=1"
        script src: "https://cdn.tailwindcss.com"
      end
      body class: "bg-gray-50 min-h-screen flex items-center justify-center" do
        div class: "bg-white rounded-lg shadow-sm border border-gray-200 p-8 w-full max-w-sm" do
          h1 "Dirless Ops", class: "text-xl font-bold text-gray-900 mb-1"
          para "Sign in to continue", class: "text-sm text-gray-500 mb-6"

          if error
            div class: "mb-4 px-3 py-2 bg-red-50 border border-red-200 rounded text-sm text-red-700" do
              text error.not_nil!
            end
          end

          form action: "/admin-login", method: "post" do
            div class: "mb-4" do
              label "Username", for: "username",
                class: "block text-sm font-medium text-gray-700 mb-1"
              input type: "text", id: "username", name: "username",
                autofocus: "autofocus", autocomplete: "username", required: "required",
                class: "w-full border border-gray-300 rounded px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
            end
            div class: "mb-6" do
              label "Password", for: "password",
                class: "block text-sm font-medium text-gray-700 mb-1"
              input type: "password", id: "password", name: "password",
                autocomplete: "current-password", required: "required",
                class: "w-full border border-gray-300 rounded px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
            end
            button type: "submit",
              class: "w-full bg-blue-600 text-white px-4 py-2 rounded text-sm hover:bg-blue-700" do
              text "Sign in"
            end
          end
        end
      end
    end
  end
end
