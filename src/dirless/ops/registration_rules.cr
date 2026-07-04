module Dirless
  module Ops
    # Pure validation rules for portal registration. No I/O - fully
    # unit-testable; PortalRegister applies the result.
    module RegistrationRules
      EMAIL_FORMAT = /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/

      # Disposable-email domains that have been used for junk signups.
      # Matched against the domain part and its subdomains.
      BLOCKED_EMAIL_DOMAINS = ["web-library.net"]

      MIN_PASSWORD_LENGTH = 12

      def self.validate(email : String,
                        password : String,
                        first_name : String,
                        last_name : String,
                        company : String,
                        country : String) : Hash(String, String)
        errors = {} of String => String
        errors["email"] = "Required" if email.empty?
        errors["email"] = "Invalid email" unless email.empty? || email.matches?(EMAIL_FORMAT)
        errors["email"] = "Please use your work email address" if blocked_domain?(email)
        errors["password"] = "Required" if password.empty?
        errors["password"] = "Must be at least #{MIN_PASSWORD_LENGTH} characters" if !password.empty? && password.size < MIN_PASSWORD_LENGTH
        errors["first_name"] = "Required" if first_name.empty?
        errors["last_name"] = "Required" if last_name.empty?
        errors["company"] = "Required" if company.empty?
        errors["country"] = "Required" if country.empty?
        errors
      end

      def self.blocked_domain?(email : String) : Bool
        domain = email.split('@').last?
        return false unless domain
        BLOCKED_EMAIL_DOMAINS.any? do |blocked|
          domain == blocked || domain.ends_with?(".#{blocked}")
        end
      end
    end
  end
end
