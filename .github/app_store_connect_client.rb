# frozen_string_literal: true

require "base64"
require "json"
require "net/http"
require "openssl"
require "uri"

# App Store Connect APIへの認証済みJSON要求だけを担当します。
class AppStoreConnectClient
  API_ORIGIN = "https://api.appstoreconnect.apple.com"
  TOKEN_LIFETIME_SECONDS = 15 * 60

  def initialize(key_id:, issuer_id:, private_key_path:)
    @key_id = key_id
    @issuer_id = issuer_id
    @private_key = OpenSSL::PKey.read(File.binread(private_key_path))
  end

  def get(path, query: {})
    request(Net::HTTP::Get, path, query: query)
  end

  def post(path, body:)
    request(Net::HTTP::Post, path, body: body)
  end

  private

  def request(request_class, path, query: {}, body: nil)
    uri = URI.join(API_ORIGIN, path)
    uri.query = URI.encode_www_form(query) unless query.empty?

    request = request_class.new(uri)
    request["Authorization"] = "Bearer #{authorization_token}"
    request["Content-Type"] = "application/json" if body
    request.body = JSON.generate(body) if body

    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
      http.request(request)
    end
    return nil if response.is_a?(Net::HTTPSuccess) && response.body.to_s.empty?
    return JSON.parse(response.body) if response.is_a?(Net::HTTPSuccess)

    raise "App Store Connect API request failed (HTTP #{response.code}): #{error_details(response.body)}"
  end

  def authorization_token
    issued_at = Time.now.to_i
    header = base64url(JSON.generate(alg: "ES256", kid: @key_id, typ: "JWT"))
    claims = base64url(JSON.generate(
      iss: @issuer_id,
      iat: issued_at,
      exp: issued_at + TOKEN_LIFETIME_SECONDS,
      aud: "appstoreconnect-v1"
    ))
    signing_input = "#{header}.#{claims}"
    signature = @private_key.dsa_sign_asn1(OpenSSL::Digest::SHA256.digest(signing_input))
    "#{signing_input}.#{base64url(jose_signature(signature))}"
  end

  def jose_signature(asn1_signature)
    sequence = OpenSSL::ASN1.decode(asn1_signature)
    sequence.value.map { |integer| [integer.value.to_s(16).rjust(64, "0")].pack("H*") }.join
  end

  def base64url(value)
    Base64.urlsafe_encode64(value, padding: false)
  end

  def error_details(body)
    parsed = JSON.parse(body)
    details = Array(parsed["errors"]).filter_map { |error| error["detail"] || error["title"] }
    details.empty? ? "response did not include an error detail" : details.join("; ")
  rescue JSON::ParserError
    "response was not valid JSON"
  end
end
