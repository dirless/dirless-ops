class Errors::Show < Lucky::ErrorAction
  default_format :html

  def default_render(error : Exception) : Lucky::Response
    if error.is_a?(Lucky::RouteNotFoundError)
      error_response(404, "Not Found")
    else
      Lucky::Log.error(exception: error) { "Unhandled error" }
      error_response(500, "Internal Server Error")
    end
  end

  def report(error : Exception) : Nil
  end

  private def error_response(status : Int32, message : String) : Lucky::Response
    context.response.status_code = status
    context.response.print(message)
    Lucky::TextResponse.new(context, "text/plain", message, status)
  end
end
