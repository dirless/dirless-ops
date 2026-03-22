require "../../dirless/ops/webui/responses"

class Customers::IndexPage < MainLayout
  needs customers : Array(Dirless::Ops::WebUI::CustomerResponse)

  def content
    div class: "flex items-center justify-between mb-6" do
      h1 "Customers", class: "text-2xl font-bold text-gray-900"
      a "+ Add Customer", href: "/customers/new",
        class: "bg-blue-600 text-white px-4 py-2 rounded text-sm hover:bg-blue-700"
    end

    if customers.empty?
      para "No customers. ", class: "text-gray-500"
      return
    end

    div class: "bg-white rounded-lg shadow-sm border border-gray-200 overflow-hidden" do
      table class: "w-full text-sm" do
        thead do
          tr class: "bg-gray-50" do
            th "Name", class: "px-6 py-3 text-left font-medium text-gray-500"
            th "Label", class: "px-6 py-3 text-left font-medium text-gray-500"
            th "Port", class: "px-6 py-3 text-left font-medium text-gray-500"
            th "AWS Account", class: "px-6 py-3 text-left font-medium text-gray-500"
            th "", class: "px-6 py-3"
          end
        end
        tbody do
          customers.each do |customer|
            tr class: "border-t border-gray-100 hover:bg-gray-50" do
              td class: "px-6 py-3" do
                a customer.name, href: "/customers/#{customer.name}",
                  class: "text-blue-600 hover:underline font-mono text-xs"
              end
              td customer.label || "-", class: "px-6 py-3 text-gray-700"
              td customer.port.to_s, class: "px-6 py-3 text-gray-500"
              td customer.aws_account_id || "-", class: "px-6 py-3 text-gray-500"
              td class: "px-6 py-3 text-right" do
                form action: "/customers/#{customer.name}/delete", method: "post" do
                  input type: "hidden", name: "_method", value: "DELETE"
                  button type: "submit", class: "text-red-600 hover:underline text-xs",
                    onclick: "return confirm('Delete #{customer.name}?')" do
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
