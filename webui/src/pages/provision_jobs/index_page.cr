require "../../dirless/ops/webui/responses"

class ProvisionJobs::IndexPage < MainLayout
  needs jobs : Array(Dirless::Ops::WebUI::ProvisionJobResponse)

  def content
    div class: "flex items-center justify-between mb-6" do
      h1 "Deployment Queue", class: "text-2xl font-bold text-gray-900"
    end

    if jobs.empty?
      para "No provision jobs.", class: "text-gray-500"
      return
    end

    div class: "bg-white rounded-lg shadow-sm border border-gray-200 overflow-hidden" do
      table class: "w-full text-sm" do
        thead do
          tr class: "bg-gray-50" do
            th "ID", class: "px-6 py-3 text-left font-medium text-gray-500"
            th "Customer", class: "px-6 py-3 text-left font-medium text-gray-500"
            th "Status", class: "px-6 py-3 text-left font-medium text-gray-500"
            th "Created", class: "px-6 py-3 text-left font-medium text-gray-500"
            th "Started", class: "px-6 py-3 text-left font-medium text-gray-500"
            th "Completed", class: "px-6 py-3 text-left font-medium text-gray-500"
            th "Error", class: "px-6 py-3 text-left font-medium text-gray-500"
          end
        end
        tbody do
          jobs.each do |job|
            tr class: "border-t border-gray-100 hover:bg-gray-50" do
              td job.id.to_s, class: "px-6 py-3 text-gray-500"
              td class: "px-6 py-3" do
                a job.customer_name, href: "/customers/#{job.customer_name}",
                  class: "text-blue-600 hover:underline font-mono text-xs"
              end
              td class: "px-6 py-3" do
                span status_label(job.status), class: status_class(job.status)
              end
              td format_time(job.created_at), class: "px-6 py-3 text-gray-500 text-xs"
              td format_time(job.started_at), class: "px-6 py-3 text-gray-500 text-xs"
              td format_time(job.completed_at), class: "px-6 py-3 text-gray-500 text-xs"
              td class: "px-6 py-3 text-xs text-red-600 max-w-xs truncate" do
                text(job.error || "-")
              end
            end
          end
        end
      end
    end
  end

  private def status_label(status : String) : String
    case status
    when "pending"     then "Pending"
    when "in_progress" then "In Progress"
    when "completed"   then "Completed"
    when "failed"      then "Failed"
    else                    status
    end
  end

  private def status_class(status : String) : String
    base = "px-2 py-1 rounded-full text-xs font-medium"
    case status
    when "pending"     then "#{base} bg-yellow-100 text-yellow-800"
    when "in_progress" then "#{base} bg-blue-100 text-blue-800"
    when "completed"   then "#{base} bg-green-100 text-green-800"
    when "failed"      then "#{base} bg-red-100 text-red-800"
    else                    "#{base} bg-gray-100 text-gray-800"
    end
  end

  private def format_time(t : String?) : String
    return "-" unless t
    # Parse ISO8601 and show a shorter format
    time = Time.parse_rfc3339(t)
    time.to_s("%Y-%m-%d %H:%M:%S")
  rescue
    t || "-"
  end
end
